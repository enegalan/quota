import Foundation
import ProviderSupport

/// Where Cursor keeps its sign-in, in the order its own installation writes it.
///
/// The sources are Cursor's — this database, these keychain services, these
/// files — and the walk over them, the non-interactive keychain read and the
/// refusal to cache any of it are `CredentialResolver`'s.
enum TokenResolver {
    /// Resolved afresh on every call: a token rotated by a new sign-in is
    /// picked up on the next reading rather than held until a cache is told
    /// to forget it. A rejection surfaces as `ResolutionError`, which already
    /// reports *no credential here* as a sign-in and *a credential that was
    /// refused* as a failed one.
    static func resolve(now: Date = Date()) throws -> ResolvedToken {
        let resolved = try CredentialResolver.resolve(
            sources: credentialSources(),
            validate: { try TokenDecoder.decode($0, now: now) }
        )
        // Only the state database knows whose the account is; every other
        // source falls back to the subject the token itself names.
        let cachedEmail = resolved.source == .stateDatabase ? StateDatabase.readCachedEmail() : nil
        return ResolvedToken(
            accessToken: resolved.rawToken,
            source: resolved.source,
            decoded: resolved.value,
            accountLabel: cachedEmail ?? resolved.value.userID
        )
    }

    private static func credentialSources() -> [(CredentialSource, () throws -> String?)] {
        var sources: [(CredentialSource, () throws -> String?)] = [
            (.stateDatabase, { try? StateDatabase.readAccessToken() }),
        ]

        for service in CursorConstants.keychainServiceNames {
            sources.append((.keychain, { KeychainReader.password(service: service) }))
        }

        for relative in CursorConstants.credentialsFileRelativePaths {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(relative)
            sources.append(
                (.credentialsFile, {
                    CredentialsFileReader.token(
                        at: url,
                        keys: CursorConstants.credentialsFileTokenKeys
                    )
                })
            )
        }

        return sources
    }
}

/// A credential resolved out of Cursor's own state: the token *and* the claims
/// read out of it, already agreed to be one thing.
struct ResolvedToken: Equatable {
    let accessToken: String
    let source: CredentialSource
    let decoded: DecodedAccessToken
    let accountLabel: String
}
