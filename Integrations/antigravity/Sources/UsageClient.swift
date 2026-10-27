import Foundation
import PluginKit
import ProviderSupport

/// Reading Antigravity's usage on the plugin's behalf.
enum UsageClient {
    private static let client = HTTPClient(userAgent: AntigravityConstants.browserUserAgent)

    static func fetchUsage(token: ResolvedToken, localDate: String) throws -> UsageResult {
        if let fixture = HTTPFixture.object(
            environmentVariable: AntigravityConstants.fixtureUsageEnvironment
        ) {
            return try UsageNormaliser.usageResult(from: fixture, updatedAtDay: localDate)
        }

        let headers = [
            "Authorization": "Bearer \(token.accessToken)",
            "Origin": AntigravityConstants.requiredOrigin,
            "Referer": AntigravityConstants.requiredReferer,
            "Accept": "application/json",
        ]

        do {
            let payload = try client.getJSON(AntigravityConstants.usageURL, headers: headers)
            return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
        } catch ProviderHTTPError.invalidResponse {
            // Try alternative endpoints
            if let payload = try? client.getJSON(
                "https://antigravity.google/api/quota",
                headers: headers
            ) {
                return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
            }
            if let payload = try? client.getJSON(
                "https://antigravity.google/api/usage/credits",
                headers: headers
            ) {
                return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
            }
            throw ProviderHTTPError.invalidResponse
        }
    }
}
