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

    /// Replaces every installed provider this build packages that has an update
    /// available, one at a time.
    ///
    /// The installer serialises them anyway, and a user watching the rows flip
    /// one at a time can tell which is which. A failure on one provider does not
    /// stop the rest — each is attempted, and the first failure is shown once
    /// everything has been re-read. Providers that are already current are
    /// skipped by `update`, so this only ever changes something that is behind.
    func updateAll() async {
        let updatable = sections.all.filter { $0.state == .updateAvailable }
        guard !updatable.isEmpty else { return }
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        var failures: [String] = []
        for listing in updatable {
            // `update` reports its own result in `lastError` (the reload it runs
            // clears it on success and records the failure otherwise), so a
            // failure here is visible right after the call without `update`
            // itself throwing.
            await update(listing)
            if let error = lastError {
                failures.append(error)
            }
        }
        lastError = failures.first
    }
}
