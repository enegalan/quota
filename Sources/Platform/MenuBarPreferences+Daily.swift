import Foundation

public extension MenuBarPreferences {
    /// Drops a deleted quota from every integration's daily list.
    ///
    /// Empty lists keep falling back to the planned quota in
    /// `effectiveDailyQuotaIDs`, so `canHideDailyQuota` only counts IDs that
    /// still exist.
    mutating func deleteQuota(_ id: UUID) {
        for integrationID in dailyQuotas.keys {
            dailyQuotas[integrationID]?.remove(id)
        }
    }

    /// Whether this quota's today's allowance belongs in the menu bar.
    ///
    /// The global switch wins: with daily quota hidden, no quota shows one.
    /// Otherwise the integration's own list wins over the planned quota, and
    /// an integration that has never been given a list still shows the planned
    /// quota — the choice the menu bar made before a list existed.
    func showsDailyAllowance(
        quotaID: UUID,
        integrationID: String,
        plannedQuotaID: UUID
    ) -> Bool {
        guard showDailyQuota else { return false }
        return effectiveDailyQuotaIDs(
            integrationID: integrationID,
            plannedQuotaID: plannedQuotaID
        ).contains(quotaID)
    }

    /// Whether one daily quota can be switched off without leaving its
    /// integration with no daily figure.
    func canHideDailyQuota(
        quotaID: UUID,
        integrationID: String,
        plannedQuotaID: UUID
    ) -> Bool {
        let chosen = effectiveDailyQuotaIDs(
            integrationID: integrationID,
            plannedQuotaID: plannedQuotaID
        )
        return chosen.count > 1 && chosen.contains(quotaID)
    }

    /// Records whether one quota shows today's allowance.
    ///
    /// The effective list is written rather than the raw one, so a quota
    /// enabled while the planned one was standing in keeps the planned one
    /// beside it. The last one cannot be removed: the integration would lose
    /// its daily figure.
    mutating func setShowsDailyAllowance(
        _ enabled: Bool,
        for quotaID: UUID,
        integrationID: String,
        plannedQuotaID: UUID
    ) {
        var chosen = effectiveDailyQuotaIDs(
            integrationID: integrationID,
            plannedQuotaID: plannedQuotaID
        )
        if enabled {
            chosen.insert(quotaID)
        } else {
            chosen.remove(quotaID)
        }
        if chosen.isEmpty {
            chosen.insert(plannedQuotaID)
        }
        dailyQuotas[integrationID] = chosen
    }
}

extension MenuBarPreferences {
    /// The quotas of one integration that show today's allowance.
    ///
    /// An empty or missing choice falls back to the planned quota, so the
    /// global switch being on cannot leave an integration with no daily row.
    func effectiveDailyQuotaIDs(
        integrationID: String,
        plannedQuotaID: UUID
    ) -> Set<UUID> {
        guard showDailyQuota else { return [] }
        if let chosen = dailyQuotas[integrationID], !chosen.isEmpty {
            return chosen
        }
        return [plannedQuotaID]
    }
}
