import Core
import Foundation

/// Where a month sits on a seven-column grid: the days it has, in order, and how
/// many blank cells precede them.
///
/// One implementation of the month's shape, because the two calendars in the app
/// — the plan's and the custom policy editor's — must agree about where a month
/// starts and how long it is. A calendar that started its rows on a different
/// weekday from the one above it would not be wrong in any way a user could
/// name, and would still be wrong.
struct MonthLayout: Hashable {
    /// The first day of the month, in the user's calendar.
    let firstDay: LocalDate

    /// The month's days, oldest first.
    let days: [LocalDate]

    /// How many cells stand before the first of the month.
    ///
    /// The user's first weekday is honoured rather than assumed: a calendar
    /// starting on Monday for most of the world should not start on Sunday
    /// because the code was written in one.
    let leadingBlankCount: Int

    /// The first instant of the month a date falls in.
    ///
    /// - Returns: nil when the calendar cannot resolve a month for the date.
    ///
    /// On `MonthLayout` rather than on either of the views, because "which
    /// month is this in" has to be one answer: a menu that ticks the month
    /// the grid is drawing and a grid that thinks a different month is
    /// current would leave the checkmark on a page nobody is looking at.
    static func monthStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .month, for: date)?.start
    }

    /// The shape of the month a date falls in.
    ///
    /// The month's length is asked of the calendar rather than assumed to be
    /// 30 or 31, so February in a leap year is right without a special case
    /// and a 31-day month does not lose a day. The reference may be any
    /// instant inside the month and the month that comes back always starts
    /// on the first: asked about the 30th, this returns the 1st through the
    /// 30th, not a month of days running from the 30th into the next one.
    ///
    /// A date the calendar cannot place yields a month of one day rather than
    /// nothing, so a grid still draws the cell it asked for and no caller has
    /// to decide what an absent month should look like.
    static func month(containing date: Date, calendar: Calendar) -> MonthLayout {
        guard
            let interval = calendar.dateInterval(of: .month, for: date)
        else {
            let alone = LocalDate(date: date, calendar: calendar)
            return MonthLayout(firstDay: alone, days: [alone], leadingBlankCount: 0)
        }
        let firstInstant = calendar.startOfDay(for: interval.start)
        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        let leading = (calendar.component(.weekday, from: firstInstant) - calendar.firstWeekday
            + DateConstants.daysInWeek) % DateConstants.daysInWeek
        let days = (0 ..< dayCount).compactMap { offset in
            LocalDate(date: firstInstant, calendar: calendar).adding(days: offset, calendar: calendar)
        }
        return MonthLayout(
            firstDay: LocalDate(date: firstInstant, calendar: calendar),
            days: days,
            leadingBlankCount: leading
        )
    }
}

/// One cell of a month grid: the date it stands for, whether it can be acted on,
/// and the text under the date.
///
/// The figures are text rather than numbers because both calendars show the same
/// thing in the same place — a share of a day's allowance, and what was spent of
/// it — and a cell that formatted its own numbers would be free to round them
/// differently from the panel underneath it. The first line is the day's
/// allocation; anything below it is what has been spent against it.
struct MonthGridDay: Identifiable, Hashable {
    /// The cell's place in the grid, which is what tells one cell from another.
    ///
    /// A position rather than the date, because the cells before the first of the
    /// month stand for no day of it and would otherwise collide with it.
    let position: Int

    /// The day this cell stands for, or nil for a cell that stands for none.
    let date: LocalDate?
    let isAvailable: Bool
    let lines: [String]

    var id: Int {
        position
    }

    /// A cell that stands for no day of the month.
    ///
    /// Unavailable, dateless and empty, so a grid can put the first of the month
    /// in the right column without inventing a date the user could click on and
    /// be told nothing about.
    static func blank(at position: Int) -> MonthGridDay {
        MonthGridDay(position: position, date: nil, isAvailable: false, lines: [])
    }
}
