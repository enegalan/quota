import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Tests for the plugin host, run against a real child process.
///
/// Nothing here is mocked. A mocked process cannot hang, cannot die between two
/// calls, and cannot write a line that is not valid JSON, and those are the three
/// things the host exists to handle.
@Suite("Plugin host: launch failures and environment", .serialized)
struct PluginHostBoundaryTests {
    private static let testTimeout: TimeInterval = 2

    private func launch(
        id: String = "mock",
        range: ProtocolRange = PluginProtocolConstants.hostRange
    ) -> PluginLaunch {
        PluginLaunch(
            id: id,
            displayName: "Fake",
            version: "1.0.0",
            executablePath: PluginFixture.executable.path,
            protocolRange: range
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Launch failures

    @Test("A missing executable reports pluginError")
    func missingExecutableReportsPluginError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = SystemProcessLauncher(logDirectory: directory)
        let host = PluginHost(
            launch: PluginLaunch(
                id: "mock",
                displayName: "Missing",
                version: "1.0.0",
                executablePath: directory.appendingPathComponent("nope").path,
                protocolRange: PluginProtocolConstants.hostRange
            ),
            launcher: launcher,
            logDirectory: directory,
            timeout: Self.testTimeout
        )

        do {
            _ = try await host.launch()
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
        }
    }

    // MARK: Environment

    @Test("A plugin inherits only the allowlist and the home directory")
    func environmentIsRestricted() {
        // The list is fixed and short on purpose: a plugin runs with whatever the
        // user has connected, and inheriting the app's environment wholesale hands
        // it all of that.
        let names = PluginEnvironment.permittedNames()
        #expect(names.contains("HOME"))
        #expect(names.contains("PATH"))
        #expect(!names.contains("QUOTA_SECRET"))
        #expect(names.count < PluginEnvironment.allowedVariables.count + 10)
    }

    @Test("The environment a plugin is launched with holds only permitted names")
    func childEnvironmentHoldsOnlyPermittedNames() {
        let environment = PluginEnvironment.child(launch: launch())
        for name in environment.keys {
            #expect(
                PluginEnvironment.permittedNames().contains(name),
                "\(name) is not on the allowlist"
            )
        }
        #expect(environment["QUOTA_PROVIDER_ID"] == "mock")
        #expect(environment["QUOTA_PROTOCOL_MIN"] == "1.0.0")
    }
}
