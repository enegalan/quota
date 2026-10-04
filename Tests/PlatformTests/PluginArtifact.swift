import Foundation
@testable import Platform

/// A tar of a plugin, built the way a plugin author would publish one.
enum PluginArtifact {
    /// A gzipped tar with a single top-level directory holding the executable the
    /// host looks for, which is the shape the installer's one stripped component
    /// assumes.
    ///
    /// - Parameters:
    ///   - identifier: the provider the executable is named for.
    ///   - executable: the name inside the directory, so a test can build an
    ///     archive that holds something other than what the host expects.
    ///   - nested: how many directories deep to put the executable. One is the
    ///     shape a real artifact has; more builds the archive a provider that
    ///     would install cleanly and then never start.
    static func archive(
        identifier: String = "mock",
        executable: String? = nil,
        nested: Int = 1
    ) throws -> Data {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-artifact-\(UUID().uuidString)")
        let name = executable ?? PluginLayout.executableName(for: identifier)
        // The top-level directory the host strips; `nested - 1` more below it.
        var container = root
        for level in 1 ... max(nested, 1) {
            container = container.appendingPathComponent(level == 1 ? name : "level-\(level)")
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binary = container.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: binary.path
        )

        let tarball = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-artifact-\(UUID().uuidString).tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: InstallerConstants.tarPath)
        tar.arguments = [
            "-czf", tarball.path, "-C", root.path, name,
        ]
        try tar.run()
        tar.waitUntilExit()
        let data = try Data(contentsOf: tarball)
        try? FileManager.default.removeItem(at: tarball)
        return data
    }
}
