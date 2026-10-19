import Core
import Foundation
import Platform
import PluginKit
import Testing
@testable import App

/// The world a provider's page is read from.
///
/// A store with one connected provider, one quota reading it, and a reading
/// that carries two limits — the arrangement a provider's page has to answer
/// about.
enum ProviderDetailFixture {
    static let providerID = "quota.test.provider"
    static let account = "work@example.com"
    static let catalogVersion = Version(major: 1, minor: 2, patch: 0)
    static let installedVersion = Version(major: 1, minor: 1, patch: 0)

    static var calendar: Calendar {
        SummaryFixture.calendar
    }

    /// What the provider says about itself.
    static func descriptor() throws -> ProviderDescriptor {
        ProviderDescriptor(
            id: providerID,
            displayName: "Test Provider",
            description: "Meters two limits",
            capabilities: [.automaticUsageRetrieval, .historicalUsage],
            protocolRange: ProtocolRange(
                minimum: Version(major: 1, minor: 0, patch: 0),
                maximum: Version(major: 1, minor: 2, patch: 0)
            ),
            suggestedRefreshIntervalSeconds: 900
        )
    }

    /// The listing the providers list shows for this provider.
    ///
    /// Describable or not, because a provider nobody has run yet has a page
    /// too — one that can say what it is and nothing about what it can do.
    static func listing(described: Bool = true) -> ProviderListing {
        ProviderListing(
            provider: AvailableProvider(
                id: providerID,
                version: catalogVersion,
                described: described ? (try? descriptor()) : nil
            ),
            state: .connected,
            installedVersion: installedVersion
        )
    }

    /// A model over that world, and the provider behind it.
    @MainActor
    static func model(now: Date = SummaryFixture.reference) async throws -> (AppModel, CountingFetcher) {
        let store = CodableStore.inMemory()
        try await arrange(store: store, now: now)
        let fetcher = CountingFetcher()
        let environment = AppEnvironment.preview(
            store: store,
            available: [AvailableProvider(
                id: providerID,
                version: catalogVersion,
                described: try descriptor()
            )],
            fetcher: fetcher,
            now: now,
            calendar: calendar
        )
        let model = AppModel(environment: environment)
        await model.load()
        return (model, fetcher)
    }

    /// The stored world: a provider, a quota reading it, and a reading.
    private static func arrange(store: any QuotaStore, now: Date) async throws {
        let month = try QuotaPeriod(
            start: now.addingTimeInterval(-86400),
            end: now.addingTimeInterval(86400 * 20)
        )
        let fiveHours = try QuotaPeriod(
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(3600 * 4)
        )
        let quota = try Quota(
            name: "Weekly",
            providerID: try ProviderID(providerID),
            bucketID: "week",
            period: month,
            policy: .even,
            createdAt: now,
            updatedAt: now
        )
        try await store.saveQuotas([QuotaRecord(quota: quota)])
        try await store.saveProviders([try providerRecord(now: now)])
        try await store.saveSnapshots([
            snapshotRecord(quotaID: quota.id, now: now, month: month, fiveHours: fiveHours),
        ])
    }

    /// The provider: connected, and answering two minutes ago.
    private static func providerRecord(now: Date) throws -> ProviderRecord {
        ProviderRecord(
            providerID: try ProviderID(providerID),
            displayName: "Test Provider",
            installedVersion: installedVersion.description,
            authenticatedAccountLabel: account,
            lastSyncAt: now.addingTimeInterval(-120)
        )
    }

    /// The reading: two limits, each over its own window.
    private static func snapshotRecord(
        quotaID: UUID,
        now: Date,
        month: QuotaPeriod,
        fiveHours: QuotaPeriod
    ) throws -> SnapshotRecord {
        SnapshotRecord(
            quotaID: quotaID,
            bucketID: "week",
            accountLabel: account,
            snapshot: try UsageSnapshot(
                updatedAt: now,
                buckets: [
                    try UsageBucket(
                        id: "week",
                        displayName: "Weekly",
                        usagePercentage: 40,
                        period: month
                    ),
                    try UsageBucket(
                        id: "five_hour",
                        displayName: "Five hours",
                        usagePercentage: 10,
                        period: fiveHours
                    ),
                ]
            )
        )
    }
}

/// A provider that answers nothing, and counts how often it was asked.
actor CountingFetcher: UsageFetching {
    private(set) var callCount = 0

    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        callCount += 1
        return .failure(
            SyncFailure(
                code: .nothingToReport,
                message: "Nothing to report.",
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        )
    }
}

@Suite("A provider's page")
struct ProviderDetailTests {
    @Test("The page says who the provider reads as, and when it last answered")
    func statusFacts() async throws {
        let (model, _) = try await ProviderDetailFixture.model()
        let detail = await model.providerDetail(for: ProviderDetailFixture.listing())

        #expect(detail.accountLabel == ProviderDetailFixture.account)
        #expect(detail.syncCaption == "Updated 2 minutes ago.")
        #expect(detail.versionCaption == "1.1.0 installed · 1.2.0 in this build")
        #expect(detail.protocolCaption == "Speaks protocol 1.0.0 to 1.2.0.")
        #expect(detail.refreshCaption == "Asked every 15 minutes.")
    }

    @Test("The page lists the limits the provider meters, and when each turns over")
    func listsPools() async throws {
        let (model, _) = try await ProviderDetailFixture.model()
        let detail = await model.providerDetail(for: ProviderDetailFixture.listing())

        // Both limits, not only the one a quota watches: a provider that meters
        // two limits is a fact about the provider, and the page is where a user
        // goes to find it out.
        #expect(detail.pools.map(\.id) == ["week", "five_hour"])
        #expect(detail.pools.map(\.name) == ["Weekly", "Five hours"])
        #expect(detail.pools.allSatisfy { $0.resetCaption != nil })
    }

    @Test("A provider that has not spoken yet says nothing about its protocol")
    func silentProviderClaimsNothing() async throws {
        let (model, _) = try await ProviderDetailFixture.model()
        let detail = await model.providerDetail(for: ProviderDetailFixture.listing(described: false))

        #expect(detail.protocolCaption == nil)
        // What the app knows about it anyway: the name, the account, and the
        // limits it meters are not the provider's to claim.
        #expect(detail.accountLabel == ProviderDetailFixture.account)
        #expect(detail.pools.count == 2)
    }

    @Test("Opening a page reads the store rather than the provider")
    func pageDoesNotAskTheProvider() async throws {
        let (model, fetcher) = try await ProviderDetailFixture.model()
        _ = await model.providerDetail(for: ProviderDetailFixture.listing())

        // A page that asked the provider for its numbers would turn a click
        // into a request, and could show figures that disagree with the ones
        // beside it.
        #expect(await fetcher.callCount == 0)
    }
}
