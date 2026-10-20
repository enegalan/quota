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

    /// The floor a day is measured from when there is no reading from before it:
    /// the rise since the day's first reading, which leaves out whatever was
    /// spent before that reading and cannot be recovered from it.
    @Test("The floor is the rise since the day's first reading")
    func floorIsTheRiseSinceTheFirstReading() throws {
        let timeline = UsageTimeline(points: [try point(9, 45), try point(17, 55)])
        let first = try quotaInstant(2026, 9, 15, hour: 9)
        let floor = try #require(timeline.usedSinceFirstReadingOn(
            bucketID: "models",
            onOrAfter: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        ))
        #expect(floor.used == 10)
        #expect(floor.since == first)
    }

    @Test("A day with a single reading has no floor")
    func floorNeedsTwoReadings() throws {
        let timeline = UsageTimeline(points: [try point(9, 45)])
        #expect(timeline.usedSinceFirstReadingOn(
            bucketID: "models",
            onOrAfter: try quotaInstant(2026, 9, 15, hour: 0),
            to: try quotaInstant(2026, 9, 15, hour: 17),
            calendar: quotaCalendar
        ) == nil)
    }

    @Test("A day with no reading at all has no floor")
    func floorWithoutAnyReading() throws {
        let timeline = UsageTimeline(points: [])
        #expect(timeline.usedSinceFirstReadingOn(
            bucketID: "models",
            onOrAfter: try quotaInstant(2026, 9, 15, hour: 0),
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

    /// The one rule for a day's usage, which the calendar cell and the today
    /// block both read: exact when a reading from before the day exists.
    @Test("A day with a baseline is measured exactly, whole day or not")
    func usedDuringPastDay() throws {
        let timeline = UsageTimeline(points: [
            try TimelinePoint(
                recordedAt: try quotaInstant(2026, 9, 14, hour: 12),
                bucketID: "models",
                usagePercentage: 20
            ),
            try point(17, 55),
        ])
        // Asked for the whole of the 14th, which the reference instant is past:
        // both readings of that day fall inside it.
        let day = try quotaInstant(2026, 9, 14)
        #expect(timeline.usedDuring(
            bucketID: "models",
            day: day,
            to: try quotaInstant(2026, 9, 15, hour: 18),
            calendar: quotaCalendar
        ) == nil)
        // The 15th has a baseline from the 14th, and is measured from it.
        #expect(timeline.usedDuring(
            bucketID: "models",
            day: try quotaInstant(2026, 9, 15),
            to: try quotaInstant(2026, 9, 15, hour: 18),
            calendar: quotaCalendar
        ) == 35)
    }

    /// The case that produced the dash on today's calendar cell: the meter
    /// started or reset during the day, so there is no reading from before it,
    /// and the day is measured from the first reading the app did see.
    @Test("A day whose meter started during it falls back to the first-reading floor")
    func usedDuringFallsBackToTheFloor() throws {
        let timeline = UsageTimeline(points: [try point(10, 40), try point(17, 41)])
        #expect(timeline.usedDuring(
            bucketID: "models",
            day: try quotaInstant(2026, 9, 15),
            to: try quotaInstant(2026, 9, 15, hour: 18),
            calendar: quotaCalendar
        ) == 1)
    }

    /// A day that has not begun has spent nothing. That is a fact the timeline
    /// can state without readings, not a silence it should report as unknown.
    @Test("A day that has not begun has used nothing")
    func usedDuringFutureDayIsZero() throws {
        let timeline = UsageTimeline(points: [try point(10, 40), try point(17, 55)])
        #expect(timeline.usedDuring(
            bucketID: "models",
            day: try quotaInstant(2026, 9, 16),
            to: try quotaInstant(2026, 9, 15, hour: 18),
            calendar: quotaCalendar
        ) == 0)
    }

    @Test("A day with no usable reading is unknown, not zero")
    func usedDuringWithoutReadings() throws {
        #expect(UsageTimeline(points: []).usedDuring(
            bucketID: "models",
            day: try quotaInstant(2026, 9, 15),
            to: try quotaInstant(2026, 9, 15, hour: 18),
            calendar: quotaCalendar
        ) == nil)
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
