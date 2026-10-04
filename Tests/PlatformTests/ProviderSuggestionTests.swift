import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Provider-suggested intervals")
struct ProviderSuggestionTests {
    private typealias Fixture = SyncFixture

    /// A harness that has read once, so a schedule has an instant to count from.
    private func refreshedHarness(
        suggestion: TimeInterval
    ) async throws -> (SyncFixture.Harness, Date) {
        let now = Fixture.periodStart
        let provider = ScriptedProvider(always: .success(try Fixture.snapshot(updatedAt: now)))
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        try await harness.coordinator.noteSuggestedRefreshInterval(
            suggestion,
            for: harness.quota.providerID
        )
        return (harness, now)
    }

    @Test("A provider's own interval is the one used")
    func providerSuggestionIsHonoured() async throws {
        let (harness, now) = try await refreshedHarness(suggestion: 20 * 60)

        let record = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(record.suggestedRefreshInterval == 20 * 60.0)
        let scheduled = try await harness.coordinator.nextRefresh(
            for: harness.quota.providerID,
            jitterSource: { RefreshConstants.jitterMidpoint }
        )
        #expect(scheduled == now.addingTimeInterval(20 * 60))
    }

    @Test("A provider asking for less than the minimum is held to the minimum")
    func providerSuggestionIsClamped() async throws {
        let (harness, now) = try await refreshedHarness(suggestion: 1)

        let scheduled = try await harness.coordinator.nextRefresh(
            for: harness.quota.providerID,
            jitterSource: { RefreshConstants.jitterMidpoint }
        )
        #expect(scheduled == now.addingTimeInterval(RefreshConstants.minimumPollInterval))
    }

    @Test("A provider asking for more than the maximum is held to the maximum")
    func providerSuggestionIsCapped() async throws {
        let (harness, now) = try await refreshedHarness(suggestion: 24 * 60 * 60)

        let scheduled = try await harness.coordinator.nextRefresh(
            for: harness.quota.providerID,
            jitterSource: { RefreshConstants.jitterMidpoint }
        )
        #expect(scheduled == now.addingTimeInterval(RefreshConstants.maximumPollInterval))
    }

    @Test("A suggestion survives the record being rewritten by failures")
    func suggestionSurvivesFailureAccounting() async throws {
        let now = Fixture.periodStart
        let provider = ScriptedProvider([
            .success(try Fixture.snapshot(updatedAt: now)),
            .failure(Fixture.failure(.rateLimited, at: now)),
            .failure(Fixture.failure(.rateLimited, at: now)),
        ])
        let harness = try await Fixture.makeHarness(fetcher: provider, now: now)
        _ = try await harness.coordinator.refresh(quotaID: harness.quota.id)
        try await harness.coordinator.noteSuggestedRefreshInterval(
            20 * 60,
            for: harness.quota.providerID
        )

        _ = try await harness.coordinator(readingAt: now).refresh(quotaID: harness.quota.id)
        _ = try await harness.coordinator(readingAt: now).refresh(quotaID: harness.quota.id)

        let record = try #require(await harness.providers.provider(harness.quota.providerID))
        #expect(record.suggestedRefreshInterval == 20 * 60.0)
        #expect(record.consecutiveFailures == 2)
    }

    @Test("A descriptor's suggestion decodes, and an older descriptor without it still does")
    func descriptorSuggestionIsOptional() throws {
        // Assembled rather than encoded, because the point is that a peer built
        // before the field existed still decodes, which encoding a current
        // descriptor and deleting a key afterwards cannot demonstrate.
        //
        // The range is written out longhand because this is also the only place
        // the wire shape of a version is pinned: it is the dotted string a person
        // writes, and a plugin compiled against another host has to read it.
        var object: [String: Any] = [
            "id": "mock",
            "displayName": "Mock",
            "description": "d",
            "capabilities": 0,
            "protocolRange": [
                "minimum": "1.0.0",
                "maximum": "1.9.0",
            ],
        ]
        object["suggestedRefreshIntervalSeconds"] = 1200
        let modern = try JSONDecoder().decode(
            ProviderDescriptor.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        object.removeValue(forKey: "suggestedRefreshIntervalSeconds")
        let older = try JSONDecoder().decode(
            ProviderDescriptor.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(modern.suggestedRefreshIntervalSeconds == 1200)
        #expect(older.suggestedRefreshIntervalSeconds == nil)
    }
}
