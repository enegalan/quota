import Foundation

/// Facts about the seven-day week that the calendar does not supply as values.
enum WeekdayConstants {
    /// The weekday numbers a `Calendar` uses, where 1 is Sunday and 7 is
    /// Saturday. The ordering is the calendar's, not this app's, so a policy
    /// written for a non-Gregorian calendar still means what it says.
    static let minimumWeekday = 1
    static let maximumWeekday = DateConstants.daysInWeek

    static let sunday = minimumWeekday
    static let saturday = DateConstants.daysInWeek

    /// Weights are a ratio, so there is no meaningful upper bound. This one
    /// exists only to reject a value large enough to overflow the engine's
    /// integer arithmetic, not to constrain a legitimate policy.
    static let maximumWeight = 1_000_000

    /// The smallest total weight that still permits a division.
    static let minimumWeight = 0

    /// The weight for a weekday the caller did not specify, and for an ordinary
    /// day in a working week.
    static let defaultWeight = 1

    /// A day a policy excludes entirely.
    static let excludedWeight = 0

    /// Whether a weekday number falls on a Saturday or a Sunday.
    ///
    /// Answered from the constants rather than by dividing by six, so a calendar
    /// whose weekend is not at the end of the week is described by changing two
    /// numbers rather than by rewriting every caller.
    static func isWeekend(_ weekday: Int) -> Bool {
        weekday == sunday || weekday == saturday
    }

    /// Every day weighted the same, built from the weekday range rather than
    /// transcribed, so a calendar with a different week length is handled by
    /// changing one constant.
    static let uniformWeights: [Int: Int] = (minimumWeekday ... maximumWeekday)
        .reduce(into: [:]) { result, weekday in
            result[weekday] = defaultWeight
        }

    /// Weekends excluded, weekdays weighted one.
    static let weekdayOnlyWeights: [Int: Int] = (minimumWeekday ... maximumWeekday)
        .reduce(into: [:]) { result, weekday in
            result[weekday] = isWeekend(weekday) ? excludedWeight : defaultWeight
        }
}
