import Foundation
import ProviderSupport

struct ResolvedToken {
    let accessToken: String
    let accountLabel: String?
}

/// Resolving Antigravity credentials from known locations.
/// Credentials are read afresh on every call and never cached or logged.
enum TokenResolver {
    static func resolve() throws -> ResolvedToken {
        let resolved = try CredentialResolver.resolve(
            sources: [
                (.environment, { ProcessInfo.processInfo.environment["ANTIGRAVITY_TOKEN"] }),
                (.environment, { ProcessInfo.processInfo.environment["ANTIGRAVITY_ACCESS_TOKEN"] }),
                (.credentialsFile, readFromCredentialsFile),
            ],
            validate: { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw CredentialValidationError.empty
                }
                return trimmed
            }
        )
        return ResolvedToken(
            accessToken: resolved.rawToken,
            accountLabel: accountLabel(for: resolved.rawToken)
        )
    }

    static func accountLabel(for token: String) -> String? {
        // Try to extract account info if it's a JWT; otherwise leave as nil.
        if let payload = try? JWT.claims(of: token),
           let email = payload["email"] as? String
        {
            return email
        }
        if let payload = try? JWT.claims(of: token),
           let sub = payload["sub"] as? String
        {
            return sub
        }
        return nil
    }

    private static func readFromCredentialsFile() throws -> String? {
        if let path = ProcessInfo.processInfo.environment[AntigravityConstants.credentialsFileEnvironment],
           !path.isEmpty
        {
            return tokenFromFile(path)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        for relative in AntigravityConstants.credentialsFileRelativePaths {
            let url = home.appendingPathComponent(relative)
            if let token = tokenFromFile(url.path) {
                return token
            }
        }
        return nil
    }

    private static func tokenFromFile(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        for key in AntigravityConstants.credentialsFileTokenKeys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }

        // Some implementations nest credentials under a "credentials" key
        if let nested = json["credentials"] as? [String: Any] {
            for key in AntigravityConstants.credentialsFileTokenKeys {
                if let value = nested[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }
}

enum CredentialValidationError: Error {
    case empty
}

extension CredentialValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "Token was empty"
        }
    }
}
