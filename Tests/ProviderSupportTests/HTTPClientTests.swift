import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

/// One canned answer, keyed by URL, for the stubbed session.
private struct StubbedAnswer {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?
    /// A transport failure rather than an answer.
    let transportError: Error?

    init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data? = nil,
        transportError: Error? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.transportError = transportError
    }
}

/// Answers requests from a table instead of the network.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [String: StubbedAnswer] = [:]

    /// The request as the session actually sent it, so a test can read the
    /// headers a client set rather than take the client's word for them.
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        Self.lastRequest = request
        guard let url = request.url else {
            client.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let answer = Self.answers[url.absoluteString] else {
            client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let transportError = answer.transportError {
            client.urlProtocol(self, didFailWithError: transportError)
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: answer.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: answer.headers
        ) else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = answer.body {
            client.urlProtocol(self, didLoad: body)
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct StubClient {
    let client: HTTPClient

    init(answers: [String: StubbedAnswer]) {
        StubURLProtocol.answers = answers
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = HTTPClient(
            session: URLSession(configuration: configuration),
            userAgent: "Quota-Test/1.0"
        )
    }
}

private let url = "https://provider.example/usage"

@Suite("HTTPClient", .serialized)
struct HTTPClientTests {
    private func expectFailure(_ answer: StubbedAnswer) -> ProviderHTTPError? {
        let stub = StubClient(answers: [url: answer])
        do {
            _ = try stub.client.getJSON(url)
            Issue.record("expected a failure")
            return nil
        } catch let error as ProviderHTTPError {
            return error
        } catch {
            Issue.record("expected ProviderHTTPError, got \(error)")
            return nil
        }
    }

    @Test("A 200 with an object is an object")
    func success() throws {
        let stub = StubClient(answers: [
            url: StubbedAnswer(statusCode: 200, body: Data(#"{"quota":42}"#.utf8)),
        ])
        let object = try stub.client.getJSON(url)
        #expect(object["quota"] as? Int == 42)
    }

    @Test("A 200 whose body is not an object is unreadable, not a reading of nothing")
    func successWithGarbage() {
        let failure = expectFailure(
            StubbedAnswer(statusCode: 200, body: Data("not json at all".utf8))
        )
        #expect(failure == .invalidResponse)
    }

    @Test("A 401 is an authentication failure, and its body is never read")
    func unauthorized() {
        let failure = expectFailure(StubbedAnswer(
            statusCode: 401,
            // Deliberately not JSON. A client that inspected this body would
            // report `invalidResponse` — so a `authenticationFailed` answer
            // shows the body was never opened.
            body: Data("and now the token you just sent me".utf8)
        ))
        #expect(failure == .authenticationFailed)
    }

    @Test("A 403 is refused on the same terms as a 401")
    func forbidden() {
        #expect(expectFailure(StubbedAnswer(statusCode: 403)) == .authenticationFailed)
    }

    @Test("A 429 carries the provider's own suggested wait")
    func rateLimited() {
        #expect(
            expectFailure(StubbedAnswer(
                statusCode: 429,
                headers: ["Retry-After": "60"],
                body: Data("{}".utf8)
            )) == .rateLimited(retryAfterSeconds: 60)
        )
        #expect(expectFailure(StubbedAnswer(statusCode: 429)) == .rateLimited(retryAfterSeconds: nil))
    }

    @Test("Any other status is a response this plugin cannot use")
    func otherStatuses() {
        #expect(expectFailure(StubbedAnswer(statusCode: 500)) == .invalidResponse)
        #expect(expectFailure(StubbedAnswer(statusCode: 404)) == .invalidResponse)
        #expect(expectFailure(StubbedAnswer(statusCode: 301)) == .invalidResponse)
    }

    @Test("A request that never got an answer is a network failure, not a plugin fault")
    func transportFailure() {
        let failure = expectFailure(StubbedAnswer(
            statusCode: 0,
            transportError: URLError(.notConnectedToInternet)
        ))
        #expect(failure == .networkUnavailable)
    }

    @Test("The user agent travels on every request")
    func userAgent() {
        StubURLProtocol.lastRequest = nil
        let stub = StubClient(answers: [
            url: StubbedAnswer(statusCode: 200, body: Data("{}".utf8)),
        ])
        _ = try? stub.client.getJSON(url, headers: ["Cookie": "session=abc"])

        let request = StubURLProtocol.lastRequest
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "Quota-Test/1.0")
        #expect(request?.value(forHTTPHeaderField: "Cookie") == "session=abc")
    }

    @Test("A failure reports the reason a user can act on")
    func failureMessages() {
        #expect(
            ProviderHTTPError.rateLimited(retryAfterSeconds: 90).providerError.message
                == "Rate limited; retry after 90 seconds."
        )
        #expect(
            ProviderHTTPError.rateLimited(retryAfterSeconds: nil).providerError.message
                == ProviderError.defaultMessage(for: .rateLimited)
        )
        #expect(
            ProviderHTTPError.authenticationFailed.providerError
                == ProviderError(code: .authenticationFailed)
        )
        #expect(ProviderHTTPError.networkUnavailable.providerError.code == .networkUnavailable)
        #expect(ProviderHTTPError.invalidResponse.providerError.code == .invalidResponse)
    }
}
