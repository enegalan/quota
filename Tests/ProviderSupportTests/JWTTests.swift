import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

@Suite("JWT reading")
struct JWTTests {
    private func base64URL(_ text: String) -> String {
        Data(text.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func token(claims: String) -> String {
        "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(claims)).signature"
    }

    @Test("The claims come out of the middle segment")
    func claims() throws {
        let claims = try JWT.claims(of: token(claims: #"{"sub":"user|42","type":"session"}"#))
        #expect(claims["sub"] as? String == "user|42")
        #expect(claims["type"] as? String == "session")
    }

    @Test("Padding is restored before decoding, whatever the segment's length was")
    func unpaddedPayload() throws {
        // "abc" is not a multiple of four, so the base64 URL form has no "=" at
        // all — and decoding it without putting them back fails.
        let claims = try JWT.claims(of: token(claims: #"{"a":"b"}"#))
        #expect(claims["a"] as? String == "b")
    }

    @Test("Anything that is not three segments, or does not open, is malformed")
    func malformed() {
        #expect(throws: JWTError.self) { try JWT.claims(of: "not-a-token") }
        #expect(throws: JWTError.self) { try JWT.claims(of: "a.b") }
        #expect(throws: JWTError.self) { try JWT.claims(of: "a.b.c.d") }
        #expect(throws: JWTError.self) { try JWT.claims(of: "a.@@@.c") }
        // Three segments, but the middle one is not claims.
        #expect(throws: JWTError.self) { try JWT.claims(of: "a.YWJj.c") }
    }

    @Test("A malformed token reads as a refusal to sign in, not as an unreadable response")
    func malformedIsAuthentication() {
        #expect(JWTError.malformed.providerError == ProviderError(code: .authenticationFailed))
    }

    @Test("An expiry is read from either number shape a serializer can write")
    func expiry() throws {
        let asDouble = try JWT.claims(of: token(claims: #"{"exp": 1760000000.5}"#))
        #expect(JWT.date(asDouble, key: "exp") == Date(timeIntervalSince1970: 1_760_000_000.5))

        let asInt = try JWT.claims(of: token(claims: #"{"exp": 1760000000}"#))
        #expect(JWT.date(asInt, key: "exp") == Date(timeIntervalSince1970: 1_760_000_000))
    }

    @Test("A claim that is not a date is absent, not malformed")
    func nonNumericExpiry() throws {
        let claims = try JWT.claims(of: token(claims: #"{"exp": "tomorrow"}"#))
        #expect(JWT.date(claims, key: "exp") == nil)
    }
}
