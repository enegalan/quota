import Foundation

/// Named values for the Codex provider plugin.
enum CodexConstants {
    static let providerID = "codex"
    static let displayName = "OpenAI Codex CLI"
    static let description =
        "Codex plan usage and limits from your ChatGPT subscription."

    /// Where Codex writes its ChatGPT OAuth session when file storage is used.
    ///
    /// Overridable with `CODEX_HOME`. The credential belongs to Codex, and this
    /// plugin never writes it — Codex refreshes the original.
    static let credentialsFileName = "auth.json"
    static let configurationFileName = "config.toml"
    static let defaultHomeRelativePath = ".codex"

    /// Codex's `cli_auth_credentials_store` key in `config.toml`.
    ///
    /// Decides whether the active sign-in lives in the keychain, in
    /// `auth.json`, or prefers the keychain with a file fallback (`auto`).
    static let credentialsStoreConfigKey = "cli_auth_credentials_store"

    /// The macOS keychain service Codex writes its sign-in under.
    ///
    /// The account name is derived from `CODEX_HOME` the same way Codex does
    /// (`cli|` plus a truncated SHA-256 of the path). Both spellings are tried.
    static let keychainServiceName = "Codex Auth"

    /// The endpoint Codex reads its ChatGPT plan limits from.
    ///
    /// Undocumented by OpenAI, and it may change or disappear without notice.
    /// It is the route the open-source Codex client uses for the same meters
    /// `/status` shows, so a plugin that answers without it would have nothing
    /// true to say about a ChatGPT-backed session.
    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"

    /// The client the endpoint expects to be asked by.
    static let userAgent = "codex_cli_rs"

    /// Header that routes the request to the selected ChatGPT account.
    static let accountHeaderName = "ChatGPT-Account-ID"

    /// Rolling windows commonly reported for Plus/Business plans.
    static let fiveHourSeconds: TimeInterval = 5 * 60 * 60
    static let sevenDaySeconds: TimeInterval = 7 * 24 * 60 * 60

    static let primaryBucketID = "primary_window"
    static let secondaryBucketID = "secondary_window"
    static let primaryDisplayName = "5-hour session"
    static let secondaryDisplayName = "Weekly"

    /// How often the provider would rather not be asked again, in seconds.
    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let credentialsFileEnvironment = "QUOTA_CODEX_CREDENTIALS"
    static let fixtureUsageEnvironment = "QUOTA_CODEX_USAGE_FIXTURE"
    static let homeEnvironment = "CODEX_HOME"
}
