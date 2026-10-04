import Core
import Foundation
import Platform
import PluginKit

extension AppModel {
    // MARK: - Connection

    /// Connects an installed provider, writing optional credentials only to the
    /// Keychain and recording the account label the plugin returned.
    ///
    /// The installed-provider record is moved to `.connected` on success: the
    /// catalog screen reads that state, and leaving it at `.installed` would make
    /// a successful Connect look like nothing happened.
    func connect(providerID: String, credentials: String? = nil) async {
        await performing(for: providerID) {
            let id = try ProviderID(providerID)
            if let credentials, !credentials.isEmpty {
                try await self.environment.credentials.writeCredential(
                    credentials, for: id
                )
            }
            do {
                let label = try await ProviderConnector.connect(
                    providerID: id,
                    environment: self.environment
                )
                try await self.saveAccountLabel(label, for: id)
                if let record = try await self.environment.installed.provider(id.rawValue) {
                    // Built fresh rather than `with(lastError: nil)`: that helper
                    // treats nil as "keep the previous error", so a successful
                    // reconnect would still show the last failure.
                    try await self.environment.installed.save(
                        InstalledProvider(
                            id: record.id,
                            version: record.version,
                            relativePath: record.relativePath,
                            state: .connected,
                            installedAt: record.installedAt,
                            contentHash: record.contentHash,
                            lastError: nil
                        )
                    )
                }
            } catch let error as ProviderError {
                try await self.markConnectionFailure(id: id, error: error)
                throw error
            }
        }
    }

    /// Drops credentials from the Keychain and clears the account label.
    func disconnect(providerID: String) async {
        await performing(for: providerID) {
            let id = try ProviderID(providerID)
            try await self.environment.credentials.deleteCredential(for: id)
            _ = try? await ProviderConnector.disconnect(
                providerID: id,
                environment: self.environment
            )
            if let record = try await self.environment.installed.provider(id.rawValue) {
                try await self.environment.installed.save(
                    record.with(state: .installed, lastError: nil)
                )
            }
            guard let existing = try await self.environment.providers.provider(id) else { return }
            try await self.environment.providers.save(
                existing.signedOut()
            )
        }
    }

    /// Sets the preferred poll interval, clamped to the platform bounds.
    func setRefreshInterval(_ seconds: TimeInterval) async {
        await perform {
            let clamped = RefreshConstants.clamped(seconds)
            let current = try await self.environment.preferences.load()
            try await self.environment.preferences.save(
                Preferences(
                    defaultPolicyKind: current.defaultPolicyKind,
                    hasCompletedOnboarding: current.hasCompletedOnboarding,
                    refreshIntervalSeconds: clamped,
                    disabledProviders: current.disabledProviders
                )
            )
        }
    }

    /// Effective poll interval shown in settings.
    func effectiveRefreshIntervalSeconds() async -> TimeInterval {
        let preferences = await (try? environment.preferences.load()) ?? .default
        return RefreshConstants.clamped(preferences.refreshIntervalSeconds)
    }

    /// A diagnostic dump of local state with no credentials.
    func diagnosticDump() async -> String {
        await DiagnosticDump.render(environment: environment)
    }

    /// Records why a connect attempt failed, on the installed-provider
    /// record.
    ///
    /// The two states it can leave behind are the decision. An authentication
    /// failure leaves the provider needing attention; anything else leaves it
    /// merely installed, because the credentials were never what was wrong
    /// and sending the user to reconnect would be advice the failure does not
    /// support.
    ///
    /// The code is stored beside the state so the Providers pane can say
    /// which of the two happened from what was already written, rather than
    /// re-running a connect to find out. A provider with no installed record
    /// is left alone: there is nothing to attach the failure to, and a record
    /// invented here would assert a location for a plugin nobody has on disk.
    private func markConnectionFailure(id: ProviderID, error: ProviderError) async throws {
        let state: ProviderState = switch error.code {
        case .notAuthenticated, .authenticationFailed: .authRequired
        default: .installed
        }
        guard let record = try await environment.installed.provider(id.rawValue) else { return }
        try await environment.installed.save(record.with(state: state, lastError: error.code))
    }

    /// Records the account label a plugin reported when it connected.
    ///
    /// Written field by field from the record already stored, so the fields
    /// this function knows nothing about survive. Last sync, the failure
    /// count and the refresh interval belong to other features, and
    /// rebuilding the record from only what was passed here would quietly
    /// reset all three on every connect.
    ///
    /// A success clears the failure record for the same reason — the
    /// credentials it was complaining about now work, and leaving
    /// "authentication failed" on a connected provider would have the app
    /// contradict itself on the next read.
    ///
    /// Saves a fresh record when there is none yet, since a plugin may be
    /// connected before anything has recorded it.
    ///
    /// - Throws: whatever the store throws. The label is not written when the
    ///   write fails, so a failure here leaves the previous state rather than
    ///   a half-applied one.
    private func saveAccountLabel(_ label: String, for id: ProviderID) async throws {
        if let existing = try await environment.providers.provider(id) {
            try await environment.providers.save(
                existing.authenticated(against: label)
            )
            return
        }
        try await environment.providers.save(
            ProviderRecord(
                providerID: id,
                displayName: id.rawValue,
                installedVersion: "1.0.0",
                authenticatedAccountLabel: label
            )
        )
    }
}
