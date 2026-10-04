import Core
import Foundation

/// Typed access to what the app knows about installed providers.
public struct ProviderRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every provider record the app holds.
    ///
    /// Records about providers rather than the providers themselves: what is
    /// installed lives in `InstalledProviderRepository`, and what a provider
    /// reports lives behind the plugins. This is only what was true last time the
    /// app was running, which is exactly what has to be persisted.
    public func all() async throws -> [ProviderRecord] {
        try await store.loadProviders()
    }

    /// The record for one provider.
    ///
    /// - Returns: nil when this app has no record of the provider, which is not
    ///   the same as a record with no failures in it: absence means nothing is
    ///   known, and a caller that read it as "no failures" would treat an
    ///   unconnected provider as one that has been failing politely.
    public func provider(_ id: ProviderID) async throws -> ProviderRecord? {
        try await all().first { $0.providerID == id }
    }

    /// Stores a provider record, replacing the one held for that provider.
    ///
    /// Carries the failure count and the last failure with it, so replacing
    /// rather than merging is what makes a backoff survive: the count is the only
    /// memory of how many times in a row a provider has failed, and it is written
    /// back on every attempt precisely because a menu bar app is mostly not
    /// running.
    public func save(_ record: ProviderRecord) async throws {
        try await store.saveProviders(
            upserting(record, into: try all()) { $0.providerID == record.providerID }
        )
    }

    /// Removes one provider's record.
    ///
    /// The record only, not the provider's quotas: an uninstalled provider is a
    /// state the interface knows how to show, and deleting a user's quotas
    /// because they removed a plugin would be losing their data to tidy a list.
    public func delete(_ id: ProviderID) async throws {
        let records = try await all().filter { $0.providerID != id }
        try await store.saveProviders(records)
    }
}

/// Typed access to user-level settings.
public struct PreferencesRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// The stored preferences, or the defaults when nothing has been saved.
    ///
    /// A missing file yields defaults rather than nil, so every caller gets a
    /// usable value and no caller has to invent its own.
    public func load() async throws -> Preferences {
        try await store.loadPreferences() ?? .default
    }

    /// Writes the preferences.
    ///
    /// A whole value rather than a merge, because a caller that changed one
    /// setting and sent back only that setting would erase the rest; the settings
    /// are read-modify-written as one unit so no caller can lose a field by
    /// reporting a change to a different one.
    public func save(_ preferences: Preferences) async throws {
        try await store.savePreferences(preferences)
    }
}

/// Typed access to what the installer recorded about providers on this machine.
public struct InstalledProviderRepository: Sendable {
    private let store: any QuotaStore

    public init(store: any QuotaStore) {
        self.store = store
    }

    /// Every installed provider this machine has a record of.
    ///
    /// A fact about a directory rather than about a user: the record can be
    /// wrong in a way that costs nothing but an install, and the repository above
    /// for connections is where a wrong record would cost something.
    public func all() async throws -> [InstalledProvider] {
        try await store.loadInstalledProviders()
    }

    /// The record for one installed provider.
    ///
    /// - Returns: nil when there is no record, which is the ordinary state for a
    ///   provider the build packages and the user has not installed — the caller
    ///   is asking before it does anything, not reporting a fault.
    public func provider(_ id: String) async throws -> InstalledProvider? {
        try await all().first { $0.id == id }
    }

    /// Records an installation, replacing any record for that provider.
    ///
    /// Whole rather than merged, because the record carries the version and path
    /// that are currently true: a partially-updated record would name one version
    /// while pointing at another, and the manager would read that as a provider
    /// installed from a release that does not exist.
    public func save(_ record: InstalledProvider) async throws {
        try await store.saveInstalledProviders(
            upserting(record, into: try all()) { $0.id == record.id }
        )
    }

    /// Forgets one installed provider.
    ///
    /// The record only. The code on disk is the installer's to remove, which keeps
    /// one component responsible for the directory layout and this one responsible
    /// for what the app believes about it.
    public func delete(_ id: String) async throws {
        try await store.saveInstalledProviders(try all().filter { $0.id != id })
    }

    /// Replaces one provider's record, leaving the others alone.
    ///
    /// Exists so a caller marking a state change does not have to read the record
    /// to write it back, and the read-then-write race that invites is the whole
    /// hazard: two concurrent updates would each be applied to the value they read,
    /// and the second would quietly undo the first.
    ///
    /// A no-op for an identifier with no record, because the alternative is a
    /// throw from a path the installer reaches while reporting why an install
    /// failed.
    public func update(_ id: String, _ transform: (InstalledProvider) -> InstalledProvider) async throws {
        let records = try await all()
        guard let record = records.first(where: { $0.id == id }) else { return }
        try await save(transform(record))
    }
}
