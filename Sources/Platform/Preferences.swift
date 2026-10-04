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

    public init(
        defaultPolicyKind: String = PreferenceConstants.defaultPolicyKind,
        hasCompletedOnboarding: Bool = false,
        refreshIntervalSeconds: TimeInterval = RefreshConstants.defaultPollInterval,
        disabledProviders: Set<String> = [],
        menuBarQuotaID: UUID? = nil
    ) {
        self.defaultPolicyKind = defaultPolicyKind
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.disabledProviders = disabledProviders
        self.menuBarQuotaID = menuBarQuotaID
    }

    /// The same preferences pointing at a different quota.
    public func withMenuBarQuotaID(_ id: UUID?) -> Preferences {
        Preferences(
            defaultPolicyKind: defaultPolicyKind,
            hasCompletedOnboarding: hasCompletedOnboarding,
            refreshIntervalSeconds: refreshIntervalSeconds,
            disabledProviders: disabledProviders,
            menuBarQuotaID: id
        )
    }

    public static let `default` = Preferences()
}
