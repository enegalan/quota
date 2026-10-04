import Core
import Foundation
import PluginKit

/// Reads one provider's usage.
///
/// A protocol so the coordinator's rules can be tested against a scripted
/// provider, and so the coordinator does not have to know how a plugin is
/// launched. `PluginHost` is the production implementation; the tests supply a
/// fake that answers from a script. requires the whole flow to be testable
/// without a network, and this is the seam that makes it so.
public protocol UsageFetching: Sendable {
    /// Reads usage for one account, or says why it could not.
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome
}

/// A reading the app is prepared to show, and what it is allowed to say about
/// it.
///
/// The pair, rather than a snapshot alone, because the two decisions are made in
/// different places and disagreeing is the bug warns about: a figure and a
/// caption that contradict each other, or worse, a figure from a period that has
/// ended shown as though it were this cycle's.
public struct ServedReading: Sendable, Equatable {
    public let snapshot: UsageSnapshot
    public let freshness: Freshness
    public let accountLabel: String

    public init(snapshot: UsageSnapshot, freshness: Freshness, accountLabel: String) {
        self.snapshot = snapshot
        self.freshness = freshness
        self.accountLabel = accountLabel
    }
}

/// What to show for a quota, or why there is nothing.
///
/// A sum rather than a `Result`, because a reason with nothing to show is not a
/// failure of the program — it is one of the states the interface must be
/// able to display — and making it `Error` would invite a caller to treat a quota
/// that has never synced as something to be thrown about.
public enum ReadingOutcome: Sendable, Equatable {
    case served(ServedReading)
    case unserved(UnservedReason)

    public var reading: ServedReading? {
        switch self {
        case .served(let reading): reading
        case .unserved: nil
        }
    }

    public var reason: UnservedReason? {
        switch self {
        case .served: nil
        case .unserved(let reason): reason
        }
    }
}

/// Why there is nothing to show for a quota.
public enum UnservedReason: Sendable, Equatable {
    /// There has never been a reading for this quota.
    case neverSynced
    /// The last reading is older than the app will show.
    case tooOld(Freshness)
    /// The reading's period has ended, so its figures belong to a cycle that is
    /// over and the provider has not been read since.
    case periodEnded(endedAt: Date)
    /// The provider has no account connected, so nothing was ever read.
    case noAccount
    /// The provider no longer reports the pool this quota watches.
    ///
    /// Carries the identifier it stopped reporting under, so the interface can
    /// name what it is waiting for rather than say a quota has no reading. The
    /// quota is kept: a pool that is renamed or merged comes back, and the
    /// alternative to reporting this honestly is showing another pool's figure
    /// under this quota's name, which is the one thing the two-panel rule exists
    /// to prevent.
    case bucketUnavailable(String)
}

public enum SyncError: Error, Equatable {
    case noQuota(UUID)
}

/// Refreshes quotas and keeps the record of what they last said.
///
/// Deliberately has no timer. It answers "refresh this quota" and "what should
/// be shown for this quota", and something above it decides when to call. A
/// coordinator that owns a timer cannot be tested for a policy, only observed,
/// and the policies here — keep the last good reading, refuse a period that has
/// ended, reset the timeline on a period change — are the whole point.
public struct SyncCoordinator: Sendable {
    let quotas: QuotaRepository
    let snapshots: SnapshotRepository
    let timelines: TimelineRepository
    let providers: ProviderRepository
    // Internal rather than private so the filing extension can reach them, as the
    // reading extension already does for the repositories.
    let plans: AllocationPlanRepository
    let engine: AllocationEngine
    private let fetcher: any UsageFetching
    let relativeTime: RelativeTime
    let schedule: RefreshSchedule
    let calendar: Calendar
    let now: @Sendable () -> Date
    let preferences: PreferencesRepository?

    public init(
        quotas: QuotaRepository,
        snapshots: SnapshotRepository,
        timelines: TimelineRepository,
        providers: ProviderRepository,
        plans: AllocationPlanRepository,
        engine: AllocationEngine,
        fetcher: any UsageFetching,
        relativeTime: RelativeTime = RelativeTime(),
        schedule: RefreshSchedule = RefreshSchedule(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        preferences: PreferencesRepository? = nil
    ) {
        self.quotas = quotas
        self.snapshots = snapshots
        self.timelines = timelines
        self.providers = providers
        self.plans = plans
        self.engine = engine
        self.fetcher = fetcher
        self.relativeTime = relativeTime
        self.schedule = schedule
        self.calendar = calendar
        self.now = now
        self.preferences = preferences
    }

    // MARK: - What a provider has said about itself

    /// Remembers how long a provider asked not to be read again.
    ///
    /// Separate from a refresh because the two happen at different times: a
    /// plugin states its preference when it describes itself, which may be long
    /// before there is a reading to file, and which for a provider that cannot
    /// be read at all is the only thing the app ever learns. Storing it on the
    /// record rather than in the schedule means it survives a restart, which is
    /// the difference between honouring a provider's rate limit and honouring it
    /// until the app is next opened.
    @discardableResult
    public func noteSuggestedRefreshInterval(
        _ interval: TimeInterval?,
        for providerID: ProviderID
    ) async throws -> ProviderRecord? {
        guard let record = try await providers.provider(providerID) else { return nil }
        let updated = ProviderRecord(
            providerID: record.providerID,
            displayName: record.displayName,
            installedVersion: record.installedVersion,
            authenticatedAccountLabel: record.authenticatedAccountLabel,
            lastSyncAt: record.lastSyncAt,
            lastFailure: record.lastFailure,
            consecutiveFailures: record.consecutiveFailures,
            suggestedRefreshInterval: interval
        )
        try await providers.save(updated)
        return updated
    }

    // MARK: - Refreshing

    /// Reads one quota's provider and records what came back.
    ///
    /// A failure records the failure and returns it; it does not touch the
    /// snapshot or the timeline. That is the whole freshness requirement, and it
    /// is why recording a failure is a different function from recording a
    /// success: a change that wrote the timeline on the way out of a failed read
    /// is caught by the same test that says a failure leaves the reading alone.
    @discardableResult
    public func refresh(quotaID: UUID) async throws -> SyncOutcome {
        guard let quota = try await quotas.quota(id: quotaID) else {
            throw SyncError.noQuota(quotaID)
        }
        let today = LocalDate(date: now(), calendar: calendar)

        guard
            let provider = try await providers.provider(quota.providerID),
            let accountLabel = provider.authenticatedAccountLabel
        else {
            // No account is a state the interface shows, not a mistake the user
            // made, so it comes back as a result rather than as a thrown error.
            let failure = SyncFailure(
                code: .notAuthenticated,
                message: "This provider is not connected to an account.",
                occurredAt: now()
            )
            try await note(failure, alongside: quota.providerID)
            return SyncOutcome(quotaID: quotaID, result: .failure(failure))
        }

        let outcome = await fetcher.fetchUsage(
            providerID: quota.providerID,
            accountLabel: accountLabel,
            localDate: today
        )
        if let suggestion = outcome.suggestedRefreshInterval {
            try await noteSuggestedRefreshInterval(suggestion, for: quota.providerID)
        }
        switch outcome.result {
        case .success(let snapshot):
            let changed = try await file(snapshot, for: quota, accountLabel: accountLabel)
            return SyncOutcome(quotaID: quotaID, result: outcome.result, periodChanged: changed)
        case .failure(let failure):
            try await note(failure, alongside: quota.providerID)
            return SyncOutcome(quotaID: quotaID, result: outcome.result)
        }
    }

    /// Reads every quota once, one at a time.
    ///
    /// Sequentially, and that is a decision rather than an oversight: providers
    /// are external services with rate limits, and a burst of simultaneous polls
    /// on first launch is the fastest way to be rate-limited on the first run a
    /// user ever sees. requires the frequency to respect rate limits, and
    /// honouring that means not firing everything at once either.
    public func refreshAll() async throws -> [SyncOutcome] {
        var outcomes: [SyncOutcome] = []
        for quota in try await quotas.all() {
            await outcomes.append(try refresh(quotaID: quota.id))
        }
        return outcomes
    }

    // MARK: - Recording

    /// Files a reading, extending the timeline and correcting the quota's period
    /// if the provider has moved it.
    ///
    /// The period corrected is the one belonging to the bucket this quota reads,
    /// not the reading's first bucket. That distinction is the whole reason the
    /// period lives on the bucket: two limits on one account can reset at
    /// different instants, and stamping both quotas with the same window made
    /// every refresh a "the provider moved the window" event — which deletes the
    /// timeline, so a five-hour quota and a weekly one erased each other's
    /// history on every poll and neither ever knew what it had spent today.
    ///
    /// - Returns: whether the period changed, which the caller reports because it
    ///   means the timeline the user has been looking at no longer applies.
    @discardableResult
    private func file(
        _ snapshot: UsageSnapshot,
        for quota: Quota,
        accountLabel: String
    ) async throws -> Bool {
        let bucketID = quota.bucketID ?? snapshot.primaryBucket?.id ?? ""

        // Filed before anything is decided about the quota, because the reading is
        // what the provider said whether or not this quota can use it.
        try await snapshots.save(
            SnapshotRecord(
                quotaID: quota.id,
                bucketID: bucketID,
                accountLabel: accountLabel,
                snapshot: snapshot
            )
        )

        guard let bucket = snapshot.bucket(id: quota.bucketID) else {
            // The provider no longer meters the pool this quota watches — it was
            // renamed, merged, or dropped. The reading is kept, and the quota keeps
            // the period it had, because another pool's window is not this quota's
            // to adopt. No timeline point is added: a point for a bucket that is
            // not in the reading would be a zero, and a zero reads as "nothing
            // spent today" when in fact the app no longer knows. `reading(for:)`
            // reports the pool as gone rather than showing a figure it cannot
            // attribute.
            try await recordSuccess(snapshot, for: quota, accountLabel: accountLabel)
            return false
        }

        let changed = bucket.period != quota.period

        if changed {
            // The provider says it is metering a different window, so the quota
            // is corrected and the timeline dropped first. Keeping points from
            // the old period would make used-today a total across two cycles,
            // which is the one number that has no meaning at all. Dropped before
            // the new point is added so the timeline is never briefly a mix.
            try await timelines.delete(quotaID: quota.id)
        }
        try await appendToTimeline(
            bucket,
            at: snapshot.updatedAt,
            bucketID: bucketID,
            quota: quota,
            accountLabel: accountLabel
        )

        if changed {
            try await quotas.save(quota.withPeriod(bucket.period, updatedAt: snapshot.updatedAt))
        } else {
            try await quotas.save(quota.withUpdatedAt(snapshot.updatedAt))
        }
        try await recordSuccess(snapshot, for: quota, accountLabel: accountLabel)
        try await replan(for: quota, bucket: bucket, at: snapshot.updatedAt, accountLabel: accountLabel)
        return changed
    }

    /// Records a failure without disturbing the last good reading.
    private func note(_ failure: SyncFailure, alongside providerID: ProviderID) async throws {
        let existing = try await providers.provider(providerID)
        let record = existing ?? ProviderRecord(
            providerID: providerID,
            displayName: providerID.rawValue,
            installedVersion: "0.0.0"
        )
        try await providers.save(record.withFailure(failure))
    }
}
