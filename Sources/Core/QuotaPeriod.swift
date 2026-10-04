import Foundation

/// The window a quota is measured over: when the allowance started and when it
/// ends.
///
/// A period comes from the provider when the provider can detect one, and from
/// the user when it cannot. It is never inferred from an account
/// creation date, because a billing cycle is anchored to a renewal, and a pricing
/// change can produce a cycle shorter than a month.
public struct QuotaPeriod: Sendable, Hashable, Codable {
    public let start: Date
    public let end: Date

    /// The calendar month containing `instant`, in the caller's calendar.
    ///
    /// On the period rather than in the interface because both the creation flow
    /// and the preview world needed the same month, and they wrote it out
    /// separately: a preview month that was not the created month would show a
    /// user a period the app could not hand them.
    ///
    /// Takes the calendar because a month is not the same month everywhere, and
    /// silently using the machine's would plan a user's quota in a time zone they
    /// do not live in.
    public static func month(containing instant: Date, calendar: Calendar) throws -> QuotaPeriod {
        guard let interval = calendar.dateInterval(of: .month, for: instant) else {
            throw QuotaDomainError.invalidPeriod(start: instant, end: instant)
        }
        return try QuotaPeriod(start: interval.start, end: interval.end)
    }

    /// Where the period sits relative to a reference instant.
    public enum Status: String, Sendable, Codable {
        case future
        case active
        case expired
    }

    /// - Throws: `QuotaDomainError.invalidPeriod` when the end precedes the
    ///   start. A period that runs backwards cannot be planned against.
    public init(start: Date, end: Date) throws {
        guard start <= end else {
            throw QuotaDomainError.invalidPeriod(start: start, end: end)
        }
        self.start = start
        self.end = end
    }

    /// Where the period sits at the given instant. Derived, never stored, so it
    /// cannot go stale.
    public func status(asOf reference: Date) -> Status {
        if reference < start {
            return .future
        }
        if reference > end {
            return .expired
        }
        return .active
    }

    /// The count of full calendar days still ahead after today, through the last
    /// day of the period.
    ///
    /// Today is not counted: "26 days remaining" means twenty-six midnights still
    /// to pass before the period ends, which is how provider dashboards phrase
    /// it. A period whose end has passed, or that has not started, has none. On
    /// the final day the count is zero.
    ///
    /// `elapsedDays` still counts today, so `elapsedDays + remainingDays ==
    /// totalDays` while the period is active.
    public func remainingDays(through reference: Date, calendar: Calendar) -> Int {
        guard status(asOf: reference) == .active else { return 0 }
        let lastDay = LocalDate(date: end, calendar: calendar)
        let today = LocalDate(date: reference, calendar: calendar)
        guard let daysAfterToday = today.distance(to: lastDay, calendar: calendar) else {
            return 0
        }
        return max(0, daysAfterToday)
    }

    /// The inclusive count of days from the period start through the reference
    /// day. Zero while the period has not started.
    ///
    /// Shares its last day with the period's start of remaining days after today;
    /// see `remainingDays`.
    public func elapsedDays(since reference: Date, calendar: Calendar) -> Int {
        guard status(asOf: reference) == .active else { return 0 }
        let firstDay = LocalDate(date: start, calendar: calendar)
        let today = LocalDate(date: reference, calendar: calendar)
        return firstDay.inclusiveDayCount(through: today, calendar: calendar) ?? 0
    }

    /// The inclusive length of the whole period, in days.
    ///
    /// Takes the caller's calendar because the count depends on it: a period
    /// running from the first instant of 1 September to the last instant of
    /// 30 September is 30 days in Madrid and 31 when measured in UTC, since the
    /// start falls on 31 August there. There is deliberately no default, so a
    /// caller cannot silently measure a user's month in the wrong time zone.
    public func totalDays(calendar: Calendar) -> Int {
        let firstDay = LocalDate(date: start, calendar: calendar)
        let lastDay = LocalDate(date: end, calendar: calendar)
        return firstDay.inclusiveDayCount(through: lastDay, calendar: calendar) ?? 0
    }

    /// Every local day the period covers, oldest first.
    ///
    /// Inclusive of both ends, the same span `totalDays` counts, so a calendar
    /// that draws these days and an engine that plans them cannot disagree about
    /// which days the period has. Days are what a quota is spent on: the
    /// allowance is spent on local days, so the days a calendar offers a user to
    /// click are the days the domain will plan against.
    public func localDates(in calendar: Calendar) -> [LocalDate] {
        let firstDay = LocalDate(date: start, calendar: calendar)
        let lastDay = LocalDate(date: end, calendar: calendar)
        guard let days = firstDay.inclusiveDayCount(through: lastDay, calendar: calendar), days > 0 else {
            return [firstDay]
        }
        return (0 ..< days).compactMap { firstDay.adding(days: $0, calendar: calendar) }
    }
}
