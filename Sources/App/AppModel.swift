import Core
import Foundation
import Observation
import Platform

/// The single object every view reads from.
///
/// One observable object holding derived state: a view asks the model for a
/// `QuotaPresentation` or a `ProviderSections` and gets values, never a
/// repository and never a coordinator. That is what keeps the interface from
/// growing provider-shaped conditionals, because nothing in a view is in a
/// position to make one.
///
/// State is derived on demand from the store and published as plain values.
/// Nothing here caches a reading the store could not produce again, so a refresh
/// that changes nothing on disk changes nothing on screen, and there is no
/// second copy of the truth to fall out of step.
@Observable
@MainActor
final class AppModel {
    /// Every quota the app knows about, ready to render.
    private(set) var presentations: [QuotaPresentation] = []

    /// The packaged providers split into available, installed, and connected.
    private(set) var sections = ProviderSections(available: [], installed: [], connected: [])

    /// What the user is looking at, when something is wrong.
    private(set) var lastError: String?

    /// Whether a refresh is in flight, so the interface can say so rather than
    /// appearing to ignore a click.
    private(set) var isRefreshing = false

    /// The provider currently connecting or disconnecting, if any.
    ///
    /// Shown on the row so Connect is not a silent wait while the plugin starts
    /// and answers.
    var busyProviderID: String?

    /// The user's calendar, resolved once.
    let userCalendar: Calendar

    /// The instant every figure on screen is relative to.
    ///
    /// Taken when a load starts and held until the next one, so a popover cannot
    /// show a "days remaining" computed at open beside an "updated N minutes ago"
    /// computed after a re-render a minute later.
    private(set) var reference: Date

    /// Whether any quota exists, which is what the first-launch screen keys on.
    var isEmpty: Bool {
        presentations.isEmpty
    }

    /// The quota the user has chosen the menu bar item to speak for.
    ///
    /// Nil until they choose, and kept as the raw stored id rather than as a
    /// quota, so the resolution below stays in one place and a stale id cannot
    /// quietly become a different quota than the one that was picked.
    private(set) var menuBarQuotaID: UUID?

    /// The quota the menu bar item speaks for.
    ///
    /// The one the user picked, and the first quota when they have not picked —
    /// never the most used and never the one with the least left, because any
    /// rule for choosing which quota that number comes from would be a rule the
    /// user cannot see or predict. With several quotas the popover is one click
    /// away and lists them all.
    ///
    /// A stored id that no longer names a quota falls back to the first rather
    /// than to nothing: a menu bar item with no number in it says the app is
    /// broken, and the first quota is a figure the user can check against the
    /// window. The stored id is left alone so a quota that comes back is picked
    /// up again.
    var primaryPresentation: QuotaPresentation? {
        guard let menuBarQuotaID else { return presentations.first }
        return presentations.first { $0.id == menuBarQuotaID } ?? presentations.first
    }

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        userCalendar = environment.calendar
        reference = environment.now()
    }

    /// Reloads everything the interface shows.
    ///
    /// One call rather than one per view, because the popover, the menu bar
    /// item, and the settings area are three renderings of one state and a view
    /// that loaded its own would be a fourth copy of the truth.
    func load() async {
        do {
            reference = environment.now()
            let preferences = try await environment.preferences.load()
            menuBarQuotaID = preferences.menuBarQuotaID
            presentations = try await environment.presenter(at: reference).presentations()
            // Attach provider failure captions so auth-expiry keeps the figure
            // and says so.
            presentations = await enrich(presentations)
            sections = try await environment.manager.sections(preferences: preferences)
            lastError = nil
        } catch {
            report(error)
        }
    }

    /// Makes one quota the one the menu bar item speaks for.
    ///
    /// Saved rather than held, because the choice has to survive the relaunch
    /// that follows quitting: a menu bar item that showed a different quota each
    /// morning would make the number beside it untrustworthy, and a number the
    /// user cannot rely on is the one thing a menu bar item is for.
    ///
    /// Not routed through `perform`, which reloads everything: the choice touches
    /// no reading, no plan, and no quota, and a popover that re-read the whole
    /// store on every click would make choosing look like waiting.
    func showInMenuBar(_ presentation: QuotaPresentation) async {
        guard presentation.id != menuBarQuotaID else { return }
        do {
            let preferences = try await environment.preferences.load()
            try await environment.preferences.save(
                preferences.withMenuBarQuotaID(presentation.id)
            )
            menuBarQuotaID = presentation.id
            lastError = nil
        } catch {
            report(error)
        }
    }

    /// Adds sync status from the provider record and continuity map.
    private func enrich(_ base: [QuotaPresentation]) async -> [QuotaPresentation] {
        let preferences = await (try? environment.preferences.load()) ?? .default
        let continuity = QuotaContinuity(
            quotas: environment.quotas,
            snapshots: environment.snapshots,
            timeline: environment.timelines,
            installed: environment.installed,
            disabledProviders: preferences.disabledProviders
        )
        let unrefreshable = await (try? continuity.unrefreshable()) ?? []
        let byQuota = Dictionary(uniqueKeysWithValues: unrefreshable.map { ($0.quotaID, $0) })

        var result: [QuotaPresentation] = []
        for presentation in base {
            var syncStatus: String?
            var isWarning = false
            if let blocked = byQuota[presentation.id] {
                syncStatus = continuityMessage(for: blocked.reason)
                isWarning = true
            } else if let record = try? await environment.providers.provider(
                presentation.summary.quota.providerID
            ), let failure = record.lastFailure {
                let age = record.lastSyncAt.map { reference.timeIntervalSince($0) } ?? 0
                syncStatus = RelativeTime().describeFailure(age: age)
                isWarning = true
                if failure.code == .authenticationFailed || failure.code == .notAuthenticated {
                    syncStatus = "Sign in again to refresh. " + (syncStatus ?? "")
                }
            }
            result.append(
                presentation.withSyncStatus(syncStatus, isWarning: isWarning)
            )
        }
        return result
    }

    /// What to say about a quota that cannot be refreshed at all.
    ///
    /// Every branch ends by promising that the last known data is still on
    /// screen, because that is the user's actual question when a refresh
    /// stops happening, and an interface that says only "unable to
    /// synchronise" leaves them guessing whether their history is gone.
    ///
    /// Disabled and missing are named as specific states; `notInstalled` is
    /// not, because a provider that can be installed again is a different
    /// situation from one that will never answer. The default covers the
    /// states that arrive later rather than naming each one.
    private func continuityMessage(for state: ProviderState) -> String {
        switch state {
        case .disabled:
            "This integration was disabled. Last known data is still shown."
        case .missing:
            "This provider is no longer installed. Last known data is still shown."
        case .notInstalled:
            "Unable to synchronise. The provider is not installed."
        default:
            "Unable to synchronise. Last known data is still shown."
        }
    }

    /// Reads every quota, and reloads what the readings changed.
    ///
    /// Guarded rather than merely sequential: a user who clicks refresh twice
    /// because nothing appeared to happen gets one read, not two, and the
    /// second click is not mistaken for impatience to be answered with more
    /// requests.
    func refreshAll() async {
        await runRefresh(trigger: .manual)
    }

    /// Reads the quotas whose schedule has come round, for the timer.
    func refreshDue() async {
        await runRefresh(trigger: .scheduleElapsed)
    }

    /// Reads every quota, for a launch or a popover opening.
    func refreshOnAppear() async {
        await runRefresh(trigger: .popoverOpened)
    }

    /// Plans, executes, and finishes a refresh for one trigger.
    func runRefresh(trigger: RefreshTrigger) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let quotaIDs = try await environment.planner.plan(for: trigger)
            await environment.planner.begin(quotaIDs)
            for quotaID in quotaIDs {
                _ = try? await environment.coordinator.refresh(quotaID: quotaID)
            }
            await environment.planner.finish(quotaIDs)
            lastError = nil
        } catch {
            report(error)
        }
        await load()
    }

    /// A calendar over one quota, at the instant the last load used.
    func calendar(for presentation: QuotaPresentation) -> CalendarPresenter {
        presentation.calendar(calendar: userCalendar, reference: reference)
    }

    // MARK: - creating a quota

    /// Creates a quota for an installed provider, and plans it.
    ///
    /// The period is the one the provider reported for this bucket. That is the
    /// whole point of asking before creating: a provider's cycle is anchored to a
    /// renewal and a pricing change can produce one shorter than a month, so the
    /// calendar month used to stand in for it was a guess the first refresh would
    /// correct. The caller passes the bucket's own period, and a nil one means the
    /// provider could not be read — where the month is not wrong so much as
    /// unconfirmed, and something still has to be drawn.
    @discardableResult
    func createQuota(
        named name: String,
        providerID: String,
        bucketID: String?,
        period: QuotaPeriod?,
        policy: AllocationPolicy
    ) async -> Bool {
        do {
            // Validated here rather than in the view: the packaged identifier is
            // the input, and a view that has to know an identifier can be
            // invalid is a view duplicating the domain's rules.
            let provider = try ProviderID(providerID)
            let resolved = try period ?? QuotaPeriod.month(containing: reference, calendar: userCalendar)
            let quota = try Quota(
                name: name,
                providerID: provider,
                bucketID: bucketID,
                period: resolved,
                policy: policy,
                createdAt: reference,
                updatedAt: reference
            )
            // `create`, not `save`: a second quota on a provider and bucket that
            // is already watched would read the same numbers as the first and
            // differ only in how they are divided, and two panels saying
            // different things about one set of readings is a question the
            // interface cannot answer honestly. The rule is in the repository so
            // it holds however the quota is created.
            try await environment.quotas.create(quota)
            await runRefresh(trigger: .manual)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Removes a quota and the readings and plans that belonged to it.
    ///
    /// Deliberate: uninstalling a provider leaves quotas in place, so the
    /// only way to clear an orphaned panel is to delete the quota itself.
    func deleteQuota(_ id: UUID) async {
        await perform {
            try await self.environment.quotas.delete(id: id)
            try await self.environment.snapshots.delete(quotaID: id)
            try await self.environment.timelines.delete(quotaID: id)
            try await self.environment.plans.delete(quotaID: id)
        }
    }

    /// Replaces a quota's allocation policy and re-plans it.
    func updatePolicy(quotaID: UUID, policy: AllocationPolicy) async {
        do {
            guard let existing = try await environment.quotas.quota(id: quotaID) else {
                return
            }
            let now = environment.now()
            try await environment.quotas.save(existing.withPolicy(policy, updatedAt: now))
            await runRefresh(trigger: .manual)
        } catch {
            report(error)
        }
    }

    // MARK: - providers

    /// What removing a provider would cost, so can say it before doing it.
    ///
    /// Asked for rather than counted in the view: a provider can back several
    /// quotas, and a row that removed it without saying so would leave those
    /// quotas listed with numbers that can never update again.
    func impact(ofUninstalling listing: ProviderListing) async -> UninstallImpact? {
        do {
            return try await environment.installer.impact(ofUninstalling: listing.id)
        } catch {
            report(error)
            return nil
        }
    }

    // Not wired: updating needs a `verify` that launches the new version and
    // confirms it answers, and no such check exists outside the installer's own
    // tests. Passing an empty one would let the interface report an update as
    // verified when nothing had been launched, which is the same false claim
    // is written against. `install` covers a first-time provider, which is
    // what the creation flow needs; an update button appears when the check exists.

    // MARK: - reporting a failure

    /// Puts a failure where the interface can show it, and reloads.
    ///
    /// Every provider action ends here so that a failure has exactly one way of
    /// reaching the user: a caption on the row that failed, not a silently
    /// unchanged list that leaves the button looking as though it had worked.
    func perform(_ action: @escaping @Sendable () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
        } catch {
            report(error)
        }
        await load()
    }

    /// `perform`, for an action that has a provider busy while it runs.
    ///
    /// The flag is what disables that provider's buttons, and it was set and
    /// cleared by hand at each of the four places an action touches a provider.
    /// Set without the matching clear — an early return, a thrown error — leaves
    /// a provider permanently unclickable, and the app says the install failed
    /// rather than that it is still running.
    func performing(
        for providerID: String,
        _ action: @escaping @Sendable () async throws -> Void
    ) async {
        busyProviderID = providerID
        defer { busyProviderID = nil }
        await perform(action)
    }

    // Records a failure without reloading, for a caller that has its own answer
    // to give alongside it.
    //
    // The setter is private, so every way of failing goes through here or
    // through `perform`: a second place assigning `lastError` would be a second
    // place deciding what a user is told went wrong.

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }
}
