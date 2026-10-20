import Core
import Foundation
import Testing
@testable import App

/// What a calendar day cell says about usage and what is left.
///
/// Kept apart from the states suite because these are the figures, not the
/// classification: a day can be classified correctly and still show a dash for
/// spending that is known to be zero, which is the bug these cover.
@Suite("A calendar day's figures")
struct CalendarDayFiguresTests {
    private static let timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current

    private static func date(_ day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(try LocalDate(year: 2026, month: 3, day: day).date(calendar: calendar))
    }

    /// An even plan covering all of March 2026.
    private static func monthPlan() throws -> AllocationPlan {
        let calendar = SummaryFixture.calendar
        let start = try #require(
            try LocalDate(year: 2026, month: 3, day: 1).date(calendar: calendar)
        )
        let end = try #require(
            try LocalDate(year: 2026, month: 3, day: 31).date(calendar: calendar)
        )
        return try AllocationEngine(calendar: calendar).plan(
            quotaID: SummaryFixture.quotaID,
            policy: .even,
            period: try QuotaPeriod(start: start, end: end),
            totalRemaining: 100,
            asOf: start
        )
    }

    /// The bug that produced a dash on today's cell: the meter reset during the
    /// day, so the cell had no baseline and the timeline reported "unknown"
    /// while the today block, which falls back to the first-reading floor,
    /// showed a real figure. The cell and the block must agree about one day.
    @Test("Today's cell matches the today block when the meter started today")
    func todayCellMatchesTheBlockWithoutABaseline() throws {
        let calendar = SummaryFixture.calendar
        let noon = try #require(
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Self.date(15))
        )
        let morning = try #require(
            calendar.date(bySettingHour: 10, minute: 7, second: 0, of: Self.date(15))
        )
        let timeline = UsageTimeline(points: [
            try TimelinePoint(recordedAt: morning, bucketID: "primary", usagePercentage: 40),
            try TimelinePoint(recordedAt: noon, bucketID: "primary", usagePercentage: 41),
        ])
        let allowance = TodayAllowance(
            date: try LocalDate(year: 2026, month: 3, day: 15),
            suggested: 5,
            usedToday: 1
        )
        let presenter = CalendarPresenter(
            plan: try Self.monthPlan(),
            timeline: timeline,
            allowance: allowance,
            bucketID: "primary",
            calendar: calendar,
            reference: noon
        )

        let today = presenter.day(try LocalDate(year: 2026, month: 3, day: 15))
        #expect(today.actual == 1)
        #expect(today.remaining == allowance.remainingAfterToday)
    }

    /// A day that has not begun has spent nothing, and its remainder is the
    /// whole of its share. The cell used to show a dash for both, which reads as
    /// "unknown" for a day whose spending is known to be zero.
    @Test("A future day has used nothing and keeps its whole share as remaining")
    func futureDayHasZeroUsedAndFullRemaining() throws {
        let presenter = try Self.presenter(plan: try Self.monthPlan())
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 20))
        #expect(day.kind == .future)
        #expect(day.actual == 0)
        let planned = try #require(day.planned)
        #expect(day.remaining == planned)
    }

    /// A future day whose usage cannot be established is still known to have
    /// spent nothing, so it says zero rather than a dash, with no history at all.
    @Test("A future day has used nothing even with no history to read")
    func futureDayWithoutHistory() throws {
        let presenter = try Self.presenter(plan: try Self.monthPlan(), timeline: nil)
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 20))
        #expect(day.actual == 0)
    }

    /// The past is measured, not assumed: a past day's usage stands on the
    /// readings that cover it, and its remainder is what the day ended short by.
    @Test("A past day carries its measured usage and remainder")
    func pastDayFigures() throws {
        let calendar = SummaryFixture.calendar
        let midnight = calendar.startOfDay(for: try Self.date(10))
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let timeline = UsageTimeline(points: [
            try TimelinePoint(recordedAt: midnight, bucketID: "primary", usagePercentage: 50),
            try TimelinePoint(recordedAt: end, bucketID: "primary", usagePercentage: 52),
        ])
        let presenter = try Self.presenter(
            plan: try Self.monthPlan(),
            timeline: timeline,
            reference: try #require(
                calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Self.date(15))
            )
        )

        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 10))
        #expect(day.actual == 2)
        let planned = try #require(day.planned)
        #expect(day.remaining == planned - 2)
    }

    /// A day whose usage cannot be established for a reason other than being in
    /// the future still says so, rather than reporting a confident zero.
    @Test("A past day with no history says nothing rather than zero")
    func pastDayWithoutHistory() throws {
        let presenter = try Self.presenter(plan: try Self.monthPlan(), timeline: nil)
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 10))
        #expect(day.kind == .past)
        #expect(day.actual == nil)
        #expect(day.remaining == nil)
    }

    private static func presenter(
        plan: AllocationPlan?,
        timeline: UsageTimeline? = nil,
        reference: Date? = nil
    ) throws -> CalendarPresenter {
        CalendarPresenter(
            plan: plan,
            timeline: timeline,
            allowance: nil,
            bucketID: "primary",
            calendar: SummaryFixture.calendar,
            reference: try reference ?? date(15)
        )
    }
}
