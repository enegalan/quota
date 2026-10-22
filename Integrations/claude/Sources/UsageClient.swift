import Foundation
import PluginKit
import ProviderSupport

/// Reading Claude's limits on the plugin's behalf.
enum UsageClient {
    private static let client = HTTPClient(userAgent: ClaudeConstants.userAgent)

    /// The usage the account's subscription reports.
    static func fetchUsage(credential: ClaudeCredential, localDate: String) throws -> UsageResult {
        if let fixture = HTTPFixture.object(
            environmentVariable: ClaudeConstants.fixtureUsageEnvironment
        ) {
            return try UsageNormaliser.usageResult(from: fixture, updatedAtDay: localDate)
        }

        let payload = try client.getJSON(
            ClaudeConstants.usageURL,
            headers: headers(for: credential)
        )
        return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
    }

    /// The request as the endpoint expects it.
    ///
    /// The bearer token is the account's own, and the beta header is what
    /// tells the endpoint this is the OAuth surface rather than the API one.
    /// The token is never logged and never leaves this header.
    private static func headers(for credential: ClaudeCredential) -> [String: String] {
        [
            "Authorization": "Bearer \(credential.accessToken)",
            ClaudeConstants.betaHeaderName: ClaudeConstants.betaHeaderValue,
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]
    }
}
