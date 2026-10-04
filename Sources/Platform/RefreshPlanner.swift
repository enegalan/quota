import Core
import Foundation

/// Decides which providers to read, and when, from the events going on around
/// the app.
///
/// The coordinator answers "read this quota" and the schedule answers "not
/// before". Neither of them knows about a popover opening, a timer firing or a
/// network cable being plugged in, so this is the one place that turns those
/// into a list of quotas to read. Keeping it here means the policy is a value
/// that can be tested at a fixed instant, rather than a timer that can only be
/// observed.
public actor RefreshPlanner {
    private let coordinator: SyncCoordinator
    private let now: @Sendable () -> Date
    private var connectivity = ConnectivityTracker()
    private var inFlight: Set<UUID> = []
    private var lastAttempt: [ProviderID: Date] = [:]
    private var nextDue: [ProviderID: Date] = [:]

    public init(coordinator: SyncCoordinator, now: @escaping @Sendable () -> Date = { Date() }) {
        self.coordinator = coordinator
        self.now = now
    }

    /// The connectivity the app starts with, before anything has been observed.
    ///
    /// Reported as a restoration when connected, because from the app's point of
    /// view the first reading after launch is the same event as a cable going
    /// back in: a reading is possible and none has been taken recently.
    public static func launch(isConnected: Bool) -> ConnectivityState {
        ConnectivityTracker.initial(isConnected)
    }

    /// Whether a trigger means anything should be read now, and if so what.
    ///
    /// - Returns: the quotas to read, which is empty when the trigger is not
    ///   enough on its own — a popover opening before a provider is due is not
    ///   an error, and a caller needs to be able to tell "nothing to do" from
    ///   "everything failed".
    public func plan(for trigger: RefreshTrigger) async throws -> [UUID] {
        guard trigger == .connectivityRestored || trigger == .manual
            || trigger == .popoverOpened || trigger == .launch
        else {
            return try await due(at: now())
        }
        // A popover, a launch, a manual request and a restored connection all
        // mean the same thing here: the user is looking at numbers, or the
        // reason the last read failed has gone. Both are reasons to read now
        // whatever the schedule says, because ask for exactly that
        // and neither is a reason to make a user wait.
        return try await quotaIDsForAllProviders()
    }

    /// The quotas whose schedule has come round.
    ///
    /// - Parameter instant: the moment being asked about, rather than the
    ///   current time, so "is it due yet" is a question with an answer a test can
    ///   choose instead of one that depends on when the test ran.
    public func due(at instant: Date) async throws -> [UUID] {
        var dueQuotaIDs: [UUID] = []
        for quota in try await allQuotas() {
            guard !inFlight.contains(quota.id) else { continue }
            // One schedule per provider, so two quotas on the same provider come
            // due together and are read together rather than one of them being
            // answered from a read the other caused. The planner's own memory of
            // the last read wins over the coordinator's answer, because it
            // includes reads made in this session that are not yet folded into
            // the provider record.
            let remembered = nextDue[quota.providerID]
            let dueAt: Date? = if let remembered {
                remembered
            } else {
                try await coordinator.nextRefresh(for: quota.providerID)
            }
            let decision = RefreshDecision.decide(
                trigger: .scheduleElapsed,
                lastAttempt: lastAttempt[quota.providerID],
                nextDue: dueAt,
                inFlight: false,
                now: instant
            )
            if decision.shouldRefresh {
                dueQuotaIDs.append(quota.id)
            }
        }
        return dueQuotaIDs
    }

    /// Records a connectivity reading and refreshes if it came back.
    public func connectivityChanged(to isConnected: Bool) async throws -> [UUID] {
        let state = connectivity.observe(isConnected)
        guard state.justRestored else { return [] }
        return try await plan(for: .connectivityRestored)
    }

    /// Marks quotas as being read, so a second trigger does not start them again.
    public func begin(_ quotaIDs: [UUID]) {
        inFlight.formUnion(quotaIDs)
    }

    /// Records the outcome of a read, releasing the quota and scheduling the next.
    ///
    /// The next time comes from the provider's own record when there is one — it
    /// accounts for the jitter and any backoff — and from the base schedule when
    /// there is not, which is the case for a read that failed before the provider
    /// ever answered. Falling back to "due now" instead would mean a provider
    /// being offline is polled in a tight loop, which is the opposite of backing
    /// off.
    public func finish(_ quotaIDs: [UUID]) async {
        inFlight.subtract(quotaIDs)
        let instant = now()
        for quotaID in quotaIDs {
            guard let quota = try? await coordinator.quotas.quota(id: quotaID) else { continue }
            lastAttempt[quota.providerID] = instant
            let scheduled = try? await coordinator.nextRefresh(for: quota.providerID)
            nextDue[quota.providerID] = scheduled ?? instant.addingTimeInterval(
                coordinator.schedule.baseInterval
            )
        }
    }

    /// When a provider is next due, as the interface shows it.
    public func due(for providerID: ProviderID) -> Date? {
        nextDue[providerID]
    }

    /// Every quota the coordinator knows about.
    ///
    /// Asked through the coordinator rather than from a repository of
    /// this actor's own, so the two places that need the whole list
    /// cannot end up working from different moments and disagreeing about
    /// what exists.
    private func allQuotas() async throws -> [Quota] {
        try await coordinator.quotas.all()
    }

    /// Every quota's id, minus the ones already being read.
    ///
    /// In flight quotas are dropped here rather than left for the caller
    /// to filter, because a trigger that hands back a quota already being
    /// read is a trigger that will start the same provider twice — and
    /// two reads filed out of order leave the later one to win regardless
    /// of which was newer.
    private func quotaIDsForAllProviders() async throws -> [UUID] {
        try await allQuotas()
            .filter { !inFlight.contains($0.id) }
            .map(\.id)
    }
}
