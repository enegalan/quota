import Core
import Foundation

/// User-level settings that are not tied to a single quota.
public struct Preferences: Codable, Sendable, Equatable {
    /// Whether a period is offered as daily, weekly, or monthly when a quota is
    /// created. The value is a preference, not a policy: a quota's own policy is
    /// stored on the quota.
    public let defaultPolicyKind: String
    public let hasCompletedOnboarding: Bool

    /// How often a connected provider is polled when it has suggested nothing.
    ///
    /// A stored number rather than an absence, because the setting is shown as a
    /// figure in the interface and the user changes it by choosing one. It
    /// defaults to the scheduler's own default rather than to a second copy of
    /// it: a preference holding 600 while the schedule polled at 900 would mean
    /// the platform default was unreachable and neither number was the truth.
    public let refreshIntervalSeconds: TimeInterval

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

    public init(
        defaultPolicyKind: String = PreferenceConstants.defaultPolicyKind,
        hasCompletedOnboarding: Bool = false,
        refreshIntervalSeconds: TimeInterval = RefreshConstants.defaultPollInterval,
        disabledProviders: Set<String> = [],
        menuBarQuotaID: UUID? = nil,
        notificationsEnabled: Bool = PreferenceConstants.defaultNotificationsEnabled
    ) {
        self.defaultPolicyKind = defaultPolicyKind
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.disabledProviders = disabledProviders
        self.menuBarQuotaID = menuBarQuotaID
        self.notificationsEnabled = notificationsEnabled
    }

    /// Older stored preferences omit `notificationsEnabled`; treat that as the
    /// platform default rather than refusing to load the rest.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultPolicyKind = try container.decode(String.self, forKey: .defaultPolicyKind)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        refreshIntervalSeconds = try container.decode(TimeInterval.self, forKey: .refreshIntervalSeconds)
        disabledProviders = try container.decode(Set<String>.self, forKey: .disabledProviders)
        menuBarQuotaID = try container.decodeIfPresent(UUID.self, forKey: .menuBarQuotaID)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)
            ?? PreferenceConstants.defaultNotificationsEnabled
    }

    /// The same preferences pointing at a different quota.
    public func withMenuBarQuotaID(_ id: UUID?) -> Preferences {
        Preferences(
            defaultPolicyKind: defaultPolicyKind,
            hasCompletedOnboarding: hasCompletedOnboarding,
            refreshIntervalSeconds: refreshIntervalSeconds,
            disabledProviders: disabledProviders,
            menuBarQuotaID: id,
            notificationsEnabled: notificationsEnabled
        )
    }

    /// The same preferences with notifications toggled.
    public func withNotificationsEnabled(_ enabled: Bool) -> Preferences {
        Preferences(
            defaultPolicyKind: defaultPolicyKind,
            hasCompletedOnboarding: hasCompletedOnboarding,
            refreshIntervalSeconds: refreshIntervalSeconds,
            disabledProviders: disabledProviders,
            menuBarQuotaID: menuBarQuotaID,
            notificationsEnabled: enabled
        )
    }

    public static let `default` = Preferences()
}
