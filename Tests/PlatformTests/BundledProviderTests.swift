import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Checks the directory a build assembles into, which is the whole list of
/// providers the application offers.
///
/// Nothing in the type system connects a file in the bundle to a row in the
/// providers screen, so the two are connected here instead: what discovery
/// reports is what a file is named, and what a file is named has to be an
/// identifier the store will accept.
@Suite("Bundled providers")
struct BundledProviderTests {
    @Test("A provider is discovered under the id its file is named")
    func discoveredByFileName() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for id in ["mock", "cursor", "a-third-one"] {
            try Data("bytes".utf8).write(to: artifact(named: id, in: directory))
        }
        let bundled = DirectoryBundledArtifacts(directory: directory)
        #expect(try bundled.providers() == ["a-third-one", "cursor", "mock"])
    }

    @Test("Discovery is in a stable order, so the interface does not reshuffle")
    func discoveryOrderIsStable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for id in ["zebra", "mock", "cursor"] {
            try Data("bytes".utf8).write(to: artifact(named: id, in: directory))
        }
        let first = try DirectoryBundledArtifacts(directory: directory).providers()
        let second = try DirectoryBundledArtifacts(directory: directory).providers()
        #expect(first == second)
        #expect(first == first.sorted())
    }

    @Test("A file that is not a provider artifact is passed over, not offered")
    func nonArtifactsAreIgnored() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("bytes".utf8).write(to: artifact(named: "mock", in: directory))
        // A resource the build leaves beside the artifacts, and a name the store
        // could not hold even if it were one.
        try Data("bytes".utf8).write(to: directory.appendingPathComponent("quota.png"))
        try Data("bytes".utf8).write(to: directory.appendingPathComponent("has spaces.tar.gz"))
        let bundled = DirectoryBundledArtifacts(directory: directory)
        #expect(try bundled.providers() == ["mock"])
    }

    @Test("The artifact read is the bytes the file holds")
    func artifactBytesMatchTheFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try PluginArtifact.archive()
        try expected.write(to: artifact(named: "mock", in: directory))
        let bundled = DirectoryBundledArtifacts(directory: directory)
        #expect(try bundled.artifact(for: "mock") == expected)
    }

    @Test("A provider this build does not ship reads as absent, not as a failure")
    func unshippedProviderIsAbsent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = DirectoryBundledArtifacts(directory: directory)
        // A caller can be holding an id from an older build, and it already has a
        // way to say so; a thrown error here would be a broken installation for
        // something that is a legitimate question with a negative answer.
        #expect(try bundled.artifact(for: "mock") == nil)
    }

    @Test("A build that ships no providers at all is a valid state")
    func noProvidersIsAValidState() throws {
        let bundled = DirectoryBundledArtifacts(directory: nil)
        #expect(try bundled.providers().isEmpty)
        #expect(try bundled.artifact(for: "mock") == nil)
    }

    // MARK: Helpers

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-bundled-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func artifact(named id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id).\(BundleConstants.artifactFileExtension)")
    }
}
