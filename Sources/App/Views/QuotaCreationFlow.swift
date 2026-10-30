import Core
import Platform
import SwiftUI

/// Quota creation flow, in order.
///
/// The steps run in a fixed order, because each one exists for a reason
/// the next depends on: a provider has to exist before it can be connected, a
/// connection has to succeed before usage means anything, and the period has to
/// be known before a policy can be turned into a plan. A user who skips ahead
/// gets a quota with no reading behind it, which is a state the
/// interface must show honestly rather than paper over.
struct QuotaCreationFlow: View {
    let model: AppModel

    @State var step: StepTrail.Step = .chooseProvider
    @State var selected: ProviderListing?
    @State var policy: AllocationPolicy = .even
    @State var name = ""

    /// The limits the chosen provider meters, once it has been connected and read.
    ///
    /// Empty until then, and empty still if the read fails — which the flow treats
    /// as "this provider does not name its limits" rather than as an error, because
    /// a provider that meters one limit has nothing to choose between and should
    /// not be asked.
    @State var buckets: [UsageBucket] = []

    /// Which limit this quota will watch, `nil` for the provider's primary one.
    @State var bucketID: String?
    @State var isWorking = false

    /// Creation steps, in order.
    ///
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            steps
            Divider()
            stepBody
            if let lastError = model.lastError {
                ErrorBanner(message: lastError)
            }
            actions
        }
        .padding(LayoutMetrics.inset)
    }

    /// The steps the user still has to walk for the current selection.
    ///
    /// Derived from the provider's state so an installed Cursor is not asked to
    /// install again, and a connected one is not asked to connect again.
    var visibleSteps: [StepTrail.Step] {
        guard let selected else { return [.chooseProvider] }
        switch selected.state.prerequisite {
        case .installation:
            return [.chooseProvider, .install, .connect, .policy]
        case .authentication:
            return [.chooseProvider, .connect, .policy]
        case .none:
            return [.chooseProvider, .policy]
        }
    }

    /// The steps the user still has to walk, as a numbered trail.
    ///
    /// Numbered rather than a bare list of names, because the question a list of
    /// names cannot answer is how far along the user is — and "Install" is a step
    /// that a connected provider skips entirely, so its absence from the trail is
    /// itself the progress report.
    private var steps: some View {
        StepTrail(steps: visibleSteps, current: step)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .chooseProvider:
            providerChoices
        case .install:
            Caption(
                text: isWorking
                    ? "Installing \(selected?.displayName ?? "provider")…"
                    : "Provider installed."
            )
        case .connect:
            Caption(
                text: isWorking
                    ? "Connecting to \(selected?.displayName ?? "provider")…"
                    : "Connected."
            )
        case .policy:
            VStack(alignment: .leading, spacing: LayoutMetrics.titleSpacing) {
                // Seeded from the provider's own display name, because the name
                // is a label the user recognises their quota by and the provider's
                // name is what they would have typed. An empty box would ask them
                // to invent a name before knowing it matters, and says the
                // interface is written against a provider without naming one.
                TextField("Quota name", text: $name)
                    .textFieldStyle(.roundedBorder)
                if buckets.count > 1 {
                    bucketChoice
                }
                if let period = chosenPeriod {
                    PolicyEditor(
                        policy: $policy,
                        period: period,
                        calendar: model.userCalendar,
                        reference: model.reference
                    )
                    Caption(text: policy.summary)
                }
            }
        }
    }

    /// Which of the provider's limits to watch.
    ///
    /// The picker itself lives in `BucketPicker`, so what this flow has to say is
    /// only which limits are spoken for — the state it holds and the view does not.
    private var bucketChoice: some View {
        BucketPicker(
            buckets: buckets,
            takenIDs: takenBucketIDs,
            reference: model.reference,
            calendar: model.userCalendar,
            selection: $bucketID
        )
    }

    /// The limits of this provider that already have a quota of their own.
    var takenBucketIDs: Set<String> {
        guard let selected else { return [] }
        return Set(
            buckets
                .filter { model.isWatched(providerID: selected.id, bucketID: $0.id) }
                .map(\.id)
        )
    }

    /// The window this quota will be planned over.
    ///
    /// The chosen limit's own window, so the calendar the user is allocating
    /// against is the provider's rather than an assumption the first refresh will
    /// contradict. `monthAround` is the fallback for a provider that could not be
    /// read: the plan has to span something, and the month is at least a span the
    /// app can defend.
    var chosenPeriod: QuotaPeriod? {
        if let bucket = buckets.first(where: { $0.id == bucketID }) {
            return bucket.period
        }
        return buckets.isEmpty
            ? (try? QuotaPeriod.month(containing: model.reference, calendar: model.userCalendar))
            : nil
    }

    private var providerChoices: some View {
        ProviderChoices(
            listings: availableListings,
            selectedID: selected?.id,
            caption: statusCaption,
            isAvailable: isAvailable,
            onSelect: { listing in
                // Ignore switches while a connect/load is in flight: the open
                // task still owns `isWorking`, and applying its buckets to a
                // different provider would be a lie about what was just read.
                guard !isWorking else { return }
                selected = listing
                name = listing.displayName
                // Drop the previous provider's limits so a stale full set
                // cannot keep Next disabled for a freshly chosen provider.
                buckets = []
                bucketID = nil
            }
        )
    }

    /// A provider whose primary limit is already spoken for cannot be chosen
    /// again.
    ///
    /// Refused at the row rather than at Create, because a button that is only
    /// found to be wrong after four steps of install, connect, and naming is a
    /// way of spending the user's time to deliver a message the row could have
    /// carried from the start.
    ///
    /// Not the other half of the rule — "is every limit taken" — because a row
    /// cannot know which limits a provider meters without reading it, and spawning
    /// a plugin per row to find out would make the list slower than the work it
    /// is preparing. That half is settled by the picker, which is the first place
    /// the limits are actually in hand.
    private func isAvailable(_ listing: ProviderListing) -> Bool {
        !model.hasUnboundQuota(forProviderID: listing.id)
    }

    /// What each row says, which is also why a row is unavailable.
    ///
    /// The caption leads with the quota rather than the provider's state when
    /// there is one in the way, because a greyed-out row whose caption still
    /// says "Connected" is a row the user cannot read; what they need is to be
    /// told the quota exists and named.
    private func statusCaption(for listing: ProviderListing) -> String {
        guard isAvailable(listing) else { return "Already has a quota" }
        return switch listing.state {
        case .connected: "Connected"
        case .installed, .authRequired, .authExpired: "Installed"
        case .notInstalled: "Not installed"
        default: listing.state.rawValue
        }
    }

    /// What can be chosen: something installed, or something installable here.
    ///
    /// A provider the app cannot install and has not got is not offered, because
    /// Creation installs inline and there would be nothing to install.
    var availableListings: [ProviderListing] {
        model.sections.connected + model.sections.installed + model.sections.available
    }

    private var actions: some View {
        CreationActions(
            step: step,
            isWorking: isWorking,
            canAdvance: canAdvance,
            canCreate: canCreate,
            hasName: !name.isEmpty,
            onBack: { step = previousVisible(of: step) },
            onNext: advance,
            onCreate: { guard let selected else { return }
                create(using: selected)
            }
        )
    }

    private var canAdvance: Bool {
        switch step {
        case .chooseProvider: selected != nil && canCreate && !isWorking
        case .install, .connect: !isWorking
        case .policy: false
        }
    }

    /// Whether the chosen provider can still take a quota.
    ///
    /// Re-read at the last step rather than assumed from the row that was tapped:
    /// a quota can be created from the window behind the sheet while this flow is
    /// open, and Create has to refuse a provider that acquired one in between.
    /// The limits only settle once the provider has answered, so this is also the
    /// place that decides whether every one of them is spoken for.
    private var canCreate: Bool {
        guard let selected, !model.hasUnboundQuota(forProviderID: selected.id) else { return false }
        // Empty means the provider could not be read, which is not the same as
        // every limit being taken: there is then nothing to have ruled out.
        return buckets.isEmpty || buckets.count > takenBucketIDs.count
    }
}
