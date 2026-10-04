import Foundation
import Testing
@testable import Core

@Suite("UsageTimeline")
struct UsageTimelineTests {
    private func point(_ hour: Int, _ percentage: Double) throws -> TimelinePoint {
        try TimelinePoint(
            recordedAt: try quotaInstant(2026, 9, 15, hour: hour),
            bucketID: "models",
            usagePercentage: percentage
        )
    }

    @Test("Points are ordered oldest first regardless of the order supplied")
    func sortsOnConstruction() throws {
        let timeline = UsageTimeline(points: [
            try point(12, 30),
            try point(1, 10),
            try point(6, 20),
        ])
        #expect(timeline.points.map(\.recordedAt) == timeline.points.map(\.recordedAt).sorted())
        #expect(timeline.points.map(\.usagePercentage) == [10, 20, 30])
    }

    @Test("Today's usage is the change since the last reading before today")
    func usedToday() throws {
        let timeline = UsageTimeline(points: [
            try TimelinePoint(
                recordedAt: try quotaInstant(2026, 9, 14, hour: 23),
                bucketID: "models",
                usagePercentage: 40
            ),
            try point(9, 45),
            try point(17, 55),
        ])
        let used = timeline.usedOn(
            bucketID: "models",
            from: try quotaInstant(2026, 9, 15, hour: 9),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        )
        #expect(used == 15)
    }

    /// The case that makes the type exist. A provider reports a cumulative
    /// figure, so without a reading from before today the app cannot tell what
    /// was spent today, and reporting zero would tell the user the opposite of
    /// the truth.
    @Test("Usage today is unknown when there is no reading from before today")
    func unknownWithoutBaseline() throws {
        let timeline = UsageTimeline(points: [try point(9, 45)])
        let used = timeline.usedOn(
            bucketID: "models",
            from: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        )
        #expect(used == nil)
    }

    @Test("Usage today is unknown when no reading exists at all")
    func unknownWithoutAnyReading() throws {
        let timeline = UsageTimeline(points: [])
        #expect(timeline.usedOn(
            bucketID: "models",
            from: try quotaInstant(2026, 9, 15),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        ) == nil)
    }

    @Test("A reading exactly at the start of the day is a valid baseline")
    func baselineAtMidnight() throws {
        let timeline = UsageTimeline(points: [
            try TimelinePoint(
                recordedAt: try quotaInstant(2026, 9, 15, hour: 0),
                bucketID: "models",
                usagePercentage: 20
            ),
            try point(17, 35),
        ])
        let used = timeline.usedOn(
            bucketID: "models",
            from: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        )
        #expect(used == 15)
    }

    /// A provider restarting its metering produces a figure lower than the
    /// baseline. The difference is not a negative day.
    @Test("A figure that goes backwards yields no usage rather than a negative day")
    func backwardsReading() throws {
        let timeline = UsageTimeline(points: [
            try TimelinePoint(
                recordedAt: try quotaInstant(2026, 9, 14, hour: 23),
                bucketID: "models",
                usagePercentage: 60
            ),
            try point(17, 10),
        ])
        #expect(timeline.usedOn(
            bucketID: "models",
            from: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        ) == nil)
    }

    @Test("A bucket with no readings is unknown, not zero")
    func unknownBucket() throws {
        let timeline = UsageTimeline(points: [try point(17, 35)])
        #expect(timeline.usedOn(
            bucketID: "absent",
            from: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        ) == nil)
    }

    @Test("The latest reading is the most recent one at or before the reference")
    func latestPoint() throws {
        let timeline = UsageTimeline(points: [try point(1, 10), try point(12, 30), try point(17, 35)])
        let latest = try #require(timeline.latestPoint(
            bucketID: "models", asOf: try quotaInstant(2026, 9, 15, hour: 13)
        ))
        #expect(latest.usagePercentage == 30)
    }

    @Test("A point rejects an out-of-range percentage")
    func rejectsInvalidPercentage() {
        #expect(throws: QuotaDomainError.self) {
            try TimelinePoint(
                recordedAt: Date(),
                bucketID: "models",
                usagePercentage: 101
            )
        }
    }

    @Test("A timeline round trips through Codable")
    func codableRoundTrip() throws {
        let timeline = UsageTimeline(points: [try point(1, 10), try point(12, 30)])
        let data = try JSONEncoder().encode(timeline)
        #expect(try JSONDecoder().decode(UsageTimeline.self, from: data) == timeline)
    }
}
