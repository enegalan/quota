import Foundation
import PluginKit
import ProviderSupport

/// Reading Codex's ChatGPT plan limits on the plugin's behalf.
enum UsageClient {
    /// Session that never follows redirects: a 3xx with the bearer still on
    /// the wire would otherwise land the token on a host the client did not ask
    /// for.
    private static let client = HTTPClient(
        session: redirectRefusingSession,
        userAgent: CodexConstants.userAgent
    )

    private static let redirectRefusingSession = URLSession(
        configuration: .ephemeral,
        delegate: RedirectRefusingDelegate.shared,
        delegateQueue: nil
    )

    /// The usage the account's ChatGPT plan reports.
    static func fetchUsage(credential: CodexCredential, localDate: String) throws -> UsageResult {
        if let fixture = HTTPFixture.object(
            environmentVariable: CodexConstants.fixtureUsageEnvironment
        ) {
            return try UsageNormaliser.usageResult(from: fixture, updatedAtDay: localDate)
        }

        let payload = try client.getJSON(
            CodexConstants.usageURL,
            headers: headers(for: credential)
        )
        return try UsageNormaliser.usageResult(from: payload, updatedAtDay: localDate)
    }

    /// The request as the endpoint expects it.
    ///
    /// The bearer is the ChatGPT OAuth access token, and the account header
    /// routes to the workspace Codex selected. Neither is logged.
    private static func headers(for credential: CodexCredential) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(credential.accessToken)",
            "Accept": "application/json",
        ]
        if let accountID = credential.accountID, !accountID.isEmpty {
            headers[CodexConstants.accountHeaderName] = accountID
        }
        return headers
    }
}

/// Refuses every redirect so an OAuth bearer is never replayed onto a new URL.
private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = RedirectRefusingDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
