import Foundation
import PluginKit

/// A provider that meters nothing, so the application can be used and tested
/// without connecting anything.
///
/// Scripted rather than random, and reading nothing from the machine. A number
/// that changed on every launch would make a bug impossible to reproduce, and a
/// provider is the one place in the application that must not reach outside its
/// own process — so this one opens no files, opens no sockets, and has no clock
/// beyond the date the host sends it.
private struct MockProvider {
    static let displayName = "Mock provider"

    /// A scripted run of usage percentages, for one bucket.
    ///
    /// Fixed, so a reading can also be computed by hand in a test. Named rather
    /// than inline so a test can read the same list this answers from instead of
    /// copying the numbers out of the implementation.
    static let readings: [Double] = MockConstants.usagePercentages

    /// Which scripted value comes next.
    ///
    /// A counter in the process rather than a global, because a plugin is a
    /// process: nothing else is reading it, and a mutable global would be the one
    /// place in a provider that Swift's concurrency checking has to be lied to
    /// about. Advances once per fetch and then holds, so a long session settles
    /// on a full quota rather than cycling back to an empty one and looking like
    /// an allowance that had been restored.
    private var index = 0

    mutating func nextUsage() -> Double {
        defer {
            if index < MockProvider.readings.count - 1 {
                index += 1
            }
        }
        return MockProvider.readings[index]
    }

    static let descriptor = ProviderDescriptor(
        id: MockConstants.identifier,
        displayName: displayName,
        description: "A scripted provider that meters nothing.",
        capabilities: [
            .automaticUsageRetrieval, .historicalUsage, .multipleQuotas,
        ],
        protocolRange: PluginProtocolConstants.hostRange
    )
}

// The mock's state for one run.
//
// A struct passed through the loop rather than a global or a `static var`. A
// plugin is a plain sequential process — one loop, one request at a time, one
// counter — and threading that one piece of state through a function is what
// lets the type system say so instead of the code having to.

/// The day a reading is dated to, from the host's own request.
///
/// The host's date rather than a clock read here: a provider that called
/// `Date()` would report against its own time zone and its own midnight, and the
/// day a quota is measured over is the user's day, not the plugin's.
private func today(from request: PluginRequest) -> String {
    if case .fetchUsage(let payload) = request.payload {
        return payload.localDate
    }
    return MockConstants.fallbackDate
}

private func answer(_ request: PluginRequest, mock: inout MockProvider) -> PluginResponse {
    let payload: PluginResponsePayload
    switch request.method {
    case .describe:
        payload = .describe(MockProvider.descriptor)
    case .connect:
        // Whatever was offered is accepted, and the account name is echoed back so
        // a test can assert the credential reached the plugin without this one
        // having to know what a real provider's credential means.
        payload = .connect(ConnectResult(accountLabel: MockConstants.accountLabel))
    case .disconnect:
        payload = .connect(ConnectResult(accountLabel: nil))
    case .fetchUsage:
        let day = today(from: request)
        payload = .usage(
            UsageResult(
                quotas: [
                    ProviderUsage(
                        externalID: "mock-external",
                        displayName: "Mock Quota",
                        bucketID: MockConstants.bucketID,
                        bucketDisplayName: "Models",
                        usagePercentage: mock.nextUsage(),
                        periodStart: day,
                        periodEnd: day,
                        updatedAt: day
                    ),
                ],
                supportsHistorical: true
            )
        )
    }
    return PluginResponse(id: request.id, result: .success(payload))
}

/// Answers every request until the host closes stdin.
private func run() throws {
    let side = PluginSide()
    var mock = MockProvider()
    while let request = side.nextRequest() {
        try side.write(answer(request, mock: &mock))
    }
}

try run()
