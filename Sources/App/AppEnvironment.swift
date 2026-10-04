import Core
import Foundation
import Platform

/// The composition root.
///
/// Every dependency in the application is constructed here, explicitly, in one
/// place. There is no container and no service locator: a reader can answer
/// "where does this come from" by reading this file, and the answer cannot drift
/// at runtime.
///
/// One private initialiser builds the whole graph, so `live` and `preview` can
/// only differ in the values they pass and never in the shape of what they
/// build. That is what makes a preview worth having: it exercises the same
/// composition the application runs, with only the store, the clock, and the
/// fetcher replaced.
struct AppEnvironment {
    let store: any QuotaStore
    let credentials: any KeychainStoring
    let quotas: QuotaRepository
    let snapshots: SnapshotRepository
    let timelines: TimelineRepository
    let providers: ProviderRepository
    let plans: AllocationPlanRepository
    let preferences: PreferencesRepository
    let installed: InstalledProviderRepository
    let manager: PluginManager
    let installer: PluginInstaller
    let coordinator: SyncCoordinator
    let planner: RefreshPlanner

    /// How the app reads a provider, exposed so the creation flow can ask a
    /// provider what it meters before a quota exists to hold the answer.
    ///
    /// The same reader the coordinator refreshes through, deliberately: a bucket
    /// list from a second code path could describe a different provider's
    /// vocabulary, and a picker built from one of those would offer limits the
    /// sync cannot then find.
    let fetcher: any UsageFetching
    let calendar: Calendar
    let now: @Sendable () -> Date

    // Filesystem paths
    let pluginsDirectory: URL
    let logDirectory: URL

    /// Process launching
    let launcher: any ProcessLaunching

    private init(
        store: any QuotaStore,
        credentials: any KeychainStoring,
        manager: PluginManager,
        installer: PluginInstaller,
        fetcher: any UsageFetching,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        pluginsDirectory: URL,
        logDirectory: URL,
        launcher: any ProcessLaunching
    ) {
        self.store = store
        self.credentials = credentials
        self.manager = manager
        self.installer = installer
        self.fetcher = fetcher
        self.calendar = calendar
        self.now = now
        self.pluginsDirectory = pluginsDirectory
        self.logDirectory = logDirectory
        self.launcher = launcher
        quotas = quotaRepository(store)
        snapshots = snapshotRepository(store)
        timelines = timelineRepository(store)
        providers = providerRepository(store)
        plans = allocationPlanRepository(store)
        preferences = preferencesRepository(store)
        installed = installedProviderRepository(store)
        coordinator = SyncCoordinator(
            quotas: quotas,
            snapshots: snapshots,
            timelines: timelines,
            providers: providers,
            plans: plans,
            engine: AllocationEngine(calendar: calendar),
            fetcher: fetcher,
            calendar: calendar,
            now: now,
            preferences: preferences
        )
        planner = RefreshPlanner(coordinator: coordinator, now: now)
    }

    /// The environment the running application uses.
    static func live(bundle: Bundle = .main) throws -> AppEnvironment {
        // One store, built once. Two stores over the same directory would be two
        // backends, and the installed-provider records one wrote would not be the
        // ones the other read.
        let store = CodableStore.onDisk()
        let manager = try PluginManager.live(store: store, bundle: bundle)
        let installed = installedProviderRepository(store)
        let credentials = KeychainCredentialStore()
        let paths = PluginPaths()
        // One launcher, because it is where a plugin's output is recorded: two
        // values would write two log files for the same run.
        let launcher = SystemProcessLauncher(logDirectory: paths.logs)
        return AppEnvironment(
            store: store,
            credentials: credentials,
            manager: manager,
            installer: PluginInstaller(
                pluginsDirectory: paths.plugins,
                repository: installed,
                quotas: quotaRepository(store),
                bundled: DirectoryBundledArtifacts.live(in: bundle),
                launcher: launcher,
                logDirectory: paths.logs,
                now: { Date() }
            ),
            fetcher: PluginUsageFetcher(
                manager: manager,
                installed: installed,
                credentials: credentials,
                pluginsDirectory: paths.plugins,
                logDirectory: paths.logs
            ),
            calendar: .current,
            now: { Date() },
            pluginsDirectory: paths.plugins,
            logDirectory: paths.logs,
            launcher: launcher
        )
    }

    /// The environment previews and interface tests use.
    ///
    /// In-memory throughout and on a fixed clock, so a rendering can be asserted
    /// and the same assertion holds tomorrow.
    static func preview(
        store: any QuotaStore = CodableStore.inMemory(),
        available: [AvailableProvider] = [],
        fetcher: any UsageFetching,
        now: Date,
        calendar: Calendar = .current,
        bundleDirectory: URL? = nil
    ) -> AppEnvironment {
        // The fetcher is supplied whole rather than assembled, because a preview
        // has no installed providers to read and a test's scripted provider is
        // the point.
        AppEnvironment(
            store: store,
            credentials: InMemoryKeychain(),
            manager: PluginManager(
                available: available,
                installed: installedProviderRepository(store),
                preferences: preferencesRepository(store),
                quotas: quotaRepository(store)
            ),
            // Installing into a preview's temporary directory rather than the
            // user's: a preview that wrote a provider into Application Support
            // would change the state the next launch reads.
            installer: PluginInstaller(
                pluginsDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quota-preview-plugins", isDirectory: true),
                repository: installedProviderRepository(store),
                quotas: quotaRepository(store),
                bundled: DirectoryBundledArtifacts(directory: bundleDirectory),
                launcher: SystemProcessLauncher(
                    logDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("quota-preview-logs", isDirectory: true)
                ),
                logDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quota-preview-logs", isDirectory: true)
            ),
            fetcher: fetcher,
            calendar: calendar,
            now: { now },
            pluginsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("quota-preview-plugins", isDirectory: true),
            logDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("quota-preview-logs", isDirectory: true),
            launcher: SystemProcessLauncher(
                logDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quota-preview-logs", isDirectory: true)
            )
        )
    }

    /// A presenter over this environment at a chosen instant.
    func presenter(at reference: Date? = nil) -> SummaryPresenter {
        SummaryPresenter(
            quotas: quotas,
            snapshots: snapshots,
            timelines: timelines,
            providers: providers,
            plans: plans,
            calendar: calendar,
            reference: reference ?? now()
        )
    }
}

/// Where the application's own plugin state lives on disk.
///
/// One description of the two directories because three things have to name the
/// same ones: a plugins directory that disagreed between the installer and the
/// fetcher would install providers where nothing looks for them.
struct PluginPaths {
    /// Where providers are installed.
    let plugins: URL

    /// Where plugin output is recorded.
    let logs: URL

    init(root: URL = CodableStore.defaultDirectory()) {
        plugins = root.appendingPathComponent(
            PersistenceConstants.pluginsDirectoryName,
            isDirectory: true
        )
        logs = root.appendingPathComponent(
            PersistenceConstants.pluginLogDirectoryName,
            isDirectory: true
        )
    }
}
