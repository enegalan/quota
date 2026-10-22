import Foundation
import ProviderSupport

struct DecodedAccessToken: Equatable {
    let subject: String
    let userID: String
    let tokenType: String
    let expiration: Date?
}

enum TokenDecoderError: Error, Equatable {
    case malformedJWT
    case missingSubject
    case apiKeyToken
    case expiredToken
}

/// What makes a token Cursor's — as opposed to merely readable as a JWT.
///
/// The splitting, the base64url decoding and the expiry are `JWT`'s, which is
/// the same work every provider does on a token; which subject shape and which
/// token type Cursor accepts is this plugin's alone.
enum TokenDecoder {
    static func decode(_ token: String, now: Date = Date()) throws -> DecodedAccessToken {
        let claims: [String: Any]
        do {
            claims = try JWT.claims(of: token)
        } catch {
            throw TokenDecoderError.malformedJWT
        }

        guard let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw TokenDecoderError.missingSubject
        }

        let tokenType = (claims["type"] as? String) ?? ""
        guard tokenType == CursorConstants.sessionTokenType else {
            throw TokenDecoderError.apiKeyToken
        }

        let expiration = JWT.date(claims, key: "exp")
        if let expiration, expiration < now {
            throw TokenDecoderError.expiredToken
        }

        // The subject is namespaced by the sign-in that produced it
        // (`provider|id`); the part after the namespace is the account itself.
        let userID = subject.split(separator: "|").last.map(String.init) ?? subject
        return DecodedAccessToken(
            subject: subject,
            userID: userID,
            tokenType: tokenType,
            expiration: expiration
        )
    }
}
