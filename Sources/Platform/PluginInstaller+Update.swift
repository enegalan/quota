import Foundation
import PluginKit

extension PluginInstaller {
    /// Puts a new version in place, keeping the old one if the new one fails.
    ///
    /// The previous symlink target is read before anything changes and restored if
    /// the new version cannot answer a handshake, because a provider that will not
    /// start is worse than one that is a version behind.
    ///
    /// The state the provider had is kept either way. The new version is the same
    /// provider as the old one — the same account, still connected — and an
    /// install that staged it did not know that: a provider that loses its
    /// connection because its code was replaced is a provider the user has to
    /// sign into again for nothing, and one whose update failed is still the
    /// provider they had, working as it did.
    public func update(
        _ provider: AvailableProvider,
        previous: InstalledProvider,
        verify: @Sendable (InstalledProvider) async throws -> Void
    ) async throws -> InstalledProvider {
        // Same version with the same bytes is already the state the caller
        // asked for. Same version with different bytes is a rebuilt provider
        // that kept its version number — refuse that as "already installed"
        // and the machine keeps running yesterday's binary after every local
        // rebuild that did not bump the app version.
        var preservedSameVersion: URL?
        if previous.version == provider.version, isActive(provider.id, at: provider.version) {
            let artifact = try await fetch(provider.id)
            if Self.sha256(artifact) == previous.contentHash {
                return previous
            }
            preservedSameVersion = try moveActiveAside(provider)
        }

        let previousDirectory = preservedSameVersion
            ?? PluginLayout.activeVersionDirectory(provider.id, in: pluginsDirectory)
        let record: InstalledProvider
        do {
            record = try await install(provider)
        } catch {
            try restorePreservedSameVersion(preservedSameVersion, provider: provider)
            try await repository.update(provider.id) { _ in
                replacing(previous, state: previous.state, lastError: .pluginError)
            }
            throw error
        }
        do {
            try await verifyTwice(verify, record: record)
        } catch {
            try await rollbackFailedVerification(
                provider: provider,
                previous: previous,
                previousDirectory: previousDirectory,
                preservedSameVersion: preservedSameVersion
            )
            throw error
        }
        if let preserved = preservedSameVersion {
            try? FileManager.default.removeItem(at: preserved)
        }
        let connected = replacing(record, state: previous.state, lastError: nil)
        try await repository.save(connected)
        return connected
    }

    /// Moves the live version directory aside so a same-version rebuild can
    /// install into the freed path without deleting yesterday's bytes yet.
    private func moveActiveAside(_ provider: AvailableProvider) throws -> URL {
        let destination = PluginLayout.versionDirectory(
            provider.id, provider.version, in: pluginsDirectory
        )
        let preserved = destination.deletingLastPathComponent()
            .appendingPathComponent(
                "\(provider.version.description).previous-\(UUID().uuidString)"
            )
        try FileManager.default.moveItem(at: destination, to: preserved)
        return preserved
    }

    /// Puts a same-version directory back when install failed before verify.
    private func restorePreservedSameVersion(
        _ preserved: URL?,
        provider: AvailableProvider
    ) throws {
        guard let preserved else { return }
        let destination = PluginLayout.versionDirectory(
            provider.id, provider.version, in: pluginsDirectory
        )
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: preserved, to: destination)
        try restoreSymlink(provider.id, to: destination)
    }

    /// Restores the previous binary after a handshake failure and records it.
    private func rollbackFailedVerification(
        provider: AvailableProvider,
        previous: InstalledProvider,
        previousDirectory: URL?,
        preservedSameVersion: URL?
    ) async throws {
        if let preserved = preservedSameVersion {
            try restorePreservedSameVersion(preserved, provider: provider)
        } else {
            try restoreSymlink(provider.id, to: previousDirectory)
            try? FileManager.default.removeItem(
                at: PluginLayout.versionDirectory(
                    provider.id, provider.version, in: pluginsDirectory
                )
            )
        }
        // The old version is running and stays launchable, and the record
        // says so: the user asked for something that did not happen, and a
        // record reading "installed" would leave them wondering why the
        // version in the interface never moved. The state it had is kept,
        // because the provider it describes is still the one that works.
        try await repository.save(
            replacing(previous, state: previous.state, lastError: .pluginError)
        )
    }

    /// Runs the check that a new version answers, once more if the first
    /// attempt failed.
    ///
    /// A plugin that has just been unpacked is one the machine has never run,
    /// and the first run of a new binary can fail for reasons that have nothing
    /// to do with the binary: the system's own check of a file it has not seen
    /// before, a disk still settling, a busy machine. Two failures are a plugin
    /// that does not work.
    private func verifyTwice(
        _ verify: @Sendable (InstalledProvider) async throws -> Void,
        record: InstalledProvider
    ) async throws {
        do {
            try await verify(record)
        } catch {
            try await verify(record)
        }
    }

    /// Whether a version is the one in use.
    ///
    /// The link and not the record: the record says what was installed, and the
    /// link says what is running, and the two can disagree after an update that
    /// failed halfway.
    private func isActive(_ id: String, at version: Version) -> Bool {
        PluginLayout.activeVersionDirectory(id, in: pluginsDirectory)?
            .lastPathComponent == version.description
    }

    /// The same record with a state and an error of its own.
    ///
    /// Built field by field rather than through `with`, whose nil means "keep
    /// what was there": an update that succeeded must clear the failure the
    /// last one recorded, and one that failed must record the failure it just
    /// had.
    private func replacing(
        _ record: InstalledProvider,
        state: ProviderState,
        lastError: ProviderErrorCode?
    ) -> InstalledProvider {
        InstalledProvider(
            id: record.id,
            version: record.version,
            relativePath: record.relativePath,
            state: state,
            installedAt: record.installedAt,
            contentHash: record.contentHash,
            lastError: lastError
        )
    }
}
