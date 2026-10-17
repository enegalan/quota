import Foundation
import PluginKit

/// The ways a request can fail, before the host has any opinion about them —
/// the vocabulary every provider reports its HTTP failures in, so one provider
/// never classifies a status differently from another.
public enum ProviderHTTPError: Error, Equatable, ProviderFailure {
    /// The request never got an answer.
    case networkUnavailable

    /// The provider asked for less traffic, and may say how much less.
    case rateLimited(retryAfterSeconds: Double?)

    /// The credential was presented and refused. The body is never read: an
    /// unauthorised response can echo the credential back, and this value ends
    /// up in logs and stored sync metadata.
    case authenticationFailed

    /// The provider answered, but not with something this plugin can use.
    case invalidResponse

    public var providerError: ProviderError {
        switch self {
        case .networkUnavailable:
            return ProviderError(code: .networkUnavailable)
        case .rateLimited(let retryAfterSeconds):
            let message = if let retryAfterSeconds {
                "Rate limited; retry after \(Int(retryAfterSeconds)) seconds."
            } else {
                ProviderError.defaultMessage(for: .rateLimited)
            }
            return ProviderError(code: .rateLimited, message: message)
        case .authenticationFailed:
            return ProviderError(code: .authenticationFailed)
        case .invalidResponse:
            return ProviderError(code: .invalidResponse)
        }
    }
}

/// The HTTP a provider plugin shares: one request, classified the same way by
/// every provider.
///
/// Synchronous, because a plugin is a loop on a pipe and the host's call
/// timeout covers the whole exchange — a plugin that answered its own requests
/// asynchronously would still have to be waiting by the deadline.
public struct HTTPClient: Sendable {
    /// How long one request may take. Deliberately shorter than the host's
    /// call timeout (10 s): a request that runs past that does not come back
    /// as a slow network — the host kills the plugin and the user is told the
    /// plugin broke when the truth is that the network never answered.
    private static let timeoutSeconds: TimeInterval = 8

    private let session: URLSession
    private let userAgent: String?

    /// - Parameter userAgent: sent on every request when present; a dashboard
    ///   usually has to look like a browser to be answered at all.
    public init(session: URLSession = .shared, userAgent: String? = nil) {
        self.session = session
        self.userAgent = userAgent
    }

    /// One GET, answered as a JSON object.
    public func getJSON(_ url: String, headers: [String: String] = [:]) throws -> [String: Any] {
        try perform(request(url: url, method: "GET", headers: headers))
    }

    /// One POST, answered as a JSON object. Sent as JSON unless the caller
    /// says otherwise: a body that does not declare itself is refused outright
    /// by some servers, and asking every provider to remember it is asking
    /// every provider to get it wrong.
    public func postJSON(
        _ url: String,
        headers: [String: String] = [:],
        body: Data = Data("{}".utf8)
    ) throws -> [String: Any] {
        var headers = headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        return try perform(request(url: url, method: "POST", headers: headers, body: body))
    }

    private func request(
        url: String,
        method: String,
        headers: [String: String],
        body: Data? = nil
    ) throws -> URLRequest {
        guard let endpoint = URL(string: url) else {
            throw ProviderHTTPError.invalidResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = Self.timeoutSeconds
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// The single place a status code becomes an opinion, so every provider
    /// reads every status code the same way.
    private func perform(_ request: URLRequest) throws -> [String: Any] {
        let answer = blockingAnswer(to: request)

        if answer.transportError != nil {
            throw ProviderHTTPError.networkUnavailable
        }
        guard let http = answer.response as? HTTPURLResponse else {
            throw ProviderHTTPError.networkUnavailable
        }

        switch http.statusCode {
        case 200 ..< 300:
            guard let data = answer.data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw ProviderHTTPError.invalidResponse
            }
            return object
        case 401, 403:
            throw ProviderHTTPError.authenticationFailed
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw ProviderHTTPError.rateLimited(retryAfterSeconds: retry)
        default:
            throw ProviderHTTPError.invalidResponse
        }
    }

    /// A semaphore rather than a continuation: the caller is a synchronous
    /// loop, and a plugin that suspends its own main loop has stopped
    /// answering.
    private func blockingAnswer(to request: URLRequest) -> Answer {
        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var transportError: Error?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)

        session.dataTask(with: request) { data, response, transportError in
            box.data = data
            box.response = response
            box.transportError = transportError
            semaphore.signal()
        }.resume()
        semaphore.wait()

        return Answer(
            data: box.data,
            response: box.response,
            transportError: box.transportError
        )
    }

    private struct Answer {
        let data: Data?
        let response: URLResponse?
        let transportError: Error?
    }
}

/// A canned provider response, read from the environment variable a test
/// points at a JSON file: a payload is exercised without the network and
/// without a real account, and the variable is read at the moment of the
/// request so a test can set it, call, and unset it. Nil when unset or not a
/// readable JSON object — a provider that cannot read a fixture should ask
/// the network rather than fail.
public enum HTTPFixture {
    public static func object(environmentVariable: String) -> [String: Any]? {
        guard let path = ProcessInfo.processInfo.environment[environmentVariable],
              !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}
