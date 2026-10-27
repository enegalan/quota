import Foundation
import PluginKit
import ProviderSupport
import Testing
@testable import QuotaPluginCopilot

@Suite("Copilot usage normalisation")
struct UsageNormalisationTests {
    private let day = "2026-10-27"

    @Test("Free-limited chat and completions become buckets")
    func freeLimitedSnapshots() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CopilotFixture.json("copilot-free-limited"),
            updatedAtDay: day
        )
        let chat = try #require(result.quotas.first { $0.bucketID == "chat" })
        #expect(chat.displayName == "Chat")
        #expect(chat.usagePercentage == 66.0)
        #expect(chat.periodEnd == "2026-11-01T00:00:00Z")
        #expect(chat.periodStart == "2026-10-01T00:00:00Z")

        let completions = try #require(result.quotas.first { $0.bucketID == "completions" })
        #expect(completions.usagePercentage == 0.0)

        #expect(result.quotas.allSatisfy { $0.bucketID != "premium_interactions" })
    }

    @Test("Legacy premium requests use entitlement counters")
    func legacyPremium() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CopilotFixture.json("copilot-legacy-premium"),
            updatedAtDay: day
        )
        let premium = try #require(result.quotas.first { $0.bucketID == "premium_interactions" })
        #expect(premium.displayName == "Premium requests")
        #expect(premium.usagePercentage == 20.0)
        #expect(premium.periodEnd == "2025-02-15T00:00:00Z")
        #expect(premium.periodStart == "2025-01-15T00:00:00Z")

        let chat = try #require(result.quotas.first { $0.bucketID == "chat" })
        #expect(chat.usagePercentage == 5.0)

        #expect(result.quotas.allSatisfy { $0.bucketID != "completions" })
    }

    @Test("Limited-user counters without snapshots still meter")
    func limitedCounters() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CopilotFixture.json("copilot-limited-counters"),
            updatedAtDay: day
        )
        let chat = try #require(result.quotas.first { $0.bucketID == "chat" })
        #expect(chat.usagePercentage == 18.0)
        #expect(chat.periodEnd == "2025-02-11T00:00:00Z")

        let completions = try #require(result.quotas.first { $0.bucketID == "completions" })
        #expect(completions.usagePercentage == 0.0)
    }

    @Test("A figure past the scale is clamped")
    func clampsBeyondTheScale() throws {
        let result = try UsageNormaliser.usageResult(
            from: [
                "quota_reset_date_utc": "2026-11-01T00:00:00Z",
                "quota_snapshots": [
                    "chat": [
                        "has_quota": true,
                        "unlimited": false,
                        "percent_remaining": -10.0,
                    ],
                ],
            ],
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first)
        #expect(bucket.usagePercentage == 100.0)
    }

    @Test("An empty payload is not a reading")
    func rejectsEmptyPayload() {
        #expect(throws: UsageDataError.noUsableMeter) {
            try UsageNormaliser.usageResult(from: [:], updatedAtDay: day)
        }
    }
}
