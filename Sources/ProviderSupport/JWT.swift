import Foundation
import PluginKit

/// The ways a token can fail to be the thing this plugin needs to read.
/// Reportable as an authentication failure, not an unreadable response: the
/// plugin is the one holding a value that will not open, and the user's way
/// forward is to sign in again.
public enum JWTError: Error, Equatable, ProviderFailure {
    case malformed

    public var providerError: ProviderError {
        ProviderError(code: .authenticationFailed)
    }
}

/// Reading a JSON Web Token without taking one apart by hand.
///
/// Only what every provider needs: the claims, and a date among them. What a
/// provider requires *of* those claims stays in that provider.
public enum JWT {
    /// JWT wire shape: header.payload.signature.
    static let segmentCount = 3

    /// The claims of a token, or `malformed`.
    ///
    /// The signature is not verified, and cannot be: a plugin reading a token
    /// out of a local file has no key for it, and the only party that can tell
    /// whether it is genuine is the provider it will be presented to. Reading
    /// the claims decides *whether to try* — never whether to trust.
    public static func claims(of token: String) throws -> [String: Any] {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == segmentCount,
              let payloadData = base64URLDecode(String(segments[1])),
              let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw JWTError.malformed
        }
        return claims
    }

    /// A date-valued claim, or nil when absent or not a number — nil rather
    /// than malformed for a missing `exp`, since plenty of credentials never
    /// expire and a token without an expiry has not failed to be readable.
    public static func date(_ claims: [String: Any], key: String) -> Date? {
        if let seconds = claims[key] as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = claims[key] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var padded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // The URL alphabet omits padding; base64 decodes in groups of four.
        let remainder = padded.count % 4
        if remainder != 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: padded)
    }
}
