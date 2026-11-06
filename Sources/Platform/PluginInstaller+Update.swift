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
        verify: @escaping @Sendable (InstalledProvider) async throws -> Void
    ) async throws -> InstalledProvider {
        // Debris recovery mutates version directories; run it behind the same
        // gate as installs so it cannot race an in-flight same-version swap.
        // `isActive` must run after recovery, once the layout is settled.
        try await InstallationGate.shared.serialise {
            try self.recoverSameVersionDebris(for: provider)
        }

        // Same version with the same bytes is already the state the caller
        // asked for. Same version with different bytes is a rebuilt provider
        // that kept its version number — refuse that as "already installed"
        // and the machine keeps running yesterday's binary after every local
        // rebuild that did not bump the app version.
        if previous.version == provider.version, isActive(provider.id, at: provider.version) {
            let artifact = try await fetch(provider.id)
            if Self.sha256(artifact) == previous.contentHash {
                return previous
            }
            return try await replaceSameVersion(
                provider,
                previous: previous,
                artifact: artifact,
                verify: verify
            )
        }

        let previousDirectory = PluginLayout.activeVersionDirectory(
            provider.id, in: pluginsDirectory
        )
        let record: InstalledProvider
        do {
            record = try await install(provider)
        } catch {
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
                previousDirectory: previousDirectory
            )
            throw error
        }
        let connected = replacing(record, state: previous.state, lastError: nil)
        try await repository.save(connected)
        return connected
    }

    /// Stages rebuilt bytes beside the live version, then swaps `current`.
    ///
    /// The live directory stays where `current` points until the new bytes are
    /// ready and the link is renamed over, so a crash mid-rebuild cannot leave
    /// the provider with a dangling active path.
    private func replaceSameVersion(
        _ provider: AvailableProvider,
        previous: InstalledProvider,
        artifact: Data,
        verify: @escaping @Sendable (InstalledProvider) async throws -> Void
    ) async throws -> InstalledProvider {
        try await InstallationGate.shared.serialise {
            try self.recoverSameVersionDebris(for: provider)
            let paths = try self.stageSameVersionIncoming(provider, artifact: artifact)
            let record = InstalledProvider(
                id: provider.id,
                version: provider.version,
                relativePath: self.relativePath(for: provider),
                state: .installed,
                installedAt: previous.installedAt,
                contentHash: Self.sha256(artifact),
                lastError: nil
            )
            do {
                try await self.verifyTwice(verify, record: record)
            } catch {
                try await self.rollbackSameVersionIncoming(paths, previous: previous)
                throw error
            }
            try self.finalizeSameVersionIncoming(paths)
            let connected = self.replacing(record, state: previous.state, lastError: nil)
            try await self.repository.save(connected)
            return connected
        }
    }

    /// Unpacks rebuilt bytes next to the live version and points `current` at them.
    private func stageSameVersionIncoming(
        _ provider: AvailableProvider,
        artifact: Data
    ) throws -> SameVersionPaths {
        let canonical = PluginLayout.versionDirectory(
            provider.id, provider.version, in: pluginsDirectory
        )
        let parent = canonical.deletingLastPathComponent()
        let incoming = parent.appendingPathComponent(
            "\(provider.version.description).next-\(UUID().uuidString)"
        )
        let staged = try extract(artifact, into: try stagingDirectory(provider))
        do {
            try requireExecutable(in: staged, id: provider.id)
            try FileManager.default.moveItem(at: staged, to: incoming)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        try replaceSymlink(provider.id, to: incoming)
        return SameVersionPaths(
            providerID: provider.id,
            canonical: canonical,
            incoming: incoming,
            parent: parent,
            versionDescription: provider.version.description
        )
    }

    /// Puts `current` back on the live version after a failed handshake.
    private func rollbackSameVersionIncoming(
        _ paths: SameVersionPaths,
        previous: InstalledProvider
    ) async throws {
        try restoreSymlink(paths.providerID, to: paths.canonical)
        try? FileManager.default.removeItem(at: paths.incoming)
        try await repository.save(
            replacing(previous, state: previous.state, lastError: .pluginError)
        )
    }

    /// Renames the verified rebuild onto the canonical version path.
    private func finalizeSameVersionIncoming(_ paths: SameVersionPaths) throws {
        let preserved = paths.parent.appendingPathComponent(
            "\(paths.versionDescription).previous-\(UUID().uuidString)"
        )
        try FileManager.default.moveItem(at: paths.canonical, to: preserved)
        do {
            try FileManager.default.moveItem(at: paths.incoming, to: paths.canonical)
        } catch {
            try? FileManager.default.moveItem(at: preserved, to: paths.canonical)
            try restoreSymlink(paths.providerID, to: paths.canonical)
            try? FileManager.default.removeItem(at: paths.incoming)
            throw error
        }
        try replaceSymlink(paths.providerID, to: paths.canonical)
        try? FileManager.default.removeItem(at: preserved)
    }

    /// Clears leftover `.previous-` / `.next-` directories from an interrupted
    /// same-version rebuild, restoring `current` when the canonical path is gone.
    func recoverSameVersionDebris(for provider: AvailableProvider) throws {
        let parent = PluginLayout.providerDirectory(provider.id, in: pluginsDirectory)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path)
        else { return }

        let version = provider.version.description
        let canonical = PluginLayout.versionDirectory(
            provider.id, provider.version, in: pluginsDirectory
        )
        for name in entries {
            let url = parent.appendingPathComponent(name)
            guard name.hasPrefix("\(version).next-")
                || name.hasPrefix("\(version).previous-")
            else { continue }
            // Rebuild after each prior recovery: moving a `.previous-` into
            // canonical changes what the next entry must do with the layout.
            let active = PluginLayout.activeVersionDirectory(
                provider.id, in: pluginsDirectory
            )
            let context = SameVersionRecovery(
                providerID: provider.id,
                canonical: canonical,
                active: active,
                canonicalExists: FileManager.default.fileExists(atPath: canonical.path),
                activeExists: active.map {
                    FileManager.default.fileExists(atPath: $0.path)
                } ?? false
            )
            if name.hasPrefix("\(version).next-") {
                try recoverNextDebris(url, context: context)
            } else {
                try recoverPreviousDebris(url, context: context)
            }
        }
    }

    private func recoverNextDebris(_ url: URL, context: SameVersionRecovery) throws {
        let isActiveTarget = context.active.map {
            $0.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        } == true
        guard isActiveTarget else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if context.canonicalExists {
            try restoreSymlink(context.providerID, to: context.canonical)
            try? FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.moveItem(at: url, to: context.canonical)
            try replaceSymlink(context.providerID, to: context.canonical)
        }
    }

    private func recoverPreviousDebris(_ url: URL, context: SameVersionRecovery) throws {
        if !context.canonicalExists {
            try FileManager.default.moveItem(at: url, to: context.canonical)
            try restoreSymlink(context.providerID, to: context.canonical)
        } else if context.activeExists {
            try? FileManager.default.removeItem(at: url)
        } else {
            try restoreSymlink(context.providerID, to: context.canonical)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Restores the previous binary after a handshake failure and records it.
    private func rollbackFailedVerification(
        provider: AvailableProvider,
        previous: InstalledProvider,
        previousDirectory: URL?
    ) async throws {
        try restoreSymlink(provider.id, to: previousDirectory)
        try? FileManager.default.removeItem(
            at: PluginLayout.versionDirectory(
                provider.id, provider.version, in: pluginsDirectory
            )
        )
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
    /// failed halfway. A same-version rebuild may point `current` at a
    /// `.next-` sibling while the new bytes are verified.
    private func isActive(_ id: String, at version: Version) -> Bool {
        guard let active = PluginLayout.activeVersionDirectory(id, in: pluginsDirectory)
        else { return false }
        let name = active.lastPathComponent
        return name == version.description
            || name.hasPrefix("\(version.description).next-")
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

/// Paths used while a same-version rebuild is staged beside the live install.
private struct SameVersionPaths {
    let providerID: String
    let canonical: URL
    let incoming: URL
    let parent: URL
    let versionDescription: String
}

/// Snapshot of the live layout while leftover rebuild directories are cleared.
private struct SameVersionRecovery {
    let providerID: String
    let canonical: URL
    let active: URL?
    let canonicalExists: Bool
    let activeExists: Bool
}
