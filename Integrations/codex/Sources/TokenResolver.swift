import Foundation
import ProviderSupport

/// Where Codex's ChatGPT sign-in is, in the order its own installation writes it.
///
/// The walk over the sources and the refusal to cache any of it are
/// `CredentialResolver`'s; which files and which keychain service Codex uses
/// are this plugin's alone.
enum TokenResolver {
    /// The credential, resolved afresh on every call.
    ///
    /// Read again on every refresh rather than remembered, so a token Codex
    /// has rotated is picked up on the next reading rather than a session
    /// later.
    static func resolve(now: Date = Date()) throws -> ResolvedCredential<CodexCredential> {
        try CredentialResolver.resolve(
            sources: credentialSources(),
            validate: { try validate($0, now: now) }
        )
    }

    /// The credential as a labelled value, for the interface to show.
    ///
    /// The label is the account's email where the ID token names one, and the
    /// plan where it does not: both are things a user recognises their
    /// subscription by, and the token is neither.
    static func accountLabel(for credential: CodexCredential) -> String? {
        credential.accountLabel ?? credential.planType
    }

    /// The sources, in the order Codex writes them under `auto` storage.
    private static func credentialSources() -> [(CredentialSource, () throws -> String?)] {
        [
            (.keychain, { CredentialStore.keychainCredentialJSON() }),
            (.credentialsFile, { CredentialStore.fileCredentialJSON() }),
        ]
    }

    /// Reads one source's JSON into a credential, or refuses it.
    private static func validate(_ json: String, now: Date) throws -> CodexCredential {
        guard let credential = CodexCredentialReader.credential(in: json) else {
            throw CodexCredentialError.missingAccessToken
        }
        if credential.isExpired(now: now) {
            throw CodexCredentialError.expired
        }
        return credential
    }
}
