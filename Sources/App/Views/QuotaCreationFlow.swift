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

    @State private var step: StepTrail.Step = .chooseProvider
    @State private var selected: ProviderListing?
    @State private var policy: AllocationPolicy = .even
    @State private var name = ""

    /// The limits the chosen provider meters, once it has been connected and read.
    ///
    /// Empty until then, and empty still if the read fails — which the flow treats
    /// as "this provider does not name its limits" rather than as an error, because
    /// a provider that meters one limit has nothing to choose between and should
    /// not be asked.
    @State private var buckets: [UsageBucket] = []

    /// Which limit this quota will watch, `nil` for the provider's primary one.
    @State private var bucketID: String?
    @State private var isWorking = false

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
    private var visibleSteps: [StepTrail.Step] {
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
    private var takenBucketIDs: Set<String> {
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
    private var chosenPeriod: QuotaPeriod? {
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
                selected = listing
                name = listing.displayName
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
    private var availableListings: [ProviderListing] {
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
        case .chooseProvider: selected != nil && canCreate
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
        guard let selected else { return false }
        guard !model.hasUnboundQuota(forProviderID: selected.id) else { return false }
        // Empty means the provider could not be read, which is not the same as
        // every limit being taken: there is then nothing to have ruled out.
        return buckets.isEmpty || buckets.count > takenBucketIDs.count
    }

    /// Moves forward according to what the selected provider still needs.
    ///
    /// Install and connect run here rather than as empty screens the user clicks
    /// through: a Next that only changed a label while claiming to install is
    /// what made an already-installed Cursor look missing.
    private func advance() {
        guard let listing = selected else { return }
        switch step {
        case .chooseProvider:
            beginFromChoice(listing)
        case .install:
            beginConnect(listing.id)
        case .connect:
            step = .policy
        case .policy:
            break
        }
    }

    /// Enters the flow at the step the chosen provider's state calls for.
    ///
    /// The listing is re-read rather than used as tapped, because Install and
    /// Connect change a provider's state and the row the user tapped can still
    /// hold the state from before that ran in the same session.
    private func beginFromChoice(_ listing: ProviderListing) {
        // Re-read from the live sections: `selected` can still hold the state
        // from when the row was tapped, which is wrong after Install / Connect
        // on the Providers screen in the same session.
        let current = refreshedListing(id: listing.id) ?? listing
        selected = current
        switch current.state.prerequisite {
        case .installation:
            beginInstall(current)
        case .authentication:
            beginConnect(current.id)
        case .none:
            step = .policy
        }
    }

    /// Installs the provider, then carries straight on to connecting it.
    ///
    /// Install and connect are one gesture to the user, so a successful install
    /// advances rather than stopping to report success the user did not ask about.
    /// A failed install falls out through `lastError`, which stops the step
    /// advancing and leaves the choice on screen to be retried.
    private func beginInstall(_ listing: ProviderListing) {
        step = .install
        isWorking = true
        Task {
            await model.install(listing)
            isWorking = false
            if let updated = refreshedListing(id: listing.id) {
                selected = updated
            }
            guard model.lastError == nil else { return }
            beginConnect(listing.id)
        }
    }

    /// Authenticates the provider, then asks it which limits it meters.
    ///
    /// The listing is refreshed afterwards so the connection state shown from here
    /// on is the state the provider actually reported, not the state that was
    /// true when the row was tapped. Connecting before asking for buckets is the
    /// order that matters: an unauthenticated provider cannot be read.
    private func beginConnect(_ providerID: String) {
        step = .connect
        isWorking = true
        Task {
            await model.connect(providerID: providerID)
            isWorking = false
            if let updated = refreshedListing(id: providerID) {
                selected = updated
            }
            guard model.lastError == nil else { return }
            await loadBuckets()
            step = .policy
        }
    }

    /// Asks the provider which limits it meters, and picks the first unwatched one.
    ///
    /// Done after Connect rather than before, because a provider that is not
    /// authenticated yet cannot be read, and its answer would be a failure the
    /// flow would then have to explain as an empty list.
    ///
    /// Choosing the first available limit rather than leaving the choice to the
    /// user means the common case — one provider, one quota — needs no decision at
    /// all, and a provider metering several arrives at a picker already on a limit
    /// that has no quota.
    private func loadBuckets() async {
        guard let selected else {
            buckets = []
            bucketID = nil
            return
        }
        buckets = await model.buckets(forProviderID: selected.id)
        bucketID = buckets.first { !takenBucketIDs.contains($0.id) }?.id ?? buckets.first?.id
    }

    /// The current state of one provider, read from the live listings.
    ///
    /// - Returns: nil once the provider has left the listings, which the caller
    ///   treats as "leave the selection as it is" rather than clearing it: a
    ///   provider that vanished mid-flow should not blank the screen.
    private func refreshedListing(id: String) -> ProviderListing? {
        availableListings.first { $0.id == id }
    }

    /// Registers the quota and, on success, resets the flow to choose a provider.
    ///
    /// The bucket is captured before the call rather than read from state
    /// afterwards, so a quota cannot be filed against a limit the user has since
    /// changed their mind about. A refused registration keeps the form as it was,
    /// because the name and policy the user entered are still what they want.
    private func create(using listing: ProviderListing) {
        isWorking = true
        let chosen = bucketID
        Task {
            let created = await model.createQuota(
                named: name,
                providerID: listing.id,
                bucketID: chosen,
                period: chosenPeriod,
                policy: policy
            )
            isWorking = false
            if created {
                name = ""
                selected = nil
                buckets = []
                bucketID = nil
                step = .chooseProvider
            }
        }
    }

    /// The step a Back press should land on.
    ///
    /// - Returns: the previous visible step, or `chooseProvider` when there is
    ///   none. Backing out of the first step returns to the start rather than
    ///   doing nothing, so Back is never a key that appears not to work.
    private func previousVisible(of step: StepTrail.Step) -> StepTrail.Step {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step), index > 0 else {
            return .chooseProvider
        }
        return steps[index - 1]
    }
}
