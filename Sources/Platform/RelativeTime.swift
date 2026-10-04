import Core
import Foundation

/// Wording for how long ago something happened.
///
/// A struct with a `describe` rather than a `DateComponentsFormatter`, because
/// the awkward part of relative wording is not the arithmetic, it is deciding
/// which unit to use and what to call the boundary. Both are decided by
/// thresholds named in `RefreshConstants`, and both are worth testing without a
/// locale in the way.
public struct RelativeTime: Sendable, Equatable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// How a moment reads relative to now.
    ///
    /// Rounded down to the unit, so "59 seconds ago" does not become "1 minute
    /// ago" and then a second later go back to seconds.
    public func describe(since moment: Date, now: Date) -> String {
        let age = now.timeIntervalSince(moment)
        return wording(for: age)
    }

    /// The wording for an age, which is the part worth testing on its own.
    public func wording(for age: TimeInterval) -> String {
        // A moment in the future reads as just now rather than as a negative
        // age, which is what a clock adjustment between two reads looks like
        // from here.
        if age < RefreshConstants.justNow {
            return "just now"
        }
        if age < RefreshConstants.oneMinute {
            return "\(plural(age, unit: "second")) ago"
        }
        if age < RefreshConstants.twoMinutes {
            return "1 minute ago"
        }
        if age < RefreshConstants.oneHour {
            return "\(plural(age / 60, unit: "minute")) ago"
        }
        if age < RefreshConstants.oneDay {
            return "\(plural(age / 3600, unit: "hour")) ago"
        }
        if age < RefreshConstants.oneWeek {
            return "\(plural(age / 86400, unit: "day")) ago"
        }
        if age < RefreshConstants.oneMonth {
            return "\(plural(age / (7 * 86400), unit: "week")) ago"
        }
        if age < RefreshConstants.oneYear {
            return "\(plural(age / (30 * 86400), unit: "month")) ago"
        }
        return "\(plural(age / (365 * 86400), unit: "year")) ago"
    }

    /// The wording used when a refresh has failed and a reading is being
    /// shown anyway.
    public func describeFailure(age: TimeInterval) -> String {
        "Unable to update usage. Showing data from \(wording(for: age))."
    }

    /// A count with its unit, pluralised when the count is not one.
    ///
    /// Only one or many, because the unit has already been chosen by the
    /// threshold above: there is no fraction left to round and no
    /// half-way form to invent wording for. One and one-half is said as
    /// "1 minute", which is what a user reading it expects rather than
    /// a number that changes shape as it ages.
    private func plural(_ value: Double, unit: String) -> String {
        let whole = Int(value.rounded(.down))
        return "\(whole) \(unit)\(whole == 1 ? "" : "s")"
    }
}
