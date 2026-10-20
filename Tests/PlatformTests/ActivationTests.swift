import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Atomic activation")
struct ActivationTests {
    /// The error a test's verification step throws to stand in for a plugin that
    /// will not complete a handshake.
    private struct VerificationFailed: Error, Equatable {}

    /// The second version each update test installs over the first.
    private static let upgraded = Version(major: 1, minor: 1, patch: 0)

    @Test("Activation leaves the previous version intact when the new one fails")
    func failedActivationLeavesPreviousVersionActive() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()

        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        await #expect(throws: VerificationFailed.self) {
            try await upgrade.installer.update(upgrade.provider, previous: previous) { _ in
                throw VerificationFailed()
            }
        }
        // The old version is still what `current` points at, and the new
        // directory is gone: a provider that will not start is worse than one
        // that is a version behind.
        #expect(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory)?
                .lastPathComponent == previous.version.description
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: PluginLayout
                    .versionDirectory(InstallerFixture.id, Self.upgraded, in: directory).path
            )
        )
    }

    @Test("An update that verifies replaces the active version")
    func successfulUpdateSwitchesVersions() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()

        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        let updated = try await upgrade.installer.update(upgrade.provider, previous: previous) { _ in }
        #expect(updated.version == Self.upgraded)
        #expect(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory)?
                .lastPathComponent == Self.upgraded.description
        )
        // The old version is left on disk: an update that turns out to be bad
        // after a restart is still recoverable, and it costs one directory.
        #expect(
            FileManager.default.fileExists(
                atPath: PluginLayout
                    .versionDirectory(InstallerFixture.id, previous.version, in: directory).path
            )
        )
    }

    @Test("An update whose first check fails is tried once more")
    func updateIsVerifiedTwice() async throws {
        // A plugin that has just been unpacked is one the machine has never run,
        // and the first run of a new binary can fail for reasons that have
        // nothing to do with the binary. A second failure is a plugin that does
        // not work.
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()
        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        let attempts = Counter()
        let updated = try await upgrade.installer.update(
            upgrade.provider,
            previous: previous
        ) { _ in
            if await attempts.next() == 1 {
                throw VerificationFailed()
            }
        }
        #expect(await attempts.count == 2)
        #expect(updated.version == Self.upgraded)
    }

    @Test("An update of the version already in use is not a failure")
    func updatingToTheVersionInUseIsANoOp() async throws {
        // The button was pressed on a provider that was already up to date —
        // perhaps because the list had not been refreshed yet. There is nothing
        // to do, and saying so as though the update had been attempted and
        // failed is what turned a button with nothing to do into an error.
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()
        let attempts = Counter()
        let updated = try await fixture.installer.update(
            fixture.provider,
            previous: previous
        ) { _ in
            await attempts.next()
        }
        #expect(await attempts.count == 0)
        #expect(updated.version == previous.version)
        #expect(updated.state == previous.state)
    }

    @Test("A failed update is recorded as an update failure, not an install one")
    func failedUpdateIsRecorded() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()
        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        _ = try? await upgrade.installer.update(upgrade.provider, previous: previous) { _ in
            throw VerificationFailed()
        }
        // Read through the upgrade's own store, which is the one its installer
        // wrote to. The user asked for something that did not happen, and a
        // record reading "installed" would leave them wondering why it never
        // moved.
        let record = try #require(await installedProviderRepository(upgrade.store).provider(
            InstallerFixture.id
        ))
        #expect(record.state == previous.state)
        #expect(record.version == previous.version)
        // And the failure is on the record, so it outlives the session that had
        // it: the next launch can say what went wrong.
        #expect(record.lastError == .pluginError)
    }

    @Test("A failed update leaves the provider connected and usable")
    func failedUpdateKeepsTheProviderUsable() async throws {
        // The provider that failed to update is the provider the user had, on
        // the version they had, connected to the account they had. A state that
        // says otherwise takes away the way back: the row would offer an Update
        // and an Uninstall and nothing else, and a user who could not sign in
        // again would have to remove the provider to get it back.
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()
        let connected = previous.with(state: .connected)
        try await installedProviderRepository(fixture.store).save(connected)
        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        _ = try? await upgrade.installer.update(upgrade.provider, previous: connected) { _ in
            throw VerificationFailed()
        }
        let record = try #require(await installedProviderRepository(upgrade.store).provider(
            InstallerFixture.id
        ))
        #expect(record.state == .connected)
        // The version on disk is the old one, and it is the one the link points
        // at: the provider that works is still the provider that runs.
        #expect(record.version == connected.version)
        let active = try #require(PluginLayout.activeVersionDirectory(
            InstallerFixture.id,
            in: directory
        ))
        #expect(active.lastPathComponent == connected.version.description)
    }

    @Test("A successful update keeps the provider connected")
    func successfulUpdateKeepsTheConnection() async throws {
        // The new version is the same provider as the old one — the same
        // account, still connected. An install that staged it did not know that,
        // and a provider that loses its connection because its code was
        // replaced is a provider the user has to sign into again for nothing.
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let previous = try await fixture.install()
        try await installedProviderRepository(fixture.store).save(
            previous.with(state: .connected)
        )
        let upgrade = try await InstallerFixture.installer(
            version: Self.upgraded, in: directory
        )
        let updated = try await upgrade.installer.update(
            upgrade.provider,
            previous: previous.with(state: .connected)
        ) { _ in }
        #expect(updated.state == .connected)
        #expect(updated.version == Self.upgraded)
        let record = try #require(await installedProviderRepository(upgrade.store).provider(
            InstallerFixture.id
        ))
        #expect(record.state == .connected)
        #expect(record.lastError == nil)
    }

    @Test("A partially written version directory is discarded, not activated")
    func partialVersionDirectoryIsReplaced() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        // A directory left by an install that died after staging.
        let versionDirectory = PluginLayout.versionDirectory(
            InstallerFixture.id, fixture.provider.version, in: directory
        )
        try FileManager.default.createDirectory(
            at: versionDirectory, withIntermediateDirectories: true
        )
        try Data("leftover".utf8).write(
            to: versionDirectory.appendingPathComponent("stale.txt")
        )
        let record = try await fixture.install()
        #expect(record.state == .installed)
        #expect(
            !FileManager.default.fileExists(
                atPath: versionDirectory.appendingPathComponent("stale.txt").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: versionDirectory
                    .appendingPathComponent(PluginLayout.executableName(for: InstallerFixture.id))
                    .path
            )
        )
    }

    @Test("Concurrent installs of one provider leave a single active version")
    func concurrentInstallsSerialise() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        // Both racing the same version: exactly one may win, and the loser must
        // be a refusal rather than a second activation half-written over the first.
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 4 {
                group.addTask {
                    await (try? fixture.install()) != nil
                }
            }
            var successes = 0
            for await success in group where success {
                successes += 1
            }
            #expect(successes == 1)
        }
        #expect(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory)?
                .lastPathComponent == fixture.provider.version.description
        )
    }
}

/// Counts how many times something was called, from code that may run anywhere.
actor Counter {
    private(set) var count = 0

    /// The number of the call, counting from one.
    @discardableResult
    func next() -> Int {
        count += 1
        return count
    }
}
