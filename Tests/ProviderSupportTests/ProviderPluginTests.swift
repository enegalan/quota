import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

/// A handler whose answers a test can set, and whose throw a test can demand.
private struct FakeHandler: ProviderPluginHandler {
    let descriptor = ProviderDescriptor(
        id: "fake",
        displayName: "Fake",
        description: "A fake provider used by tests.",
        capabilities: [.automaticUsageRetrieval],
        suggestedRefreshIntervalSeconds: 300
    )

    var connectResult = ConnectResult(accountLabel: "work")
    var disconnectResult = ConnectResult(accountLabel: nil)
    var usage = UsageResult(quotas: [])
    var thrown: (any Error & Sendable)?
    var onConnect: @Sendable (ConnectRequest) -> Void = { _ in }

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        onConnect(request)
        if let thrown {
            throw thrown
        }
        return connectResult
    }

    func disconnect() -> ConnectResult {
        disconnectResult
    }

    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult {
        if let thrown {
            throw thrown
        }
        return usage
    }
}

/// A failure a plugin raises for itself, and names how it appears.
private struct FakeFailure: ProviderFailure {
    let providerError = ProviderError(code: .notAuthenticated, message: "Sign in again.")
}

/// A fault in the plugin, which is no one's idea of an answer.
private struct Boom: Error {}

/// A place a test can leave a result for another closure to write to.
private final class Recorder<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Answers every call by throwing whatever it was given.
private struct Raiser: ProviderPluginHandler {
    let descriptor = ProviderDescriptor(id: "fake", displayName: "Fake", description: "A fake.")
    let thrown: any Error & Sendable

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        throw thrown
    }

    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult {
        throw thrown
    }
}

private func fetchUsageRequest(_ day: String = "2026-10-17") -> PluginRequestPayload {
    .fetchUsage(FetchUsageRequest(localDate: day))
}

private func raised(_ error: any Error & Sendable) -> ProviderError? {
    let response = ProviderPlugin(handler: Raiser(thrown: error))
        .answer(PluginRequest(id: "req-1", method: .fetchUsage, payload: fetchUsageRequest()))
    guard case .failure(let failure) = response.result else {
        Issue.record("expected a failure, got \(response.result)")
        return nil
    }
    return failure
}

@Suite("ProviderPlugin routing")
struct ProviderPluginTests {
    private func request(_ method: PluginMethod, payload: PluginRequestPayload? = nil) -> PluginRequest {
        PluginRequest(id: "req-1", method: method, payload: payload)
    }

    @Test("describe answers the handler's descriptor, with this build's protocol range")
    func describe() {
        let response = ProviderPlugin(handler: FakeHandler()).answer(request(.describe))
        #expect(response.id == "req-1")
        guard case .success(.describe(let descriptor)) = response.result else {
            Issue.record("expected a describe, got \(response.result)")
            return
        }
        #expect(descriptor.id == "fake")
        #expect(descriptor.capabilities == [.automaticUsageRetrieval])
        #expect(descriptor.protocolRange == PluginProtocolConstants.hostRange)
        #expect(descriptor.suggestedRefreshIntervalSeconds == 300)
    }

    @Test("connect carries the request's credentials through to the handler")
    func connect() {
        let received = Recorder<String?>(nil)
        var handler = FakeHandler()
        handler.onConnect = { received.value = $0.credentials }

        let payload = PluginRequestPayload.connect(ConnectRequest(credentials: "user typed this"))
        let response = ProviderPlugin(handler: handler).answer(request(.connect, payload: payload))

        #expect(received.value == "user typed this")
        guard case .success(.connect(let result)) = response.result else {
            Issue.record("expected a connect, got \(response.result)")
            return
        }
        #expect(result.accountLabel == "work")
    }

    @Test("A connect with no payload is a connect with no credentials")
    func connectWithoutPayload() {
        let received = Recorder<String?>(nil)
        var handler = FakeHandler()
        handler.onConnect = { received.value = $0.credentials }

        let response = ProviderPlugin(handler: handler).answer(request(.connect))
        #expect(received.value == nil)
        guard case .success(.connect) = response.result else {
            Issue.record("expected a connect, got \(response.result)")
            return
        }
    }

    @Test("disconnect is answered in the same shape as connect: an account, possibly absent")
    func disconnect() {
        let response = ProviderPlugin(handler: FakeHandler()).answer(request(.disconnect))
        guard case .success(.connect(let result)) = response.result else {
            Issue.record("expected a connect payload, got \(response.result)")
            return
        }
        #expect(result.accountLabel == nil)
    }

    @Test("fetchUsage answers with the handler's usage")
    func fetchUsage() {
        var handler = FakeHandler()
        handler.usage = UsageResult(quotas: [
            ProviderUsage(
                externalID: "ext",
                displayName: "Quota",
                bucketID: "plan",
                bucketDisplayName: "Plan",
                usagePercentage: 10,
                periodStart: "2026-10-01",
                periodEnd: "2026-10-31",
                updatedAt: "2026-10-17"
            ),
        ])

        let response = ProviderPlugin(handler: handler)
            .answer(request(.fetchUsage, payload: fetchUsageRequest()))

        guard case .success(.usage(let usage)) = response.result else {
            Issue.record("expected usage, got \(response.result)")
            return
        }
        #expect(usage.quotas.first?.externalID == "ext")
        #expect(usage.quotas.first?.usagePercentage == 10)
    }

    @Test("fetchUsage with no day is refused rather than answered for an invented one")
    func fetchUsageWithoutDay() {
        let response = ProviderPlugin(handler: FakeHandler()).answer(request(.fetchUsage))
        guard case .failure(let error) = response.result else {
            Issue.record("expected a failure, got \(response.result)")
            return
        }
        #expect(error.code == .invalidResponse)
    }

    @Test("A method this build of the protocol does not have cannot even be read")
    func unknownMethod() {
        let message = Data(#"{"id":"req-1","method":"timeTravel","payload":null}"#.utf8)
        #expect(throws: DecodingError.self) {
            try PluginJSON.decoder.decode(PluginRequest.self, from: message)
        }
    }
}

@Suite("ProviderPlugin error translation")
struct ProviderPluginErrorTranslationTests {
    @Test("A ProviderError passes through untouched, message included")
    func providerErrorPassesThrough() {
        let original = ProviderError(code: .nothingToReport, message: "No subscription here.")
        let failure = raised(original)
        #expect(failure?.code == .nothingToReport)
        #expect(failure?.message == "No subscription here.")
    }

    @Test("A ProviderFailure is translated through its own mapping")
    func providerFailureIsTranslated() {
        let failure = raised(FakeFailure())
        #expect(failure?.code == .notAuthenticated)
        #expect(failure?.message == "Sign in again.")
    }

    @Test("Anything else is the plugin's own fault, and says nothing about what broke")
    func unexpectedErrorIsPluginError() {
        let failure = raised(Boom())
        #expect(failure?.code == .pluginError)
        #expect(failure?.message == ProviderError.defaultMessage(for: .pluginError))
    }

    @Test("A handler's failure on connect is translated the same way")
    func failuresAreTranslatedOnEveryMethod() {
        let response = ProviderPlugin(handler: Raiser(thrown: Boom()))
            .answer(PluginRequest(id: "req-1", method: .connect))
        guard case .failure(let failure) = response.result else {
            Issue.record("expected a failure, got \(response.result)")
            return
        }
        #expect(failure.code == .pluginError)
    }
}
