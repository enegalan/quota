import Core
import Foundation
import Platform
import PluginKit

/// Launches a provider plugin just long enough to connect or disconnect.
///
/// Kept out of `AppModel` so the model stays free of process-launch detail, and
/// so the Keychain is the only place credentials are written.
enum ProviderConnector {
    /// Signs in to a provider and reports the account it landed on.
    ///
    /// The plugin is launched, connected, and shut down around the one call,
    /// so no provider process outlives the operation. Credentials are read
    /// from the Keychain here rather than passed in, so a secret never
    /// travels through the model layer.
    ///
    /// - Returns: the provider's own account label, which is the key its
    ///   readings are filed under and so must be the provider's wording
    ///   rather than one this app composed.
    /// - Throws: `ProviderError.notAuthenticated` when the provider connects
    ///   but answers with no account, which is how a plugin reports a
    ///   refusal. Storing an empty label would file later readings under a
    ///   key no history can ever match.
    static func connect(
        providerID: ProviderID,
        environment: AppEnvironment
    ) async throws -> String {
        let (host, _) = try await host(for: providerID, environment: environment)
        _ = try await host.launch()
        let result = try await host.connect(
            credentials: try environment.credentials.readCredential(for: providerID)
        )
        await host.shutdown()
        guard let label = result.accountLabel, !label.isEmpty else {
            throw ProviderError(code: .notAuthenticated)
        }
        return label
    }

    /// Signs out, leaving the stored account label for the caller to clear.
    ///
    /// The credentials stay in the Keychain: a user signing out may be about
    /// to reinstall, and destroying the only copy would turn that into a
    /// re-authentication with no way to know it was wanted.
    ///
    /// - Throws: whatever the plugin raises, or `ProviderError.notInstalled`
    ///   when there is no longer anything to run — the code a fetch reports
    ///   for the same situation, so the interface needs one caption for both.
    static func disconnect(
        providerID: ProviderID,
        environment: AppEnvironment
    ) async throws {
        let (host, _) = try await host(for: providerID, environment: environment)
        _ = try await host.launch()
        _ = try await host.disconnect()
        await host.shutdown()
    }

    /// Confirms a freshly installed plugin can start, for the update path.
    static func verifyLaunch(
        providerID: ProviderID,
        environment: AppEnvironment
    ) async throws {
        let (host, _) = try await host(for: providerID, environment: environment)
        _ = try await host.launch()
        await host.shutdown()
    }

    /// Builds a runnable host for a provider, or says it cannot be run.
    ///
    /// The one place the installed version, what this build offers, and the
    /// on-disk layout become something launchable. Install and update both
    /// check the result, and a fetch builds one on every call, so the paths
    /// cannot disagree: a provider verified here and missing there would be a
    /// plugin that installs and then cannot report.
    ///
    /// - Returns: the host, and the provider whose identity and display name the
    ///   caller shows. The provider is returned rather than looked up again because
    ///   the provider and the install record that made this host launchable come
    ///   from two repositories that can change in between.
    /// - Throws: `ProviderError.notInstalled` for each of the three ways this
    ///   can fail — not in the catalog, no install record, no launchable
    ///   layout for the version on disk. They mean the same thing to a user,
    ///   and splitting them would leak a state they cannot act on.
    private static func host(
        for providerID: ProviderID,
        environment: AppEnvironment
    ) async throws -> (PluginHost, AvailableProvider) {
        guard let provider = environment.manager.provider(id: providerID.rawValue) else {
            throw ProviderError(code: .notInstalled)
        }
        guard let record = try await environment.installed.provider(provider.id) else {
            throw ProviderError(code: .notInstalled)
        }
        guard
            let launch = PluginLayout.installedLaunch(
                for: provider, version: record.version, in: environment.pluginsDirectory
            )
        else {
            throw ProviderError(code: .notInstalled)
        }
        let host = PluginHost(
            launch: launch,
            launcher: environment.launcher,
            logDirectory: environment.logDirectory
        )
        return (host, provider)
    }
}
