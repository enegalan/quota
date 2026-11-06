import Foundation

public extension MenuBarPreferences {
    /// Whether one limit of an integration is drawn in the menu bar.
    ///
    /// The global switch wins. While it is on, an integration whose chosen
    /// list is empty shows its first available limit rather than none.
    func showsLimit(
        _ limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = [],
        unavailableLimitIDs: [String] = []
    ) -> Bool {
        guard showAvailableLimits else { return false }
        return effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        ).contains(limitID)
    }

    /// Whether one limit can be switched off without leaving its integration
    /// with no limit in the menu bar.
    func canHideLimit(
        _ limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = [],
        unavailableLimitIDs: [String] = []
    ) -> Bool {
        let chosen = effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        return chosen.count > 1 && chosen.contains(limitID)
    }

    /// Records whether one limit is drawn in the menu bar.
    ///
    /// The effective list is written rather than the raw one, so a limit
    /// enabled while the first available one was standing in keeps that first
    /// limit beside it. The last limit cannot be removed: the bar would lose
    /// the integration's limit figure entirely.
    mutating func setShowsLimit(
        _ enabled: Bool,
        limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = [],
        unavailableLimitIDs: [String] = []
    ) {
        materializeLegacyLimits(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        var chosen = effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        if enabled {
            chosen.insert(limitID)
        } else {
            chosen.remove(limitID)
        }
        let declared = availableLimitIDs + unavailableLimitIDs
        if chosen.isEmpty, let fallback = declared.first {
            chosen.insert(fallback)
        }
        shownBuckets[integrationID] = chosen.isEmpty ? nil : chosen
    }

    /// Writes a legacy integration's migrated selection into `shownBuckets`.
    ///
    /// Declared IDs are required: without them the old "all available minus
    /// hidden" rule cannot be applied, and unavailable choices cannot be kept.
    mutating func materializeLegacyLimits(
        integrationID: String,
        availableLimitIDs: [String],
        unavailableLimitIDs: [String] = []
    ) {
        guard usesLegacyLimitDefaults,
              shownBuckets[integrationID] == nil,
              !(availableLimitIDs.isEmpty && unavailableLimitIDs.isEmpty)
        else { return }
        let migrated = legacyMigratedLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
        if !migrated.isEmpty {
            shownBuckets[integrationID] = migrated
        }
        legacyHiddenBuckets.removeValue(forKey: integrationID)
        legacyShownUnavailableBuckets.removeValue(forKey: integrationID)
        // Keep usesLegacyLimitDefaults set: other integrations may still rely on
        // the implicit all-available rule until each has its own shownBuckets
        // entry. Clearing the flag here would turn those into first-only.
    }
}

extension MenuBarPreferences {
    /// The limits of one integration the menu bar draws.
    ///
    /// Saved IDs that the integration no longer declares are dropped. When
    /// nothing declared remains, the first declared limit stands in — not
    /// today's allowance, which has its own switch.
    func effectiveLimitIDs(
        integrationID: String,
        availableLimitIDs: [String],
        unavailableLimitIDs: [String]
    ) -> Set<String> {
        guard showAvailableLimits else { return [] }
        let declared = availableLimitIDs + unavailableLimitIDs
        let declaredSet = Set(declared)
        if let chosen = shownBuckets[integrationID], !chosen.isEmpty {
            let retained = chosen.intersection(declaredSet)
            if !retained.isEmpty {
                return retained
            }
            return declared.first.map { [$0] } ?? []
        }
        if usesLegacyLimitDefaults {
            return legacyMigratedLimitIDs(
                integrationID: integrationID,
                availableLimitIDs: availableLimitIDs,
                unavailableLimitIDs: unavailableLimitIDs
            )
        }
        return declared.first.map { [$0] } ?? []
    }

    /// Legacy visible available IDs minus hidden, plus chosen unavailable IDs,
    /// minus hidden again. Falls back to the first declared ID when none remain.
    func legacyMigratedLimitIDs(
        integrationID: String,
        availableLimitIDs: [String],
        unavailableLimitIDs: [String]
    ) -> Set<String> {
        let hidden = legacyHiddenBuckets[integrationID] ?? []
        let extras = legacyShownUnavailableBuckets[integrationID] ?? []
        let declared = availableLimitIDs + unavailableLimitIDs
        var migrated = Set(availableLimitIDs).subtracting(hidden)
        migrated.formUnion(extras)
        migrated.subtract(hidden)
        let retained = migrated.intersection(Set(declared))
        if retained.isEmpty, let first = declared.first {
            return [first]
        }
        return retained
    }
}
