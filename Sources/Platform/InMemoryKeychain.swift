import Foundation

/// A keychain that keeps items in memory.
///
/// Lets the whole credential path — writing, reading, replacing, deleting — be
/// exercised without reading or writing the user's login keychain, which a test
/// has no business doing.
public actor InMemoryKeychain: KeychainStoring {
    private var items: [String: Data] = [:]
    private let service: String

    public init(service: String = PersistenceConstants.keychainService) {
        self.service = service
    }

    /// Returns one stored value, or nil when the account holds none.
    ///
    /// The value is copied out of the dictionary and nowhere else — never
    /// logged, never put in a fixture, never asserted on by value. Tests here
    /// assert that an account exists, not what it holds: a test that compared
    /// the secret would be a second copy of it on disk.
    public func read(_ account: String) async throws -> Data? {
        items[account]
    }

    /// Stores a value under an account, replacing any value already there.
    ///
    /// Replaces rather than duplicating so a test cannot build up a keychain
    /// with two live credentials for one provider and call that a passing
    /// state.
    public func write(_ data: Data, for account: String) async throws {
        items[account] = data
    }

    /// Removes a value, treating an absent one as already removed.
    ///
    /// Matches the real store so that code tested against this one is already
    /// written to handle a sign-out that had nothing to remove.
    public func delete(_ account: String) async throws {
        items[account] = nil
    }

    /// The account names currently held, for tests to assert on.
    public func accounts() -> [String] {
        Array(items.keys).sorted()
    }

    /// The service this keychain stands for, so a test can assert that a
    /// credential was filed under the app's own service.
    public var serviceName: String {
        service
    }
}
