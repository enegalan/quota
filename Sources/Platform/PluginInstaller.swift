import CryptoKit
import Foundation
import PluginKit

/// Puts a provider's code on this machine, or refuses to.
///
/// Every step is explicit and ordered so that a refusal happens before anything is
/// written: an archive with nothing runnable in it is discovered while the artifact
/// is still a file somewhere else, and the versioned directory this installer would
/// have created does not exist at all. The property that makes a failed install
/// harmless is that no step before the last one touches the active version.
public struct PluginInstaller: Sendable {
    private let pluginsDirectory: URL
    private let repository: InstalledProviderRepository
    private let quotas: QuotaRepository
    private let archive: any ArchiveFormat
    private let bundled: any BundledArtifacts
    private let launcher: any ProcessLaunching
    private let logDirectory: URL
    private let version: Version
    private let now: @Sendable () -> Date

    public init(
        pluginsDirectory: URL,
        repository: InstalledProviderRepository,
        quotas: QuotaRepository,
        archive: any ArchiveFormat = TarArchiveFormat(),
        bundled: any BundledArtifacts = DirectoryBundledArtifacts(directory: nil),
        launcher: any ProcessLaunching,
        logDirectory: URL,
        version: Version = BundleConstants.applicationVersion,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pluginsDirectory = pluginsDirectory
        self.repository = repository
        self.quotas = quotas
        self.archive = archive
        self.bundled = bundled
        self.launcher = launcher
        self.logDirectory = logDirectory
        self.version = version
        self.now = now
    }

    // The fixed places an install can be in.

    /// Why an install did not complete.
    public enum InstallError: Error, Equatable {
        /// The archive is not readable as an archive.
        case extractionFailed(String)
        /// The archive holds no executable where the host will look for one.
        case missingExecutable(String)
        /// This build does not package that provider.
        case notShipped(String)
        /// Something about the plugins directory stopped this.
        case fileSystem(String)
        /// A provider with that id is already installed at that version.
        case alreadyInstalled(String, String)
    }

    /// Installs a provider, activating it only once everything has been checked.
    ///
    /// An install of a version that is already active is refused rather than
    /// repeated: the caller wanted a change, and there is none to make.
    public func install(_ provider: AvailableProvider) async throws -> InstalledProvider {
        // The whole of staging, activation and the record is one critical
        // section. Two concurrent installs of the same version would otherwise
        // both find the destination missing, both extract, and both rename over
        // the same link — leaving a provider on disk that neither of them
        // installed. Coarse across providers on purpose: an install is rare, and
        // one gate is easier to reason about than a table of them.
        try await InstallationGate.shared.serialise {
            try await performInstall(provider)
        }
    }

    /// The ordered steps of one install, run behind the gate.
    ///
    /// The destination is claimed before the artifact is read, so an install that
    /// cannot proceed is refused before it costs an unpack. Staging is cleaned up on
    /// every path out of this function, which is why only `activate` moves anything
    /// into a place a launcher will ever look. The record is written after
    /// activation rather than before: a provider described as installed while the
    /// directory it names is not yet in place is a record the host will resolve to
    /// an executable that is not there.
    private func performInstall(_ provider: AvailableProvider) async throws -> InstalledProvider {
        // Claimed before the artifact is read, so an install that cannot proceed
        // is refused before it costs an unpack.
        _ = try reclaimableDestination(for: provider)

        // Everything that can refuse happens before the first write to the
        // plugins directory, so a rejected artifact leaves no trace at all.
        let artifact = try await fetch(provider.id)

        let staged = try extract(artifact, into: try stagingDirectory(provider))
        defer { try? FileManager.default.removeItem(at: staged) }

        try requireExecutable(in: staged, id: provider.id)
        let record = InstalledProvider(
            id: provider.id,
            version: provider.version,
            relativePath: relativePath(for: provider),
            state: .installed,
            installedAt: now(),
            contentHash: Self.sha256(artifact),
            lastError: nil
        )
        try activate(record, from: staged)
        try await repository.save(record)
        return record
    }

    /// Asks a packaged provider what it is, without installing it.
    ///
    /// The list of providers has to show what each one is before anyone has chosen
    /// to install it, and the only answer worth showing is the provider's own. So
    /// the artifact is unpacked somewhere temporary, run for one handshake, and
    /// thrown away. Nothing is activated and no record is written, because nothing
    /// has been installed: this asks a question about a file, and the answer is
    /// worth keeping only in memory.
    public func describe(_ provider: AvailableProvider) async throws -> ProviderDescriptor {
        let artifact = try await fetch(provider.id)
        let staged = try extract(artifact, into: try stagingDirectory(provider))
        defer { try? FileManager.default.removeItem(at: staged) }

        try requireExecutable(in: staged, id: provider.id)
        let host = PluginHost(
            launch: PluginLayout.launch(for: provider, version: provider.version, in: staged),
            launcher: launcher,
            logDirectory: logDirectory
        )
        // Shutting down on both paths is the point: the plugin is a process this
        // method started, and one that is still running after the staged directory
        // it came out of has been deleted is a process nothing can account for.
        let descriptor: ProviderDescriptor
        do {
            // The host refuses a plugin that answers under another id, so what
            // comes back is this provider's own account of itself.
            descriptor = try await host.launch()
        } catch {
            await host.shutdown()
            throw error
        }
        await host.shutdown()
        return descriptor
    }

    /// Puts a new version in place, keeping the old one if the new one fails.
    ///
    /// The previous symlink target is read before anything changes and restored if
    /// the new version cannot answer a handshake, because a provider that will not
    /// start is worse than one that is a version behind.
    public func update(
        _ provider: AvailableProvider,
        previous: InstalledProvider,
        verify: @Sendable (InstalledProvider) async throws -> Void
    ) async throws -> InstalledProvider {
        let previousDirectory = PluginLayout.activeVersionDirectory(provider.id, in: pluginsDirectory)
        let record: InstalledProvider
        do {
            record = try await install(provider)
        } catch {
            try await repository.update(provider.id) { _ in
                previous.with(state: .updateFailed, lastError: .pluginError)
            }
            throw error
        }
        do {
            try await verify(record)
        } catch {
            // Roll back to what was there: the directory is still intact, because
            // activation added a symlink rather than replacing anything.
            try restoreSymlink(provider.id, to: previousDirectory)
            try? FileManager.default.removeItem(
                at: PluginLayout.versionDirectory(provider.id, provider.version, in: pluginsDirectory)
            )
            // The old version is running and stays launchable, but the record
            // says the update failed: the user asked for something that did not
            // happen, and a state that reads "installed" would leave them
            // wondering why the version in the interface never moved.
            try await repository.save(
                previous.with(state: .updateFailed, lastError: .pluginError)
            )
            throw error
        }
        try await repository.save(record)
        return record
    }

    /// Removes a provider's code, and only its code.
    ///
    /// Quota records are left exactly as they are. They name a provider that is no
    /// longer installed, which is a state the rest of the application knows how to
    /// show, and deleting a user's history because they removed a plugin would be
    /// losing their data to save them one confusing row.
    public func uninstall(_ id: String) async throws {
        try await repository.delete(id)
        try? FileManager.default.removeItem(at: PluginLayout.providerDirectory(id, in: pluginsDirectory))
    }

    /// What removing a provider would cost, for the confirmation dialog.
    ///
    /// Asked before the removal, never after: a user told afterwards that three
    /// quotas stopped refreshing has learned it too late to do anything about it.
    public func impact(ofUninstalling id: String) async throws -> UninstallImpact {
        let affected = try await quotas.all().filter { $0.providerID.rawValue == id }
        return UninstallImpact(
            affectedQuotas: affected.map(\.id.uuidString),
            unrefreshableCount: affected.count
        )
    }

    // MARK: - Steps

    /// The packaged bytes for `id`.
    ///
    /// The only source there is. A provider that arrives from anywhere else would
    /// be code this application did not build and did not ship, and nothing about
    /// a file on disk or a URL says who wrote it — so a build that wanted one would
    /// have to answer for it, rather than this method quietly accepting it.
    private func fetch(_ id: String) async throws -> Data {
        guard let artifact = try bundled.artifact(for: id) else {
            throw InstallError.notShipped(id)
        }
        return artifact
    }

    /// Unpacks into a staging directory, never into the version directory itself.
    ///
    /// A directory that is being written to is a directory something else might
    /// read, and the only thing that should ever be readable under a version's
    /// name is a version that finished being written.
    private func stagingDirectory(_ provider: AvailableProvider) throws -> URL {
        let root = pluginsDirectory.appendingPathComponent(
            InstallerConstants.stagingDirectoryName, isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(
            "\(provider.id)-\(provider.version.description)-\(UUID().uuidString)", isDirectory: true
        )
    }

    /// Unpacks an artifact into a directory that is still only staging.
    ///
    /// The archive format's own failure is wrapped, so an artifact that will not
    /// unpack is reported as an install error rather than as whatever error a
    /// subprocess happened to raise, and `InstallError` stays the single set of
    /// reasons the interface has to be able to word.
    private func extract(_ artifact: Data, into directory: URL) throws -> URL {
        do {
            try archive.unarchive(artifact, to: directory)
        } catch {
            throw InstallError.extractionFailed(String(describing: error))
        }
        return directory
    }

    /// Refuses an archive with nothing runnable in it.
    ///
    /// The executable's name is a convention rather than something the artifact
    /// declares, so this is the only place that knows whether the two agree — and
    /// an archive without it would install cleanly and then fail every launch
    /// afterwards, which is the worst of both outcomes.
    private func requireExecutable(in directory: URL, id: String) throws {
        let executable = directory.appendingPathComponent(PluginLayout.executableName(for: id))
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw InstallError.missingExecutable(id)
        }
    }

    /// Moves staged files into their version directory and points `current` at it.
    private func activate(_ record: InstalledProvider, from staged: URL) throws {
        let destination = PluginLayout.versionDirectory(record.id, record.version, in: pluginsDirectory)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Left over from an install that died between staging and activation.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staged, to: destination)
        try replaceSymlink(record.id, to: destination)
    }

    /// Points a provider's `current` link at a version directory.
    ///
    /// - Throws: `InstallError.fileSystem`, carrying the system's own words for
    ///   the failure, rather than letting the raw `rename` error escape. This is
    ///   the step at which activation either happened or did not, and a caller
    ///   that cannot tell those two apart will go on to write a record naming a
    ///   version that is not the one in use.
    private func replaceSymlink(_ id: String, to directory: URL) throws {
        let link = PluginLayout.activeLink(id, in: pluginsDirectory)
        let parent = link.deletingLastPathComponent()
        // A relative target, so the plugins directory can be moved or restored
        // somewhere else without every link in it becoming a dangling pointer.
        let relative = directory.path.replacingOccurrences(
            of: parent.path + "/", with: ""
        )
        // A link is created somewhere else and renamed over the old one, because
        // `createSymbolicLink` fails where a link already exists and unlinking
        // first would leave a gap where there is no active version at all.
        let incoming = parent.appendingPathComponent(".current-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: incoming)
        try FileManager.default.createSymbolicLink(
            atPath: incoming.path, withDestinationPath: relative
        )
        defer { try? FileManager.default.removeItem(at: incoming) }
        // `rename` rather than `replaceItemAt`, which needs the destination to
        // already exist and so fails on the first install of every provider.
        guard rename(incoming.path, link.path) == 0 else {
            throw InstallError.fileSystem(
                "could not activate \(id): \(String(cString: strerror(errno)))"
            )
        }
    }

    /// Puts the active link back to a directory it can still reach, if there is
    /// one.
    ///
    /// Only reached after a new version has been activated and has then failed
    /// its handshake, and a directory that has since gone is a no-op rather than
    /// an error. A rollback that cannot find what it is rolling back to must not
    /// replace a working link with a dangling one, which would leave a provider
    /// that was launchable before the update unlaunchable after it.
    private func restoreSymlink(_ id: String, to directory: URL?) throws {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        try replaceSymlink(id, to: directory)
    }

    /// The version directory to install into, or a refusal.
    ///
    /// A directory nobody is using is wreckage from an install that died before
    /// it could activate, and keeping it would refuse every future attempt at
    /// that version. A directory something is using is a real install, and
    /// re-installing over it is not this method's business.
    private func reclaimableDestination(for provider: AvailableProvider) throws -> URL {
        let destination = PluginLayout.versionDirectory(
            provider.id, provider.version, in: pluginsDirectory
        )
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }
        let active = PluginLayout.activeVersionDirectory(provider.id, in: pluginsDirectory)
        let isLive = active.map { $0.resolvingSymlinksInPath() == destination } ?? false
        guard isLive else {
            try? FileManager.default.removeItem(at: destination)
            return destination
        }
        throw InstallError.alreadyInstalled(provider.id, provider.version.description)
    }

    /// How the record refers to where this version's code lives.
    ///
    /// Relative to the plugins directory, for the same reason the active link's
    /// target is: the directory can be moved, restored from a backup or handed to
    /// another machine, and a record full of absolute paths stops pointing at
    /// anything the moment that happens.
    private func relativePath(for provider: AvailableProvider) -> String {
        "\(provider.id)/\(provider.version.description)"
    }

    /// The hex SHA-256 of some bytes.
    ///
    /// Recorded with the install so a later read can say which bytes produced this
    /// record. Nothing compares it: with providers packaged into the application,
    /// the trust is the application's own signature and there is no second claim
    /// about the bytes for a digest to disagree with.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
