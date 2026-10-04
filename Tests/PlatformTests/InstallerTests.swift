import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Plugin installer")
struct InstallerTests {
    // MARK: A successful install

    @Test("Installing a packaged provider leaves a clean, active state")
    func installThenUninstallIsClean() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)

        let record = try await fixture.install()
        #expect(record.id == InstallerFixture.id)
        #expect(record.state == .installed)

        let active = try #require(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory)
        )
        #expect(active.lastPathComponent == fixture.provider.version.description)
        #expect(
            FileManager.default.fileExists(
                atPath: active
                    .appendingPathComponent(
                        PluginLayout.executableName(for: InstallerFixture.id)
                    ).path
            )
        )

        try await fixture.installer.uninstall(InstallerFixture.id)
        #expect(
            !FileManager.default.fileExists(
                atPath: PluginLayout.activeLink(InstallerFixture.id, in: directory).path
            )
        )
    }

    @Test("The version directory is named for the version installed")
    func versionDirectoryIsVersioned() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let version = Version(major: 2, minor: 3, patch: 4)
        let fixture = try await InstallerFixture.installer(
            version: version, in: directory
        )
        _ = try await fixture.install()
        #expect(
            FileManager.default.fileExists(
                atPath: PluginLayout
                    .versionDirectory(InstallerFixture.id, version, in: directory).path
            )
        )
    }

    @Test("The record carries the digest of the bytes that were installed")
    func recordCarriesTheArtifactDigest() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = try PluginArtifact.archive()
        let fixture = try await InstallerFixture.installer(
            artifact: artifact, in: directory
        )
        let record = try await fixture.install()
        // Recorded so a later read can tell whether the bytes on disk are still
        // the bytes that were checked, even though with providers packaged into
        // the application nothing compares it yet.
        #expect(record.contentHash == PluginInstaller.sha256(artifact))
    }

    // MARK: Refusals happen before anything is written

    @Test("A provider this build does not package is refused")
    func unshippedProviderIsRefused() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Discovery points at a directory holding nothing, which is what an
        // application without that provider packaged looks like from here.
        let fixture = try await InstallerFixture.installer(
            providerIdentifier: "not-packaged",
            in: directory,
            bundled: DirectoryBundledArtifacts(directory: directory.appendingPathComponent("none"))
        )
        await #expect(throws: PluginInstaller.InstallError.notShipped("not-packaged")) {
            try await fixture.install()
        }
    }

    @Test("A truncated archive is refused rather than half-installed")
    func truncatedArchiveIsRefused() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let full = try PluginArtifact.archive()
        let fixture = try await InstallerFixture.installer(
            artifact: Data(full.prefix(full.count / 2)), in: directory
        )
        await #expect(throws: PluginInstaller.InstallError.self) {
            try await fixture.install()
        }
        #expect(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory) == nil
        )
    }

    @Test("An archive with nothing to run in it is refused")
    func missingExecutableIsRefused() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A directory of files, none of them the executable the host resolves.
        let fixture = try await InstallerFixture.installer(
            artifact: try PluginArtifact.archive(executable: "something-else"), in: directory
        )
        await #expect(
            throws: PluginInstaller.InstallError.missingExecutable(InstallerFixture.id)
        ) {
            try await fixture.install()
        }
        // Refused before activation, so there is no version directory to run from.
        #expect(
            !FileManager.default.fileExists(
                atPath: PluginLayout
                    .versionDirectory(InstallerFixture.id, fixture.provider.version, in: directory).path
            )
        )
    }

    @Test("An archive whose files are one level deeper is not searched for")
    func executableMustBeAtTheRootOfTheVersionDirectory() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The name is right but the path is not: a host that looked would find
        // nothing, and a provider that installed to this directory could never
        // start.
        let fixture = try await InstallerFixture.installer(
            artifact: try PluginArtifact.archive(nested: 2), in: directory
        )
        await #expect(
            throws: PluginInstaller.InstallError.missingExecutable(InstallerFixture.id)
        ) {
            try await fixture.install()
        }
    }

    @Test("Installing a version that is already there is refused, not repeated")
    func alreadyInstalledIsRefused() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        _ = try await fixture.install()
        await #expect(throws: PluginInstaller.InstallError.alreadyInstalled(
            InstallerFixture.id,
            fixture.provider.version.description
        )) {
            try await fixture.install()
        }
    }

    @Test("Uninstalling removes the provider's code and only its code")
    func uninstallRemovesOnlyTheProvidersCode() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        _ = try await fixture.install()

        try await fixture.installer.uninstall(InstallerFixture.id)
        #expect(
            !FileManager.default.fileExists(
                atPath: PluginLayout
                    .providerDirectory(InstallerFixture.id, in: directory).path
            )
        )
        // Another provider's directory is none of this one's business.
        let other = PluginLayout.versionDirectory("other", fixture.provider.version, in: directory)
        try FileManager.default.createDirectory(
            at: other, withIntermediateDirectories: true
        )
        try await fixture.installer.uninstall(InstallerFixture.id)
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(try await installedProviderRepository(fixture.store).provider(InstallerFixture.id) == nil)
    }
}
