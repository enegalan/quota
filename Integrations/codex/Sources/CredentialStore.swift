import CryptoKit
import Foundation
import ProviderSupport

/// Where Codex keeps its ChatGPT sign-in.
///
/// Codex's `cli_auth_credentials_store` chooses the place: the keychain, the
/// file, both under `auto`, or neither under `ephemeral`. Nothing here is
/// written — the credential belongs to Codex.
enum CredentialStore {
    /// Where Codex itself will look for the active sign-in.
    ///
    /// Mirrored from Codex so this plugin does not prefer a stale `auth.json`
    /// after Codex has moved the session into the keychain.
    enum CredentialsStoreMode: String {
        case file
        case keyring
        case auto
        case ephemeral
    }

    /// Codex's home directory (`CODEX_HOME`, or `~/.codex`).
    static var homeDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment[CodexConstants.homeEnvironment],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(CodexConstants.defaultHomeRelativePath, isDirectory: true)
    }

    /// The credentials file's path.
    static var credentialsFileURL: URL {
        if let override = ProcessInfo.processInfo.environment[
            CodexConstants.credentialsFileEnvironment
        ], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return homeDirectoryURL.appendingPathComponent(CodexConstants.credentialsFileName)
    }

    /// Codex's configuration file (`config.toml` under the home directory).
    static var configurationFileURL: URL {
        homeDirectoryURL.appendingPathComponent(CodexConstants.configurationFileName)
    }

    /// The storage mode Codex is configured to use.
    ///
    /// Defaults to `auto` when the key is absent or unreadable, matching Codex.
    static func credentialsStoreMode(
        configuration: String? = nil
    ) -> CredentialsStoreMode {
        let text = configuration ?? (try? String(contentsOf: configurationFileURL, encoding: .utf8))
        guard let text else { return .auto }
        return parseCredentialsStoreMode(from: text) ?? .auto
    }

    /// Reads `cli_auth_credentials_store` from a Codex `config.toml` body.
    ///
    /// Only the top-level key is accepted: the same name nested under a table
    /// is not Codex's setting. Unknown values are ignored so a typo falls back
    /// to `auto` at the call site rather than inventing a mode.
    static func parseCredentialsStoreMode(from configuration: String) -> CredentialsStoreMode? {
        for line in configuration.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            // A table header ends the top-level keys; later assignments belong
            // to that table, not to Codex's storage setting.
            if trimmed.hasPrefix("[") {
                return nil
            }
            guard trimmed.hasPrefix(CodexConstants.credentialsStoreConfigKey) else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == CodexConstants.credentialsStoreConfigKey else {
                continue
            }
            let raw = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return CredentialsStoreMode(rawValue: raw)
        }
        return nil
    }

    /// The credential JSON from the keychain, or nil when there is none.
    ///
    /// Codex stores the whole `auth.json` payload under service `Codex Auth`
    /// and an account derived from the home path. The bare service is tried
    /// too, so a single-item keychain still answers.
    static func keychainCredentialJSON() -> String? {
        let account = keychainAccount(for: homeDirectoryURL)
        if let json = KeychainReader.password(
            service: CodexConstants.keychainServiceName,
            account: account
        ) {
            return json
        }
        return KeychainReader.password(service: CodexConstants.keychainServiceName)
    }

    /// The credential JSON from the file, or nil when there is none.
    static func fileCredentialJSON() -> String? {
        guard let data = try? Data(contentsOf: credentialsFileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Codex's keychain account name for a given home directory.
    ///
    /// Mirrors `compute_store_key` in Codex: `cli|` plus the first sixteen
    /// hex characters of the SHA-256 of the canonical path.
    static func keychainAccount(for home: URL) -> String {
        let path = home.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let truncated = String(hex.prefix(16))
        return "cli|\(truncated)"
    }
}
