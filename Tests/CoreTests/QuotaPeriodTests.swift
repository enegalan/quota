import Foundation
import Testing
@testable import Core

private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    return calendar
}()

/// Builds an instant from components rather than from a string.
///
/// A `DateFormatter` would work, but `dateFormat` is deprecated and this SDK
/// silently falls back to a default when it is set, which turns a wrong test
/// helper into a passing test suite that proves nothing.
private func instant(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0
) throws -> Date {
    let components = DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute
    )
    return try #require(fixedCalendar.date(from: components))
}

private func instant(_ iso: String) throws -> Date {
    let parsed = try LocalDate(iso: iso)
    return try #require(parsed.date(calendar: fixedCalendar))
}

@Suite("QuotaPeriod")
struct QuotaPeriodTests {
    @Test("A period that runs backwards is rejected")
    func rejectsInvertedPeriod() throws {
        let start = try instant("2026-09-01")
        let end = try instant("2026-08-31")
        #expect(throws: QuotaDomainError.self) { try QuotaPeriod(start: start, end: end) }
    }

    @Test("A zero-length period is valid and immediately expired")
    func acceptsZeroLengthPeriod() throws {
        let moment = try instant(2026, 9, 1, hour: 12)
        let period = try QuotaPeriod(start: moment, end: moment)
        #expect(period.totalDays(calendar: fixedCalendar) == 1)
        #expect(period.status(asOf: moment) == .active)
    }

    @Test("Status is derived from the reference instant")
    func status() throws {
        let start = try instant("2026-09-01")
        let end = try instant("2026-09-30")
        let period = try QuotaPeriod(start: start, end: end)

        #expect(try period.status(asOf: instant("2026-08-31")) == .future)
        #expect(period.status(asOf: start) == .active)
        #expect(try period.status(asOf: instant("2026-09-15")) == .active)
        #expect(period.status(asOf: end) == .active)
        #expect(try period.status(asOf: instant("2026-10-01")) == .expired)
    }

    @Test("Both boundary instants belong to the active range")
    func boundariesAreInclusive() throws {
        let start = try instant("2026-09-01")
        let end = try instant("2026-09-30")
        let period = try QuotaPeriod(start: start, end: end)
        #expect(period.status(asOf: start) == .active)
        #expect(period.status(asOf: end) == .active)
    }

    @Test("Total days counts both endpoints")
    func totalDays() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        #expect(period.totalDays(calendar: fixedCalendar) == 30)

        let singleDay = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-01")
        )
        #expect(singleDay.totalDays(calendar: fixedCalendar) == 1)
    }

    @Test("Remaining days counts full days after today through the final day")
    func remainingDays() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        #expect(try period.remainingDays(through: instant("2026-09-01"), calendar: fixedCalendar) == 29)
        #expect(try period.remainingDays(through: instant("2026-09-15"), calendar: fixedCalendar) == 15)
        #expect(try period.remainingDays(through: instant("2026-09-30"), calendar: fixedCalendar) == 0)
    }

    @Test("Remaining days is zero outside the active range")
    func remainingDaysOutsideRange() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        #expect(try period.remainingDays(through: instant("2026-08-31"), calendar: fixedCalendar) == 0)
        #expect(try period.remainingDays(through: instant("2026-10-01"), calendar: fixedCalendar) == 0)
    }

    @Test("Elapsed days is inclusive of the first day and of today")
    func elapsedDays() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        #expect(try period.elapsedDays(since: instant("2026-09-01"), calendar: fixedCalendar) == 1)
        #expect(try period.elapsedDays(since: instant("2026-09-15"), calendar: fixedCalendar) == 15)
        #expect(try period.elapsedDays(since: instant("2026-09-30"), calendar: fixedCalendar) == 30)
    }

    @Test("Elapsed days is zero before the period starts")
    func elapsedDaysBeforeStart() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        #expect(try period.elapsedDays(since: instant("2026-08-31"), calendar: fixedCalendar) == 0)
    }

    @Test("Elapsed plus remaining equals the total")
    func elapsedPlusRemainingIsTotal() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        for day in 1 ... 30 {
            let reference = try instant(2026, 9, day)
            // Elapsed includes today; remaining is only the days after today.
            let elapsed = period.elapsedDays(since: reference, calendar: fixedCalendar)
            let remaining = period.remainingDays(through: reference, calendar: fixedCalendar)
            #expect(elapsed + remaining == period.totalDays(calendar: fixedCalendar))
        }
    }

    @Test("Total days is measured in the caller's calendar, not in UTC")
    func totalDaysDependsOnCalendar() throws {
        // 1 September 00:00 to 30 September 23:59:59 in Madrid. In UTC the start
        // falls on 31 August, so a UTC count says 31 days and every downstream
        // calculation built on it is wrong for the user.
        let period = try QuotaPeriod(
            start: try instant("2026-09-01"),
            end: try instant(2026, 9, 30, hour: 23, minute: 59)
        )
        #expect(period.totalDays(calendar: fixedCalendar) == 30)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        #expect(period.totalDays(calendar: utc) == 31)
    }

    @Test("A period spanning a spring-forward day still totals its calendar days")
    func periodAcrossSpringForward() throws {
        // Europe/Madrid springs forward on 2026-03-29.
        let period = try QuotaPeriod(
            start: instant("2026-03-28"),
            end: instant("2026-03-30")
        )
        #expect(period.totalDays(calendar: fixedCalendar) == 3)
    }

    @Test("A period spanning a fall-back day still totals its calendar days")
    func periodAcrossFallBack() throws {
        // Europe/Madrid falls back on 2026-10-25.
        let period = try QuotaPeriod(
            start: instant("2026-10-24"),
            end: instant("2026-10-26")
        )
        #expect(period.totalDays(calendar: fixedCalendar) == 3)
    }

    @Test("A reference part-way through the final day has no full days left")
    func partialFinalDayStillCounts() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant(2026, 9, 30, hour: 6)
        )
        // Still inside the period, but no midnight remains after today.
        #expect(try period.remainingDays(through: instant(2026, 9, 30, hour: 6), calendar: fixedCalendar) == 0)
        let justAfterEnd = try instant(2026, 9, 30, hour: 6, minute: 1)
        #expect(period.status(asOf: justAfterEnd) == .expired)
        #expect(period.remainingDays(through: justAfterEnd, calendar: fixedCalendar) == 0)
    }

    @Test("A period round trips through Codable") func codableRoundTrip() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-01"),
            end: instant("2026-09-30")
        )
        let data = try JSONEncoder().encode(period)
        let decoded = try JSONDecoder().decode(QuotaPeriod.self, from: data)
        #expect(decoded == period)
    }

    // MARK: The days a period has

    @Test("A period's days are every day of it, oldest first")
    func listsEveryDay() throws {
        let period = try QuotaPeriod(
            start: instant("2026-09-15"),
            end: instant("2026-09-22")
        )
        let days = period.localDates(in: fixedCalendar)
        // Eight days for the fifteenth through the twenty-second inclusive: the
        // same span `totalDays` counts, so a calendar that draws these and an
        // engine that plans them are working from one list.
        #expect(days.count == 8)
        #expect(days.count == period.totalDays(calendar: fixedCalendar))
        #expect(days == days.sorted())
        #expect(days.first?.day == 15)
        #expect(days.last?.day == 22)
    }

    @Test("A period's days cross a month boundary without losing or repeating one")
    func daysCrossAMonthBoundary() throws {
        let period = try QuotaPeriod(
            start: instant("2026-03-28"),
            end: instant("2026-04-03")
        )
        let days = period.localDates(in: fixedCalendar)
        #expect(days.count == 7)
        #expect(Set(days).count == days.count)
        #expect(days.first?.month == 3)
        #expect(days.last?.month == 4)
    }

    @Test("A period's days include a leap day when the span covers it")
    func daysIncludeALeapDay() throws {
        let period = try QuotaPeriod(
            start: instant("2024-02-28"),
            end: instant("2024-03-01")
        )
        #expect(
            period.localDates(in: fixedCalendar).contains(try LocalDate(year: 2024, month: 2, day: 29))
        )
    }

    @Test("A single-day period has exactly that day")
    func singleDayPeriod() throws {
        let period = try QuotaPeriod(
            start: instant(2026, 9, 15, hour: 9),
            end: instant(2026, 9, 15, hour: 23)
        )
        #expect(period.localDates(in: fixedCalendar) == [try LocalDate(iso: "2026-09-15")])
    }
}
