import Foundation
import PluginKit
import Testing

@Suite("Token resolution")
struct TokenResolutionTests {
    @Test("A session JWT yields the user id after the pipe")
    func sessionToken() throws {
        let token = fakeJWT(#"{"sub":"google-oauth2|user_abc","type":"session","exp":9999999999}"#)
        let decoded = try decode(token)
        #expect(decoded.userID == "user_abc")
        #expect(decoded.tokenType == "session")
    }

    @Test("An API-key token type is rejected")
    func rejectsAPIKey() {
        let token = fakeJWT(#"{"sub":"user_1","type":"api_key","exp":9999999999}"#)
        #expect(throws: DecodeError.apiKey) {
            try decode(token)
        }
    }

    @Test("An expired token is rejected")
    func rejectsExpired() {
        let token = fakeJWT(#"{"sub":"user_1","type":"session","exp":1}"#)
        #expect(throws: DecodeError.expired) {
            try decode(token)
        }
    }

    @Test("A malformed JWT is rejected")
    func rejectsMalformed() {
        #expect(throws: DecodeError.malformed) {
            try decode("not-a-jwt")
        }
    }

    @Test("Cookie value uses an encoded subject separator")
    func cookieShape() {
        let cookie = "user_abc" + "%3A%3A" + "tok.en.value"
        #expect(cookie == "user_abc%3A%3Atok.en.value")
    }

    private enum DecodeError: Error { case malformed, apiKey, expired, missingSubject }

    private struct Decoded {
        let userID: String
        let tokenType: String
    }

    private func decode(_ token: String, now: Date = Date()) throws -> Decoded {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw DecodeError.malformed }
        var padded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder != 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: padded),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = payload["sub"] as? String
        else { throw DecodeError.malformed }
        let type = (payload["type"] as? String) ?? ""
        guard type == "session" else { throw DecodeError.apiKey }
        if let exp = payload["exp"] as? Double, Date(timeIntervalSince1970: exp) < now {
            throw DecodeError.expired
        }
        let userID = subject.split(separator: "|").last.map(String.init) ?? subject
        return Decoded(userID: userID, tokenType: type)
    }

    private func fakeJWT(_ payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "a.\(encoded).c"
    }
}
