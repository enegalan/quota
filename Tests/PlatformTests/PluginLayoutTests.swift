import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Installed layout")
struct PluginLayoutTests {
    @Test("Activation is a symlink, so it is one rename")
    func activationIsASymlink() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        _ = try await fixture.install()
        let link = PluginLayout.activeLink(InstallerFixture.id, in: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test("A relative path is stored rather than an absolute one")
    func storedPathIsRelative() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let record = try await fixture.install()
        // An absolute path would break the moment the application moved, and one
        // outside the plugins directory is not something this type should express.
        #expect(!record.relativePath.hasPrefix("/"))
        #expect(record.relativePath == "\(InstallerFixture.id)/\(fixture.provider.version.description)")
    }

    @Test("The active link holds a relative target, so the directory can be moved")
    func activeLinkIsRelative() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        _ = try await fixture.install()
        let target = try FileManager.default.destinationOfSymbolicLink(
            atPath: PluginLayout.activeLink(InstallerFixture.id, in: directory).path
        )
        // Absolute here would work right up until the plugins directory was
        // restored from a backup somewhere else, and then every provider would
        // point at a path that is not there.
        #expect(!target.hasPrefix("/"))
        #expect(target == fixture.provider.version.description)
    }

    @Test("Every path the installer writes is inside the plugins directory")
    func everyPathIsInsideThePluginsDirectory() async throws {
        let directory = try InstallerFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await InstallerFixture.installer(in: directory)
        let record = try await fixture.install()
        let active = try #require(
            PluginLayout.activeVersionDirectory(InstallerFixture.id, in: directory)
        )
        #expect(active.path.hasPrefix(directory.path))
        #expect(
            FileManager.default.fileExists(
                atPath: active.appendingPathComponent(
                    PluginLayout.executableName(for: InstallerFixture.id)
                ).path
            )
        )
        // The staging directory does not survive an install, so nothing is left
        // behind for the next one to trip over.
        let staging = directory.appendingPathComponent(
            InstallerConstants.stagingDirectoryName, isDirectory: true
        )
        #expect(
            (try? FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty) == true
        )
        #expect(record.state == .installed)
    }
}
