import Foundation
import Security

enum TokenSourceName: String, Equatable {
    case stateDatabase
    case keychain
    case credentialsFile
}

struct ResolvedToken: Equatable {
    let accessToken: String
    let source: TokenSourceName
    let decoded: DecodedAccessToken
    let accountLabel: String
}

enum TokenResolverError: Error, Equatable {
    case notFound
    case rejected(TokenDecoderError)
}

enum TokenResolver {
    /// Ordered strategy: state database, then keychain, then credentials file.
    /// Re-reads on every call; never caches.
    static func resolve(now: Date = Date()) throws -> ResolvedToken {
        var lastDecoderError: TokenDecoderError?

        if let resolved = tryResolve(
            token: try? StateDatabase.readAccessToken(),
            source: .stateDatabase,
            accountLabel: StateDatabase.readCachedEmail(),
            now: now,
            lastError: &lastDecoderError
        ) {
            return resolved
        }

        for service in CursorConstants.keychainServiceNames {
            if let resolved = tryResolve(
                token: readKeychainPassword(service: service),
                source: .keychain,
                accountLabel: nil,
                now: now,
                lastError: &lastDecoderError
            ) {
                return resolved
            }
        }

        for relative in CursorConstants.credentialsFileRelativePaths {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(relative)
            if let resolved = tryResolve(
                token: readCredentialsFile(at: url),
                source: .credentialsFile,
                accountLabel: nil,
                now: now,
                lastError: &lastDecoderError
            ) {
                return resolved
            }
        }

        if let lastDecoderError {
            throw TokenResolverError.rejected(lastDecoderError)
        }
        throw TokenResolverError.notFound
    }

    private static func tryResolve(
        token: String?,
        source: TokenSourceName,
        accountLabel: String?,
        now: Date,
        lastError: inout TokenDecoderError?
    ) -> ResolvedToken? {
        guard let token else { return nil }
        do {
            let decoded = try TokenDecoder.decode(token, now: now)
            return ResolvedToken(
                accessToken: token,
                source: source,
                decoded: decoded,
                accountLabel: accountLabel ?? decoded.userID
            )
        } catch let error as TokenDecoderError {
            lastError = error
            return nil
        } catch {
            return nil
        }
    }

    private static func readKeychainPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readCredentialsFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        for key in CursorConstants.credentialsFileTokenKeys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
