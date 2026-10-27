import Foundation

/// Named values for the Antigravity provider plugin.
enum AntigravityConstants {
    static let providerID = "antigravity"
    static let displayName = "Antigravity"
    static let description =
        "Antigravity platform AI credits and quota."

    /// Where Antigravity credentials may be stored.
    static let credentialsFileRelativePaths = [
        ".config/antigravity/auth.json",
        ".antigravity/auth.json",
        "Library/Application Support/Antigravity/auth.json",
    ]

    static let credentialsFileTokenKeys = ["accessToken", "access_token", "token", "apiKey"]

    /// The endpoint Antigravity reports usage and quota from (discovered; may
    /// change). The request is sent as a browser-style request to avoid CORS
    /// barriers seen by API-only clients.
    static let usageURL = "https://antigravity.google/api/usage"
    static let userInfoURL = "https://antigravity.google/api/user"

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    static let requiredOrigin = "https://antigravity.google"
    static let requiredReferer = "https://antigravity.google/"

    /// Bucket identifiers and display names.
    static let creditsBucketID = "credits"
    static let creditsBucketDisplayName = "AI credits"
    static let planBucketID = "plan"
    static let planBucketDisplayName = "Plan usage"

    /// How often the provider would rather not be asked again, in seconds.
    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let fixtureUsageEnvironment = "QUOTA_ANTIGRAVITY_USAGE_FIXTURE"
    static let credentialsFileEnvironment = "QUOTA_ANTIGRAVITY_CREDENTIALS"
}
