import Foundation
import PluginKit
import ProviderSupport

/// Reading Claude's limits on the plugin's behalf.
enum UsageClient {
    /// Session that never follows redirects: a 3xx with the bearer still on
    /// the wire would otherwise land the token on a host the client did not ask
    /// for. Non-2xx answers, including those 3xx responses, stay
    /// `invalidResponse` through `HTTPClient`.
    private static let client = HTTPClient(
        session: redirectRefusingSession,
        userAgent: ClaudeConstants.userAgent
    )

    private static let redirectRefusingSession: URLSession = {
        URLSession(
            configuration: .ephemeral,
            delegate: RedirectRefusingDelegate.shared,
            delegateQueue: nil
        )
    }()

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
