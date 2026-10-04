import Core
import Foundation
import Security

/// Where provider credentials live.
///
/// A protocol rather than a direct call to `Security` so the credential path can
/// be exercised in tests without touching the user's login keychain, and so a
/// reviewer can see every credential operation in the codebase by looking at the
/// conforming types rather than by grepping for `SecItem`.
public protocol KeychainStoring: Sendable {
    /// - Returns: nil when no item exists. A missing credential is an ordinary
    ///   state — the user has not authenticated yet — so it is reported as an
    ///   absent value rather than as an error the caller has to catch.
    func read(_ account: String) async throws -> Data?

    /// Stores a value, creating the item if it is absent and replacing it if it
    /// is already there. One operation for both cases so no caller can implement
    /// "add" and forget "update", which is the usual way credentials end up
    /// duplicated or stale.
    func write(_ data: Data, for account: String) async throws

    /// Removes a value, treating an absent one as already removed.
    ///
    /// Idempotent so that signing a provider out can call it unconditionally.
    /// The alternative — a throw for a credential that was never written —
    /// makes every caller decide whether "already gone" is a problem, and it
    /// is not: the state the user asked for is the state the machine is
    /// already in.
    func delete(_ account: String) async throws
}

public extension KeychainStoring {
    /// Reads a provider's credential, addressed by provider rather than by
    /// account name.
    ///
    /// On the protocol rather than on the concrete store so a caller holding
    /// `any KeychainStoring` can ask for a credential without knowing which
    /// store it has, and so the account name is assembled in exactly one place:
    /// two callers each building `<providerID>.<keyName>` is how a credential
    /// ends up written under one name and read under another.
    ///
    /// The result is a string because that is what every provider's credential
    /// is: a token, a key, or a path to one, all of which a plugin reads as
    /// text.
    func readCredential(for providerID: ProviderID) async throws -> String? {
        let account = try KeychainCredentialStore.account(
            providerID: providerID,
            keyName: PersistenceConstants.credentialKeyName
        )
        guard let data = try await read(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes a provider's credential under the same account name `readCredential`
    /// uses. Secrets stay in the Keychain and never on disk.
    func writeCredential(_ value: String, for providerID: ProviderID) async throws {
        let account = try KeychainCredentialStore.account(
            providerID: providerID,
            keyName: PersistenceConstants.credentialKeyName
        )
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.malformedData(account: account)
        }
        try await write(data, for: account)
    }

    /// Removes a provider's credential from the Keychain.
    func deleteCredential(for providerID: ProviderID) async throws {
        let account = try KeychainCredentialStore.account(
            providerID: providerID,
            keyName: PersistenceConstants.credentialKeyName
        )
        try await delete(account)
    }
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case malformedData(account: String)
}

/// The login keychain, under this app's own service name.
///
/// Every credential uses an account of `<providerID>.<keyName>`, so one provider
/// can hold several values without colliding with another, and so a credential
/// can be found without reading the others.
/// The login keychain. A `struct` rather than an actor because the underlying
/// calls are synchronous and safe to make from any context; the protocol is
/// async because a keychain read can block waiting on the user.
public struct KeychainCredentialStore: KeychainStoring, Sendable {
    private let service: String
    private let accessGroup: String?

    public init(
        service: String = PersistenceConstants.keychainService,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Builds the account name a provider's credential is stored under.
    ///
    /// - Throws: `QuotaDomainError.invalidIdentifier` when either part is empty
    ///   or contains whitespace, which would make the account name ambiguous.
    public static func account(providerID: ProviderID, keyName: String) throws -> String {
        guard (try? ProviderID(keyName)) != nil else {
            throw QuotaDomainError.invalidIdentifier(keyName)
        }
        return "\(providerID.rawValue).\(keyName)"
    }

    /// Returns one credential's bytes, without copying them anywhere else.
    ///
    /// The data is handed straight to the caller and never written down,
    /// described in a log, or folded into a diagnostic dump: a secret that
    /// gets copied is a secret that has to be revoked somewhere else, and the
    /// app has no way to know where that copy ended up. Callers get it to
    /// hand to the provider and let go.
    ///
    /// - Returns: nil when no item exists, which is the ordinary state before
    ///   the user has authenticated — not a failure to report as an error.
    /// - Throws: `KeychainError.malformedData` when the keychain returns
    ///   something that is not data, and `KeychainError.unexpectedStatus` for
    ///   any other status. Both mean the secret's integrity is in question,
    ///   which is not something to paper over with an empty value.
    public func read(_ account: String) async throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.malformedData(account: account)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Stores a credential, replacing any value already under that account.
    ///
    /// Update-then-add rather than delete-then-add. Deleting first would
    /// leave a window with no credential in it at all, so a read during a
    /// sign-in could see a provider as unauthenticated and send the user
    /// through authentication a second time; here the old value stays
    /// readable right up to the swap.
    ///
    /// Never logged, and never written to the store's own files on the way
    /// here. The only copy that leaves this call is the keychain's.
    public func write(_ data: Data, for account: String) async throws {
        let query = baseQuery(account: account)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Readable by this app only. A credential that another app on the
            // machine could read would not be protected by being in the keychain.
            kSecAttrAccessible as String: PersistenceConstants.keychainAccessibility,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Removes a credential, treating an absent one as already removed.
    ///
    /// Used when a provider is signed out or uninstalled, so the window in
    /// which a revoked token is still readable is as short as the user asked
    /// for. Leaving the item behind "just in case" would mean a secret
    /// outliving the reason it existed.
    public func delete(_ account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The lookup shared by read, write, and delete.
    ///
    /// Built from the service, the account, and the access group, and nothing
    /// else — no secret is ever part of a query, because a query that carries
    /// the value it is searching for is a value that gets logged by whatever
    /// is asked to describe the failing call.
    ///
    /// One definition so the three operations cannot drift: a write that
    /// filed a credential under a slightly different query than the read that
    /// looks for it produces a credential the app can neither find nor
    /// explain.
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
