import Core
import Foundation
import Platform

/// One quota, with everything a view needs to render it.
///
/// The app's own wrapper rather than an extension of the core's `QuotaSummary`,
/// because the extra values are presentation state: which account the figures
/// belong to, and which timeline they came from. Keeping them here means the
/// core's summary stays the domain's, and a view is handed one value that is
/// complete rather than three that must be matched up correctly.
struct QuotaPresentation: Identifiable, Hashable {
    let summary: QuotaSummary
    let accountLabel: String?
    let bucketID: String?
    let timeline: UsageTimeline?
    /// Sync caption from a failure or an unrefreshable provider.
    let syncStatus: String?
    let syncStatusIsWarning: Bool
    /// The name of the limit this quota watches, when the provider has stopped
    /// reporting it. Named so the interface can say which one rather than
    /// announcing that a quota has no reading.
    let unavailableBucketName: String?

    var id: UUID {
        summary.id
    }

    init(
        summary: QuotaSummary,
        accountLabel: String? = nil,
        bucketID: String? = nil,
        timeline: UsageTimeline? = nil,
        syncStatus: String? = nil,
        syncStatusIsWarning: Bool = false,
        unavailableBucketName: String? = nil
    ) {
        self.summary = summary
        self.accountLabel = accountLabel
        self.bucketID = bucketID
        self.timeline = timeline
        self.syncStatus = syncStatus
        self.syncStatusIsWarning = syncStatusIsWarning
        self.unavailableBucketName = unavailableBucketName
    }

    /// The same presentation with its sync caption filled in.
    ///
    /// A copy rather than a mutation, because the caption is decided by the
    /// model's continuity pass after the summary has been built. A
    /// presentation that could be annotated in place would let a view still
    /// holding an earlier one miss the caption while seeing the figures it
    /// belongs beside.
    func withSyncStatus(_ status: String?, isWarning: Bool) -> QuotaPresentation {
        QuotaPresentation(
            summary: summary,
            accountLabel: accountLabel,
            bucketID: bucketID,
            timeline: timeline,
            syncStatus: status,
            syncStatusIsWarning: isWarning,
            unavailableBucketName: unavailableBucketName
        )
    }

    /// A calendar over this quota's plan and history.
    ///
    /// Built from the timeline already resolved rather than looked up again, so
    /// the calendar cannot disagree with the summary above it about what was
    /// spent today.
    func calendar(calendar: Calendar, reference: Date) -> CalendarPresenter {
        CalendarPresenter(
            plan: summary.plan,
            timeline: timeline,
            allowance: summary.todayAllowance,
            bucketID: bucketID,
            calendar: calendar,
            reference: reference
        )
    }

    /// What is spent against the period.
    var usagePercentage: Double? {
        summary.usage?.usagePercentage
    }

    /// The share of the allowance not yet spent.
    ///
    /// Optional for the same reason the spent figure is: a limit the provider
    /// has stopped reporting carries no measurement, and printing "100%
    /// remaining" would hand back an allowance nobody is metering.
    ///
    /// Clamped at zero, because a provider reporting more than the whole
    /// allowance has spent none of what is left rather than a negative share of
    /// it, and two panels printing that differently is the disagreement the
    /// two-panel rule exists to remove.
    var remainingPercentage: Double? {
        summary.usage.map {
            max(0, UsageConstants.percentageScale - $0.usagePercentage)
        }
    }

    /// The period these figures belong to.
    ///
    /// The plan's where there is one, because the plan is computed for a
    /// specific period, and the quota's own otherwise — so a quota that has not
    /// been planned yet still counts down to its reset instead of losing the
    /// line. The days are a property of the clock the quota reads, not of
    /// whether a plan exists for it.
    var period: QuotaPeriod {
        summary.plan?.period ?? summary.quota.period
    }

    /// How many days the period has left, counted in the user's calendar.
    ///
    /// Counted against the user's calendar rather than any fixed one, because a
    /// day boundary set elsewhere reports a day still to run at an hour when the
    /// user's own day has already turned over.
    func daysRemaining(asOf reference: Date, calendar: Calendar) -> Int? {
        period.remainingDays(through: reference, calendar: calendar)
    }

    /// The line that says when the figures were last fetched.
    ///
    /// The provider's own failure text wins where there is one, because it names
    /// the reason and the user can do something about it. The relative age is
    /// what is left once a sync has succeeded, and freshness is then the only
    /// question worth asking about a number.
    ///
    /// "Never updated." is a sentence of its own rather than an age of zero: a
    /// provider that has never answered has not answered recently, and the two
    /// call for different reactions.
    func syncCaption(asOf reference: Date, calendar: Calendar) -> String {
        if let syncStatus {
            return syncStatus
        }
        guard let last = summary.snapshot?.updatedAt else {
            return "Never updated."
        }
        let age = RelativeTime(calendar: calendar).describe(since: last, now: reference)
        return "Updated \(age)."
    }

    /// The account this quota reads, or the words for not having one.
    ///
    /// Named here because four views said it, and a fourth view saying
    /// "Connected" instead is what a user would notice.
    var accountCaption: CaptionText {
        CaptionText(accountLabel ?? Self.disconnectedAccountCaption, isWarning: accountLabel == nil)
    }

    /// Whether the sync caption should read as a warning at this instant.
    ///
    /// The tone and the words come from the same place, so a screen cannot show
    /// "Updated a moment ago" in the warning colour because one of the two
    /// conditions was forgotten where the caption is written.
    func syncIsWarning(asOf reference: Date) -> Bool {
        syncStatusIsWarning || summary.isOutOfDate(asOf: reference)
    }

    /// What is said for a quota with no account.
    static let disconnectedAccountCaption = "Not connected"
}

extension Collection {
    /// The element at an index that may be out of range.
    ///
    /// `Calendar.weekdaySymbols` is indexed by a component value that comes from
    /// the user's own calendar, and a custom calendar can return a weekday the
    /// symbol array does not cover. Indexing it directly would trap; returning
    /// nil lets the caller fall back to something readable.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
