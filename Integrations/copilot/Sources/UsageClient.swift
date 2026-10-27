import Foundation
import PluginKit
import ProviderSupport

/// Reading GitHub Copilot's quota on the plugin's behalf.
enum UsageClient {
    private static let client = HTTPClient(userAgent: CopilotConstants.userAgent)

    /// The usage the account's Copilot plan reports.
    static func fetchUsage(token: String, localDate: String) throws -> UsageResult {
        if let fixture = HTTPFixture.object(
            environmentVariable: CopilotConstants.fixtureUsageEnvironment
        ) {
            return try UsageNormaliser.usageResult(from: fixture, updatedAtDay: localDate)
        }

        let payload = try client.getJSON(
            CopilotConstants.usageURL,
            headers: copilotHeaders(token: token)
        )
        return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
    }

    /// The GitHub login for the token, or nil when the profile cannot be read.
    static func fetchLogin(token: String) -> String? {
        guard let payload = try? client.getJSON(
                  CopilotConstants.userURL,
                  headers: [
                      "Authorization": "Bearer \(token)",
                      "Accept": "application/vnd.github+json",
                  ]
              ),
              let login = JSONAccess.string(payload, key: "login"),
              !login.isEmpty
        else {
            return nil
        }
        return login
    }

    /// Headers the internal Copilot endpoint expects from an editor client.
    private static func copilotHeaders(token: String) -> [String: String] {
        [
            "Authorization": "token \(token)",
            "Accept": CopilotConstants.acceptHeader,
            CopilotConstants.apiVersionHeaderName: CopilotConstants.apiVersionHeaderValue,
            CopilotConstants.editorVersionHeaderName: CopilotConstants.editorVersionHeaderValue,
            CopilotConstants.editorPluginVersionHeaderName:
                CopilotConstants.editorPluginVersionHeaderValue,
        ]
    }
}
