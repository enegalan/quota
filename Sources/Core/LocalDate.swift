import Foundation

/// A calendar date with no time and no time zone.
///
/// The engine never adds a fixed number of seconds to advance a day, because a
/// day is not always 86 400 seconds: a daylight-saving transition makes it 23 or
/// 25. Working in this type rather than in `Date` removes that entire class of
/// bug, and makes a plan identical for every user regardless of their location.
///
/// Every conversion to and from `Date` takes the caller's `Calendar`, so a
/// non-Gregorian calendar or a different first weekday is honoured rather than
/// assumed.
public struct LocalDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a date from its components.
    ///
    /// The combination is validated by round-tripping it through a calendar, so
    /// 30 February and 29 February of a common year are rejected rather than
    /// silently normalised.
    ///
    /// - Throws: `QuotaDomainError.invalidDate` when the components do not
    ///   describe a real date.
    public init(year: Int, month: Int, day: Int) throws {
        let components = DateComponents(year: year, month: month, day: day)
        guard let resolved = DateConstants.validationCalendar.date(from: components) else {
            throw QuotaDomainError.invalidDate(year: year, month: month, day: day)
        }

        let roundTripped = LocalDate(date: resolved, calendar: DateConstants.validationCalendar)
        let matches = roundTripped.year == year
            && roundTripped.month == month
            && roundTripped.day == day
        guard matches else {
            throw QuotaDomainError.invalidDate(year: year, month: month, day: day)
        }
        self = roundTripped
    }

    /// Creates the date on which the given instant falls, in the given calendar.
    ///
    /// Total by construction: decomposing a `Date` with a `Calendar` always
    /// yields all three components. The fallbacks below are unreachable and
    /// exist so the initialiser is not failable for a reason that cannot occur.
    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents(DateConstants.dayComponentKeys, from: date)
        year = components.year ?? 0
        month = components.month ?? 1
        day = components.day ?? 1
    }

    /// The instant at the start of this date, or nil when the caller's calendar
    /// cannot represent it.
    public func date(calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    /// The date `days` after this one.
    ///
    /// Returns nil when the caller's calendar cannot represent the result, which
    /// is the honest answer rather than a silently clamped date.
    public func adding(days: Int, calendar: Calendar) -> LocalDate? {
        guard let start = date(calendar: calendar),
              let advanced = calendar.date(byAdding: .day, value: days, to: start)
        else { return nil }
        return LocalDate(date: advanced, calendar: calendar)
    }

    /// The number of calendar days from this date to `other`. Negative when
    /// `other` is earlier.
    ///
    /// Counted as calendar days, so a 23 or 25 hour day is exactly one day.
    public func distance(to other: LocalDate, calendar: Calendar) -> Int? {
        guard let start = date(calendar: calendar), let end = other.date(calendar: calendar) else {
            return nil
        }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    /// The count of days from this date through `other`, both ends counted.
    ///
    /// One place for it because every span in the domain is inclusive: a period
    /// that starts and ends on the same day is one day long, and a count that
    /// said zero would plan a day with nothing to spend and let a day at each
    /// end go unplanned.
    public func inclusiveDayCount(through other: LocalDate, calendar: Calendar) -> Int? {
        guard let days = distance(to: other, calendar: calendar) else { return nil }
        return days + DateConstants.inclusiveDayOffset
    }

    /// The weekday, using the calendar's own numbering, where 1 is Sunday.
    public func weekday(calendar: Calendar) -> Int? {
        date(calendar: calendar).map { calendar.component(.weekday, from: $0) }
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The ISO 8601 calendar date, `YYYY-MM-DD`. This is also the stored form.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(iso: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes as the ISO string, the same form `description` produces.
    ///
    /// A single value rather than three fields, so a date used as a key in a
    /// stored custom policy stays a key: a JSON object can only have string keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Parses the ISO form produced by `description`.
    ///
    /// - Throws: `QuotaDomainError.invalidDate` for a malformed or impossible
    ///   date. A stored value that cannot be parsed is a real error, not
    ///   something to paper over with a default.
    public init(iso: String) throws {
        guard let numbers = Self.numbers(in: iso),
              numbers.count == DateConstants.isoComponentCount
        else {
            throw QuotaDomainError.invalidDate(year: 0, month: 0, day: 0)
        }

        var components = numbers.makeIterator()
        guard let year = components.next(),
              let month = components.next(),
              let day = components.next()
        else {
            throw QuotaDomainError.invalidDate(year: 0, month: 0, day: 0)
        }

        try self.init(year: year, month: month, day: day)
    }

    /// Extracts the numbers from an ISO date in the order they are written.
    ///
    /// Returns nil for anything that is not numbers joined by single hyphens, so
    /// an empty component such as the one in `2026--25` is rejected here rather
    /// than being coerced to zero further down.
    private static func numbers(in iso: String) -> [Int]? {
        var numbers: [Int] = []
        var digits = ""

        /// Commits the digits gathered so far as one component.
        ///
        /// - Returns: false when nothing was collected or the digits are not a
        ///   number; that is the caller's signal to reject the whole string.
        func commit() -> Bool {
            guard !digits.isEmpty, let value = Int(digits) else { return false }
            numbers.append(value)
            digits = ""
            return true
        }

        for character in iso {
            if character.isNumber {
                digits.append(character)
            } else if character == DateConstants.isoSeparator, commit() {
                continue
            } else {
                return nil
            }
        }

        return commit() ? numbers : nil
    }
}
