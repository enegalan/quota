import Foundation

/// Every interval, threshold, factor and cap the refresh machinery uses.
///
/// Named and gathered here so that no threshold is a literal somewhere in a
/// branch. A magic number in a scheduling decision is a number nobody can change
/// without finding it, and these are the values most likely to need changing on
/// the evidence of real use.
public enum RefreshConstants {
    // MARK: When to poll

    /// The shortest gap between two polls of one provider.
    ///
    /// A floor and not a preference: a provider that suggests one second would
    /// otherwise have the app polling it a thousand times an hour, which is a
    /// way to get an account rate-limited and the provider disabled.
    public static let minimumPollInterval: TimeInterval = 60

    /// The longest gap between two polls of one provider.
    ///
    /// A ceiling because a provider that asks to be polled weekly still has to
    /// notice a period rolling over, and a number taken from the provider alone
    /// would let a broken value stop the app refreshing at all.
    public static let maximumPollInterval: TimeInterval = 6 * 60 * 60

    /// The interval a preference is held to.
    ///
    /// Here with the bounds rather than at each call site, because a preference
    /// stored outside them and a preference shown after being clamped are two
    /// different numbers for the same setting: the app would report one and the
    /// scheduler would use the other.
    public static func clamped(_ interval: TimeInterval) -> TimeInterval {
        min(max(interval, minimumPollInterval), maximumPollInterval)
    }

    /// The interval used when the provider suggests nothing.
    public static let defaultPollInterval: TimeInterval = 15 * 60

    /// How far a poll's time is nudged off the schedule.
    ///
    /// A fraction of the interval rather than a fixed number of seconds, so a
    /// short interval gets a small nudge and a long one a large one. Without it
    /// every install on earth polls at the same second.
    public static let jitterFraction: Double = 0.1

    /// The most a poll's time moves, whatever the interval.
    ///
    /// A cap on the fraction so a six-hour interval does not become "some time in
    /// the next twenty minutes", which would make the schedule meaningless.
    /// Where a random draw is centred: half, so the offset is symmetric.
    public static let jitterMidpoint = 0.5

    /// How wide the jitter is, in multiples of the spread. Two, so a draw of 0
    /// moves the read a full spread earlier and a draw of 1 a full spread later.
    public static let jitterSpan: Double = 2

    public static let maximumJitter: TimeInterval = 60

    // MARK: Backoff

    /// What each consecutive failure multiplies the wait by.
    ///
    /// Applied to the interval the provider would otherwise have been read at,
    /// rather than to a delay of its own: the first failure therefore waits one
    /// whole interval, which is what "back off" means when there is nothing yet
    /// to be impatient about.
    public static let backoffFactor: Double = 2

    /// The most the wait grows, however many failures there have been.
    public static let maximumBackoff: TimeInterval = 60 * 60

    // MARK: What is kept

    /// How many readings one bucket's timeline holds.
    ///
    /// Bounded because a reading is written on every successful refresh, and a
    /// poll every five minutes is about a hundred thousand points a year. The
    /// figure is generous enough to answer "how much have I used this hour",
    /// which is the only question the timeline is asked, and small enough that
    /// the file stays a file.
    public static let timelineRetention = 5000

    // MARK: Wording

    /// Thresholds for the relative-time wording, in seconds.
    ///
    /// Descending, so the first one a value is under is the one that applies.
    /// Each is a boundary where the wording changes, which is why they are named
    /// rather than written into the formatter's branches.
    public static let justNow: TimeInterval = 45
    public static let oneMinute: TimeInterval = 60
    public static let twoMinutes: TimeInterval = 60 * 2
    public static let oneHour: TimeInterval = 60 * 60
    public static let sixHours: TimeInterval = 6 * 60 * 60
    public static let oneDay: TimeInterval = 24 * 60 * 60
    public static let oneWeek: TimeInterval = 7 * 24 * 60 * 60
    public static let oneMonth: TimeInterval = 30 * 24 * 60 * 60
    public static let oneYear: TimeInterval = 365 * 24 * 60 * 60
}
