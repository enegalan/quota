import Foundation

/// Facts about dates that are structural rather than tunable.
///
/// The seconds-per-day constant exists for one purpose only: formatting a
/// duration such as "3 hours ago". It must never be used to advance a date,
/// because a calendar day is 23, 24, or 25 hours depending on the transition and
/// the location. Date arithmetic goes through `Calendar`.
public enum DateConstants {
    /// The components that identify a calendar date, and no more.
    public static let dayComponentKeys: Set<Calendar.Component> = [.year, .month, .day]

    /// A fixed, locale-independent calendar used to validate that a year, month,
    /// and day combination describes a real date. Validation must not vary with
    /// the user's settings.
    public static let validationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// The separator between date components in the stored form.
    public static let isoSeparator: Character = "-"

    /// Year, month, and day: the number of components a stored date has.
    public static let isoComponentCount = 3

    /// Both the first and the last day of a period count towards it, so a day
    /// count between two dates needs one added to become an inclusive count.
    public static let inclusiveDayOffset: Int = 1

    public static let secondsPerMinute: TimeInterval = 60
    public static let secondsPerHour: TimeInterval = 3600
    public static let secondsPerDay: TimeInterval = 86400

    /// The number of days in a week, which is structural rather than a tunable:
    /// a calendar's week is seven days in every locale, even where the first day
    /// of that week differs.
    public static let daysInWeek = 7
}
