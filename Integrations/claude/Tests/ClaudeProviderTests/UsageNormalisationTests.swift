import Foundation
import PluginKit
import Testing
@testable import QuotaPluginClaude

@Suite("Claude usage normalisation")
struct UsageNormalisationTests {
    private let day = "2026-04-08"

    @Test("The five-hour window ends where the limit resets")
    func fiveHourWindow() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "five_hour" })
        #expect(bucket.displayName == "5-hour session")
        #expect(bucket.usagePercentage == 6.0)
        #expect(bucket.periodEnd == "2026-04-08T18:59:59Z")
        #expect(bucket.periodStart == "2026-04-08T13:59:59Z")
    }

    @Test("The weekly window runs back seven days")
    func sevenDayWindow() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "seven_day" })
        #expect(bucket.displayName == "Weekly")
        #expect(bucket.usagePercentage == 35.0)
        #expect(bucket.periodEnd == "2026-04-14T16:59:59Z")
        #expect(bucket.periodStart == "2026-04-07T16:59:59Z")
    }

    @Test("A limit that is not reported is left out")
    func omitsAbsentLimits() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        #expect(result.quotas.allSatisfy { $0.bucketID != "seven_day_sonnet" })
    }

    @Test("A per-model weekly limit becomes a bucket of its own")
    func scopedLimit() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "scoped-fable" })
        #expect(bucket.displayName == "Weekly Fable")
        #expect(bucket.usagePercentage == 21.0)
        #expect(bucket.periodStart == "2026-04-07T17:59:59Z")
    }

    @Test("A limit of another kind is left out")
    func ignoresOtherLimitKinds() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        #expect(result.quotas.allSatisfy { $0.usagePercentage != 99.0 })
    }

    @Test("The extra usage figure is the share of the monthly limit")
    func extraUsage() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "extra_usage" })
        #expect(bucket.usagePercentage == 12.5)
    }

    @Test("A figure is read as a percentage, not as a fraction")
    func percentageScale() throws {
        // Claude reports 6.0 for six percent. A reader that treated the number
        // as a fraction would report six hundred percent and the limit would
        // look spent.
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first { $0.bucketID == "five_hour" })
        #expect(bucket.usagePercentage == 6.0)
    }

    @Test("A figure past the scale is clamped")
    func clampsBeyondTheScale() throws {
        let result = try UsageNormaliser.usageResult(
            from: ["five_hour": ["utilization": 140.0, "resets_at": "2026-04-08T18:59:59Z"]],
            updatedAtDay: day
        )
        let bucket = try #require(result.quotas.first)
        #expect(bucket.usagePercentage == 100.0)
    }

    @Test("A limit without a reset instant is left out")
    func omitsLimitsWithoutAReset() throws {
        let result = try UsageNormaliser.usageResult(
            from: ["five_hour": ["utilization": 10.0]],
            updatedAtDay: day
        )
        #expect(result.quotas.isEmpty)
    }

    @Test("A reading is filed against the day it was asked for")
    func updatedAtDay() throws {
        let result = try UsageNormaliser.usageResult(
            from: try ClaudeFixture.json("claude-usage"),
            updatedAtDay: day
        )
        #expect(result.quotas.allSatisfy { $0.updatedAt == day })
    }
}
