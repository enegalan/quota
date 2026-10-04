import Core
import Foundation
import Testing
@testable import App

/// The shape of a month, which every calendar in the window is drawn from.
///
/// The claims here are the ones a calendar gets wrong quietly: a month that
/// starts in the wrong column, a February that loses a day, a first weekday the
/// user never asked for. None of them throws, and all of them are visible.
@Suite("Month layout")
struct MonthLayoutTests {
    @Test("A month has as many days as the calendar says it does")
    func dayCount() throws {
        #expect(try days(of: 2026, 9, in: madridFirst).count == 30)
        #expect(try days(of: 2026, 2, in: madridFirst).count == 28)
        #expect(try days(of: 2024, 2, in: madridFirst).count == 29)
        #expect(try days(of: 2026, 12, in: madridFirst).count == 31)
    }

    @Test("The first of the month lands in the column its weekday is in")
    func firstDayFallsInItsColumn() throws {
        // 1 September 2026 is a Tuesday, and a calendar that starts its weeks on
        // Monday puts it in the second column.
        let layout = try layout(of: 2026, 9, day: 1, in: madridFirst)
        #expect(layout.leadingBlankCount == 1)
        #expect(layout.days.first == (try LocalDate(iso: "2026-09-01")))
    }

    @Test("The first weekday is the user's, not the code's")
    func honoursFirstWeekday() throws {
        // The same month under two calendars: one opening on Monday and one on
        // Sunday. A grid that ignored the setting would pad both the same way.
        let monday = try layout(of: 2026, 9, day: 1, in: madridFirst)
        let sunday = try layout(of: 2026, 9, day: 1, in: sundayFirst)
        #expect(monday.leadingBlankCount == 1)
        #expect(sunday.leadingBlankCount == 2)
        // The days themselves do not move: only the padding in front of them does.
        #expect(monday.days == sunday.days)
    }

    @Test("A month that opens on the first weekday needs no blank before it")
    func noLeadingBlank() throws {
        // 1 November 2026 is a Sunday, so a calendar opening on Sunday has nothing
        // to pad with.
        #expect(try layout(of: 2026, 11, day: 1, in: sundayFirst).leadingBlankCount == 0)
    }

    @Test("The days of a month are the month's, oldest first, with none repeated")
    func daysAreTheMonthsOwn() throws {
        // Asked about the middle of the month, and answered with the whole of it:
        // a layout that counted forward from the day it was handed would report a
        // month beginning on the fifteenth and run on into October.
        let layout = try layout(of: 2026, 9, day: 15, in: madridFirst)
        #expect(layout.firstDay == (try LocalDate(iso: "2026-09-01")))
        #expect(layout.days == layout.days.sorted())
        #expect(Set(layout.days).count == layout.days.count)
        #expect(layout.days.first?.day == 1)
        #expect(layout.days.last?.day == 30)
    }

    @Test("A month can be asked for by any day inside it")
    func anyDayFindsItsMonth() throws {
        let fromFirst = try layout(of: 2026, 9, day: 1, in: madridFirst)
        let fromLast = try layout(of: 2026, 9, day: 30, in: madridFirst)
        #expect(fromFirst == fromLast)
    }

    @Test("The weekday headers start on the user's first weekday")
    func headersStartOnTheUsersWeek() throws {
        // A header row that always began on Sunday would mislabel every column for
        // a user whose week begins on Monday.
        let mondayHeaders = MonthGrid.weekdayInitials(in: madridFirst)
        let sundayHeaders = MonthGrid.weekdayInitials(in: sundayFirst)
        #expect(mondayHeaders.count == DateConstants.daysInWeek)
        #expect(try #require(mondayHeaders.first) == initial(of: 2, in: madridFirst))
        #expect(try #require(sundayHeaders.first) == initial(of: 1, in: sundayFirst))
    }

    // MARK: Arranging

    private var madridFirst: Calendar {
        calendar(firstWeekday: 2)
    }

    private var sundayFirst: Calendar {
        calendar(firstWeekday: 1)
    }

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func layout(
        of year: Int,
        _ month: Int,
        day: Int,
        in calendar: Calendar
    ) throws -> MonthLayout {
        MonthLayout.month(
            containing: try #require(
                calendar.date(from: DateComponents(year: year, month: month, day: day))
            ),
            calendar: calendar
        )
    }

    private func days(of year: Int, _ month: Int, in calendar: Calendar) throws -> [LocalDate] {
        try layout(of: year, month, day: 1, in: calendar).days
    }

    private func initial(of weekday: Int, in calendar: Calendar) -> String {
        String(calendar.veryShortWeekdaySymbols[weekday - 1].prefix(1))
    }
}
