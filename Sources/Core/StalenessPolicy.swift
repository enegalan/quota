import Foundation

/// How old a reading may be before the interface must say so.
///
/// One line, applied everywhere, so that the interface cannot show a reading as
/// current in one place and out of date in another. The line is
/// `StalenessConstants.ageingAfter`; the states on either side of it are the
/// interface's to choose, and it takes the instant from the caller rather than
/// reading a clock, so the answer cannot differ between the place that renders a
/// reading and the place that schedules the next refresh.
public enum StalenessPolicy {
    /// Whether the reading must be presented as out of date.
    ///
    /// Not the same question as "is this reading stale": a stale reading is one
    /// that has been wrong for hours, and this one is true from the moment a
    /// refresh has missed its slot. The interface decides what to say about a
    /// reading that is out of date.
    public static func isOutOfDate(snapshot: UsageSnapshot, now: Date) -> Bool {
        isOutOfDate(age: now.timeIntervalSince(snapshot.updatedAt))
    }

    /// Whether a reading of this age is out of date.
    ///
    /// Split out so the interface's four freshness states can be decided by this
    /// policy rather than by a second comparison against the same constant.
    public static func isOutOfDate(age: TimeInterval) -> Bool {
        age >= StalenessConstants.ageingAfter
    }

    /// The age of a reading, for the interface to describe.
    public static func age(of snapshot: UsageSnapshot, now: Date) -> TimeInterval {
        now.timeIntervalSince(snapshot.updatedAt)
    }
}
