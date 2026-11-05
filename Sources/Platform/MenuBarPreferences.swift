import Foundation

public struct MenuBarPreferences: Codable, Sendable, Equatable {
    public enum ValueMode: String, Codable, Sendable, CaseIterable {
        case both, used, remaining
    }

    public var showLogos = true
    public var showDailyQuota = true

    /// Whether the limits chosen under each integration are drawn.
    ///
    /// Off by default: the menu bar is narrow, and today's allowance is the
    /// figure worth showing without a choice. Turning this on makes each
    /// integration keep at least one limit, so no integration loses its only
    /// limit figure.
    public var showAvailableLimits = false
    public var valueMode: ValueMode = .both
    public var hiddenIntegrations: Set<String> = []

    /// Limits the user chose to show in the menu bar, per integration.
    ///
    /// An integration with no entry shows the first available limit while
    /// `showAvailableLimits` is on, so every integration keeps one limit.
    public var shownBuckets: [String: Set<String>] = [:]

    /// Quotas whose today's allowance is shown, per integration.
    ///
    /// An integration with no entry keeps the older choice: the planned quota.
    /// An entry is the list the user picked; if it is empty the planned quota
    /// stands in, because a visible integration always keeps a daily figure.
    public var dailyQuotas: [String: Set<UUID>] = [:]

    private enum CodingKeys: String, CodingKey {
        case showLogos
        case showDailyQuota
        case showAvailableLimits
        case valueMode
        case hiddenIntegrations
        case shownBuckets
        case dailyQuotas
        case legacyShownUnavailableBuckets = "shownUnavailableBuckets"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showLogos = try values.decodeIfPresent(Bool.self, forKey: .showLogos) ?? true
        showDailyQuota = try values.decodeIfPresent(Bool.self, forKey: .showDailyQuota) ?? true
        showAvailableLimits = try values.decodeIfPresent(
            Bool.self,
            forKey: .showAvailableLimits
        ) ?? false
        valueMode = try values.decodeIfPresent(ValueMode.self, forKey: .valueMode) ?? .both
        hiddenIntegrations = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenIntegrations) ?? []
        // Before limits were off by default the only chosen set was the one for
        // unavailable limits, so carry those choices over rather than dropping
        // them when the stored document is read.
        shownBuckets = try values.decodeIfPresent(
            [String: Set<String>].self,
            forKey: .shownBuckets
        ) ?? values.decodeIfPresent(
            [String: Set<String>].self,
            forKey: .legacyShownUnavailableBuckets
        ) ?? [:]
        dailyQuotas = try values.decodeIfPresent([String: Set<UUID>].self, forKey: .dailyQuotas) ?? [:]
        // An older document could store both switches off. The menu bar needs
        // one of them to have a figure to draw, so today's allowance returns.
        if !showDailyQuota, !showAvailableLimits {
            showDailyQuota = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(showLogos, forKey: .showLogos)
        try values.encode(showDailyQuota, forKey: .showDailyQuota)
        try values.encode(showAvailableLimits, forKey: .showAvailableLimits)
        try values.encode(valueMode, forKey: .valueMode)
        try values.encode(hiddenIntegrations, forKey: .hiddenIntegrations)
        try values.encode(shownBuckets, forKey: .shownBuckets)
        try values.encode(dailyQuotas, forKey: .dailyQuotas)
    }

    /// Whether turning today's allowance off would leave the menu bar with no
    /// figures to draw.
    public var canTurnOffDailyQuota: Bool {
        showAvailableLimits
    }

    /// Whether turning the limits off would leave the menu bar with no figures
    /// to draw.
    public var canTurnOffAvailableLimits: Bool {
        showDailyQuota
    }

    /// Turns today's allowance on or off.
    ///
    /// With limits off, today's allowance is the only figure the menu bar has,
    /// so it stays on.
    public mutating func setShowsDailyQuota(_ enabled: Bool) {
        guard enabled || showAvailableLimits else { return }
        showDailyQuota = enabled
    }

    /// Turns the limits on or off.
    ///
    /// With today's allowance off, limits are the only figures the menu bar
    /// has, so they stay on.
    public mutating func setShowsAvailableLimits(_ enabled: Bool) {
        guard enabled || showDailyQuota else { return }
        showAvailableLimits = enabled
    }

    /// Whether one limit of an integration is drawn in the menu bar.
    ///
    /// The global switch wins. While it is on, an integration whose chosen
    /// list is empty shows its first available limit rather than none.
    public func showsLimit(
        _ limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = []
    ) -> Bool {
        guard showAvailableLimits else { return false }
        return effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs
        ).contains(limitID)
    }

    /// Whether one limit can be switched off without leaving its integration
    /// with no limit in the menu bar.
    public func canHideLimit(
        _ limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = []
    ) -> Bool {
        let chosen = effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs
        )
        return chosen.count > 1 && chosen.contains(limitID)
    }

    /// Records whether one limit is drawn in the menu bar.
    ///
    /// The effective list is written rather than the raw one, so a limit
    /// enabled while the first available one was standing in keeps that first
    /// limit beside it. The last limit cannot be removed: the bar would lose
    /// the integration's limit figure entirely.
    public mutating func setShowsLimit(
        _ enabled: Bool,
        limitID: String,
        integrationID: String,
        availableLimitIDs: [String] = []
    ) {
        var chosen = effectiveLimitIDs(
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs
        )
        if enabled {
            chosen.insert(limitID)
        } else {
            chosen.remove(limitID)
        }
        if chosen.isEmpty, let fallback = availableLimitIDs.first {
            chosen.insert(fallback)
        }
        shownBuckets[integrationID] = chosen.isEmpty ? nil : chosen
    }

    /// The limits of one integration the menu bar draws.
    private func effectiveLimitIDs(
        integrationID: String,
        availableLimitIDs: [String]
    ) -> Set<String> {
        guard showAvailableLimits else { return [] }
        if let chosen = shownBuckets[integrationID], !chosen.isEmpty {
            return chosen
        }
        return availableLimitIDs.first.map { [$0] } ?? []
    }

    /// Whether this quota's today's allowance belongs in the menu bar.
    ///
    /// The global switch wins: with daily quota hidden, no quota shows one.
    /// Otherwise the integration's own list wins over the planned quota, and
    /// an integration that has never been given a list still shows the planned
    /// quota — the choice the menu bar made before a list existed.
    public func showsDailyAllowance(
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
    public func canHideDailyQuota(
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
    public mutating func setShowsDailyAllowance(
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

    /// The quotas of one integration that show today's allowance.
    ///
    /// An empty or missing choice falls back to the planned quota, so the
    /// global switch being on cannot leave an integration with no daily row.
    private func effectiveDailyQuotaIDs(
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
