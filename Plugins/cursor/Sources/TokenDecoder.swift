import Foundation

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

enum TokenDecoder {
    static func decode(_ token: String, now: Date = Date()) throws -> DecodedAccessToken {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == CursorConstants.jwtSegmentCount else {
            throw TokenDecoderError.malformedJWT
        }

        guard let payloadData = base64URLDecode(String(segments[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw TokenDecoderError.malformedJWT
        }

        guard let subject = payload["sub"] as? String, !subject.isEmpty else {
            throw TokenDecoderError.missingSubject
        }

        let tokenType = (payload["type"] as? String) ?? ""
        guard tokenType == CursorConstants.sessionTokenType else {
            throw TokenDecoderError.apiKeyToken
        }

        let expiration: Date? = if let exp = payload["exp"] as? Double {
            Date(timeIntervalSince1970: exp)
        } else if let exp = payload["exp"] as? Int {
            Date(timeIntervalSince1970: TimeInterval(exp))
        } else {
            nil
        }

        if let expiration, expiration < now {
            throw TokenDecoderError.expiredToken
        }

        let userID = subject.split(separator: "|").last.map(String.init) ?? subject
        return DecodedAccessToken(
            subject: subject,
            userID: userID,
            tokenType: tokenType,
            expiration: expiration
        )
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var padded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % CursorConstants.base64PaddingModulus
        if remainder != 0 {
            padded.append(
                String(
                    repeating: "=",
                    count: CursorConstants.base64PaddingModulus - remainder
                )
            )
        }
        return Data(base64Encoded: padded)
    }
}
