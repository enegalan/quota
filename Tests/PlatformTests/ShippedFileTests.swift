import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Checks that the files a build assembles agree with each other.
///
/// What providers an application offers is read off a directory of tarballs in
/// its bundle, and each tarball holds an executable whose name is a convention
/// the host derives rather than reads. Nothing in the type system connects those
/// three facts — the directory of plugin packages, each package's declared
/// executable, and the name `PluginLayout` resolves — and a mismatch only shows up
/// as an install that fails at runtime on a user's machine, so it is checked here
/// instead.
@Suite("Shipped files agree")
struct ShippedFileTests {
    /// The repository root, derived from this file's own path so the tests need
    /// no fixture path of their own to keep in step with the build.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PlatformTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root

    /// The plugin packages this repository ships, by the id discovery will file
    /// them under.
    ///
    /// Read from the packages themselves rather than from a list, because a list
    /// is the thing that has been wrong before: a provider added without being
    /// listed is not offered, and one removed but still listed is a row in the
    /// interface for code the build no longer ships.
    private static func packagedProviders() throws -> [String] {
        let plugins = repositoryRoot.appendingPathComponent("Plugins", isDirectory: true)
        return try FileManager.default
            .subpathsOfDirectory(atPath: plugins.path)
            .filter { $0.hasSuffix("Package.swift") }
            // The directory the package sits in is the id discovery will file its
            // artifact under.
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }
            .sorted()
    }

    @Test("Every packaged provider builds the executable the host looks for")
    func packagedProvidersBuildTheExpectedExecutable() throws {
        for id in try Self.packagedProviders() {
            let package = Self.repositoryRoot
                .appendingPathComponent("Plugins", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
                .appendingPathComponent("Package.swift")
            // The name of the executable is a convention rather than a file, so
            // the package is the only place it can be declared, and the only place
            // a provider can disagree with the host about what to run.
            let declared = try String(contentsOf: package, encoding: .utf8)
            #expect(
                declared.contains(
                    ".executable(name: \"\(PluginLayout.executableName(for: id))\""
                ),
                "Plugins/\(id) does not build \(PluginLayout.executableName(for: id))"
            )
        }
    }

    @Test("Every packaged provider has an id discovery would accept")
    func packagedProvidersHaveUsableIdentifiers() throws {
        for id in try Self.packagedProviders() {
            #expect(
                (try? ProviderID(id)) != nil,
                "Plugins/\(id) cannot be the name of a packaged artifact"
            )
        }
    }

    /// The version the application itself declares.
    ///
    /// Read from the shipped Info.plist rather than from `Bundle.main`, because
    /// under `swift test` the main bundle is the test runner and reports nothing
    /// useful. A version here that will not parse would silently become `0.0.0`
    /// in every versioned directory name, so it is parsed instead.
    @Test("The version this application declares is one that parses")
    func declaredAppVersionParses() throws {
        let plist = Self.repositoryRoot
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let object = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: plist), format: nil
        ) as? [String: Any]
        let raw = try #require(object?["CFBundleShortVersionString"] as? String)
        #expect(Version(string: raw) != nil, "\(raw) is not a version")
    }

    @Test("The build script packages providers the way the host reads them")
    func bundleScriptAgreesWithDiscovery() throws {
        let script = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("Scripts/bundle.sh"),
            encoding: .utf8
        )
        // The directory name and the file extension are read off a constant by the
        // host, so the script naming its own copies of them is a second place to
        // get wrong.
        #expect(script.contains(BundleConstants.providersDirectoryName))
        #expect(script.contains(BundleConstants.artifactFileExtension))
        #expect(script.contains("quota-provider-"))
    }
}
