import Core
import Foundation

/// Reading several quotas with one plugin launch per provider.
///
/// Every read launches the provider's plugin, so quotas on the same provider
/// (a five-hour and a weekly limit on one account, say) share one reading
/// rather than starting the same process once per limit.
extension SyncCoordinator {
    /// One read per provider, filed against every quota on it, in input order.
    func refresh(_ group: [Quota]) async throws -> [SyncOutcome] {
        let today = LocalDate(date: now(), calendar: calendar)
        var providerOrder: [ProviderID] = []
        for quota in group where !providerOrder.contains(quota.providerID) {
            providerOrder.append(quota.providerID)
        }
        var outcomes: [UUID: SyncOutcome] = [:]
        var firstError: Error?
        for providerID in providerOrder {
            let members = group.filter { $0.providerID == providerID }
            do {
                for outcome in try await refresh(members, of: providerID, on: today) {
                    outcomes[outcome.quotaID] = outcome
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
        return group.compactMap { outcomes[$0.id] }
    }

    /// Reads one provider once and files the reading against each of its quotas.
    private func refresh(
        _ members: [Quota],
        of providerID: ProviderID,
        on today: LocalDate
    ) async throws -> [SyncOutcome] {
        guard
            let provider = try await providers.provider(providerID),
            let accountLabel = provider.authenticatedAccountLabel
        else {
            // No account is a state the interface shows, not a mistake the user
            // made, so it comes back as a result rather than as a thrown error.
            let failure = SyncFailure(
                code: .notAuthenticated,
                message: "This provider is not connected to an account.",
                occurredAt: now()
            )
            try await note(failure, alongside: providerID)
            return members.map { SyncOutcome(quotaID: $0.id, result: .failure(failure)) }
        }

        let outcome = await fetcher.fetchUsage(
            providerID: providerID,
            accountLabel: accountLabel,
            localDate: today
        )
        if let suggestion = outcome.suggestedRefreshInterval {
            try await noteSuggestedRefreshInterval(suggestion, for: providerID)
        }
        switch outcome.result {
        case .success(let snapshot):
            var filed: [SyncOutcome] = []
            var firstError: Error?
            for quota in members {
                do {
                    let changed = try await file(snapshot, for: quota, accountLabel: accountLabel)
                    filed.append(SyncOutcome(quotaID: quota.id, result: outcome.result, periodChanged: changed))
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let firstError {
                throw firstError
            }
            return filed
        case .failure(let failure):
            // Once per read, not per quota: the failure count is the provider's,
            // and it failed once.
            try await note(failure, alongside: providerID)
            return members.map { SyncOutcome(quotaID: $0.id, result: outcome.result) }
        }
    }
}
