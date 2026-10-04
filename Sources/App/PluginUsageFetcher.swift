import Core
import Foundation
import Platform
import PluginKit

/// Reads usage from real plugins, for the running application.
///
/// The one place the app crosses from its own types to a provider's. Everything
/// specific to a provider is behind a plugin process, so what crosses the
/// boundary is a `UsageResult` on the way in and a `UsageSnapshot` on the way
/// out — no provider name, no field of anybody's API, and no knowledge of how
/// any particular service meters anything.
///
/// Failures come back as values rather than throws, because a provider being
/// unreachable is a state the interface shows, not an exceptional condition the
/// caller has to remember to catch: a refresher that forgot one `catch` would
/// leave a quota showing a stale reading with no explanation beside it.
struct PluginUsageFetcher: UsageFetching {
    private let manager: PluginManager
    private let installed: InstalledProviderRepository
    private let credentials: any KeychainStoring
    private let pluginsDirectory: URL
    private let launcher: any ProcessLaunching
    private let logDirectory: URL

    /// - Parameters:
    ///   - launcher: injectable so this type can be built in a test without
    ///     spawning anything; the live environment passes the real one.
    ///   - logDirectory: where a plugin's output is written when it misbehaves.
    ///   - pluginsDirectory: passed in rather than derived, because where
    ///     providers are installed is the composition root's decision and the
    ///     same one the installer was given.
    init(
        manager: PluginManager,
        installed: InstalledProviderRepository,
        credentials: any KeychainStoring,
        pluginsDirectory: URL,
        logDirectory: URL,
        launcher: (any ProcessLaunching)? = nil
    ) {
        self.manager = manager
        self.installed = installed
        self.credentials = credentials
        self.pluginsDirectory = pluginsDirectory
        // The launcher writes a plugin's stderr where it was told to, so the
        // same directory serves both: the host reports a failed launch into it
        // and the launcher keeps the output there to look at afterwards.
        self.launcher = launcher ?? SystemProcessLauncher(logDirectory: logDirectory)
        self.logDirectory = logDirectory
    }

    /// The error a result carries, built from one code and the moment it
    /// happened.
    ///
    /// A provider's own message is not kept: it can contain a path, a token, or
    /// whatever the service chose to say, and the interface has nine states to
    /// show regardless.
    static func failure(
        _ code: ProviderErrorCode,
        at date: Date
    ) -> SyncFailure {
        SyncFailure(code: code, message: code.rawValue.description, occurredAt: date)
    }

    /// Reads one day of usage from a provider.
    ///
    /// All three guards report `.notInstalled`, because they are three ways
    /// of saying the same thing to a user — there is nothing here to talk to
    /// — and a code per stage would be a support question the interface has
    /// no answer to. The plugin's suggested interval rides back with the
    /// reading instead of being remembered here, so it is never applied to a
    /// schedule for a provider whose data was not read this time.
    ///
    /// The instant is taken before the plugin is launched, so a slow provider
    /// backdates its reading rather than claiming the usage arrived later
    /// than it did: a timestamp that drifted by the plugin's latency would
    /// make every refresh look staler than it is.
    ///
    /// - Returns: an outcome rather than a throw. A provider being
    ///   unreachable is a state the interface shows beside the reading, not
    ///   an exceptional condition every caller has to remember to catch.
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        let now = Date()
        guard let provider = manager.provider(id: providerID.rawValue) else {
            return .failure(Self.failure(.notInstalled, at: now))
        }
        guard let record = try? await installed.provider(provider.id) else {
            return .failure(Self.failure(.notInstalled, at: now))
        }
        let launch = PluginLayout.installedLaunch(
            for: provider, version: record.version, in: pluginsDirectory
        )
        guard let launch else {
            return .failure(Self.failure(.notInstalled, at: now))
        }
        let host = PluginHost(launch: launch, launcher: launcher, logDirectory: logDirectory)

        do {
            let descriptor = try await host.launch()
            try await connect(host: host, provider: provider, providerID: providerID)
            let result = try await host.fetchUsage(localDate: localDate.description)
            return normalise(
                result,
                at: now,
                suggestion: descriptor.suggestedRefreshIntervalSeconds
            )
        } catch let error as ProviderError {
            return .failure(Self.failure(error.code, at: now))
        } catch {
            return .failure(Self.failure(.pluginError, at: now))
        }
    }

    /// Connects the plugin, if it is not already.
    ///
    /// Credentials are read from the Keychain rather than passed in, so a
    /// refresh never carries a secret through the model layer and a screenshot
    /// of a call stack cannot leak one.
    private func connect(
        host: PluginHost,
        provider: AvailableProvider,
        providerID: ProviderID
    ) async throws {
        let result = try await host.connect(
            credentials: try credentials.readCredential(for: providerID)
        )
        // The protocol reports a refused connection by answering with no account
        // rather than with a code, so an absent label is the refusal. Treating it
        // as success would let a refresh claim an account it does not have and
        // file a reading under the wrong key.
        guard result.accountLabel != nil else {
            throw ProviderError(code: .notAuthenticated)
        }
    }

    /// Turns a plugin's answer into a snapshot, or says why it cannot be one.
    private func normalise(
        _ result: UsageResult,
        at now: Date,
        suggestion: Double?
    ) -> UsageFetchOutcome {
        do {
            let snapshot = try SnapshotNormaliser.snapshot(from: result, recordedAt: now)
            return .success(snapshot, suggestedRefreshInterval: suggestion)
        } catch let error as NormalisationError {
            return .failure(Self.failure(error.code, at: now))
        } catch {
            return .failure(Self.failure(.invalidResponse, at: now))
        }
    }
}
