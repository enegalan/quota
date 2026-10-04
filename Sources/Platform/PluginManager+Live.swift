import Core
import Foundation
import PluginKit

public extension PluginManager {
    /// Builds a manager over the providers packaged in the bundle.
    static func live(
        store: any QuotaStore,
        bundle: Bundle = .main
    ) throws -> PluginManager {
        let bundled = DirectoryBundledArtifacts.live(in: bundle)
        let ids = try bundled.providers()
        let version = BundleConstants.applicationVersion
        let available = ids.map { AvailableProvider(id: $0, version: version) }
        return PluginManager(
            available: available,
            installed: installedProviderRepository(store),
            preferences: preferencesRepository(store),
            quotas: quotaRepository(store)
        )
    }
}
