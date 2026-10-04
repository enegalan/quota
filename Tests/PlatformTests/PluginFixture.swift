import Foundation
import Testing

/// The real plugin executable these host tests run against.
enum PluginFixture {
    /// Anchored on a compile-time path rather than on a bundle: under
    /// swift-testing the loaded bundles are the toolchain's own, and the products
    /// directory is named after the target triple, so a hard-coded path or a
    /// bundle-relative one would only work on the machine that wrote it.
    static let executable: URL = {
        let sourceFile = URL(fileURLWithPath: #filePath)
        // .../Tests/PlatformTests/PluginFixture.swift -> repository root
        let repositoryRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildDirectory = repositoryRoot.appendingPathComponent(".build")
        let fixtureName = "TestPlugin"

        var candidates: [URL] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: buildDirectory, includingPropertiesForKeys: nil
        ) {
            // A plain .build/debug layout, and a triple-named one.
            candidates.append(
                buildDirectory
                    .appendingPathComponent("debug")
                    .appendingPathComponent(fixtureName)
            )
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory == true
            {
                candidates.append(
                    entry
                        .appendingPathComponent("debug")
                        .appendingPathComponent(fixtureName)
                )
            }
        }
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let found else {
            Issue.record("could not find \(fixtureName); looked in \(candidates.map(\.path))")
            return URL(fileURLWithPath: "/nonexistent/\(fixtureName)")
        }
        return found
    }()
}
