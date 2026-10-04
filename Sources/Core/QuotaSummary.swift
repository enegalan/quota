import Foundation

/// The single value the interface renders for one quota.
///
/// This type is where the separation between what a provider reported and what
/// the user planned is resolved. It holds both a `Quota` and, when one is
/// available, the `UsageSnapshot` it should be read against, so the interface
/// never has to decide for itself which of the two is stale, and never sees a
/// usage figure without the timestamp that qualifies it.
///
/// A summary with no snapshot is a legitimate state: the app is correct before
/// the first sync completes, and it is correct again whenever a provider is
/// unreachable. The interface renders "no reading yet" rather than zero, because
/// a quota that has never been measured is not an exhausted quota.
public struct QuotaSummary: Sendable, Hashable, Identifiable {
    public let quota: Quota
    public let snapshot: UsageSnapshot?
    public let plan: AllocationPlan?
    public let pacing: PacingStatus?
    public let todayAllowance: TodayAllowance?
    public let upcoming: [Allocation]

    public var id: UUID {
        quota.id
    }

    public init(
        quota: Quota,
        snapshot: UsageSnapshot? = nil,
        plan: AllocationPlan? = nil,
        pacing: PacingStatus? = nil,
        todayAllowance: TodayAllowance? = nil,
        upcoming: [Allocation] = []
    ) {
        self.quota = quota
        self.snapshot = snapshot
        self.plan = plan
        self.pacing = pacing
        self.todayAllowance = todayAllowance
        self.upcoming = upcoming
    }

    /// The provider reading this quota is interested in, if there is one.
    ///
    /// Resolved through the quota's bucket reference, so a quota pointing at a
    /// non-primary bucket shows that bucket's figure rather than the first one.
    public var usage: UsageBucket? {
        snapshot?.bucket(id: quota.bucketID)
    }

    /// The limit this quota watches, when the reading no longer carries it.
    ///
    /// The provider has stopped metering this pool — renamed, merged, or gone —
    /// and the quota is kept rather than deleted, because a pool that comes back
    /// must find the quota that was waiting for it. What the interface must not
    /// do in the meantime is show another pool's figure here: two quotas on one
    /// provider showing one set of numbers is the failure the bucket rule exists
    /// to prevent.
    ///
    /// Nil when there is no reading at all. A quota never read is waiting for a
    /// first reading, which is a different thing to say, and a limit cannot be
    /// missing from a reading that does not exist.
    public var unavailableBucketID: String? {
        guard let snapshot, let bucketID = quota.bucketID else { return nil }
        return snapshot.bucket(id: bucketID) == nil ? bucketID : nil
    }

    /// Whether the reading is old enough that the interface must say so.
    ///
    /// Takes the reference instant rather than reading the clock, so a test can
    /// place itself at a chosen moment and so the value cannot drift between
    /// being computed and being displayed.
    ///
    /// False when there is no reading at all: absence is already communicated by
    /// the summary having no snapshot, and calling a reading nobody has out of
    /// date would describe a value that does not exist.
    public func isOutOfDate(asOf now: Date) -> Bool {
        guard let snapshot else { return false }
        return StalenessPolicy.isOutOfDate(snapshot: snapshot, now: now)
    }
}
