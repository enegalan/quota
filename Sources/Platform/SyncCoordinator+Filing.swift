import Foundation
@testable import Core

/// What happens to the record of a reading once it has been accepted.
///
/// Split from the coordinator the way `SyncCoordinator+Reading` is: filing is the
/// half that can lose data, and keeping it in its own file is what makes the
/// question "what did this reading do to the stored state" answerable without
/// also reading what the interface is allowed to show.
extension SyncCoordinator {
    /// Notes that the provider answered, and which account it answered for.
    ///
    /// Against the provider rather than the quota: the schedule and the interface
    /// both ask "when did this provider last answer", and a quota reading does not
    /// answer it. Recorded here rather than at the call site so every path that
    /// files a reading records the answer, including the one a future caller adds.
    func recordSuccess(
        _ snapshot: UsageSnapshot,
        for quota: Quota,
        accountLabel: String
    ) async throws {
        guard let record = try await providers.provider(quota.providerID) else { return }
        try await providers.save(
            record.withSuccessfulSync(at: snapshot.updatedAt, accountLabel: accountLabel)
        )
    }

    /// Recomputes the allocation plan from the reading just filed.
    ///
    /// Every successful snapshot, with nothing asked of the user:
    /// make the plan a consequence of the reading rather than something the user
    /// sets up, and a plan that waited for a button would be a plan that is
    /// wrong for as long as nobody presses it.
    ///
    /// Takes the bucket the quota reads rather than the snapshot, so neither the
    /// usage figure nor the window can come from a pool the user did not pick, and
    /// the reading's own instant rather than the clock, so a plan is computed as of
    /// the reading that justified it.
    func replan(
        for quota: Quota,
        bucket: UsageBucket,
        at instant: Date,
        accountLabel: String
    ) async throws {
        let remaining = max(
            UsageConstants.percentageScale - bucket.usagePercentage,
            UsageConstants.minimumPercentage
        )
        // Not caught, and that is a decision: the only way the engine throws is
        // a negative allowance, and the value above is the difference of two
        // validated percentages, so it cannot be negative. Catching it here
        // would mean a plan silently not existing for a quota whose usage is
        // perfectly readable, which is the failure is most concerned with.
        let plan = try engine.plan(
            quotaID: quota.id,
            policy: quota.policy,
            period: bucket.period,
            totalRemaining: remaining,
            asOf: instant
        )
        try await plans.save(plan, accountLabel: accountLabel)
    }

    /// Extends a bucket's timeline with this reading.
    ///
    /// Separate from the rest of filing a success because the timeline is the
    /// only part that has to merge with what is already there, and merging is
    /// where a period change would otherwise be mixed into the old cycle's
    /// points.
    func appendToTimeline(
        _ bucket: UsageBucket,
        at instant: Date,
        bucketID: String,
        quota: Quota,
        accountLabel: String
    ) async throws {
        let existing = try await timelines.timeline(
            quotaID: quota.id, bucketID: bucketID, accountLabel: accountLabel
        )?.timeline ?? UsageTimeline(points: [])
        let point = try TimelinePoint(
            recordedAt: instant,
            bucketID: bucketID,
            usagePercentage: bucket.usagePercentage
        )
        try await timelines.append(
            TimelineRecord(
                quotaID: quota.id,
                bucketID: bucketID,
                accountLabel: accountLabel,
                timeline: UsageTimeline(points: existing.points + [point])
            ),
            keepingAtMost: RefreshConstants.timelineRetention
        )
    }
}
