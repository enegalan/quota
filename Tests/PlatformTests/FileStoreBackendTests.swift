import Foundation
import Testing
@testable import Core
@testable import Platform

/// A fixed clock, so a quarantine name is deterministic.
private let fixedInstant = Date(timeIntervalSince1970: 1_700_000_000)

private func makeQuota(name: String = "Cursor") async throws -> Quota {
    let start = QuotaFixture.start
    let end = QuotaFixture.end
    return try Quota(
        name: name,
        providerID: try ProviderID("mock"),
        period: try QuotaPeriod(start: start, end: end),
        policy: .even,
        createdAt: start,
        updatedAt: start
    )
}

private func makeSnapshot(_ percentage: Double, bucketID: String = "models") async throws -> UsageSnapshot {
    let start = QuotaFixture.start
    let end = QuotaFixture.end
    return try UsageSnapshot(
        updatedAt: fixedInstant,
        buckets: [
            try UsageBucket(
                id: bucketID,
                displayName: bucketID,
                usagePercentage: percentage,
                period: try QuotaPeriod(start: start, end: end)
            ),
        ]
    )
}

/// A directory that removes itself, so a test cannot leave state behind for the
/// next one to trip over.
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("FileQuotaStore")
struct FileQuotaStoreTests {
    /// Writes one record of every family, so the round trip covers all five files
    /// rather than whichever one is easiest to assert on.
    private func writeEveryFamily(
        _ quota: Quota,
        provider: ProviderRecord,
        to store: any QuotaStore
    ) async throws {
        let point = try TimelinePoint(
            recordedAt: fixedInstant,
            bucketID: "models",
            usagePercentage: 42.5
        )
        try await store.saveQuotas([QuotaRecord(quota: quota)])
        try await store.saveSnapshots([
            SnapshotRecord(
                quotaID: quota.id,
                bucketID: "models",
                accountLabel: "work",
                snapshot: try makeSnapshot(42.5)
            ),
        ])
        try await store.saveTimelines([
            TimelineRecord(
                quotaID: quota.id,
                bucketID: "models",
                accountLabel: "work",
                timeline: UsageTimeline(points: [point])
            ),
        ])
        try await store.saveProviders([provider])
        try await store.savePreferences(Preferences(hasCompletedOnboarding: true))
    }

    @Test("Every record family round trips through the store")
    func roundTripEveryFamily() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })

        let quota = try await makeQuota()
        let provider = ProviderRecord(
            providerID: try ProviderID("mock"),
            displayName: "Mock",
            installedVersion: "1.0.0"
        )
        try await writeEveryFamily(quota, provider: provider, to: store)

        let reopened = CodableStore.onDisk(directory: directory, now: { fixedInstant })
        #expect(try await reopened.loadQuotas().map(\.quota) == [quota])
        let loadedSnapshots = try await reopened.loadSnapshots()
        #expect(loadedSnapshots.count == 1)
        let expectedSnapshot = try await makeSnapshot(42.5)
        #expect(loadedSnapshots.first?.snapshot == expectedSnapshot)
        let expectedPoints = [try TimelinePoint(
            recordedAt: fixedInstant,
            bucketID: "models",
            usagePercentage: 42.5
        )]
        #expect(try await reopened.loadTimelines().first?.timeline.points == expectedPoints)
        #expect(try await reopened.loadProviders() == [provider])
        #expect(try await reopened.loadPreferences()?.hasCompletedOnboarding == true)
    }

    @Test("A missing directory is created on first write")
    func createsMissingDirectory() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let missing = parent.appendingPathComponent("does-not-exist", isDirectory: true)

        let store = CodableStore.onDisk(directory: missing, now: { fixedInstant })
        try await store.saveQuotas([QuotaRecord(quota: try makeQuota())])
        #expect(FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("A store over an empty directory reports empty, not missing")
    func emptyStoreReadsAsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })

        #expect(try await store.loadQuotas().isEmpty)
        #expect(try await store.loadSnapshots().isEmpty)
        #expect(try await store.loadTimelines().isEmpty)
        #expect(try await store.loadProviders().isEmpty)
        #expect(try await store.loadPreferences() == nil)
    }

    @Test("An atomic write leaves no temporary file behind")
    func writeLeavesNoTemporaryFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskStoreFixture(directory: directory, now: { fixedInstant })

        try await disk.store.saveQuotas([QuotaRecord(quota: try makeQuota())])
        let contents = try disk.directoryContents()
        #expect(contents == [PersistenceConstants.FileName.quotas])
        #expect(!contents.contains { $0.hasSuffix(".tmp") })
    }

    @Test("Overwriting a file replaces it rather than accumulating copies")
    func overwriteReplaces() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskStoreFixture(directory: directory, now: { fixedInstant })

        try await disk.store.saveQuotas([QuotaRecord(quota: try makeQuota(name: "First"))])
        try await disk.store.saveQuotas([QuotaRecord(quota: try makeQuota(name: "Second"))])

        let quotas = try await disk.store.loadQuotas()
        #expect(quotas.count == 1)
        #expect(quotas.first?.quota.name == "Second")
        let contents = try disk.directoryContents()
        #expect(contents.filter { $0 == PersistenceConstants.FileName.quotas }.count == 1)
    }

    @Test("A corrupt file is quarantined and the app starts from empty state")
    func corruptFileIsQuarantined() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let corruptURL = directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        try Data("this is not json".utf8).write(to: corruptURL)

        let disk = DiskStoreFixture(directory: directory, now: { fixedInstant })
        #expect(try await disk.store.loadQuotas().isEmpty)

        let contents = try disk.directoryContents()
        #expect(contents.contains { $0.hasSuffix(PersistenceConstants.quarantineSuffix) })
        #expect(contents.contains(PersistenceConstants.FileName.quotas))
    }

    @Test("A file from another schema version is set aside rather than guessed at")
    func schemaVersionIsChecked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let future: StoreSchema.Envelope<[QuotaRecord]> = await StoreSchema.Envelope(
            version: StoreSchema.currentVersion + 1,
            payload: [QuotaRecord(quota: try makeQuota())]
        )
        let url = directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        try JSONEncoder().encode(future).write(to: url)

        let disk = DiskStoreFixture(directory: directory, now: { fixedInstant })
        // Not decoded: a file written by a newer build may mean something else now.
        #expect(try await disk.store.loadQuotas().isEmpty)
        #expect(try disk.directoryContents().contains {
            $0.hasSuffix(PersistenceConstants.quarantineSuffix)
        })
    }

    @Test("A written file records the current schema version")
    func writesCurrentSchemaVersion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })
        try await store.saveQuotas([])

        let data = try Data(
            contentsOf: directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["version"] as? Int == StoreSchema.currentVersion)
    }

    @Test("Every written file is protected until the first unlock")
    func writesAreProtected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })
        try await store.saveQuotas([QuotaRecord(quota: try makeQuota())])

        let path = directory.appendingPathComponent(PersistenceConstants.FileName.quotas).path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let protection = try #require(attributes[.protectionKey] as? FileProtectionType)
        #expect(protection == PersistenceConstants.fileProtection)
    }

    @Test("Concurrent saves to the same file leave a readable file")
    func concurrentSaves() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 8 {
                group.addTask {
                    guard let quota = try? await makeQuota(name: "Quota \(index)") else { return }
                    try? await store.saveQuotas([QuotaRecord(quota: quota)])
                }
            }
        }

        // Whatever won the race, the file is one complete document.
        let quotas = try await store.loadQuotas()
        #expect(quotas.count <= 1)
        let leftovers = try DiskStoreFixture(directory: directory).directoryContents()
        #expect(!leftovers.contains { $0.hasSuffix(".tmp") })
    }

    @Test("A record family is stored in its own file, so one cannot break another")
    func familiesAreIsolated() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("broken".utf8).write(
            to: directory.appendingPathComponent(PersistenceConstants.FileName.quotas)
        )
        let store = CodableStore.onDisk(directory: directory, now: { fixedInstant })
        try await store.saveProviders([
            ProviderRecord(
                providerID: try ProviderID("mock"),
                displayName: "Mock",
                installedVersion: "1.0.0"
            ),
        ])

        #expect(try await store.loadQuotas().isEmpty)
        #expect(try await store.loadProviders().count == 1)
    }
}
