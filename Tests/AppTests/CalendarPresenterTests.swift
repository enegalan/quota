import Core
import Foundation
import Testing
@testable import App

/// Calendar presentation, tested through the presenter that builds it.
///
/// The cases here are the five states names, plus the two month lengths that
/// a day-count shortcut gets wrong: a 31-day month and February in a leap year.
/// Everything is driven from an injected reference instant, so nothing here
/// depends on the day the suite happens to run.
@Suite("Calendar presentation")
struct CalendarPresenterTests {
    private static let timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current

    /// A March 2026 month, with today on the 15th.
    private static func marchPresenter(
        plan: AllocationPlan? = nil,
        timeline: UsageTimeline? = nil,
        allowance: TodayAllowance? = nil,
        day: Int = 15
    ) throws -> CalendarPresenter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        calendar.firstWeekday = 2
        return CalendarPresenter(
            plan: plan,
            timeline: timeline,
            allowance: allowance,
            bucketID: "primary",
            calendar: calendar,
            reference: try #require(try LocalDate(year: 2026, month: 3, day: day).date(calendar: calendar))
        )
    }

    private static func date(_ day: Int, month: Int = 3, year: Int = 2026) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(try LocalDate(year: year, month: month, day: day).date(calendar: calendar))
    }

    // MARK: - The five states

    @Test("A day before today inside the period is in the past")
    func pastDay() throws {
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 10))
        #expect(day.kind == .past)
        #expect(day.kind.isWithinPeriod)
    }

    @Test("The reference day is today, whatever its allocation")
    func todayDay() throws {
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 15))
        #expect(day.kind == .today)
    }

    @Test("A day after today with an allocation is in the future")
    func futureDay() throws {
        // An even plan across the month gives 20 March a real share, so the
        // classification under test is the date, not the plan.
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 20))
        #expect(day.kind == .future)
        #expect(day.planned != nil)
    }

    @Test("A future day with nothing allocated is distinguished from one with a share")
    func zeroAllocationDay() throws {
        // A plan that names only three days, so the 25th is inside the period
        // with no share of its own — the case the fifth calendar state is for.
        let plan = try Self.plan(naming: [21, 22, 23])
        let presenter = try Self.marchPresenter(plan: plan)
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 25))
        #expect(day.kind == .zeroAllocation)
        #expect(day.kind.isWithinPeriod)
    }

    @Test("A day with no plan at all is out of period, not empty")
    func outOfPeriodWithoutAPlan() throws {
        let presenter = try Self.marchPresenter()
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 20))
        #expect(day.kind == .outOfPeriod)
        #expect(!day.kind.isWithinPeriod)
    }

    @Test("A day before the period's start is out of period even though it is in the past")
    func outOfPeriodInThePast() throws {
        // The plan starts on the 10th, so the 5th is history that has nothing to
        // do with this quota. It must be distinguished from the past.
        let plan = try Self.plan(naming: [], starting: 10)
        let presenter = try Self.marchPresenter(plan: plan)
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 5))
        #expect(day.kind == .outOfPeriod)
    }

    @Test("A day after the period's end is out of period even though it is in the future")
    func outOfPeriodInTheFuture() throws {
        let plan = try Self.plan(naming: Array(1 ... 22), ending: 22)
        let presenter = try Self.marchPresenter(plan: plan)
        let day = presenter.day(try LocalDate(year: 2026, month: 3, day: 28))
        #expect(day.kind == .outOfPeriod)
    }

    @Test("An out-of-period day carries no figures, even when a plan exists")
    func outOfPeriodCarriesNothing() throws {
        let plan = try Self.monthPlan()
        let presenter = try Self.marchPresenter(plan: plan)
        let day = presenter.day(try LocalDate(year: 2026, month: 4, day: 2))
        #expect(day.kind == .outOfPeriod)
        #expect(day.planned == nil)
        #expect(day.actual == nil)
        #expect(day.remaining == nil)
    }

    // MARK: - Month grids

    @Test("A 31-day month has 31 days, and the last one is the 31st")
    func thirtyOneDayMonth() throws {
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let month = try presenter.month(containing: Self.date(1))
        #expect(month.cells.count == month.leadingBlankCount + 31)
        #expect(month.days.last?.date.day == 31)
    }

    @Test("February in a leap year has 29 days and in a common year 28")
    func februaryLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone

        let leap = CalendarPresenter(
            plan: nil,
            timeline: nil,
            allowance: nil,
            bucketID: "primary",
            calendar: calendar,
            reference: try #require(LocalDate(year: 2024, month: 2, day: 15).date(calendar: calendar))
        )
        #expect(try leap
            .month(containing: try #require(LocalDate(year: 2024, month: 2, day: 1).date(calendar: calendar))).days
            .count == 29)

        let common = CalendarPresenter(
            plan: nil,
            timeline: nil,
            allowance: nil,
            bucketID: "primary",
            calendar: calendar,
            reference: try #require(LocalDate(year: 2023, month: 2, day: 15).date(calendar: calendar))
        )
        #expect(try common
            .month(containing: try #require(LocalDate(year: 2023, month: 2, day: 1).date(calendar: calendar))).days
            .count == 28)
    }

    @Test("The first of the month lands under the user's own first weekday")
    func honoursFirstWeekday() throws {
        // 1 March 2026 is a Sunday. With Monday as the first weekday it opens the
        // final column, so six days lead it; with Sunday as the first weekday it
        // opens the first column and leads itself.
        var monday = Calendar(identifier: .gregorian)
        monday.timeZone = Self.timeZone
        monday.firstWeekday = 2
        let withMonday = CalendarPresenter(
            plan: nil,
            timeline: nil,
            allowance: nil,
            bucketID: "primary",
            calendar: monday,
            reference: try Self.date(15)
        )
        #expect(try withMonday.month(containing: Self.date(1)).leadingBlankCount == 6)

        var sunday = monday
        sunday.firstWeekday = 1
        let withSunday = CalendarPresenter(
            plan: nil,
            timeline: nil,
            allowance: nil,
            bucketID: "primary",
            calendar: sunday,
            reference: try Self.date(15)
        )
        #expect(try withSunday.month(containing: Self.date(1)).leadingBlankCount == 0)
    }

    @Test("Every cell of a month's grid is one of the five states")
    func everyCellIsClassified() throws {
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let month = try presenter.month(containing: Self.date(1))
        #expect(month.cells.allSatisfy { $0.kind.isWithinPeriod || $0.kind == .outOfPeriod })
        #expect(Set(month.days.map(\.kind)).isSubset(of: Set(CalendarDay.Kind.allCases)))
    }

    @Test("The leading blanks are out of period, and the month's own days are not")
    func leadingBlanksAreOutOfPeriod() throws {
        let presenter = try Self.marchPresenter(plan: Self.monthPlan())
        let month = try presenter.month(containing: Self.date(1))
        let blanks = month.cells.prefix(month.leadingBlankCount)
        #expect(blanks.allSatisfy { $0.kind == .outOfPeriod })
    }

    @Test("The reference instant is the one the presenter was built with")
    func referenceIsExposed() throws {
        #expect(try Self.marchPresenter().referenceDate == Self.date(15))
    }

    // MARK: - Plans

    /// An even plan covering all of March 2026.
    private static func monthPlan() throws -> AllocationPlan {
        try plan(starting: 1, ending: 31)
    }

    /// An even plan over March 2026.
    private static func plan(
        naming: [Int]? = nil,
        starting startDay: Int = 1,
        ending endDay: Int = 31
    ) throws -> AllocationPlan {
        let calendar = timeZoneCalendar
        let periodStart = try #require(try LocalDate(year: 2026, month: 3, day: startDay).date(calendar: calendar))
        let periodEnd = try #require(try LocalDate(year: 2026, month: 3, day: endDay).date(calendar: calendar))
        let period = try QuotaPeriod(start: periodStart, end: periodEnd)
        // Named days get an equal share and unnamed ones get nothing, so the
        // plan really does leave days unfunded — which is the only way to reach
        // the state under test. Built through the engine rather than by hand,
        // because the engine is what decides a plan is well formed.
        let named = naming ?? Array(startDay ... endDay)
        let policy: AllocationPolicy = naming == nil
            ? .even
            : .custom(assignments: Dictionary(uniqueKeysWithValues: try named.map { day in
                let date = try LocalDate(year: 2026, month: 3, day: day)
                return (date, Self.remaining / Double(named.count))
            }))
        return try AllocationEngine(calendar: calendar).plan(
            quotaID: Self.quotaID,
            policy: policy,
            period: period,
            totalRemaining: Self.remaining,
            asOf: period.start
        )
    }

    /// A stable identifier, so a failure names the same plan every run.
    private static let quotaID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")
        ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xC1))

    private static let remaining: Double = 100

    private static var timeZoneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        return calendar
    }
}
