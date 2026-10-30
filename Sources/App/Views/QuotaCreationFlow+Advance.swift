import Core
import Platform
import SwiftUI

extension QuotaCreationFlow {
    /// Moves forward according to what the selected provider still needs.
    ///
    /// Install and connect run here rather than as empty screens the user clicks
    /// through: a Next that only changed a label while claiming to install is
    /// what made an already-installed Cursor look missing.
    func advance() {
        guard let listing = selected else { return }
        switch step {
        case .chooseProvider:
            beginFromChoice(listing)
        case .install:
            beginConnect(listing.id)
        case .connect:
            // A failed connect clears `isWorking` and would otherwise let Next
            // skip into policy with no reading behind it. Retry instead.
            beginConnect(listing.id)
        case .policy:
            break
        }
    }

    /// Enters the flow at the step the chosen provider's state calls for.
    ///
    /// The listing is re-read rather than used as tapped, because Install and
    /// Connect change a provider's state and the row the user tapped can still
    /// hold the state from before that ran in the same session.
    func beginFromChoice(_ listing: ProviderListing) {
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
            // Already connected: still ask which limits it meters before the
            // policy step. Skipping that left `buckets` empty, hid the picker
            // for providers that meter several windows, and created an unbound
            // quota on the primary limit alone — which then closed the provider
            // off from a second quota on the weekly (or other) window.
            beginPolicy(afterLoadingBucketsFor: current.id)
        }
    }

    /// Loads the provider's limits, then opens the policy step.
    ///
    /// Used when the provider is already connected, so there is no Connect step
    /// to hang the load on. The policy step is opened only after the limits are
    /// in hand: opening it empty would hide the picker for a multi-window
    /// provider and create an unbound quota on the primary limit alone.
    func beginPolicy(afterLoadingBucketsFor providerID: String) {
        isWorking = true
        Task {
            if let updated = refreshedListing(id: providerID), selected?.id == providerID {
                selected = updated
            }
            await loadBuckets(for: providerID)
            guard selected?.id == providerID else {
                isWorking = false
                return
            }
            isWorking = false
            step = .policy
        }
    }

    /// Installs the provider, then carries straight on to connecting it.
    ///
    /// Install and connect are one gesture to the user, so a successful install
    /// advances rather than stopping to report success the user did not ask about.
    /// A failed install falls out through `lastError`, which stops the step
    /// advancing and leaves the choice on screen to be retried.
    func beginInstall(_ listing: ProviderListing) {
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
    func beginConnect(_ providerID: String) {
        step = .connect
        isWorking = true
        Task {
            await model.connect(providerID: providerID)
            if let updated = refreshedListing(id: providerID) {
                selected = updated
            }
            guard model.lastError == nil else {
                isWorking = false
                return
            }
            await loadBuckets(for: providerID)
            guard selected?.id == providerID else {
                isWorking = false
                return
            }
            isWorking = false
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
    ///
    /// Results are applied only while `providerID` is still the selection: a load
    /// started for one provider must not overwrite buckets after another was
    /// chosen.
    func loadBuckets(for providerID: String) async {
        let loaded = await model.buckets(forProviderID: providerID)
        guard selected?.id == providerID else { return }
        buckets = loaded
        bucketID = buckets.first { !takenBucketIDs.contains($0.id) }?.id ?? buckets.first?.id
    }

    /// The current state of one provider, read from the live listings.
    ///
    /// - Returns: nil once the provider has left the listings, which the caller
    ///   treats as "leave the selection as it is" rather than clearing it: a
    ///   provider that vanished mid-flow should not blank the screen.
    func refreshedListing(id: String) -> ProviderListing? {
        availableListings.first { $0.id == id }
    }

    /// Registers the quota and, on success, resets the flow to choose a provider.
    ///
    /// The bucket is captured before the call rather than read from state
    /// afterwards, so a quota cannot be filed against a limit the user has since
    /// changed their mind about. A refused registration keeps the form as it was,
    /// because the name and policy the user entered are still what they want.
    func create(using listing: ProviderListing) {
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
    func previousVisible(of step: StepTrail.Step) -> StepTrail.Step {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step), index > 0 else {
            return .chooseProvider
        }
        return steps[index - 1]
    }
}
