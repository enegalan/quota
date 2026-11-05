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

    /// Legacy opt-out selections, kept until declared limit IDs can migrate them.
    var legacyHiddenBuckets: [String: Set<String>] = [:]

    /// Legacy opt-in selections for unavailable limits, kept with
    /// `legacyHiddenBuckets` until migration.
    var legacyShownUnavailableBuckets: [String: Set<String>] = [:]

    /// Whether this value was decoded without `shownBuckets`, so missing entries
    /// still mean "all available limits that were not hidden".
    var usesLegacyLimitDefaults = false

    enum CodingKeys: String, CodingKey {
        case showLogos
        case showDailyQuota
        case showAvailableLimits
        case valueMode
        case hiddenIntegrations
        case shownBuckets
        case dailyQuotas
        case legacyHiddenBuckets = "hiddenBuckets"
        case legacyShownUnavailableBuckets = "shownUnavailableBuckets"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showLogos = try values.decodeIfPresent(Bool.self, forKey: .showLogos) ?? true
        showDailyQuota = try values.decodeIfPresent(Bool.self, forKey: .showDailyQuota) ?? true
        // A missing key is not the same as false: older documents without the
        // field kept a figure by showing limits whenever today's allowance was
        // off. An explicit false still means off.
        if values.contains(.showAvailableLimits) {
            showAvailableLimits = try values.decode(Bool.self, forKey: .showAvailableLimits)
        } else {
            showAvailableLimits = !showDailyQuota
        }
        valueMode = try values.decodeIfPresent(ValueMode.self, forKey: .valueMode) ?? .both
        hiddenIntegrations = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenIntegrations) ?? []
        dailyQuotas = try values.decodeIfPresent([String: Set<UUID>].self, forKey: .dailyQuotas) ?? [:]
        // Older documents stored hidden available limits and chosen unavailable
        // ones separately. Keep those until declared IDs exist; mapping them into
        // shownBuckets here would drop every available limit the user had not
        // hidden.
        if values.contains(.shownBuckets) {
            shownBuckets = try values.decodeIfPresent(
                [String: Set<String>].self,
                forKey: .shownBuckets
            ) ?? [:]
        } else {
            usesLegacyLimitDefaults = true
            shownBuckets = [:]
            legacyHiddenBuckets = try values.decodeIfPresent(
                [String: Set<String>].self,
                forKey: .legacyHiddenBuckets
            ) ?? [:]
            legacyShownUnavailableBuckets = try values.decodeIfPresent(
                [String: Set<String>].self,
                forKey: .legacyShownUnavailableBuckets
            ) ?? [:]
        }
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
        try values.encode(dailyQuotas, forKey: .dailyQuotas)
        // Omit shownBuckets while still on the legacy path with nothing
        // materialized, so the next read keeps the all-available default.
        if !usesLegacyLimitDefaults || !shownBuckets.isEmpty {
            try values.encode(shownBuckets, forKey: .shownBuckets)
        }
        if !legacyHiddenBuckets.isEmpty {
            try values.encode(legacyHiddenBuckets, forKey: .legacyHiddenBuckets)
        }
        if !legacyShownUnavailableBuckets.isEmpty {
            try values.encode(
                legacyShownUnavailableBuckets,
                forKey: .legacyShownUnavailableBuckets
            )
        }
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
}
