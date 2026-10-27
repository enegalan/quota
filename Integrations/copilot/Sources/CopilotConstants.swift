import Foundation

/// Named values for the GitHub Copilot provider plugin.
enum CopilotConstants {
    static let providerID = "copilot"
    static let displayName = "GitHub Copilot"
    static let description =
        "Premium usage, chat, completions, and plan limits from GitHub Copilot."

    /// The undocumented endpoint editors use for live Copilot quota.
    ///
    /// Undocumented by GitHub, and it may change or disappear without notice.
    /// It is the only source of real-time remaining entitlement, so a plugin
    /// that answers without it would have nothing true to say.
    static let usageURL = "https://api.github.com/copilot_internal/user"

    /// The public profile endpoint, used only to name the signed-in account.
    static let userURL = "https://api.github.com/user"

    /// Headers the internal Copilot endpoint expects from an editor client.
    static let acceptHeader = "application/json"
    static let apiVersionHeaderName = "X-Github-Api-Version"
    static let apiVersionHeaderValue = "2025-04-01"
    static let editorVersionHeaderName = "Editor-Version"
    static let editorVersionHeaderValue = "vscode/1.96.2"
    static let editorPluginVersionHeaderName = "Editor-Plugin-Version"
    static let editorPluginVersionHeaderValue = "copilot-chat/0.26.7"
    static let userAgent = "GitHubCopilotChat/0.26.7"

    /// Keychain service Copilot CLI writes its OAuth token under.
    static let copilotCLIKeychainService = "copilot-cli"

    /// Environment variables checked first, in order.
    static let tokenEnvironmentNames = [
        "COPILOT_GITHUB_TOKEN",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "COPILOT_TOKEN",
    ]

    /// Where Copilot CLI may leave a plaintext token when the keychain is not
    /// available.
    static let credentialsFileRelativePath = ".copilot/config.json"
    static let credentialsFileTokenKeys = [
        "token",
        "oauth_token",
        "access_token",
        "accessToken",
    ]

    /// GitHub CLI hosts file — names the active login, never stores the token
    /// on modern installs.
    static let ghHostsRelativePath = ".config/gh/hosts.yml"
    static let ghHostName = "github.com"

    /// Snapshot keys Copilot reports under `quota_snapshots`.
    static let premiumInteractionsKey = "premium_interactions"
    static let chatKey = "chat"
    static let completionsKey = "completions"

    static let premiumInteractionsDisplayName = "Premium requests"
    static let chatDisplayName = "Chat"
    static let completionsDisplayName = "Completions"

    /// Free/limited payloads that omit `quota_snapshots` and use these instead.
    static let limitedUserQuotasKey = "limited_user_quotas"
    static let monthlyQuotasKey = "monthly_quotas"
    static let limitedUserResetDateKey = "limited_user_reset_date"

    static let quotaSnapshotsKey = "quota_snapshots"
    static let quotaResetDateUTCKey = "quota_reset_date_utc"
    static let quotaResetDateKey = "quota_reset_date"

    /// How often the provider would rather not be asked again, in seconds.
    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let fixtureUsageEnvironment = "QUOTA_COPILOT_USAGE_FIXTURE"
    static let credentialsFileEnvironment = "QUOTA_COPILOT_CREDENTIALS"
    static let tokenEnvironmentOverride = "QUOTA_COPILOT_TOKEN"
}
