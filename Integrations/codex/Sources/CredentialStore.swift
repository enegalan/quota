import CryptoKit
import Foundation
import ProviderSupport

/// Where Codex keeps its ChatGPT sign-in.
///
/// Two places, in the order Codex itself prefers them when `auto` storage is
/// configured: the macOS keychain, then `auth.json` under `CODEX_HOME`. Nothing
/// here is written — the credential belongs to Codex.
enum CredentialStore {
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
