import Foundation
import PluginKit
import ProviderSupport

/// Reading Cursor's dashboard on the plugin's behalf.
enum UsageClient {
    private static let client = HTTPClient(userAgent: CursorConstants.browserUserAgent)

    static func fetchUsage(token: ResolvedToken, localDate: String) throws -> UsageResult {
        if let fixture = HTTPFixture.object(
            environmentVariable: CursorConstants.fixtureCurrentPeriodEnvironment
        ) {
            return try UsageNormaliser.usageResult(
                fromCurrentPeriod: fixture,
                updatedAtDay: localDate
            )
        }

        let cookie = SessionCookie.header(
            userID: token.decoded.userID,
            accessToken: token.accessToken
        )

        do {
            let current = try client.postJSON(
                CursorConstants.currentPeriodUsageURL,
                headers: headers(cookie: cookie, includeOrigin: true)
            )
            return try UsageNormaliser.usageResult(
                fromCurrentPeriod: current,
                updatedAtDay: localDate
            )
        } catch ProviderHTTPError.invalidResponse {
            if let fixture = HTTPFixture.object(
                environmentVariable: CursorConstants.fixtureSummaryEnvironment
            ) {
                return try UsageNormaliser.usageResult(
                    fromUsageSummary: fixture,
                    updatedAtDay: localDate
                )
            }
            let summary = try client.getJSON(
                CursorConstants.usageSummaryURL,
                headers: headers(cookie: cookie)
            )
            return try UsageNormaliser.usageResult(
                fromUsageSummary: summary,
                updatedAtDay: localDate
            )
        }
    }

    /// The session as the dashboard expects to see it.
    private static func headers(cookie: String, includeOrigin: Bool = false) -> [String: String] {
        var headers = ["Cookie": cookie]
        if includeOrigin {
            headers["Origin"] = CursorConstants.requiredOrigin
            headers["Referer"] = CursorConstants.spendingReferer
        }
        return headers
    }
}
