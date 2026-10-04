import Core
import Foundation
import Platform
import PluginKit
import Testing
@testable import App

/// The world a quota-creation test runs against.
///
/// Its own file because it is the only test that needs an `AppEnvironment`: the
/// other suites read the store directly, and building an environment for them
/// would mean arranging plugins and a clock they never look at.
enum QuotaCreationFixture {
    static let providerID = "quota.test.provider"
    static let providerName = "Test Provider"
    static let catalogVersion = Version(major: 1, minor: 0, patch: 0)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SummaryFixture.timeZone
        return calendar
    }

    static func available(unofficial: Bool = false) -> [AvailableProvider] {
        [AvailableProvider(id: providerID, version: catalogVersion)]
    }

    /// A fetcher that reports nothing, because a creation test is about the quota
    /// the flow saves and not about what a provider would have said.
    static func environment(
        store: any QuotaStore = CodableStore.inMemory(),
        now: Date = SummaryFixture.reference,
        unofficial: Bool = false
    ) -> AppEnvironment {
        AppEnvironment.preview(
            store: store,
            available: available(unofficial: unofficial),
            fetcher: UnconnectedFetcher(),
            now: now,
            calendar: calendar
        )
    }

    /// A model on a fixed clock, so a period this test reads is the period that
    /// was created rather than the one containing whenever it ran.
    @MainActor
    static func model(now: Date = SummaryFixture.reference) -> AppModel {
        AppModel(environment: environment(now: now))
    }

    /// The two pools a provider metering several limits reports.
    static let twoPools = ["five_hour", "week"]

    /// A model over a connected provider that meters two pools, each over its own
    /// window — the arrangement the picker and the period-per-pool creation exist
    /// for. Connected because a provider is only read once an account is stored,
    /// and the bucket discovery reads the provider through the same path as a
    /// refresh.
    @MainActor
    static func modelWithTwoPools(now: Date = SummaryFixture.reference) async throws -> AppModel {
        let store = CodableStore.inMemory()
        try await store.saveProviders([
            ProviderRecord(
                providerID: try ProviderID(providerID),
                displayName: providerName,
                installedVersion: "1.0.0",
                authenticatedAccountLabel: "work@example.com"
            ),
        ])
        let env = AppEnvironment.preview(
            store: store,
            available: available(),
            fetcher: TwoPoolFetcher(),
            now: now,
            calendar: calendar
        )
        return AppModel(environment: env)
    }

    /// The quotas in a store, in the order they were written.
    static func quotas(in store: any QuotaStore) async throws -> [Quota] {
        try await QuotaRepository(store: store).all()
    }
}

/// A provider metering two limits, one resetting every few hours and one weekly.
///
/// The two windows are different by design: a provider whose pools share a clock
/// would not need the period to live on the pool, and a fixture that gave them one
/// window would pass against an implementation that put it back on the snapshot.
private struct TwoPoolFetcher: UsageFetching {
    private let updatedAt = SummaryFixture.reference

    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        guard let snapshot = try? snapshot() else {
            return .failure(
                SyncFailure(
                    code: .nothingToReport,
                    message: "No pools.",
                    occurredAt: Date(timeIntervalSince1970: 0)
                )
            )
        }
        return .success(snapshot)
    }

    private func snapshot() throws -> UsageSnapshot {
        let fiveHours = try QuotaPeriod(
            start: updatedAt.addingTimeInterval(-3600 * 2),
            end: updatedAt.addingTimeInterval(3600 * 3)
        )
        let week = try QuotaPeriod(
            start: updatedAt.addingTimeInterval(-86400 * 2),
            end: updatedAt.addingTimeInterval(86400 * 5)
        )
        return try UsageSnapshot(
            updatedAt: updatedAt,
            buckets: [
                try UsageBucket(
                    id: QuotaCreationFixture.twoPools[0],
                    displayName: "Five hours",
                    usagePercentage: 12,
                    period: fiveHours
                ),
                try UsageBucket(
                    id: QuotaCreationFixture.twoPools[1],
                    displayName: "Weekly",
                    usagePercentage: 34,
                    period: week
                ),
            ]
        )
    }
}

/// A provider that has nothing to say.
///
/// A failure rather than an empty success, because a `UsageSnapshot` has to
/// contain a bucket and an empty one would be a claim that the provider reported
/// a period holding no usage at all. A provider with no credentials is exactly
/// what a created-but-not-yet-connected quota has, and `SyncFailure` is a value,
/// so this is a quiet provider rather than a thrown error.
private struct UnconnectedFetcher: UsageFetching {
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        .failure(
            SyncFailure(
                code: .notAuthenticated,
                message: "No account is connected yet.",
                occurredAt: Date(timeIntervalSince1970: 0)
            )
        )
    }
}
