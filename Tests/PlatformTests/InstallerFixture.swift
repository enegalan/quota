import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Shared fixtures for the installer tests.
///
/// The installer only handles packaged providers, so a fixture writes one tarball
/// where `PluginManager.live` reads the real bundle and hands back an installer
/// pointed at a private plugins directory.
enum InstallerFixture {
    /// The identifier every fixture installs as.
    ///
    /// One declaration because the assertions below read the version directory's
    /// name literally, and a second place to change it is a second place to forget.
    static let id = "mock"

    /// A temporary plugins directory, unique per call so two tests never share one.
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-installer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An installer over `directory`, holding exactly one packaged provider.
    ///
    /// The bytes are written where discovery looks for them rather than injected
    /// past it, so the fixture goes through the same read path the application
    /// does. The archive format is the real one: the steps these tests are about
    /// are the ones around the unpack, and a fake one would leave the unpack
    /// itself untested everywhere at once.
    static func installer(
        artifact: Data? = nil,
        version: Version = ProviderFixture.version,
        providerIdentifier: String = id,
        in directory: URL,
        store: CodableStore = CodableStore.inMemory(),
        bundled: (any BundledArtifacts)? = nil
    ) async throws -> InstalledFixture {
        let provider = AvailableProvider(id: providerIdentifier, version: version)
        let providers = directory.appendingPathComponent(
            BundleConstants.providersDirectoryName, isDirectory: true
        )
        try FileManager.default.createDirectory(at: providers, withIntermediateDirectories: true)
        try (artifact ?? PluginArtifact.archive(identifier: providerIdentifier)).write(
            to: providers.appendingPathComponent(
                "\(providerIdentifier).\(BundleConstants.artifactFileExtension)"
            )
        )
        try await store.saveInstalledProviders([])
        try await store.saveQuotas([])
        try await store.savePreferences(.default)

        return InstalledFixture(
            provider: provider,
            installer: PluginInstaller(
                pluginsDirectory: directory,
                repository: installedProviderRepository(store),
                quotas: quotaRepository(store),
                bundled: bundled ?? DirectoryBundledArtifacts(directory: providers),
                launcher: TestPluginLauncher(),
                logDirectory: directory.appendingPathComponent(
                    PersistenceConstants.pluginLogDirectoryName, isDirectory: true
                ),
                version: ProviderFixture.applicationVersion
            ),
            store: store
        )
    }
}

/// What an installed fixture is made of.
///
/// Named rather than returned as a three-part tuple, because a caller that wrote
/// `.0` and `.2` had to count: which is the provider, and which is the store the
/// installer writes to.
struct InstalledFixture {
    let provider: AvailableProvider
    let installer: PluginInstaller
    let store: CodableStore

    /// Installs the packaged provider and returns what was recorded.
    ///
    /// Shorthand for the pair these tests almost always want together, so a test
    /// about installing reads as one call rather than as the fixture's parts.
    @discardableResult
    func install() async throws -> InstalledProvider {
        try await installer.install(provider)
    }
}

/// A launcher that starts nothing.
final class TestPluginLauncher: ProcessLaunching, @unchecked Sendable {
    func launch(
        executable: URL,
        environment: [String: String],
        arguments: [String]
    ) throws -> any ProcessHandle {
        NullHandle()
    }
}

/// A process that is not running, for a launcher that never started one.
final class NullHandle: ProcessHandle, @unchecked Sendable {
    func writeLine(_ data: Data) throws {}
    func closeInput() throws {}
    func terminate() async {}
    var isRunning: Bool {
        false
    }

    var terminationStatus: Int32? {
        0
    }

    func output() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
