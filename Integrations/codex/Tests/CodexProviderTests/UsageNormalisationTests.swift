import Foundation
import PluginKit
import Testing
@testable import QuotaPluginCodex

@Suite("Codex usage normalisation")
struct UsageNormalisationTests {
    private let day = "2026-04-08"

    @Test("The primary window ends where the limit resets")
    func primaryWindow() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CodexFixture.json("codex-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "primary_window" })
        #expect(bucket.displayName == "5-hour session")
        #expect(bucket.usagePercentage == 27.0)
        #expect(bucket.periodEnd == "2026-04-08T15:00:00Z")
        #expect(bucket.periodStart == "2026-04-08T10:00:00Z")
    }

    @Test("The secondary window runs back seven days")
    func secondaryWindow() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CodexFixture.json("codex-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "secondary_window" })
        #expect(bucket.displayName == "Weekly")
        #expect(bucket.usagePercentage == 4.0)
        #expect(bucket.periodEnd == "2026-04-14T15:00:00Z")
        #expect(bucket.periodStart == "2026-04-07T15:00:00Z")
    }

    @Test("An additional feature limit becomes a bucket of its own")
    func additionalLimit() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CodexFixture.json("codex-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "additional-fast-mode" })
        #expect(bucket.displayName == "Fast mode")
        #expect(bucket.usagePercentage == 12.0)
    }

    @Test("A figure is read as a percentage, not as a fraction")
    func percentageScale() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CodexFixture.json("codex-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "primary_window" })
        #expect(bucket.usagePercentage == 27.0)
    }

    @Test("A figure past the scale is clamped")
    func clampsBeyondTheScale() throws {
        let result = try UsageNormaliser.usageResult(
            from: [
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 140,
                        "limit_window_seconds": 18000,
                        "reset_at": 1_775_670_000,
                    ],
                ],
            ],
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first)
        #expect(bucket.usagePercentage == 100.0)
    }

    @Test("A window without a reset instant is left out")
    func omitsWindowsWithoutAReset() {
        let result = try? UsageNormaliser.usageResult(
            from: [
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 10,
                        "limit_window_seconds": 18000,
                    ],
                ],
            ],
            updatedAtDay: day
        )
        #expect(result == nil)
    }

    @Test("A reading is filed against the day it was asked for")
    func updatedAtDay() throws {
        let result = try UsageNormaliser.usageResult(
            from: try CodexFixture.json("codex-usage"),
            updatedAtDay: day
        )
        #expect(result.quotas.allSatisfy { $0.updatedAt == day })
    }
}
