import Foundation
@testable import Core
@testable import PluginKit

/// How a provider's failure is put to the user.
///
/// One table, so every screen translates a failure the same way. A failure
/// translated at the point of display is translated differently on each screen,
/// and the user learns that "Rate limited" on one row means "try later" and on
/// another means "something is wrong with your account".
public enum ProviderFailurePresentation: Sendable, Equatable {
    /// The provider needs the user to sign in.
    case authenticationRequired
    /// Credentials existed and were refused, so they must be replaced.
    case authenticationExpired
    /// The provider could not be reached at all.
    case providerUnavailable
    /// The provider is asking for less traffic.
    case rateLimited
    /// The provider answered, and has no usage to report.
    case usageUnavailable
    /// The provider answered with something unusable.
    case invalidResponse
    /// What was asked for is not something this provider meters.
    case unsupportedQuota
    /// The plugin itself is broken.
    case pluginError
    /// The failure is not one of the above.
    case unknown

    /// Every state, in declaration order.
    public static let all: [ProviderFailurePresentation] = [
        .authenticationRequired, .authenticationExpired, .providerUnavailable,
        .rateLimited, .usageUnavailable, .invalidResponse, .unsupportedQuota,
        .pluginError, .unknown,
    ]

    /// A title for the state, in the interface's own words rather than the
    /// provider's.
    public var title: String {
        switch self {
        case .authenticationRequired: "Authentication Required"
        case .authenticationExpired: "Authentication Expired"
        case .providerUnavailable: "Provider Unavailable"
        case .rateLimited: "Rate Limited"
        case .usageUnavailable: "Usage Unavailable"
        case .invalidResponse: "Invalid Response"
        case .unsupportedQuota: "Unsupported Quota"
        case .pluginError: "Plugin Error"
        case .unknown: "Unknown Error"
        }
    }

    /// What the interface offers to do about it.
    ///
    /// A closed set rather than a bool, because "is this retryable" is the
    /// question that got the answer wrong: a rate limit is retryable, a plugin
    /// error is retryable, and an unsupported quota is not, and both of the
    /// first two are retryable *later* rather than *now*.
    public var action: UserAction {
        switch self {
        case .authenticationRequired, .authenticationExpired: .reconnect
        // A provider that is merely unreachable may answer in a moment, so
        // retrying is the honest offer. A rate limit is not that: it is the
        // provider saying when to come back, so the wait is part of the action.
        case .providerUnavailable, .unknown: .retry
        case .rateLimited: .waitAndRetry
        case .usageUnavailable, .unsupportedQuota: .none
        // The last two are the app's own fault rather than the provider's, so
        // what they offer is telling someone, not asking the user to try again.
        case .pluginError, .invalidResponse: .reportProblem
        }
    }

    /// Whether cached readings may still be shown, and if so how.
    ///
    /// This is the decision "retain cached data when appropriate" turns
    /// on. Usage unavailable and unsupported quota are not failures of the last
    /// reading, so it stands; an authentication or transport failure says
    /// nothing about the reading either, so it stands too. A rate limit is the
    /// one case where the provider is telling us the reading is probably fine
    /// and we should stop asking.
    public var retainsCachedData: Bool {
        self != .usageUnavailable
    }
}

/// What the interface can offer in response to a failure.
public enum UserAction: String, Sendable, Equatable, CaseIterable {
    /// Ask the provider to authenticate again.
    case reconnect
    /// Try the same read again now.
    case retry
    /// Try again after a wait; offering "retry" would invite hammering.
    case waitAndRetry
    /// Offer nothing, because retrying cannot help.
    case none
    /// Offer to report the problem, because the app is what is wrong.
    case reportProblem
}

public extension ProviderErrorCode {
    /// Whether this failure means the app should wait longer before trying again.
    ///
    /// Only failures where asking sooner is likely to fail the same way count.
    /// Being told the provider is not connected, or that it has nothing to
    /// report, is an answer: backing off from it would delay the app learning
    /// that the user has just connected the account, or that the provider has
    /// come back. Backing off from those is how a fixed problem stays broken.
    var backsOff: Bool {
        switch self {
        case .notInstalled, .notPermitted, .networkUnavailable, .rateLimited, .pluginError: true
        case .notAuthenticated, .authenticationFailed, .invalidResponse, .nothingToReport,
             .providerError: false
        }
    }
}

/// Translates protocol error codes into what the user is told.
public enum ProviderFailureTranslator {
    /// The state a protocol error code puts the user in.
    ///
    /// Total by construction: a new case on the protocol enum breaks this
    /// switch at compile time rather than appearing in the interface as
    /// something nobody wrote a word for.
    public static func presentation(for code: ProviderErrorCode) -> ProviderFailurePresentation {
        // One switch over every code, so a case added to the protocol enum
        // without a decision here fails to compile rather than appearing in the
        // interface as something nobody wrote a word for. It is split in two
        // halves only to keep each function small enough to read.
        switch code {
        case .notInstalled, .notPermitted, .networkUnavailable: .providerUnavailable
        case .notAuthenticated: .authenticationRequired
        case .authenticationFailed: .authenticationExpired
        case .rateLimited: .rateLimited
        case .invalidResponse: .invalidResponse
        case .nothingToReport: .usageUnavailable
        // The plugin's own failure, kept apart from the provider being
        // unreachable: one is the app's fault and offers a report, the other may
        // simply answer in a moment and offers a retry.
        case .pluginError: .pluginError
        case .providerError: .unknown
        }
    }

    /// The state a recorded failure puts the user in.
    public static func presentation(for failure: SyncFailure) -> ProviderFailurePresentation {
        presentation(for: failure.code)
    }
}
