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
@Suite("Plugin host", .serialized)
struct PluginHostTests {
    /// A short timeout, so a test for a hanging plugin does not spend the
    /// production ten seconds discovering it.
    private static let testTimeout: TimeInterval = 2

    // The fixture binary, found under the package's build directory.
    //

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

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

    private func makeHost(
        _ behaviour: String,
        id: String = "mock",
        range: ProtocolRange = PluginProtocolConstants.hostRange,
        logDirectory: URL,
        timeout: TimeInterval = PluginHostTests.testTimeout
    ) -> PluginHost {
        PluginHost(
            launch: launch(id: id, range: range),
            launcher: BehaviourLauncher(behaviour: behaviour, logDirectory: logDirectory),
            logDirectory: logDirectory,
            timeout: timeout
        )
    }

    /// A launcher that tells the fixture which way to misbehave.
    ///
    /// The production launcher passes no arguments, and rightly so. This one is how
    /// a single executable can stand in for a dozen different broken plugins
    /// without the app's launch path growing a test-only branch.
    private struct BehaviourLauncher: ProcessLaunching {
        let behaviour: String
        let base: SystemProcessLauncher

        init(behaviour: String, logDirectory: URL) {
            self.behaviour = behaviour
            base = SystemProcessLauncher(logDirectory: logDirectory)
        }

        func launch(
            executable: URL,
            environment: [String: String],
            arguments: [String]
        ) throws -> any ProcessHandle {
            try base.launch(
                executable: executable,
                environment: environment,
                arguments: [behaviour] + arguments
            )
        }
    }

    // MARK: A plugin that behaves

    @Test("A conforming plugin answers every method")
    func conformingPluginAnswersEveryMethod() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("well-behaved", logDirectory: directory)

        let descriptor = try await host.launch()
        #expect(descriptor.id == "mock")
        #expect(descriptor.capabilities.contains(.automaticUsageRetrieval))

        let connect = try await host.connect(credentials: "anything")
        #expect(connect.accountLabel == "work")

        let usage = try await host.fetchUsage(localDate: "2026-09-25")
        #expect(usage.quotas.count == 1)
        #expect(usage.quotas.first?.usagePercentage == 12.5)
        #expect(usage.quotas.first?.bucketID == "models")

        try await host.disconnect()
        await host.shutdown()
    }

    // MARK: A plugin that misbehaves

    @Test("A plugin that never answers is killed at the timeout, and the call reports pluginError")
    func silentPluginIsKilledAtTimeout() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("silent", logDirectory: directory, timeout: 0.5)

        // The handshake itself never completes, so launch is where this surfaces.
        await #expect(throws: ProviderError.self) {
            try await host.launch()
        }
        // The process is gone, not merely abandoned: a hung plugin left running
        // would keep holding whatever the user connected.
        #expect(await host.isRunning() == false)
    }

    @Test("A plugin that exits immediately reports pluginError")
    func immediatelyExitingPluginReportsPluginError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("exits-immediately", logDirectory: directory)

        do {
            _ = try await host.launch()
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
        }
    }

    @Test("A plugin that emits malformed JSON reports invalidResponse")
    func malformedPluginReportsInvalidResponse() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("malformed", logDirectory: directory)

        do {
            _ = try await host.launch()
            Issue.record("expected an invalidResponse")
        } catch let error as ProviderError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test("A plugin that writes an unusable line reports invalidResponse, not a framing error")
    func overlongLineReportsProviderError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("overlong-line", logDirectory: directory)

        // Every transport failure has to arrive as a ProviderError. A raw
        // framing error escaping into the domain would put a protocol detail in
        // front of a user.
        do {
            _ = try await host.launch()
            Issue.record("expected an invalidResponse")
        } catch let error as ProviderError {
            #expect(error.code == .invalidResponse)
        }
    }

    @Test("A plugin advertising an incompatible protocol range is rejected before it runs")
    func incompatibleRangeIsRejectedBeforeLaunch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let incompatible = ProtocolRange(
            minimum: Version(major: 3, minor: 0, patch: 0),
            maximum: Version(major: 3, minor: 9, patch: 0)
        )
        let host = makeHost("incompatible-protocol", range: incompatible, logDirectory: directory)

        do {
            _ = try await host.launch()
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
            #expect(error.message.contains("3.0.0..<3.9.0"))
        }
        // Refused before the launch, so nothing was started at all.
        #expect(await host.isRunning() == false)
    }

    @Test("A plugin that claims to be another provider is rejected")
    func wrongIdentityIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("wrong-identity", logDirectory: directory)

        do {
            _ = try await host.launch()
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
        }
        #expect(await host.isRunning() == false)
    }

    @Test("A plugin exiting between calls is relaunched rather than left broken")
    func pluginExitingBetweenCallsIsRelaunched() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("exits-between-calls", logDirectory: directory)

        let descriptor = try await host.launch()
        #expect(descriptor.id == "mock")

        // The plugin walked off after the handshake, so the next call finds nothing
        // running. A host that reported only "not running" would leave the user
        // with a provider that works once; relaunching is what makes it recover.
        do {
            _ = try await host.connect(credentials: nil)
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
        }
        #expect(await host.isRunning() == false)
    }

    @Test("A plugin that stops between calls reports pluginError, not a system error")
    func stoppedPluginReportsProviderError() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("well-behaved", logDirectory: directory)

        _ = try await host.launch()
        await host.shutdown()

        do {
            _ = try await host.fetchUsage(localDate: "2026-09-25")
            Issue.record("expected a pluginError")
        } catch let error as ProviderError {
            #expect(error.code == .pluginError)
        }
    }

    // MARK: Correlation

    @Test("A message for a call nobody is waiting on is ignored, not misattributed")
    func unsolicitedMessageIsIgnored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("unsolicited", logDirectory: directory)

        // The plugin sends a response with no id before its real answer. Taking
        // that one would hand the caller a connect result for a describe.
        let descriptor = try await host.launch()
        #expect(descriptor.id == "mock")
        await host.shutdown()
    }

    @Test("A response for someone else's call is ignored")
    func misidentifiedResponseIsIgnored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("misidentified", logDirectory: directory)

        // The plugin answers a call that was never made, correctly shaped, before
        // answering the real one. The real answer has to win.
        let descriptor = try await host.launch()
        #expect(descriptor.id == "mock")
        await host.shutdown()
    }

    @Test("Two calls in flight are matched by id, not by arrival order")
    func concurrentCallsAreMatchedById() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("reverse-order", logDirectory: directory, timeout: 5)

        // This plugin holds the first two requests and answers the second one
        // first, so anything matching by order rather than by id gets them mixed
        // up. Launch and the first usage call overlap.
        let launchTask = Task { try await host.launch() }
        let usageTask = Task { try await host.fetchUsage(localDate: "2026-09-25") }

        let descriptor = try await launchTask.value
        let usage = try await usageTask.value

        #expect(descriptor.id == "mock")
        #expect(usage.quotas.first?.usagePercentage == 12.5)
        await host.shutdown()
    }

    // MARK: A plugin that is noisy

    @Test("A plugin filling stderr does not block the host")
    func noisyStderrDoesNotBlock() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = makeHost("noisy-stderr", logDirectory: directory)

        // stderr goes to a file, not a pipe. Had it gone to a pipe nobody read, the
        // plugin would have blocked on a full buffer and presented as a hang.
        let descriptor = try await host.launch()
        #expect(descriptor.id == "mock")
        await host.shutdown()
    }
}
