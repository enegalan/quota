import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Shared fixtures for the plugin-management tests.
enum ManagerFixture {
    static func provider(
        id: String = "mock",
        version: Version = ProviderFixture.version
    ) -> AvailableProvider {
        AvailableProvider(id: id, version: version)
    }

    static func installed(
        id: String = "mock",
        version: Version = ProviderFixture.version,
        state: ProviderState = .installed
    ) -> InstalledProvider {
        InstalledProvider(
            id: id,
            version: version,
            relativePath: "\(id)/\(version.description)",
            state: state,
            installedAt: ProviderFixture.referenceInstant,
            contentHash: "hash"
        )
    }

    static func manager(
        available: [AvailableProvider],
        installed: [InstalledProvider] = [],
        quotas: [Quota] = [],
        preferences: Preferences = .default
    ) async throws -> (PluginManager, CodableStore) {
        let store = CodableStore.inMemory()
        try await store.saveInstalledProviders(installed)
        try await store.saveQuotas(quotas.map(QuotaRecord.init(quota:)))
        try await store.savePreferences(preferences)
        return (
            PluginManager(
                available: available,
                installed: installedProviderRepository(store),
                preferences: preferencesRepository(store),
                quotas: quotaRepository(store)
            ),
            store
        )
    }

    static func quota(
        id: UUID = UUID(), name: String, providerID: String = "mock"
    ) throws -> Quota {
        try QuotaFixture.quota(id: id, name: name, providerID: providerID)
    }
}
