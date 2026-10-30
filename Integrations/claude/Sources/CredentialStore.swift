import Foundation
import ProviderSupport

/// Where Claude Code keeps its sign-in.
///
/// Two places: the credentials file and the macOS keychain. The resolver
/// prefers the file so a machine that has both is never asked for keychain
/// consent on every refresh. Nothing here is written — the credential belongs
/// to Claude Code, and Claude Code refreshes it. This plugin reads it afresh
/// on every call so a token Claude Code has just rotated is picked up on the
/// next refresh rather than a session later.
enum CredentialStore {
    /// The credentials file's path.
    static var credentialsFileURL: URL {
        if let override = ProcessInfo.processInfo.environment[
            ClaudeConstants.credentialsFileEnvironment
        ], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ClaudeConstants.credentialsFileRelativePath)
    }

    /// Claude Code's configuration file, which names the signed-in account.
    static var configurationFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ClaudeConstants.configurationFileRelativePath)
    }

    /// The credential JSON from the keychain, or nil when there is none.
    ///
    /// The keychain item holds the same JSON the file holds, so the two are
    /// read through one reader and cannot drift apart.
    static func keychainCredentialJSON() -> String? {
        KeychainReader.password(service: ClaudeConstants.keychainServiceName)
    }

    /// The credential JSON from the file, or nil when there is none.
    static func fileCredentialJSON() -> String? {
        guard let data = try? Data(contentsOf: credentialsFileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The account's email, as Claude Code's configuration file names it.
    ///
    /// Read from the configuration rather than guessed from the credential: the
    /// email is the one thing a user recognises an account by, and the
    /// credential file does not always carry it.
    static func accountLabel() -> String? {
        guard let data = try? Data(contentsOf: configurationFileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object[ClaudeCredentialReader.oauthAccountKey] as? [String: Any],
              let email = account[ClaudeCredentialReader.accountEmailKey] as? String,
              !email.isEmpty
        else { return nil }
        return email
    }
}
