import Foundation
import PluginKit
import ProviderSupport

/// Why a credential could not be used.
enum ClaudeCredentialError: Error, Equatable, ProviderFailure {
    /// The bytes were not the JSON Claude Code writes.
    case malformed

    /// The JSON was Claude Code's, but held no access token.
    case missingAccessToken

    /// The token's own expiry has passed.
    case expired

    var providerError: ProviderError {
        ProviderError(code: .authenticationFailed)
    }
}

/// Claude Code's OAuth credential, as this plugin understands it.
///
/// The fields are the ones that decide whether the credential can be used and
/// who it belongs to. Nothing else is read out of the file: a credential file
/// holds more than this, and the rest is Claude Code's to keep.
struct ClaudeCredential: Equatable {
    /// The bearer token the usage endpoint is asked with.
    let accessToken: String

    /// When the token stops working, if it says.
    let expiresAt: Date?

    /// The plan the account is on, when the credential says.
    let subscriptionType: String?

    /// The account's email, when it could be read.
    let accountLabel: String?

    /// Whether the token's own expiry has passed.
    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

/// Reads Claude Code's OAuth credential out of the JSON it writes.
///
/// The `claudeAiOauth` block is the one that matters. The block may sit at the
/// root of the file or under that key, because the two spellings have both
/// been shipped, and a reader that only accepts one of them refuses
/// credentials that are perfectly good.
enum ClaudeCredentialReader {
    /// The key the OAuth block is written under.
    static let oauthKey = "claudeAiOauth"

    /// The token key inside the block.
    static let accessTokenKey = "accessToken"

    /// The expiry key inside the block.
    static let expiresAtKey = "expiresAt"

    /// The plan key inside the block.
    static let subscriptionTypeKey = "subscriptionType"

    /// The email key inside the block, where it is written.
    static let emailKey = "email"

    /// The email key in Claude Code's configuration file.
    static let accountEmailKey = "emailAddress"

    /// The nested key Claude Code's configuration file puts the account under.
    static let oauthAccountKey = "oauthAccount"

    /// The threshold above which an expiry is read as milliseconds.
    ///
    /// Claude Code writes the expiry in milliseconds, and older builds wrote it
    /// in seconds. The two are told apart by their size rather than by a
    /// preference: a value that could be a date in 5138 is a date in 1970 read
    /// as milliseconds, and one that could not is already milliseconds.
    static let millisecondThreshold: Double = 100_000_000_000

    /// The credential in a JSON string, or nil when it holds none.
    ///
    /// - Returns: nil when there is no OAuth block or no access token in it.
    ///   A credential file without an OAuth block is an API-key sign-in, and
    ///   the OAuth endpoint refuses those.
    static func credential(in json: String, accountLabel: String? = nil) -> ClaudeCredential? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return credential(in: object, accountLabel: accountLabel)
    }

    /// The credential in an already-parsed object.
    static func credential(
        in object: [String: Any],
        accountLabel: String? = nil
    ) -> ClaudeCredential? {
        let block = (object[oauthKey] as? [String: Any]) ?? object
        guard let token = block[accessTokenKey] as? String, !token.isEmpty else { return nil }
        let email = (block[emailKey] as? String)
            ?? (block[oauthAccountKey] as? [String: Any])?[accountEmailKey] as? String
        return ClaudeCredential(
            accessToken: token,
            expiresAt: expiry(from: block[expiresAtKey]),
            subscriptionType: block[subscriptionTypeKey] as? String,
            accountLabel: accountLabel ?? email
        )
    }

    /// The expiry, read in whichever unit it was written in.
    ///
    /// The unit is decided by the value's size and not by a flag: the file
    /// carries no unit, and a token whose expiry is read in the wrong unit is
    /// either always expired or never expired.
    static func expiry(from value: Any?) -> Date? {
        let seconds: Double? = if let number = value as? NSNumber {
            number.doubleValue
        } else if let text = value as? String {
            Double(text)
        } else {
            nil
        }
        guard let seconds else { return nil }
        let interval = seconds >= millisecondThreshold ? seconds / 1000 : seconds
        return Date(timeIntervalSince1970: interval)
    }
}
