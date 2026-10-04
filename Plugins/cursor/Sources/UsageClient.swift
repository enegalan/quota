import Foundation
import PluginKit

enum UsageClientError: Error, Equatable {
    case networkUnavailable
    case rateLimited(retryAfterSeconds: Double?)
    case authenticationFailed
    case invalidResponse
    case nothingToReport
}

enum UsageClient {
    static func fetchUsage(token: ResolvedToken, localDate: String) throws -> UsageResult {
        if let fixture = loadFixture(
            environment: CursorConstants.fixtureCurrentPeriodEnvironment
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
            let current = try postJSON(
                url: CursorConstants.currentPeriodUsageURL,
                cookie: cookie,
                includeOrigin: true
            )
            return try UsageNormaliser.usageResult(
                fromCurrentPeriod: current,
                updatedAtDay: localDate
            )
        } catch UsageClientError.invalidResponse {
            if let summaryFixture = loadFixture(
                environment: CursorConstants.fixtureSummaryEnvironment
            ) {
                return try UsageNormaliser.usageResult(
                    fromUsageSummary: summaryFixture,
                    updatedAtDay: localDate
                )
            }
            let summary = try getJSON(url: CursorConstants.usageSummaryURL, cookie: cookie)
            return try UsageNormaliser.usageResult(
                fromUsageSummary: summary,
                updatedAtDay: localDate
            )
        }
    }

    private static func loadFixture(environment: String) -> [String: Any]? {
        guard let path = ProcessInfo.processInfo.environment[environment],
              !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func postJSON(
        url: String,
        cookie: String,
        includeOrigin: Bool
    ) throws -> [String: Any] {
        guard let endpoint = URL(string: url) else { throw UsageClientError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(CursorConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(CursorConstants.spendingReferer, forHTTPHeaderField: "Referer")
        if includeOrigin {
            request.setValue(CursorConstants.requiredOrigin, forHTTPHeaderField: "Origin")
        }
        return try perform(request)
    }

    private static func getJSON(url: String, cookie: String) throws -> [String: Any] {
        guard let endpoint = URL(string: url) else { throw UsageClientError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(CursorConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
        return try perform(request)
    }

    private static func perform(_ request: URLRequest) throws -> [String: Any] {
        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var transportError: Error?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { body, urlResponse, error in
            box.data = body
            box.response = urlResponse
            box.transportError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if box.transportError != nil {
            throw UsageClientError.networkUnavailable
        }

        guard let http = box.response as? HTTPURLResponse else {
            throw UsageClientError.networkUnavailable
        }

        switch http.statusCode {
        case CursorConstants.httpOK:
            guard let data = box.data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw UsageClientError.invalidResponse
            }
            return object
        case CursorConstants.httpUnauthorized, CursorConstants.httpForbidden:
            // Do not inspect the body: unauthorised responses can echo the cookie.
            throw UsageClientError.authenticationFailed
        case CursorConstants.httpTooManyRequests:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw UsageClientError.rateLimited(retryAfterSeconds: retry)
        default:
            throw UsageClientError.invalidResponse
        }
    }
}
