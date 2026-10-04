import Foundation

/// Where a `QuotaStore`'s bytes actually go.
///
/// Split out so the encoding, versioning, and empty-state rules live in one
/// place and the two stores differ only in how they move bytes. Two stores that
/// each implemented the five record families would be two places for a migration
/// bug to hide in.
public protocol StoreBackend: Sendable {
    /// The stored bytes for a family, or nil when nothing has been written yet.
    func read(_ fileName: String) async throws -> Data?

    /// Replaces a family's bytes with `data`.
    ///
    /// The backend's own atomicity is what the family guarantee rests on, so
    /// it is required here rather than assumed: a backend that wrote in place
    /// would let a crash truncate one file and take every record in it with
    /// it.
    func write(_ data: Data, to fileName: String) async throws

    /// Sets unreadable bytes aside under a distinct name, so the file can be
    /// inspected afterwards instead of being deleted or, worse, re-read on every
    /// launch.
    func quarantine(_ data: Data, from fileName: String) async throws
}

/// The one `QuotaStore` implementation, over a pluggable `StoreBackend`.
///
/// Decoding failures are not errors: a file that cannot be read is quarantined
/// and treated as absent, because failing to launch over one bad file is worse
/// for a user than starting again with an empty configuration they can rebuild.
///
/// There is no second store and no per-backend wrapper. Everything about
/// encoding, versioning, and empty state is answered here, so a store that
/// differed only in where its bytes went could only differ by getting one of
/// those answers wrong — in a bug that a memory-backed test never reproduced.
/// Where the bytes go is the whole of the difference between a test and the app.
public struct CodableStore: QuotaStore, Sendable {
    private let backend: any StoreBackend
    private let migrator: SchemaMigrator

    public init(backend: any StoreBackend, migrator: SchemaMigrator = .current) {
        self.backend = backend
        self.migrator = migrator
    }

    /// A store that keeps everything in memory, for a world that only needs to
    /// look real.
    public static func inMemory(seed: [String: Data] = [:]) -> CodableStore {
        CodableStore(backend: InMemoryStoreBackend(seed: seed))
    }

    /// JSON files under Application Support.
    ///
    /// - Parameters:
    ///   - directory: where the files live. Defaults to the standard Application
    ///     Support location, created on first write.
    ///   - now: the clock, injected so a quarantine name is predictable in a
    ///     test without the test having to wait for a second to tick.
    public static func onDisk(
        directory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        migrator: SchemaMigrator = .current
    ) -> CodableStore {
        CodableStore(
            backend: FileStoreBackend(directory: directory ?? defaultDirectory(), now: now),
            migrator: migrator
        )
    }

    /// The application's data root, public because the composition root has to
    /// decide what else lives beside the JSON files — the installed plugins, a
    /// plugin's captured output — and it should not have to reimplement where
    /// that root is to do it.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(PersistenceConstants.directoryName, isDirectory: true)
    }

    /// Reads the quotas family, treating an unreadable file as no quotas.
    public func loadQuotas() async throws -> [QuotaRecord] {
        try await load(PersistenceConstants.FileName.quotas) ?? []
    }

    /// Writes the quotas family.
    public func saveQuotas(_ records: [QuotaRecord]) async throws {
        try await save(records, to: PersistenceConstants.FileName.quotas)
    }

    /// Reads the snapshots family, treating an unreadable file as none.
    public func loadSnapshots() async throws -> [SnapshotRecord] {
        try await load(PersistenceConstants.FileName.snapshots) ?? []
    }

    /// Writes the snapshots family.
    public func saveSnapshots(_ records: [SnapshotRecord]) async throws {
        try await save(records, to: PersistenceConstants.FileName.snapshots)
    }

    /// Reads the plans family, treating an unreadable file as no plans.
    public func loadAllocationPlans() async throws -> [AllocationPlanRecord] {
        try await load(PersistenceConstants.FileName.allocationPlans) ?? []
    }

    /// Writes the plans family.
    public func saveAllocationPlans(_ records: [AllocationPlanRecord]) async throws {
        try await save(records, to: PersistenceConstants.FileName.allocationPlans)
    }

    /// Reads the timelines family, treating an unreadable file as no history.
    public func loadTimelines() async throws -> [TimelineRecord] {
        try await load(PersistenceConstants.FileName.timelines) ?? []
    }

    /// Writes the timelines family.
    public func saveTimelines(_ records: [TimelineRecord]) async throws {
        try await save(records, to: PersistenceConstants.FileName.timelines)
    }

    /// Reads the providers family, treating an unreadable file as none.
    public func loadProviders() async throws -> [ProviderRecord] {
        try await load(PersistenceConstants.FileName.providers) ?? []
    }

    /// Writes the providers family.
    public func saveProviders(_ records: [ProviderRecord]) async throws {
        try await save(records, to: PersistenceConstants.FileName.providers)
    }

    /// Reads the settings, which are the one family with a meaningful nil.
    ///
    /// Preferences are not coerced to an empty value here, unlike every other
    /// family: a first launch and a file that would not decode both have to
    /// produce the same result, and only "never written" can be represented
    /// without inventing settings the user did not choose.
    public func loadPreferences() async throws -> Preferences? {
        try await load(PersistenceConstants.FileName.preferences)
    }

    /// Writes the settings.
    public func savePreferences(_ preferences: Preferences) async throws {
        try await save(preferences, to: PersistenceConstants.FileName.preferences)
    }

    /// Reads the installed-providers family, treating unreadable as none.
    ///
    /// Nothing is inferred from the directory here. A store that scanned the
    /// filesystem would report a provider the user had removed and never
    /// finished uninstalling as installed, and the app would then offer to
    /// delete something it had never found.
    public func loadInstalledProviders() async throws -> [InstalledProvider] {
        try await load(PersistenceConstants.FileName.installedProviders) ?? []
    }

    /// Writes the installed-provider family.
    public func saveInstalledProviders(_ records: [InstalledProvider]) async throws {
        try await save(records, to: PersistenceConstants.FileName.installedProviders)
    }

    // MARK: - Shared encoding

    /// Reads one family, migrating it forward or setting it aside.
    ///
    /// The one place decode failures stop being errors. Quarantining and
    /// reporting nil rather than throwing is a deliberate choice about who
    /// pays: a user loses a configuration they can rebuild, while the
    /// alternative is an app that will not launch until they delete a file
    /// they cannot name.
    private func load<Payload: Codable & Sendable>(
        _ fileName: String
    ) async throws -> Payload? {
        guard let data = try await backend.read(fileName) else { return nil }
        do {
            // Ask for the version first: the answer decides whether these bytes
            // can be decoded at all, and decoding first would throw away the
            // distinction between "written by an older build" and "corrupt".
            guard let storedVersion = StoreSchema.version(of: data) else {
                try await quarantine(fileName, data: data)
                return nil
            }

            let current: Data
            if storedVersion == migrator.targetVersion {
                current = data
            } else if let migrated = try migrator.migrate(data, from: storedVersion, for: fileName) {
                current = migrated
            } else {
                // No path to the current version. Treated exactly like a corrupt
                // file: set aside, start clean, and let the build that
                // understands it run again. Guessing what an old field means now
                // is how a migration turns into silent data loss.
                try await quarantine(fileName, data: data)
                return nil
            }

            let envelope = try JSONDecoder.quota.decode(StoreSchema.Envelope<Payload>.self, from: current)
            if storedVersion != migrator.targetVersion {
                // Write the upgraded bytes back, so the migration runs once
                // rather than on every launch.
                try await backend.write(current, to: fileName)
            }
            return envelope.payload
        } catch {
            try await quarantine(fileName, data: data)
            return nil
        }
    }

    /// Wraps a payload in the versioned envelope and writes it.
    ///
    /// Every write goes through here so that no family can be saved without a
    /// version: the envelope is what a later build dispatches on, and a file
    /// written without one would be indistinguishable from a corrupt file and
    /// would be quarantined on the next launch.
    private func save(
        _ payload: some Codable & Sendable,
        to fileName: String
    ) async throws {
        let envelope = StoreSchema.Envelope(payload: payload)
        let data = try JSONEncoder.quota.encode(envelope)
        try await backend.write(data, to: fileName)
    }

    /// Sets one family's bytes aside under a distinct name.
    ///
    /// A pass-through kept for symmetry with `load` and `save`, so the decode
    /// paths read as one vocabulary. It adds no recovery: nothing reads these
    /// bytes back, which is deliberate — a store that tried to restore them
    /// would reintroduce whatever made them unreadable.
    private func quarantine(_ fileName: String, data: Data) async throws {
        try await backend.quarantine(data, from: fileName)
    }
}
