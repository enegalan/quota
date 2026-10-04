import Foundation
import Testing
@testable import Core
@testable import Platform

@Suite("Keychain")
struct KeychainTests {
    /// Writes one record of every family, so the scan below looks at the files an
    /// app really leaves behind rather than an empty directory.
    private func writeEveryFamily(
        _ quota: Quota,
        to store: any QuotaStore,
        providerID: ProviderID
    ) async throws {
        try await store.saveQuotas([QuotaRecord(quota: quota)])
        try await store.saveSnapshots([
            SnapshotRecord(
                quotaID: quota.id,
                bucketID: "models",
                accountLabel: "work",
                snapshot: try SampleRecords.snapshot()
            ),
        ])
        try await store.saveTimelines([
            TimelineRecord(
                quotaID: quota.id,
                bucketID: "models",
                accountLabel: "work",
                timeline: UsageTimeline(points: [try SampleRecords.point()])
            ),
        ])
        try await store.saveProviders([
            ProviderRecord(
                providerID: providerID,
                displayName: "Mock",
                installedVersion: "1.0.0",
                authenticatedAccountLabel: "work"
            ),
        ])
        try await store.savePreferences(.default)
    }

    @Test("An item can be created, read, and replaced")
    func createReadUpdate() async throws {
        let keychain = InMemoryKeychain()
        let account = "mock.sessionToken"

        #expect(try await keychain.read(account) == nil)

        try await keychain.write(Data("first".utf8), for: account)
        #expect(try await keychain.read(account) == Data("first".utf8))

        try await keychain.write(Data("second".utf8), for: account)
        #expect(try await keychain.read(account) == Data("second".utf8))
        // Replaced, not duplicated.
        #expect(await keychain.accounts() == [account])
    }

    @Test("Reading an item that was never written returns nil rather than throwing")
    func readMissingReturnsNil() async throws {
        let keychain = InMemoryKeychain()
        #expect(try await keychain.read("never-written") == nil)
    }

    @Test("An item can be deleted, and deleting twice is not an error")
    func deleteIsIdempotent() async throws {
        let keychain = InMemoryKeychain()
        try await keychain.write(Data("value".utf8), for: "mock.token")
        try await keychain.delete("mock.token")
        #expect(try await keychain.read("mock.token") == nil)
        try await keychain.delete("mock.token")
    }

    @Test("A credential account is named after its provider and key")
    func accountNaming() throws {
        let provider = try ProviderID("mock")
        #expect(
            try KeychainCredentialStore.account(providerID: provider, keyName: "sessionToken")
                == "mock.sessionToken"
        )
    }

    @Test("A credential account rejects a key name that could collide")
    func accountNamingRejectsInvalidKey() throws {
        let provider = try ProviderID("mock")
        for invalid in ["", "has space", "tab\there"] {
            #expect(throws: QuotaDomainError.self) {
                try KeychainCredentialStore.account(providerID: provider, keyName: invalid)
            }
        }
    }

    /// The assertion that matters most in this milestone. A credential that
    /// reaches a JSON file is readable by anything that can read the user's
    /// Application Support directory, and unlike the Keychain it is not removed
    /// when the user logs out.
    @Test("No credential material ever appears in a store payload")
    func noCredentialInStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-credential-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let keychain = InMemoryKeychain()
        let disk = DiskStoreFixture(directory: directory, now: { Date(timeIntervalSince1970: 0) })
        let store = disk.store

        // A credential that is recognisable as one: a value long enough and
        // distinctive enough that finding it in a payload is unambiguous.
        let secret = "sk-live-DO-NOT-PERSIST-0123456789abcdef"
        let provider = try ProviderID("mock")
        try await keychain.write(
            Data(secret.utf8),
            for: try KeychainCredentialStore.account(providerID: provider, keyName: "sessionToken")
        )

        // Write a full set of records, the kind an app holds after a sync.
        let quota = try await SampleRecords.quota()
        try await writeEveryFamily(quota, to: store, providerID: provider)

        for fileName in try disk.directoryContents() {
            let data = try Data(
                contentsOf: directory.appendingPathComponent(fileName)
            )
            let text = try #require(String(bytes: data, encoding: .utf8))
            #expect(!text.contains(secret), "\(fileName) contains credential material")
        }

        // The credential is still where it belongs.
        #expect(try await keychain.read("mock.sessionToken") == Data(secret.utf8))
    }

    @Test("A provider record names the account without holding its credential")
    func providerRecordHoldsNoCredential() throws {
        let record = ProviderRecord(
            providerID: try ProviderID("mock"),
            displayName: "Mock",
            installedVersion: "1.0.0",
            authenticatedAccountLabel: "work@example.com"
        )
        let data = try JSONEncoder().encode(record)
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json.contains("work@example.com"))
        #expect(!json.lowercased().contains("token"))
        #expect(!json.lowercased().contains("secret"))
        #expect(!json.lowercased().contains("password"))
    }
}

/// Records shaped like the ones a running app holds, so the credential scan
/// covers real payloads rather than empty ones.
enum SampleRecords {
    static func quota() async throws -> Quota {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        return try Quota(
            name: "Cursor",
            providerID: try ProviderID("mock"),
            bucketID: "models",
            period: try QuotaPeriod(start: start, end: end),
            policy: .even,
            createdAt: start,
            updatedAt: start
        )
    }

    static func snapshot() throws -> UsageSnapshot {
        let start = QuotaFixture.start
        let end = QuotaFixture.end
        return try UsageSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            buckets: [
                try UsageBucket(
                    id: "models",
                    displayName: "Models",
                    usagePercentage: 42.5,
                    period: try QuotaPeriod(start: start, end: end)
                ),
            ]
        )
    }

    static func point() throws -> TimelinePoint {
        try TimelinePoint(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bucketID: "models",
            usagePercentage: 42.5
        )
    }
}
