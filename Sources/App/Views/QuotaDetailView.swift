import Core
import Platform
import SwiftUI

/// Full quota detail for the main window: figures, today, calendar, policy, remove.
///
/// One section per card, in the order the questions are asked: how much of the
/// allowance is gone, how much of today is left, what was planned for any given
/// day, and how the plan is set.
///
/// There is no list of the coming days. Every day of the period has its own share
/// and the calendar below shows that share on the day it belongs to, so a list of
/// the same figures in a column was a second way to read one thing — and a second
/// way that grew with the period: a yearly quota would have listed three hundred
/// and sixty rows in front of the calendar that answers the same question.
struct QuotaDetailView: View {
    let presentation: QuotaPresentation
    let calendar: CalendarPresenter
    let calendarGrid: Calendar
    let reference: Date
    let model: AppModel

    @State private var selectedDate: LocalDate?
    @State private var isConfirmingDelete = false

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            header
            usage
            SectionCard("Today") {
                TodayAllowanceView(
                    presentation: presentation,
                    showsTitle: false
                )
            }
            outlook
            PeriodCalendarSection(
                presenter: calendar,
                calendar: calendarGrid,
                selectedDate: $selectedDate,
                validation: presentation.summary.plan?.validation
            )
            PolicySection(
                presentation: presentation,
                calendar: calendarGrid,
                reference: reference,
                model: model
            )
            lastSynchronised
            removal
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Figures

    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            Text(presentation.summary.quota.name)
                .font(.title2.weight(.semibold))
            Caption(
                text: presentation.accountCaption.text,
                isWarning: presentation.accountCaption.isWarning
            )
        }
    }

    /// The two headline figures, with the bar that says how they relate.
    private var usage: some View {
        SectionCard("Allowance") {
            VStack(alignment: .leading, spacing: LayoutMetrics.barRowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.sectionSpacing) {
                    figure(formatter.string(presentation.usagePercentage), "used", emphasised: true)
                    Spacer(minLength: 0)
                    figure(formatter.string(presentation.remainingPercentage), "remaining", emphasised: false)
                }
                UsageBar(
                    value: presentation.usagePercentage ?? 0,
                    maximum: UsageConstants.percentageScale,
                    tint: usageTint
                )
                if let unavailable {
                    Caption(text: unavailable, isWarning: true)
                }
            }
        }
    }

    /// What to say when the provider has stopped reporting this quota's limit.
    ///
    /// Named, so the user can tell which of a provider's limits has gone rather
    /// than being told a quota of theirs has no reading — with several limits on
    /// one provider, "no data" would not say which. It is a warning and not an
    /// error because nothing has failed: the quota is intact and the figures it
    /// was last given are still the figures, and a limit that comes back is
    /// picked up again.
    private var unavailable: String? {
        presentation.unavailableBucketName.map {
            "The provider is no longer reporting \($0)."
        }
    }

    /// Draws one figure of the headline pair: a value with its caption.
    ///
    /// Both halves of the pair are built here so "used" and "remaining"
    /// cannot drift apart in type ramp, `emphasised` being the only
    /// difference between them. The caption is a separate `Text` rather than
    /// part of the value, because the value arrives already formatted: an
    /// absent reading has to stay a marker beside a word, not become the
    /// first word of a sentence.
    private func figure(_ value: String, _ label: String, emphasised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.lineSpacing) {
            Text(value)
                .font(.system(size: LayoutMetrics.headlineFigureSize, weight: emphasised ? .semibold : .regular))
                .monospacedDigit()
            Text(label)
                .font(.system(size: LayoutMetrics.footnoteSize))
                .foregroundStyle(.secondary)
        }
    }

    private var outlook: some View {
        OutlookRow(presentation: presentation, reference: reference, calendar: calendarGrid)
    }

    /// The bar follows the pacing state, so "behind" is visible before the text
    /// under the calendar is read.
    private var usageTint: Color {
        presentation.summary.pacing?.phase.usageTint ?? .accentColor
    }

    // MARK: Footer

    private var lastSynchronised: some View {
        Caption(
            text: presentation.syncCaption(asOf: reference, calendar: calendarGrid),
            isWarning: presentation.syncIsWarning(asOf: reference)
                || unavailable != nil
        )
    }

    /// Removal, behind a confirmation that says what it costs.
    ///
    /// A destructive action at the end of a long page, in a place a user reaches
    /// by scrolling past everything else, rather than a button beside the figures
    /// they are looking at.
    @ViewBuilder
    private var removal: some View {
        if isConfirmingDelete {
            NoticeCard(
                title: "Remove \(presentation.summary.quota.name)?",
                message: "Its readings and plan are deleted. This cannot be undone."
            ) {
                HStack(spacing: LayoutMetrics.actionSpacing) {
                    Button("Cancel") { isConfirmingDelete = false }
                        .buttonStyle(.bordered)
                    Button("Remove", role: .destructive) {
                        Task { await model.deleteQuota(presentation.id) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Button("Remove Quota", role: .destructive) {
                isConfirmingDelete = true
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Period calendar with month navigation and a selected-day strip.
struct PeriodCalendarSection: View {
    let presenter: CalendarPresenter
    let calendar: Calendar
    @Binding var selectedDate: LocalDate?
    /// The plan's own verdict on itself, when it has one to give.
    ///
    /// A warning rather than a figure, and the only thing about the plan the grid
    /// cannot say: every day can show its own share and a plan that does not add
    /// up still looks like a month of perfectly ordinary days. It sits above the
    /// grid because it is a statement about all of them.
    var validation: AllocationValidation?

    var body: some View {
        SectionCard("Calendar") {
            VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
                if let validation {
                    AllocationValidationView(validation: validation)
                }
                MonthCalendarView(
                    presenter: presenter,
                    calendar: calendar,
                    selected: selectedDate,
                    onSelect: { date in
                        selectedDate = selectedDate == date ? nil : date
                    },
                    showsNavigation: true
                )
                if let selectedDate {
                    DateDetailView(
                        day: presenter.day(selectedDate),
                        calendar: calendar
                    )
                } else {
                    Caption(text: "Select a day for planned and spent. Click again to clear.")
                }
            }
        }
    }
}

/// Edit the allocation policy for an existing quota.
struct PolicySection: View {
    let presentation: QuotaPresentation
    let calendar: Calendar
    let reference: Date
    let model: AppModel

    @State private var policy: AllocationPolicy
    @State private var isSaving = false

    init(presentation: QuotaPresentation, calendar: Calendar, reference: Date, model: AppModel) {
        self.presentation = presentation
        self.calendar = calendar
        self.reference = reference
        self.model = model
        _policy = State(initialValue: presentation.summary.quota.policy)
    }

    var body: some View {
        SectionCard("Policy") {
            VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
                PolicyEditor(
                    policy: $policy,
                    period: presentation.summary.quota.period,
                    calendar: calendar,
                    reference: reference
                )
                HStack {
                    Caption(text: policyCaption)
                    Spacer(minLength: 0)
                    Button(isSaving ? "Saving…" : "Save Policy") {
                        isSaving = true
                        Task {
                            await model.updatePolicy(quotaID: presentation.id, policy: policy)
                            isSaving = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || policy == presentation.summary.quota.policy)
                }
            }
        }
        .onChange(of: presentation.summary.quota.policy) { _, newValue in
            policy = newValue
        }
    }

    /// What the policy will do, in one line, so the segmented control's choice is
    /// not the only thing the user has to go on.
    private var policyCaption: String {
        policy.summary
    }
}
