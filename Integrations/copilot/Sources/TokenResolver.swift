import Foundation
import ProviderSupport

/// Where a GitHub Copilot credential may be found, in the order tools leave it.
///
/// Environment variables and Copilot CLI's own store come first. GitHub CLI's
/// keychain item is not read directly: modern `gh` stores an opaque keyring
/// reference there, not the token. The last source asks `gh auth token`, which
/// is how editors and other quota tools resolve the same session.
enum TokenResolver {
    /// Source name for a token obtained from `gh auth token`.
    static let githubCLISource = CredentialSource(rawValue: "githubCLI")

    /// Resolved afresh on every call so a rotated token is picked up on the
    /// next refresh rather than held until a cache is told to forget it.
    static func resolve() throws -> ResolvedCredential<String> {
        try CredentialResolver.resolve(
            sources: credentialSources(),
            validate: validate
        )
    }

    /// A label the UI can show for the account, never the token.
    ///
    /// Prefers the active `gh` login from `hosts.yml`, then the login returned
    /// by GitHub's `/user` endpoint for the resolved token.
    static func accountLabel(for token: String) -> String? {
        if let login = activeGitHubLogin() {
            return login
        }
        return UsageClient.fetchLogin(token: token)
    }

    private static func credentialSources() -> [(CredentialSource, () throws -> String?)] {
        var sources: [(CredentialSource, () throws -> String?)] = []

        sources.append((.environment, {
            ProcessInfo.processInfo.environment[CopilotConstants.tokenEnvironmentOverride]
        }))

        for name in CopilotConstants.tokenEnvironmentNames {
            sources.append((.environment, {
                ProcessInfo.processInfo.environment[name]
            }))
        }

        sources.append((.keychain, {
            KeychainReader.password(service: CopilotConstants.copilotCLIKeychainService)
        }))

        sources.append((.credentialsFile, readCredentialsFile))
        sources.append((githubCLISource, readGitHubCLIToken))

        return sources
    }

    private static func validate(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CopilotCredentialError.empty
        }
        // Modern `gh` keychain values are opaque `go-keyring-…` references, not
        // bearer tokens. Refusing them here lets the walk continue to `gh auth
        // token`, which returns the real credential.
        if trimmed.hasPrefix("go-keyring-") {
            throw CopilotCredentialError.opaqueKeyringReference
        }
        return trimmed
    }

    private static func readCredentialsFile() throws -> String? {
        let url: URL = if let override = ProcessInfo.processInfo.environment[
            CopilotConstants.credentialsFileEnvironment
        ], !override.isEmpty {
            URL(fileURLWithPath: override)
        } else {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(CopilotConstants.credentialsFileRelativePath)
        }
        return CredentialsFileReader.token(
            at: url,
            keys: CopilotConstants.credentialsFileTokenKeys
        )
    }

    /// Asks GitHub CLI for the active account's token.
    ///
    /// Nil when `gh` is missing or not signed in: that is a source that is not
    /// there, and the walk reports authentication failure only after every
    /// source has been tried.
    private static func readGitHubCLIToken() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "token"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The active GitHub login as `gh` records it in `hosts.yml`.
    private static func activeGitHubLogin() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(CopilotConstants.ghHostsRelativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return YAMLLite.string(for: "user", underHost: CopilotConstants.ghHostName, in: text)
    }
}

enum CopilotCredentialError: Error {
    case empty
    case opaqueKeyringReference
}

extension CopilotCredentialError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "Token was empty"
        case .opaqueKeyringReference:
            "Keychain value is a keyring reference, not a token"
        }
    }
}

/// Minimal YAML reader for `gh`'s hosts file.
///
/// Only the `github.com` → `user:` mapping is needed. A full YAML parser would
/// be a dependency for one key.
enum YAMLLite {
    static func string(for key: String, underHost host: String, in text: String) -> String? {
        var inHost = false
        let hostLine = "\(host):"
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if indent == 0 {
                inHost = trimmed == hostLine || trimmed.hasPrefix("\(host):")
                continue
            }
            guard inHost else { continue }
            let prefix = "\(key):"
            guard trimmed.hasPrefix(prefix) else { continue }
            let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
