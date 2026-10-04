import Foundation

/// The instant the mock worlds are built at: 15 March 2026, midday, in
/// `MockUsageWorld.timeZone`.
///
/// Fixed rather than read from the clock, because a snapshot is a picture of
/// one instant: a world that moved with the wall clock would produce a
/// different picture on every run and there would be nothing to compare.
enum MockUsageInstant {
    static let year = 2026
    static let month = 3
    static let day = 15
    /// Midday, so the day's window from midnight to the reference instant is
    /// half over and today's reading is not empty.
    static let hour = 12
}

/// The three usage levels the popover is previewed and snapshotted at.
///
/// Spread across the period rather than close together, because two levels a
/// few points apart render the same words in the same colours: a set of
/// snapshots that differed only slightly would agree with each other and all
/// be wrong.
enum MockUsageLevels {
    /// Barely started: nearly the whole allowance is still ahead.
    static let under: Double = 5
    /// Halfway through the month and half spent.
    static let onPace: Double = 40
    /// Nearly spent, with days still to run.
    static let over: Double = 90
    /// How much of a day has passed at the mock world's midday reference, as a
    /// fraction of the day.
    static let elapsedShare: Double = 0.5
    /// How many days of history a mock world keeps. A month, so the calendar
    /// draws has something behind every day of the period it shows.
    static let timelineDays = 31
}
