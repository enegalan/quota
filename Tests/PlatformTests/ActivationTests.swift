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
        #expect(record.state == .updateFailed)
        #expect(record.version == previous.version)
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
