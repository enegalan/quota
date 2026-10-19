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

    /// A write to a plugin that has died must be an error, not a signal.
    ///
    /// A plugin that exits leaves its stdin closed, and writing to a pipe whose
    /// reader is gone raises SIGPIPE — which, unhandled, takes the whole host
    /// down with it. In the application that is the app itself closing over a
    /// provider that crashed; in a test run it is the whole suite.
    @Test("Writing to a plugin that has died is an error, not a dead process")
    func writingToADeadPluginThrows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try SystemProcessHandle(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            environment: [:],
            standardErrorURL: log
        )
        // Waited for rather than assumed: the write has to happen after the
        // process is gone for the pipe to be broken, and a test that races it
        // would pass without ever reaching the write.
        for _ in 0 ..< 100 where handle.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!handle.isRunning)

        #expect(throws: (any Error).self) {
            try handle.writeLine(Data("are you there".utf8))
        }
    }

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
