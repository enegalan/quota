import Foundation

/// Named values for the Claude provider plugin.
enum ClaudeConstants {
    static let providerID = "claude"
    static let displayName = "Claude Code"
    static let description =
        "The usage your Claude Code subscription reports."

    /// The macOS keychain service Claude Code writes its sign-in under.
    ///
    /// Claude Code keeps its OAuth credentials in the keychain on macOS and in
    /// a file elsewhere. Both are read, and neither is written: the credential
    /// belongs to Claude Code, and a copy this plugin made could not be
    /// refreshed when Claude Code refreshed the original.
    static let keychainServiceName = "Claude Code-credentials"

    /// Where Claude Code writes its credentials when the keychain is not used.
    static let credentialsFileRelativePath = ".claude/.credentials.json"

    /// Claude Code's own configuration file, which names the signed-in account.
    static let configurationFileRelativePath = ".claude.json"

    /// The endpoint Claude Code reads its own limits from.
    ///
    /// Undocumented by Anthropic, and it may change or disappear without
    /// notice. It is the only source of a subscription's actual limits, so a
    /// plugin that answers without it would have nothing true to say.
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"

    /// The beta header the usage endpoint is served under.
    static let betaHeaderValue = "oauth-2025-04-20"

    /// The beta header's name.
    static let betaHeaderName = "anthropic-beta"

    /// The client the endpoint expects to be asked by.
    ///
    /// The endpoint is Anthropic's own and expects Claude Code's own client.
    /// A plugin identifying itself honestly is the right thing to do and the
    /// wrong thing for the request to go through, so the name is Claude Code's
    /// and the reason is written down here rather than left as a mystery.
    static let userAgent = "claude-code/2.0.32"

    /// The rolling windows Claude meters, and how long each one lasts.
    static let fiveHourWindow: TimeInterval = 5 * 60 * 60
    static let sevenDayWindow: TimeInterval = 7 * 24 * 60 * 60

    // The buckets Claude reports, named by the keys it uses.

    static let fiveHourKey = "five_hour"
    static let sevenDayKey = "seven_day"
    static let sevenDayOpusKey = "seven_day_opus"
    static let sevenDaySonnetKey = "seven_day_sonnet"

    static let fiveHourBucketID = "five_hour"
    static let sevenDayBucketID = "seven_day"
    static let sevenDayOpusBucketID = "seven_day_opus"
    static let sevenDaySonnetBucketID = "seven_day_sonnet"

    static let fiveHourDisplayName = "5-hour session"
    static let sevenDayDisplayName = "Weekly"
    static let sevenDayOpusDisplayName = "Weekly Opus"
    static let sevenDaySonnetDisplayName = "Weekly Sonnet"

    /// The per-model weekly limits, which arrive in a list rather than under a
    /// key of their own.
    static let limitsKey = "limits"
    static let scopedLimitKind = "weekly_scoped"

    /// The optional pay-as-you-go credit pool.
    static let extraUsageKey = "extra_usage"
    static let extraUsageBucketID = "extra_usage"
    static let extraUsageDisplayName = "Extra usage"

    /// How often the provider would rather not be asked again, in seconds.
    ///
    /// Claude's limits turn over on a schedule of hours, and the endpoint is
    /// not a public API: asking it often is asking a lot of a service that
    /// does not promise to answer.
    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let credentialsFileEnvironment = "QUOTA_CLAUDE_CREDENTIALS"
    static let fixtureUsageEnvironment = "QUOTA_CLAUDE_USAGE_FIXTURE"
}
