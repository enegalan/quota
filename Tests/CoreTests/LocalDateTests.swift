import Foundation
import Testing
@testable import Core

/// A fixed calendar, so every assertion in this suite holds in every time zone.
/// `Calendar.current` in a test is how a daylight-saving bug survives review and
/// then fails for one user a year later.
private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    return calendar
}()

private func date(_ iso: String) throws -> Date {
    let parsed = try LocalDate(iso: iso)
    return try #require(parsed.date(calendar: fixedCalendar))
}

@Suite("LocalDate")
struct LocalDateTests {
    // MARK: Codable

    @Test("ISO form round trips through Codable")
    func isoRoundTrip() throws {
        let original = try LocalDate(year: 2026, month: 9, day: 25)
        let data = try JSONEncoder().encode(original)
        #expect(String(data: data, encoding: .utf8) == "\"2026-09-25\"")
        #expect(try JSONDecoder().decode(LocalDate.self, from: data) == original)
    }

    @Test("ISO form pads single-digit components")
    func isoPadding() throws {
        #expect(try LocalDate(iso: "2026-01-05").description == "2026-01-05")
        #expect(try LocalDate(iso: "0007-03-09").description == "0007-03-09")
    }

    @Test("Malformed ISO forms are rejected")
    func isoRejectsMalformed() {
        let malformed = ["", "2026", "2026-09", "2026-09-25-01", "not-a-date", "2026--25", "-09-25"]
        for value in malformed {
            #expect(throws: QuotaDomainError.self) { try LocalDate(iso: value) }
        }
    }

    // MARK: Validation

    @Test("Impossible component combinations are rejected")
    func rejectsImpossibleDates() {
        let impossible = [
            (2026, 2, 30),
            (2023, 2, 29), // 2023 is not a leap year
            (1900, 2, 29), // 1900 is divisible by 100 and not by 400
            (2026, 13, 1),
            (2026, 0, 1),
            (2026, 1, 32),
            (2026, 1, 0),
        ]
        for (year, month, day) in impossible {
            #expect(throws: QuotaDomainError.self) {
                try LocalDate(year: year, month: month, day: day)
            }
        }
    }

    @Test("Valid leap days are accepted")
    func acceptsLeapDays() throws {
        #expect(try LocalDate(iso: "2024-02-29").description == "2024-02-29")
        #expect(try LocalDate(iso: "2000-02-29").description == "2000-02-29")
        #expect(try LocalDate(iso: "2026-02-28").description == "2026-02-28")
    }

    // MARK: Ordering

    @Test("Dates order chronologically, not lexically")
    func ordering() throws {
        let earlier = try LocalDate(iso: "2026-09-09")
        let later = try LocalDate(iso: "2026-10-01")
        #expect(earlier < later)
        #expect(later > earlier)
        #expect(!(earlier < earlier))
        #expect([later, earlier].sorted() == [earlier, later])
    }

    @Test("Ordering is by component, not by string length")
    func orderingAcrossComponentWidths() throws {
        let narrow = try LocalDate(iso: "2026-09-09")
        let wide = try LocalDate(iso: "2026-10-01")
        #expect(narrow < wide)
    }

    // MARK: Distance

    @Test("Distance counts days, not seconds")
    func distanceCountsDays() throws {
        let start = try LocalDate(iso: "2026-09-01")
        let end = try LocalDate(iso: "2026-09-30")
        #expect(start.distance(to: end, calendar: fixedCalendar) == 29)
        #expect(end.distance(to: start, calendar: fixedCalendar) == -29)
        #expect(start.distance(to: start, calendar: fixedCalendar) == 0)
    }

    @Test("A spring-forward day counts as one day")
    func springForward() throws {
        // Europe/Madrid springs forward on 2026-03-29: that local day is 23 hours.
        let beforeTransition = try LocalDate(iso: "2026-03-28")
        let afterTransition = try LocalDate(iso: "2026-03-30")
        #expect(beforeTransition.distance(to: afterTransition, calendar: fixedCalendar) == 2)
        #expect(afterTransition.adding(days: -1, calendar: fixedCalendar) == afterTransition.adding(
            days: -1,
            calendar: fixedCalendar
        ))
    }

    @Test("A fall-back day counts as one day")
    func fallBack() throws {
        // Europe/Madrid falls back on 2026-10-25: that local day is 25 hours.
        let beforeTransition = try LocalDate(iso: "2026-10-24")
        let afterTransition = try LocalDate(iso: "2026-10-26")
        #expect(beforeTransition.distance(to: afterTransition, calendar: fixedCalendar) == 2)
    }

    @Test("Advancing across a transition lands on consecutive calendar days")
    func advancingAcrossTransitions() throws {
        var cursor = try LocalDate(iso: "2026-03-27")
        for expectedDay in 28 ... 31 {
            cursor = try #require(cursor.adding(days: 1, calendar: fixedCalendar))
            #expect(cursor.day == expectedDay)
        }
    }

    @Test("Distance crosses a year boundary")
    func distanceAcrossYearBoundary() throws {
        let start = try LocalDate(iso: "2026-12-30")
        let end = try LocalDate(iso: "2027-01-02")
        #expect(start.distance(to: end, calendar: fixedCalendar) == 3)
    }

    @Test("Distance across a leap day")
    func distanceAcrossLeapDay() throws {
        let start = try LocalDate(iso: "2024-02-28")
        let end = try LocalDate(iso: "2024-03-01")
        #expect(start.distance(to: end, calendar: fixedCalendar) == 2)
    }

    // MARK: Conversion

    @Test("Conversion to Date and back is lossless")
    func conversionRoundTrip() throws {
        let original = try LocalDate(iso: "2026-09-25")
        let converted = try #require(original.date(calendar: fixedCalendar))
        #expect(LocalDate(date: converted, calendar: fixedCalendar) == original)
    }

    @Test("Weekday follows the calendar's own numbering")
    func weekday() throws {
        // 2026-09-21 is a Monday, which is weekday 2 in the Gregorian convention
        // where 1 is Sunday.
        let monday = try LocalDate(iso: "2026-09-21")
        #expect(monday.weekday(calendar: fixedCalendar) == 2)
    }
}
