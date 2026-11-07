import Core
import Foundation

/// User-level settings that are not tied to a single quota.
public struct Preferences: Codable, Sendable, Equatable {
    /// Whether a period is offered as daily, weekly, or monthly when a quota is
    /// created. The value is a preference, not a policy: a quota's own policy is
    /// stored on the quota.
    public let defaultPolicyKind: String
    public let hasCompletedOnboarding: Bool

    /// Legacy global poll interval kept for documents written before per-integration
    /// intervals. Scheduling no longer reads it; each integration has its own value.
    public let refreshIntervalSeconds: TimeInterval

    /// Poll interval chosen for one integration, keyed by integration id.
    ///
    /// An integration with no entry uses its own suggested interval, then the
    /// platform default. The entry is removed when the user returns to that default.
    public let refreshIntervalSecondsByProvider: [String: TimeInterval]

    /// Providers switched off without a release.
    ///
    /// A provider can be turned off because it is misbehaving, and waiting for a
    /// release to do it means every user keeps it until then. It is a preference
    /// rather than a code path so the switch is data: a build that ships a provider
    /// nobody can reach is still reachable the moment the entry is removed from
    /// this set.
    public let disabledProviders: Set<String>

    /// The quota the menu bar item speaks for.
    ///
    /// Optional and nil by default, and it stays that way until the user picks:
    /// a menu bar has room for one number, so with several quotas the app has to
    /// know which one the user is asking about, and the only answer it can be
    /// given is the user's own. A stored id that names a quota which has since
    /// been deleted is not corrected here — see `AppModel`'s resolution, which
    /// falls back rather than rewriting, because a missing quota may be restored
    /// and a choice silently forgotten would not.
    public let menuBarQuotaID: UUID?

    /// Whether quota alerts are delivered as notifications.
    public let notificationsEnabled: Bool

    /// Whether the app asks GitHub for a newer release on its own.
    public let automaticUpdateChecksEnabled: Bool

    /// When the last update check finished, or nil if none has run yet.
    ///
    /// Used to keep automatic checks to at most one per day, so a preference
    /// save that reloads the model does not hammer the releases endpoint.
    public let lastUpdateCheckAt: Date?

    /// The release version the user was already told about, if any.
    ///
    /// An automatic check that finds the same version again must not reopen the
    /// browser; a manual check still may.
    public let announcedUpdateVersion: String?
    public let menuBar: MenuBarPreferences

    public init(
        defaultPolicyKind: String = PreferenceConstants.defaultPolicyKind,
        hasCompletedOnboarding: Bool = false,
        refreshIntervalSeconds: TimeInterval = RefreshConstants.defaultPollInterval,
        refreshIntervalSecondsByProvider: [String: TimeInterval] = [:],
        disabledProviders: Set<String> = [],
        menuBarQuotaID: UUID? = nil,
        notificationsEnabled: Bool = PreferenceConstants.defaultNotificationsEnabled,
        automaticUpdateChecksEnabled: Bool = PreferenceConstants.defaultAutomaticUpdateChecksEnabled,
        lastUpdateCheckAt: Date? = nil,
        announcedUpdateVersion: String? = nil,
        menuBar: MenuBarPreferences = MenuBarPreferences()
    ) {
        self.defaultPolicyKind = defaultPolicyKind
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.refreshIntervalSecondsByProvider = refreshIntervalSecondsByProvider
        self.disabledProviders = disabledProviders
        self.menuBarQuotaID = menuBarQuotaID
        self.notificationsEnabled = notificationsEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.lastUpdateCheckAt = lastUpdateCheckAt
        self.announcedUpdateVersion = announcedUpdateVersion
        self.menuBar = menuBar
    }

    /// Older stored preferences omit newer keys; treat those as the platform
    /// defaults rather than refusing to load the rest.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultPolicyKind = try container.decode(String.self, forKey: .defaultPolicyKind)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        refreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .refreshIntervalSeconds)
        refreshIntervalSecondsByProvider = try container.decodeIfPresent(
            [String: TimeInterval].self,
            forKey: .refreshIntervalSecondsByProvider
        ) ?? [:]
        disabledProviders = try container.decode(Set<String>.self, forKey: .disabledProviders)
        menuBarQuotaID = try container.decodeIfPresent(UUID.self, forKey: .menuBarQuotaID)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)
            ?? PreferenceConstants.defaultNotificationsEnabled
        automaticUpdateChecksEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdateChecksEnabled
        ) ?? PreferenceConstants.defaultAutomaticUpdateChecksEnabled
        lastUpdateCheckAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckAt)
        announcedUpdateVersion = try container.decodeIfPresent(
            String.self,
            forKey: .announcedUpdateVersion
        )
        menuBar = try container.decodeIfPresent(MenuBarPreferences.self, forKey: .menuBar) ?? MenuBarPreferences()
    }

    /// The same preferences pointing at a different quota.
    public func withMenuBarQuotaID(_ id: UUID?) -> Preferences {
        copy(menuBarQuotaID: id)
    }

    /// The same preferences with a different menu-bar block.
    public func withMenuBar(_ menuBar: MenuBarPreferences) -> Preferences {
        copy(menuBar: menuBar)
    }

    /// The same preferences with notifications toggled.
    public func withNotificationsEnabled(_ enabled: Bool) -> Preferences {
        copy(notificationsEnabled: enabled)
    }

    /// The same preferences with automatic update checks toggled.
    public func withAutomaticUpdateChecksEnabled(_ enabled: Bool) -> Preferences {
        copy(automaticUpdateChecksEnabled: enabled)
    }

    /// The same preferences after an update check finished.
    public func withLastUpdateCheckAt(_ date: Date?) -> Preferences {
        copy(lastUpdateCheckAt: date)
    }

    /// The same preferences after a release was announced to the user.
    public func withAnnouncedUpdateVersion(_ version: String?) -> Preferences {
        copy(announcedUpdateVersion: version)
    }

    /// The same preferences with a different legacy global refresh interval.
    public func withRefreshIntervalSeconds(_ seconds: TimeInterval) -> Preferences {
        copy(refreshIntervalSeconds: seconds)
    }

    /// The interval in force for one integration.
    ///
    /// Order: the user's override, then the integration's suggested default, then
    /// the platform default. Every path is clamped to the platform bounds.
    public func refreshInterval(
        for integrationID: String,
        suggested: TimeInterval? = nil
    ) -> TimeInterval {
        if let override = refreshIntervalSecondsByProvider[integrationID] {
            return RefreshConstants.clamped(override)
        }
        if let suggested {
            return RefreshConstants.clamped(suggested)
        }
        return RefreshConstants.clamped(RefreshConstants.defaultPollInterval)
    }

    /// The same preferences with one integration's interval set, or cleared.
    ///
    /// Nil removes the entry, so the integration goes back to its suggested
    /// default (or the platform default when it has none).
    public func withRefreshInterval(_ seconds: TimeInterval?, for integrationID: String) -> Preferences {
        var intervals = refreshIntervalSecondsByProvider
        if let seconds {
            intervals[integrationID] = RefreshConstants.clamped(seconds)
        } else {
            intervals.removeValue(forKey: integrationID)
        }
        return copy(refreshIntervalSecondsByProvider: intervals)
    }

    private func copy(
        defaultPolicyKind: String? = nil,
        hasCompletedOnboarding: Bool? = nil,
        refreshIntervalSeconds: TimeInterval? = nil,
        refreshIntervalSecondsByProvider: [String: TimeInterval]? = nil,
        disabledProviders: Set<String>? = nil,
        menuBarQuotaID: UUID?? = nil,
        notificationsEnabled: Bool? = nil,
        automaticUpdateChecksEnabled: Bool? = nil,
        lastUpdateCheckAt: Date?? = nil,
        announcedUpdateVersion: String?? = nil,
        menuBar: MenuBarPreferences? = nil
    ) -> Preferences {
        Preferences(
            defaultPolicyKind: defaultPolicyKind ?? self.defaultPolicyKind,
            hasCompletedOnboarding: hasCompletedOnboarding ?? self.hasCompletedOnboarding,
            refreshIntervalSeconds: refreshIntervalSeconds ?? self.refreshIntervalSeconds,
            refreshIntervalSecondsByProvider: refreshIntervalSecondsByProvider
                ?? self.refreshIntervalSecondsByProvider,
            disabledProviders: disabledProviders ?? self.disabledProviders,
            menuBarQuotaID: menuBarQuotaID ?? self.menuBarQuotaID,
            notificationsEnabled: notificationsEnabled ?? self.notificationsEnabled,
            automaticUpdateChecksEnabled: automaticUpdateChecksEnabled
                ?? self.automaticUpdateChecksEnabled,
            lastUpdateCheckAt: lastUpdateCheckAt ?? self.lastUpdateCheckAt,
            announcedUpdateVersion: announcedUpdateVersion ?? self.announcedUpdateVersion,
            menuBar: menuBar ?? self.menuBar
        )
    }

    public static let `default` = Preferences()
}
