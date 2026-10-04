import Core
import Foundation

/// Typed access to the quotas a user has configured.
///
/// A thin typed layer over `QuotaStore`, not a second persistence boundary: it
/// adds no storage of its own, so there is exactly one place where a record can
/// be written and exactly one set of atomicity guarantees.
public struct QuotaRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every configured quota.
    ///
    /// The whole set rather than a page, and the single read every lookup below
    /// filters. Keeping the narrowing in one place is the point: a caller that
    /// filtered the store itself would be able to hold a different idea of what
    /// is configured from the one the repository acts on.
    public func all() async throws -> [Quota] {
        try await store.loadQuotas().map(\.quota)
    }

    /// The quota with this identifier.
    ///
    /// - Returns: nil when no such quota is stored. Absence is a normal answer:
    ///   a quota removed in one window is still on screen in another, and the
    ///   interface has to be able to ask without treating the question as a
    ///   fault.
    public func quota(id: UUID) async throws -> Quota? {
        try await all().first { $0.id == id }
    }

    /// Writes a quota that must not already be there.
    ///
    /// Separate from `save` because saving is also how a quota is *changed* — a
    /// policy edit rewrites the same record — and a uniqueness rule applied to
    /// every write would refuse an edit of the very quota it is protecting.
    /// Only a caller creating a new quota comes through here, so the rule cannot
    /// be skipped by reaching for `save` instead.
    public func create(_ new: Quota) async throws {
        if let existing = try await quota(conflictingWith: new) {
            throw QuotaRegistrationError.alreadyRegistered(
                providerID: new.providerID.rawValue,
                bucketID: new.bucketID,
                quotaName: existing.name
            )
        }
        try await save(new)
    }

    /// Writes a quota, replacing any record with the same identifier.
    ///
    /// An upsert rather than an insert, because a policy edit rewrites the same
    /// record: appending would leave the old copy beside the new one and every
    /// listing would show the quota twice. Creating a quota goes through
    /// `create`, which is where the uniqueness rule is enforced.
    public func save(_ quota: Quota) async throws {
        try await store.saveQuotas(
            upserting(QuotaRecord(quota: quota), into: try store.loadQuotas()) {
                $0.quota.id == quota.id
            }
        )
    }

    /// Replaces every stored quota with this set.
    ///
    /// Wholesale, so a caller writing a known set does not have to read what is
    /// already there to know what will survive. Nothing in the app uses this
    /// form; it exists for the tests that need a starting position they can state
    /// in one line.
    public func save(_ quotas: [Quota]) async throws {
        try await store.saveQuotas(quotas.map(QuotaRecord.init(quota:)))
    }

    /// Removes one quota and leaves the rest of the store alone.
    ///
    /// Only the quota itself: the readings, timeline, and plan keyed to it are
    /// dropped by the caller in the same operation. A cascade here would own a
    /// rule the interface cannot see, and the interface is what has to say what
    /// deleting a quota takes with it.
    public func delete(id: UUID) async throws {
        let records = try await store.loadQuotas().filter { $0.quota.id != id }
        try await store.saveQuotas(records)
    }

    /// Every quota belonging to a provider.
    ///
    /// A list rather than a single value because a provider can hold several —
    /// one per bucket, one per account — and a caller asking "what does this
    /// provider cost me" is asking about all of them.
    public func quotas(providerID: ProviderID) async throws -> [Quota] {
        try await all().filter { $0.providerID == providerID }
    }

    /// The quota watching one bucket of one provider, if there is one.
    ///
    /// A nil bucket and a named bucket are different quotas, not the same one
    /// twice: a provider that meters several pools is entitled to a quota per
    /// pool, and a rule that ignored the bucket would refuse the second of two
    /// quotas that read genuinely different numbers.
    public func quota(providerID: ProviderID, bucketID: String?) async throws -> Quota? {
        try await all().first { $0.providerID == providerID && $0.bucketID == bucketID }
    }

    /// The quota already in the way of `new`, if any.
    ///
    /// The bucket comparison alone is not enough, because a quota that names no
    /// bucket reads the provider's primary one: a nil-bucket quota and a quota
    /// naming that primary are two records describing one set of readings, which
    /// is the two-panels-disagreeing case the rule exists to refuse. The
    /// repository cannot know which identifier a provider calls its primary
    /// without a reading, so the safe direction is taken instead: a quota that
    /// names no bucket is in the way of every quota on its provider, and is in
    /// the way of any quota created without one.
    ///
    /// Only consulted on creation. A quota never changes which bucket it reads,
    /// so an existing pair cannot drift into this state and an edit is unaffected.
    public func quota(conflictingWith new: Quota) async throws -> Quota? {
        try await all().first { existing in
            existing.providerID == new.providerID
                && (existing.bucketID == nil || new.bucketID == nil || existing.bucketID == new.bucketID)
        }
    }
}

/// Why a quota was not registered.
///
/// A distinct type rather than a `QuotaDomainError` case, because this is not a
/// claim about a value being malformed: the value is well formed, and what
/// refuses it is what is already stored next to it. A domain error here would
/// say a user typed something wrong when they typed something correct.
public enum QuotaRegistrationError: Error, Equatable, Sendable, LocalizedError {
    /// This provider already has a quota on this bucket.
    case alreadyRegistered(providerID: String, bucketID: String?, quotaName: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRegistered(_, let bucketID, let quotaName):
            if let bucketID {
                "\(quotaName) already watches \(bucketID) on this provider. Remove it first, or watch a different bucket."
            } else {
                "\(quotaName) already watches this provider. Remove it first, or watch a different bucket."
            }
        }
    }
}

/// Typed access to the latest reading per quota, bucket, and account.
public struct SnapshotRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every cached reading.
    ///
    /// The unfiltered read the three below filter. Nothing is pre-indexed, so
    /// this is the only place the whole family is read and the only place a
    /// caller could get an answer that disagrees with the others.
    public func all() async throws -> [SnapshotRecord] {
        try await store.loadSnapshots()
    }

    /// The reading for one quota, bucket, and account.
    ///
    /// The account label is part of the key, not a field to compare afterwards.
    /// A user who switches accounts inside one provider would otherwise be shown
    /// the previous account's numbers for as long as the old cache entry lived.
    public func snapshot(
        quotaID: UUID,
        bucketID: String,
        accountLabel: String
    ) async throws -> SnapshotRecord? {
        try await all().first {
            $0.quotaID == quotaID && $0.bucketID == bucketID && $0.accountLabel == accountLabel
        }
    }

    /// Every reading for a quota, so a quota with several buckets resolves all of
    /// them rather than only the last one written.
    public func snapshots(quotaID: UUID, accountLabel: String) async throws -> [SnapshotRecord] {
        try await all().filter { $0.quotaID == quotaID && $0.accountLabel == accountLabel }
    }

    /// Stores a reading, replacing the record held under the same key.
    ///
    /// Replaced on the full key rather than the quota, because a quota watching
    /// two buckets has two readings and neither is the other's successor: the
    /// upsert that is right for a quota would overwrite one pool's figure with
    /// the other's on every refresh.
    public func save(_ record: SnapshotRecord) async throws {
        try await store.saveSnapshots(
            upserting(record, into: try all()) { $0.id == record.id }
        )
    }

    /// Removes every reading belonging to one quota.
    ///
    /// Across every bucket and account, because those readings belong to a quota
    /// that no longer exists and nothing else will ever overwrite or invalidate
    /// them: they would sit in the file being read as if they were current.
    public func delete(quotaID: UUID) async throws {
        let records = try await all().filter { $0.quotaID != quotaID }
        try await store.saveSnapshots(records)
    }
}

/// Typed access to the recorded usage history.
public struct TimelineRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every recorded history.
    ///
    /// The read the two below filter, and the one place trimming is assumed to
    /// have happened already: `append` is the only route in, so what comes back
    /// is already within whatever limit each record was written under.
    public func all() async throws -> [TimelineRecord] {
        try await store.loadTimelines()
    }

    /// The recorded history for one quota, bucket, and account.
    ///
    /// - Returns: nil when nothing has been recorded for that key yet, which is
    ///   the ordinary state for a quota that has never been refreshed rather than
    ///   a fault to report.
    ///
    /// Keyed the same way as `SnapshotRepository`, for the same reason: a history
    /// under the previous account's label is a chart of numbers that are no longer
    /// the user's.
    public func timeline(
        quotaID: UUID,
        bucketID: String,
        accountLabel: String
    ) async throws -> TimelineRecord? {
        try await all().first {
            $0.quotaID == quotaID && $0.bucketID == bucketID && $0.accountLabel == accountLabel
        }
    }

    /// Appends points, discarding any beyond the retention limit.
    ///
    /// The bound is applied on write rather than on read so the file cannot grow
    /// without limit, and applying it here means the same limit holds however
    /// the timeline was reached.
    public func append(
        _ record: TimelineRecord,
        keepingAtMost limit: Int
    ) async throws {
        let trimmed = TimelineRecord(
            quotaID: record.quotaID,
            bucketID: record.bucketID,
            accountLabel: record.accountLabel,
            timeline: UsageTimeline(points: Array(record.timeline.points.suffix(limit)))
        )
        try await store.saveTimelines(
            upserting(trimmed, into: try all()) { $0.id == trimmed.id }
        )
    }

    /// Removes every recorded history belonging to one quota.
    ///
    /// Across every bucket and account, as with the snapshots: points left behind
    /// for a deleted quota would still be drawn on a chart, and a chart of a quota
    /// that no longer exists is a claim the interface cannot make.
    public func delete(quotaID: UUID) async throws {
        let records = try await all().filter { $0.quotaID != quotaID }
        try await store.saveTimelines(records)
    }
}

/// Typed access to the allocation plan last computed for each quota.
public struct AllocationPlanRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every stored plan.
    ///
    /// The read the lookups below filter. Plans are derived rather than recorded,
    /// so this list is a cache of what the engine last produced and nothing in it
    /// is the user's decision — which is why a caller that cannot find a plan
    /// here should recompute rather than complain.
    public func all() async throws -> [AllocationPlanRecord] {
        try await store.loadAllocationPlans()
    }

    /// The plan for one quota and account.
    ///
    /// The account is part of the key, so switching accounts inside a provider
    /// cannot show the previous account's plan, which is the same rule the
    /// snapshots follow.
    ///
    /// - Returns: nil when the quota has not been planned for that account, so
    ///   the caller knows to compute rather than to present nothing as a plan.
    public func plan(quotaID: UUID, accountLabel: String) async throws -> AllocationPlan? {
        try await all()
            .first { $0.quotaID == quotaID && $0.accountLabel == accountLabel }?
            .plan
    }

    /// The plan for one quota, whichever account it was computed for.
    ///
    /// The looser of the two lookups, for callers that have no account to hand:
    /// a quota's plan is a function of its own policy and period, so an account
    /// only ever affected which key it was filed under.
    public func plan(quotaID: UUID) async throws -> AllocationPlan? {
        try await all().first { $0.quotaID == quotaID }?.plan
    }

    /// Replaces the plan for a quota and account, discarding the old one.
    ///
    /// Replaced rather than merged because a plan is not a running total: each
    /// computation stands on its own, and keeping the previous one would let a
    /// caller present two different allocations for the same day.
    public func save(_ plan: AllocationPlan, accountLabel: String) async throws {
        let record = AllocationPlanRecord(
            quotaID: plan.quotaID, accountLabel: accountLabel, plan: plan
        )
        try await store.saveAllocationPlans(
            upserting(record, into: try all()) {
                $0.quotaID == record.quotaID && $0.accountLabel == record.accountLabel
            }
        )
    }

    /// Removes every stored plan belonging to one quota.
    ///
    /// Not just the current account's: a plan outlives nothing, and leaving one
    /// keyed to an account the user has left would let the looser lookup above
    /// hand it back as the plan for a quota being reconnected.
    public func delete(quotaID: UUID) async throws {
        let records = try await all().filter { $0.quotaID != quotaID }
        try await store.saveAllocationPlans(records)
    }
}
