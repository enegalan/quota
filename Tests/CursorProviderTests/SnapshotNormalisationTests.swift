import Core
import Foundation
import PluginKit
import Testing
@testable import Platform

@Suite("Snapshot normalisation")
struct SnapshotNormalisationTests {
    @Test("Current-period fixture becomes a valid UsageSnapshot with two pools")
    func currentPeriod() throws {
        let result = try CursorFixtureLoader.usageResult(
            fromCurrentPeriod: CursorFixtureLoader.json("get-current-period-usage"),
            day: "2026-09-26"
        )
        let snapshot = try SnapshotNormaliser.snapshot(from: result, recordedAt: Date())
        #expect(snapshot.buckets.count == 2)
        #expect(snapshot.buckets[0].id == "plan")
        #expect(snapshot.buckets[0].usagePercentage == 11.306666666666667)
        #expect(snapshot.buckets[1].id == "api")
        #expect(snapshot.buckets[1].usagePercentage == 0)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // Read through the pool rather than off the reading: the whole point of
        // the period living on the bucket is that this is where the window for a
        // pool is found.
        let period = try #require(snapshot.period(forBucket: "plan"))
        #expect(calendar.component(.day, from: period.start) == 22)
        #expect(calendar.component(.day, from: period.end) == 22)
    }

    @Test("Usage-summary fallback agrees on period and plan percentage")
    func summaryFallback() throws {
        let current = try SnapshotNormaliser.snapshot(
            from: CursorFixtureLoader.usageResult(
                fromCurrentPeriod: CursorFixtureLoader.json("get-current-period-usage"),
                day: "2026-09-26"
            ),
            recordedAt: Date()
        )
        let summary = try SnapshotNormaliser.snapshot(
            from: CursorFixtureLoader.usageResult(
                fromSummary: CursorFixtureLoader.json("usage-summary"),
                day: "2026-09-26"
            ),
            recordedAt: Date()
        )
        let currentPeriod = try #require(current.period(forBucket: "plan"))
        let summaryPeriod = try #require(summary.period(forBucket: "plan"))
        #expect(abs(currentPeriod.start.timeIntervalSince(summaryPeriod.start)) < 1)
        #expect(abs(currentPeriod.end.timeIntervalSince(summaryPeriod.end)) < 1)
        #expect(current.buckets[0].usagePercentage == summary.buckets[0].usagePercentage)
    }

    @Test("Pools sharing one billing cycle each keep that window")
    func sharedWindowLandsOnEveryPool() throws {
        let snapshot = try SnapshotNormaliser.snapshot(
            from: CursorFixtureLoader.usageResult(
                fromCurrentPeriod: CursorFixtureLoader.json("get-current-period-usage"),
                day: "2026-09-26"
            ),
            recordedAt: Date()
        )
        // Cursor's two pools are metered over the same cycle, so they must not be
        // forced to differ — the per-bucket window is only there for providers
        // whose limits genuinely reset at different instants.
        #expect(snapshot.buckets[0].period == snapshot.buckets[1].period)
    }

    @Test("An unknown on-demand cap is absent from the fixture, not zero")
    func unknownCapAbsent() throws {
        let summary = try CursorFixtureLoader.json("usage-summary")
        let onDemand = try #require(
            (summary["individualUsage"] as? [String: Any])?["onDemand"] as? [String: Any]
        )
        #expect(onDemand["limit"] is NSNull || onDemand["limit"] == nil)
        #expect((onDemand["enabled"] as? Bool) == false)
    }

    @Test("Legacy request-count fixture has no usable cap")
    func legacyHasNoCap() throws {
        let legacy = try CursorFixtureLoader.json("legacy-usage")
        let gpt = try #require(legacy["gpt-4"] as? [String: Any])
        #expect(gpt["maxRequestUsage"] is NSNull || gpt["maxRequestUsage"] == nil)
    }
}
