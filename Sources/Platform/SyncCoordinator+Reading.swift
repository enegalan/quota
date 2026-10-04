import Core
import Foundation

/// What the coordinator shows, and what it knows about a provider.
///
/// Split from the coordinator itself so the decision of *what may be shown*
/// can be read without also reading the decision of *how a reading is filed*.
/// They are the two halves of and they fail in different ways: filing
/// wrongly loses data, showing wrongly lies to the user, and a file holding
/// both invites review to check the second whenever the first changes.
public extension SyncCoordinator {
    // MARK: - What to show

    /// The reading to show for a quota right now, or why there is none.
    ///
    /// The order of the checks is the design. A pool the provider has stopped
    /// reporting is refused before the period is considered, because a quota
    /// watching it has no window of its own left to have ended. Then a period
    /// that has ended is refused before freshness, because a reading whose
    /// period is over is not a stale reading of this cycle, it is a *correct*
    /// reading of a cycle that has finished; showing it as this cycle's numbers
    /// is the failure describes, and an outage spanning a period boundary is
    /// exactly when it would happen.
    func reading(for quotaID: UUID) async throws -> ReadingOutcome {
        guard let quota = try await quotas.quota(id: quotaID) else {
            throw SyncError.noQuota(quotaID)
        }
        guard let accountLabel = try await providers.provider(quota.providerID)?
            .authenticatedAccountLabel
        else { return .unserved(.noAccount) }

        guard let record = try await latestReading(of: quota, accountLabel: accountLabel) else {
            return .unserved(.neverSynced)
        }

        // The window of the bucket this quota reads, not the reading's first one.
        // A five-hour quota and a weekly quota can share a reading and share
        // nothing else, and refusing one of them five hours in because the
        // reading as a whole is stale would be a rule about the provider rather
        // than about the quota the user is looking at.
        guard let period = record.snapshot.period(forBucket: quota.bucketID) else {
            return .unserved(.bucketUnavailable(quota.bucketID ?? record.bucketID))
        }

        let now = now()
        if period.end <= now {
            return .unserved(.periodEnded(endedAt: period.end))
        }
        let freshness = Freshness.of(age: StalenessPolicy.age(of: record.snapshot, now: now))
        guard freshness.permitsDisplay else { return .unserved(.tooOld(freshness)) }

        return .served(
            ServedReading(
                snapshot: record.snapshot, freshness: freshness, accountLabel: accountLabel
            )
        )
    }

    /// The most recent reading filed for a quota, whichever bucket it is in.
    ///
    /// A quota does not always name its bucket — a provider that meters one pool
    /// is left unnamed until the pool is known. Looking it up by the quota's own
    /// bucket alone would then search for a bucket that does not exist and report
    /// a quota that has been read all along as never synced, so the bucket is
    /// taken from the reading when the quota does not say.
    private func latestReading(of quota: Quota, accountLabel: String) async throws -> SnapshotRecord? {
        if let bucketID = quota.bucketID {
            return try await snapshots.snapshot(
                quotaID: quota.id, bucketID: bucketID, accountLabel: accountLabel
            )
        }
        return try await snapshots.all()
            .filter { $0.quotaID == quota.id && $0.accountLabel == accountLabel }
            .max { $0.snapshot.updatedAt < $1.snapshot.updatedAt }
    }

    /// The words to put under a reading.
    ///
    /// A failure changes the sentence, not the figure: the reading
    /// stays visible with its age stated, and the age is the thing a user
    /// cannot see for themselves.
    func caption(
        for reading: ServedReading,
        lastFailure: SyncFailure? = nil
    ) -> String {
        let age = StalenessPolicy.age(of: reading.snapshot, now: now())
        guard lastFailure != nil else {
            return "Updated \(relativeTime.wording(for: age))."
        }
        return relativeTime.describeFailure(age: age)
    }

    // MARK: - State

    /// What is known about a provider right now.
    func status(for providerID: ProviderID) async -> ConnectionStatus {
        guard let record = try? await providers.provider(providerID) else {
            return .unknown(providerID)
        }
        return await ConnectionStatus(
            providerID: providerID,
            accountLabel: record.authenticatedAccountLabel,
            lastSuccessfulSync: record.lastSyncAt,
            lastError: record.lastFailure,
            // Taken from the same place as the exact answer, so the two cannot
            // disagree. `nextRefresh(for:)` needs a jitter source to be
            // testable, which a status has no way to supply, so this uses the
            // schedule's own default and the interface treats the value as
            // approximate — it is for a "next check in" label, not for deciding
            // when to read.
            nextScheduledRefresh: try? nextRefresh(for: providerID)
        )
    }

    /// When this provider should next be read, given the outcome of its last
    /// attempt.
    ///
    /// - Parameter jitterSource: injected so the offset is testable; a real
    ///   random source would make every test of the schedule either flaky or
    ///   unable to assert the offset at all.
    func nextRefresh(
        for providerID: ProviderID,
        jitterSource: () -> Double = { Double.random(in: 0 ..< 1) }
    ) async throws -> Date? {
        guard let record = try await providers.provider(providerID) else { return nil }
        let last = record.lastFailure?.occurredAt ?? record.lastSyncAt
        guard let last else { return nil }
        return await effectiveSchedule(for: record).nextRefresh(after: last, jitterSource: jitterSource)
    }

    /// The schedule in force for a provider, given what it last said.
    ///
    /// The failure count comes off the stored record rather than off the
    /// coordinator, so a provider that failed five times before the app was last
    /// opened still backs off for the sixth. Counting in memory would back off
    /// exactly once per launch, and a menu bar app is mostly not running.
    ///
    /// Preference order: the provider's own suggestion, then the user's configured
    /// interval, then the platform default. All are clamped by the schedule.
    func effectiveSchedule(for record: ProviderRecord) async -> RefreshSchedule {
        let userPreferred: TimeInterval? = if let preferences {
            try? await preferences.load().refreshIntervalSeconds
        } else {
            nil
        }
        let suggestion = record.suggestedRefreshInterval ?? userPreferred
        let base = suggestion.map { RefreshSchedule(providerSuggestion: $0) } ?? schedule
        guard let code = record.lastFailure?.code, code.backsOff else { return base }
        return base.withConsecutiveFailures(record.consecutiveFailures)
    }

    /// What is known about a provider, for the freshness states the interface
    /// must be able to show.
    func freshness(for providerID: ProviderID) async -> Freshness {
        guard let last = try? await providers.provider(providerID)?.lastSyncAt else {
            return .unavailable
        }
        return Freshness.of(age: now().timeIntervalSince(last))
    }
}
