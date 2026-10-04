import Core
import Foundation
import Platform

/// Builds the `QuotaSummary` a view renders, out of what is stored.
///
/// The one place the stored facts become the values lists. Doing it here
/// rather than in a view means the popover, the menu bar item, and the calendar
/// cannot each decide separately what "remaining" means, and it means the rules
/// are testable without rendering anything.
///
/// Everything it needs arrives through the initialiser — the repositories, the
/// calendar, and the reference instant — so a summary can be built for a chosen
/// moment in a test, and so a figure cannot be computed once for display and
/// once for a decision and come out different.
struct SummaryPresenter: Sendable {
    /// How many days the future-allocation strip shows.
    ///
    /// A week, because that is the span a user can act on: a strip long enough
    /// to show a whole month's daily shares would be a list.
    static let upcomingDayCount = DateConstants.daysInWeek

    private let quotas: QuotaRepository
    private let snapshots: SnapshotRepository
    private let timelines: TimelineRepository
    private let providers: ProviderRepository
    private let plans: AllocationPlanRepository
    private let calendar: Calendar
    private let reference: Date

    init(
        quotas: QuotaRepository,
        snapshots: SnapshotRepository,
        timelines: TimelineRepository,
        providers: ProviderRepository,
        plans: AllocationPlanRepository,
        calendar: Calendar,
        reference: Date
    ) {
        self.quotas = quotas
        self.snapshots = snapshots
        self.timelines = timelines
        self.providers = providers
        self.plans = plans
        self.calendar = calendar
        self.reference = reference
    }

    /// Every quota the app knows about, as a summary.
    ///
    /// A quota whose provider has never answered produces a summary with no
    /// snapshot rather than being left out: the user added it, and an
    /// interface that silently omits a quota looks like data loss.
    func presentations() async throws -> [QuotaPresentation] {
        var presentations: [QuotaPresentation] = []
        for quota in try await quotas.all() {
            await presentations.append(try presentation(for: quota))
        }
        return presentations
    }

    /// One quota, ready to render.
    ///
    /// The account label travels with the summary because two things need it and
    /// neither can derive it: the timeline is keyed by it, so a calendar built
    /// without it would show no history, and the provider line is expected to
    /// say which account the numbers belong to.
    func presentation(for quota: Quota) async throws -> QuotaPresentation {
        let account = try await accountLabel(for: quota)
        guard let account else {
            return QuotaPresentation(summary: QuotaSummary(quota: quota), accountLabel: nil)
        }
        let record = try await reading(for: quota, accountLabel: account)
        let snapshot = record?.snapshot
        let bucketID = quota.bucketID ?? record?.bucketID ?? snapshot?.primaryBucket?.id
        let timeline: UsageTimeline? = if let bucketID {
            try await timelines.timeline(
                quotaID: quota.id,
                bucketID: bucketID,
                accountLabel: account
            )?.timeline
        } else {
            nil
        }
        let plan = try await plans.plan(quotaID: quota.id)
        let summary = QuotaSummary(
            quota: quota,
            snapshot: snapshot,
            plan: plan,
            pacing: pacing(for: quota, snapshot: snapshot, plan: plan),
            todayAllowance: todayAllowance(plan: plan, timeline: timeline, bucketID: bucketID),
            upcoming: upcoming(from: plan)
        )
        return await QuotaPresentation(
            summary: summary,
            accountLabel: account,
            bucketID: bucketID,
            timeline: timeline,
            unavailableBucketName: try unavailableBucketName(for: summary, accountLabel: account)
        )
    }

    /// What to call the limit this quota watches, when the provider no longer
    /// reports it.
    ///
    /// The name comes from the last reading that did carry the limit, because the
    /// identifier a provider uses is its own — `cursor.premium` says nothing to
    /// the user looking at a quota called "Premium requests". The search is across
    /// every quota on the same provider rather than this one alone, because a
    /// provider that meters several limits writes one reading per quota and the
    /// record that still holds the name is whichever of them was not refreshed
    /// after the limit went: the quota that watched it is precisely the one whose
    /// reading has lost it.
    ///
    /// The identifier is the fallback rather than the first choice: a provider
    /// that drops a limit and renames it in the same refresh leaves nothing to
    /// name it by, and the identifier still identifies it exactly.
    private func unavailableBucketName(
        for summary: QuotaSummary,
        accountLabel: String
    ) async throws -> String? {
        guard let bucketID = summary.unavailableBucketID else { return nil }
        let onProvider = try await quotas.all()
            .filter { $0.providerID == summary.quota.providerID }
            .map(\.id)
        let lastNamed = try await snapshots.all()
            .filter { $0.accountLabel == accountLabel && onProvider.contains($0.quotaID) }
            .sorted { $0.snapshot.updatedAt > $1.snapshot.updatedAt }
            .compactMap { $0.snapshot.bucket(id: bucketID)?.displayName }
            .first
        return lastNamed ?? bucketID
    }

    /// The stored reading for a quota, however the quota names its bucket.
    ///
    /// A quota that names a bucket is read by that name. One that does not is
    /// read from whichever record the provider filed, because the bucket's name
    /// is the provider's to choose: a quota created before the provider reported
    /// a bucket has no name to look up, and assuming one — "primary", the name
    /// this app happens to use internally — would find nothing and render the
    /// quota as though it had never been read. To a user that is indistinguishable
    /// from losing their history.
    private func reading(for quota: Quota, accountLabel: String) async throws -> SnapshotRecord? {
        if let bucketID = quota.bucketID {
            return try await snapshots.snapshot(
                quotaID: quota.id,
                bucketID: bucketID,
                accountLabel: accountLabel
            )
        }
        return try await snapshots.snapshots(quotaID: quota.id, accountLabel: accountLabel)
            .sorted { $0.snapshot.updatedAt > $1.snapshot.updatedAt }
            .first
    }

    /// Today's block: how much is planned for today, how much has been used, and
    /// what is left of it.
    ///
    /// Usage is stored; remaining is derived from it. A view that read usage from
    /// the timeline and remaining from a figure baked earlier could disagree about
    /// the same day, and the three lines of the today block would stop adding up.
    /// The used figure is nil whenever the day's usage cannot be established: a
    /// provider that has not reported since yesterday has not spent nothing today,
    /// it has spent an unknown amount, and showing the whole allowance as
    /// available would invite the user to overspend.
    func todayAllowance(
        plan: AllocationPlan?,
        timeline: UsageTimeline?,
        bucketID: String?
    ) -> TodayAllowance? {
        let today = LocalDate(date: reference, calendar: calendar)
        guard let suggested = plan?.allocation(on: today)?.percentage else { return nil }
        return TodayAllowance(
            date: today,
            suggested: suggested,
            usedToday: usedToday(timeline: timeline, bucketID: bucketID)
        )
    }

    /// What the user has used so far today, as the timeline can establish it.
    func usedToday(timeline: UsageTimeline?, bucketID: String?) -> Double? {
        guard let timeline, let bucketID else { return nil }
        return timeline.usedOn(
            bucketID: bucketID,
            from: calendar.startOfDay(for: reference),
            to: reference,
            calendar: calendar
        )
    }

    /// Future strip: the days coming up, with the zeros left in.
    ///
    /// Zero-allocation days are kept rather than filtered out. A strip that
    /// skipped them would suggest a run of days that all have an allowance,
    /// which is the opposite of what a weekly pattern is for.
    func upcoming(from plan: AllocationPlan?) -> [Allocation] {
        guard let plan else { return [] }
        let today = LocalDate(date: reference, calendar: calendar)
        return Array(
            plan.allocations
                .filter { $0.date >= today }
                .sorted { $0.date < $1.date }
                .prefix(Self.upcomingDayCount)
        )
    }

    /// Empty-plan state, when the policy left nothing to plan.
    func noEligibleDays(in plan: AllocationPlan?) -> Double? {
        guard case .noEligibleDays(let retained) = plan?.validation else { return nil }
        return retained
    }

    /// The pacing verdict, or nil when there is no plan to pace against.
    ///
    /// Held here rather than in a view because evaluating a plan needs a
    /// calendar, and this type's calendar is the one the rest of the summary
    /// was resolved against. A view building its own would be building a
    /// second from the current locale, and "today" could then differ from the
    /// instant the figures beside it were computed for.
    private func pacing(
        for quota: Quota,
        snapshot: UsageSnapshot?,
        plan: AllocationPlan?
    ) -> PacingStatus? {
        guard let plan else { return nil }
        return PacingCalculator(calendar: calendar).status(
            quota: quota,
            snapshot: snapshot,
            plan: plan,
            asOf: reference
        )
    }

    /// The account this quota's figures are filed under, as the provider words it.
    private func accountLabel(for quota: Quota) async throws -> String? {
        try await providers.provider(quota.providerID)?.authenticatedAccountLabel
    }
}
