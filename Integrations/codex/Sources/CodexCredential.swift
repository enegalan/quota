import Foundation
import PluginKit
import ProviderSupport

/// Why a credential could not be used.
enum CodexCredentialError: Error, Equatable, ProviderFailure {
    /// The bytes were not the JSON Codex writes.
    case malformed

    /// The JSON held no ChatGPT access token (API-key-only sign-ins included).
    case missingAccessToken

    /// The token's own expiry has passed.
    case expired

    var providerError: ProviderError {
        ProviderError(code: .authenticationFailed)
    }
}

/// Codex's ChatGPT OAuth credential, as this plugin understands it.
///
/// Only the fields that decide whether the credential can be used and who it
/// belongs to. The refresh token is never read: Codex owns refresh, and a
/// second refresher would race it.
struct CodexCredential: Equatable {
    /// The bearer token the usage endpoint is asked with.
    let accessToken: String

    /// Selected ChatGPT account/workspace ID, when Codex recorded one.
    let accountID: String?

    /// When the access token stops working, if the JWT says.
    let expiresAt: Date?

    /// The account's email, when the ID token names one.
    let accountLabel: String?

    /// The ChatGPT plan, when the ID token names one.
    let planType: String?

    /// Whether the token's own expiry has passed.
    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

/// Reads Codex's ChatGPT OAuth credential out of the JSON it writes.
///
/// Accepts both the nested `tokens` block Codex ships today and a flatter
/// shape some tools leave behind with `access_token` at the root.
enum CodexCredentialReader {
    static let tokensKey = "tokens"
    static let accessTokenKey = "access_token"
    static let idTokenKey = "id_token"
    static let accountIDKey = "account_id"
    static let emailClaimKey = "email"
    static let openaiAuthClaimKey = "https://api.openai.com/auth"
    static let planTypeKey = "chatgpt_plan_type"

    /// The credential in a JSON string, or nil when it holds no ChatGPT token.
    ///
    /// Nil for an API-key-only `auth.json`: the ChatGPT usage endpoint refuses
    /// those, and inventing a meter from an API key would be a different
    /// product.
    static func credential(in json: String) -> CodexCredential? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return credential(in: object)
    }

    /// The credential in an already-parsed object.
    static func credential(in object: [String: Any]) -> CodexCredential? {
        let tokens = (object[tokensKey] as? [String: Any]) ?? object
        guard let accessToken = tokens[accessTokenKey] as? String, !accessToken.isEmpty else {
            return nil
        }

        let accountID = (tokens[accountIDKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let idToken = tokens[idTokenKey] as? String
        let claims = idToken.flatMap { try? JWT.claims(of: $0) }
        let auth = claims?[openaiAuthClaimKey] as? [String: Any]
        let email = (claims?[emailClaimKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let plan = (auth?[planTypeKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expiresAt = (try? JWT.claims(of: accessToken)).flatMap { JWT.date($0, key: "exp") }
            ?? idToken.flatMap { try? JWT.claims(of: $0) }.flatMap { JWT.date($0, key: "exp") }

        return CodexCredential(
            accessToken: accessToken,
            accountID: accountID ?? (auth?["chatgpt_account_id"] as? String),
            expiresAt: expiresAt,
            accountLabel: email,
            planType: plan
        )
    }
}
