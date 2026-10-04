import Core
import Foundation
import Platform
import PluginKit

extension AppModel {
    /// Installs a provider.
    ///
    /// The version, display name and other metadata shown to the user all come
    /// from the provider listing, so the interface cannot ask for something this
    /// build does not offer or pin a version of its own.
    func install(_ listing: ProviderListing) async {
        await performing(for: listing.id) {
            // The record is not read: the model reloads from the store rather
            // than keeping a second copy of what the installer already wrote.
            _ = try await self.environment.installer.install(listing.provider)
        }
    }

    /// Replaces an installed provider with this build's version.
    func update(_ listing: ProviderListing) async {
        await performing(for: listing.id) {
            guard let previous = try await self.environment.installed.provider(listing.id) else {
                throw ProviderError(code: .notInstalled)
            }
            // Ignored for the same reason the install's is: the reload that
            // follows reads the updated record back.
            _ = try await self.environment.installer.update(
                listing.provider,
                previous: previous,
                verify: { record in
                    try await ProviderConnector.verifyLaunch(
                        providerID: ProviderID(record.id),
                        environment: self.environment
                    )
                }
            )
        }
    }

    /// Removes a provider from this machine.
    ///
    /// The user is asked to confirm before this is called, and the impact is
    /// shown at the time of asking. Removing is not undoable, and leaving quotas
    /// that still name the provider is exactly what the installer does.
    func uninstall(_ listing: ProviderListing) async {
        await perform { try await self.environment.installer.uninstall(listing.provider.id) }
    }
}
