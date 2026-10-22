import Foundation

/// Named values for the Cursor provider plugin.
enum CursorConstants {
    static let providerID = "cursor"
    static let displayName = "Cursor"
    static let description =
        "The subscription quota reported by the Cursor dashboard."

    static let stateDatabaseRelativePath =
        "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    static let accessTokenKey = "cursorAuth/accessToken"
    static let cachedEmailKey = "cursorAuth/cachedEmail"

    static let sessionTokenType = "session"
    static let sessionCookieName = "WorkosCursorSessionToken"
    static let cookieSubjectSeparator = "%3A%3A"

    /// Keychain service names tried after the state database, in order.
    static let keychainServiceNames = [
        "cursor-access-token",
        "Cursor Auth",
        "cursorAuth/accessToken",
    ]

    /// Credential file paths tried last, relative to the home directory.
    static let credentialsFileRelativePaths = [
        ".cursor/auth.json",
        ".config/cursor/auth.json",
        "Library/Application Support/Cursor/User/credentials.json",
    ]

    static let credentialsFileTokenKeys = ["accessToken", "access_token", "token"]

    static let requiredOrigin = "https://cursor.com"
    static let spendingReferer = "https://cursor.com/dashboard/spending"
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    static let currentPeriodUsageURL =
        "https://cursor.com/api/dashboard/get-current-period-usage"
    static let usageSummaryURL = "https://cursor.com/api/usage-summary"

    /// The period boundaries both payloads carry, under the same two names.
    static let billingStartKey = "billingCycleStart"
    static let billingEndKey = "billingCycleEnd"

    static let planBucketID = "plan"
    static let apiBucketID = "api"
    static let planBucketDisplayName = "Included plan"
    static let apiBucketDisplayName = "API / named models"
    static let planExternalID = "cursor-plan"
    static let apiExternalID = "cursor-api"

    /// Validated by the spike poll; clamped by the host to its own bounds.
    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let stateDatabasePathEnvironment = "QUOTA_CURSOR_STATE_DB"
    static let fixtureCurrentPeriodEnvironment = "QUOTA_CURSOR_USAGE_FIXTURE"
    static let fixtureSummaryEnvironment = "QUOTA_CURSOR_SUMMARY_FIXTURE"
}
