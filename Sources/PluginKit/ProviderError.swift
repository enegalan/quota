import Foundation

/// The nine ways asking a provider can go wrong.
///
/// Raw values are fixed. They cross the plugin boundary and land in logs and in
/// stored sync metadata, so renumbering one would change what an already-recorded
/// failure means to whatever reads it later. New states get new numbers; existing
/// ones never move.
public enum ProviderErrorCode: Int, Codable, Sendable, CaseIterable {
    /// The provider is not installed, or its executable is missing.
    case notInstalled = 1

    /// The provider is installed but the app is not allowed to talk to it.
    case notPermitted = 2

    /// The provider needs credentials and has none.
    case notAuthenticated = 3

    /// Credentials are present but were refused.
    case authenticationFailed = 4

    /// The provider could not be reached, or did not answer in time.
    case networkUnavailable = 5

    /// The provider answered, but not with something the app can use.
    case invalidResponse = 6

    /// The provider reports that the account has none of the thing asked for —
    /// no subscription, no quota, no such period.
    case nothingToReport = 7

    /// The plugin broke: it crashed, spoke nonsense, or did not honour the
    /// protocol. Distinct from `invalidResponse` because this one says nothing
    /// about whether the provider's data was any good.
    case pluginError = 8

    /// The provider's own failure, described in the response's message.
    case providerError = 9

    /// The provider is asking for less traffic.
    ///
    /// Appended rather than folded into `providerError`, whose raw value is
    /// frozen, because the two need opposite handling: a rate limit says wait,
    /// and the same wait applied to an unknown failure would turn every provider
    /// hiccup into a silent stall. Raw value 10 is unused, so adding it changes
    /// nothing about what a version 1 plugin already sends.
    case rateLimited = 10
}

/// A failure, as it crosses the plugin boundary.
///
/// The message is provider-authored text intended for a user. The core displays
/// it and never reads it: branching on a message would make a provider's wording
/// part of the core's contract, and a plugin could change it in a patch release.
/// Anything the core needs to act on is in the code.
public struct ProviderError: Codable, Sendable, Equatable, Error, LocalizedError {
    public let code: ProviderErrorCode
    public let message: String

    public init(code: ProviderErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    /// A message for a state the core decided, used when a plugin returns a code
    /// with nothing to say for itself.
    public init(code: ProviderErrorCode) {
        self.code = code
        message = ProviderError.defaultMessage(for: code)
    }

    public var errorDescription: String? {
        message
    }

    /// The text a provider would need to write nothing to be understood.
    ///
    /// A table rather than a switch: nine branches is a lookup, and reading it as
    /// a switch invites adding a tenth case that nobody notices is missing. Being
    /// a table also means the compiler enforces coverage — a new code with no
    /// message here will not build until one is written.
    public static let defaultMessages: [ProviderErrorCode: String] = [
        .notInstalled: "This provider is not installed.",
        .notPermitted: "The app is not allowed to read this provider.",
        .notAuthenticated: "Sign in to this provider to see its usage.",
        .authenticationFailed: "This provider rejected the sign-in.",
        .networkUnavailable: "This provider could not be reached.",
        .invalidResponse: "This provider sent something unreadable.",
        .nothingToReport: "This provider reported no usage.",
        .pluginError: "This provider's plugin stopped working.",
        .providerError: "This provider reported a problem.",
        .rateLimited: "This provider asked for less traffic.",
    ]

    /// The text to show for a code with no entry of the provider's own.
    ///
    /// A `String` rather than an optional because a user has to be shown
    /// something for every code, including one a newer plugin introduces that
    /// this build has never heard of. The wording is deliberately bland: it has
    /// to be true of any failure, and it must not excuse the provider or blame
    /// the user.
    public static func defaultMessage(for code: ProviderErrorCode) -> String {
        defaultMessages[code] ?? "This provider reported a problem."
    }
}
