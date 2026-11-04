import Foundation
import ProviderSupport

/// Where Claude Code's sign-in is, in the order its own installation writes it.
///
/// The walk over the sources and the refusal to cache any of it are
/// `CredentialResolver`'s; which files and which keychain service Claude Code
/// uses are this plugin's alone.
enum TokenResolver {
    /// The credential, resolved afresh on every call.
    ///
    /// Read again on every refresh rather than remembered, so a token Claude
    /// Code has rotated is picked up on the next reading rather than a session
    /// later. A rejection surfaces as `ResolutionError`, which already reports
    /// *no credential here* as a sign-in and *a credential that was refused* as
    /// a failed one.
    static func resolve(now: Date = Date()) throws -> ResolvedCredential<ClaudeCredential> {
        try CredentialResolver.resolve(
            sources: credentialSources(),
            validate: { try validate($0, now: now) }
        )
    }

    /// The credential as a labelled value, for the interface to show.
    ///
    /// The label is the account's email where Claude Code names one, and the
    /// plan where it does not: both are things a user recognises their
    /// subscription by, and the token is neither.
    static func accountLabel(for credential: ClaudeCredential) -> String? {
        credential.accountLabel ?? credential.subscriptionType
    }

    /// The sources Claude Code leaves on disk or in the keychain.
    ///
    /// The credentials file is tried first: it holds the same JSON the keychain
    /// does, and reading it never asks the OS for consent. The keychain is the
    /// fallback for installations that only wrote there.
    private static func credentialSources() -> [(CredentialSource, () throws -> String?)] {
        [
            (.credentialsFile, { CredentialStore.fileCredentialJSON() }),
            (.keychain, { CredentialStore.keychainCredentialJSON() }),
        ]
    }

    /// Reads one source's JSON into a credential, or refuses it.
    ///
    /// The expiry is checked here rather than at the call site because a token
    /// that has expired is not a credential: presenting it would be answered
    /// with a rejection that says nothing about which of the two problems it
    /// was.
    private static func validate(_ json: String, now: Date) throws -> ClaudeCredential {
        guard let credential = ClaudeCredentialReader.credential(
            in: json,
            accountLabel: CredentialStore.accountLabel()
        ) else {
            throw ClaudeCredentialError.missingAccessToken
        }
        if credential.isExpired(now: now) {
            throw ClaudeCredentialError.expired
        }
        return credential
    }
}
