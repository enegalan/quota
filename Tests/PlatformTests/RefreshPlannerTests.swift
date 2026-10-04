import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Refresh planner")
struct RefreshPlannerTests {
    private static let start = Date(timeIntervalSince1970: 1_757_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// A coordinator with two quotas on one provider and one on another.
    private func makePlanner(
        now: @escaping @Sendable () -> Date
    ) async throws -> (RefreshPlanner, [Quota]) {
        let store = CodableStore.inMemory()
        let repositories = SyncFixture.Repositories(store: store)
        return await (
            RefreshPlanner(coordinator: makeCoordinator(store: repositories, now: now), now: now),
            try arrange(store: store)
        )
    }

    /// Three quotas over two providers, which is the smallest arrangement that
    /// can show two quotas sharing a provider and one provider owning a quota
    /// alone.
    private func arrange(store: any QuotaStore) async throws -> [Quota] {
        let period = try QuotaPeriod(
            start: Self.start,
            end: Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: Self.start) ?? Self.start
        )
        let first = try Quota(
            name: "One", providerID: try ProviderID("mock"), period: period, policy: .even,
            createdAt: Self.start, updatedAt: Self.start
        )
        let second = try Quota(
            name: "Two", providerID: try ProviderID("mock"), period: period, policy: .even,
            createdAt: Self.start, updatedAt: Self.start
        )
        let other = try Quota(
            name: "Other", providerID: try ProviderID("other"), period: period, policy: .even,
            createdAt: Self.start, updatedAt: Self.start
        )
        try await store.saveQuotas([first, second, other].map(QuotaRecord.init(quota:)))
        try await store.saveProviders([
            ProviderRecord(
                providerID: try ProviderID("mock"), displayName: "Mock", installedVersion: "1",
                authenticatedAccountLabel: "work@example.com"
            ),
            ProviderRecord(
                providerID: try ProviderID("other"), displayName: "Other", installedVersion: "1",
                authenticatedAccountLabel: "work@example.com"
            ),
        ])
        return [first, second, other]
    }

    private func makeCoordinator(
        store: SyncFixture.Repositories,
        now: @escaping @Sendable () -> Date
    ) -> SyncCoordinator {
        SyncCoordinator(
            quotas: store.quotas,
            snapshots: store.snapshots,
            timelines: store.timelines,
            providers: store.providers,
            plans: store.plans,
            engine: AllocationEngine(calendar: calendar),
            fetcher: ScriptedProvider([]),
            calendar: calendar,
            now: now,
            preferences: store.preferences
        )
    }

    @Test("A popover opening reads every quota, ahead of any schedule")
    func popoverReadsEverything() async throws {
        let instant = Self.start
        let (planner, quotas) = try await makePlanner(now: { instant })

        let planned = try await planner.plan(for: .popoverOpened)

        #expect(Set(planned) == Set(quotas.map(\.id)))
    }

    @Test("A launch reads every quota")
    func launchReadsEverything() async throws {
        let instant = Self.start
        let (planner, quotas) = try await makePlanner(now: { instant })

        #expect(await Set(try planner.plan(for: .launch)) == Set(quotas.map(\.id)))
    }

    @Test("A read already under way is not started a second time")
    func inFlightIsNotRestarted() async throws {
        let instant = Self.start
        let (planner, quotas) = try await makePlanner(now: { instant })
        await planner.begin([quotas[0].id])

        let planned = try await planner.plan(for: .popoverOpened)

        #expect(!planned.contains(quotas[0].id))
        #expect(planned.count == quotas.count - 1)
    }

    @Test("A quota never read before is due immediately")
    func neverReadIsDue() async throws {
        let instant = Self.start
        let (planner, _) = try await makePlanner(now: { instant })

        #expect(try await planner.due(at: instant).count == 3)
    }

    @Test("Connectivity coming back reads; staying connected does not")
    func connectivityRestoration() async throws {
        let instant = Self.start
        let (planner, quotas) = try await makePlanner(now: { instant })

        #expect(try await planner.connectivityChanged(to: false).isEmpty)
        let restored = try await planner.connectivityChanged(to: true)
        #expect(Set(restored) == Set(quotas.map(\.id)))
        // Reading the same value again is not an event.
        #expect(try await planner.connectivityChanged(to: true).isEmpty)
    }

    @Test("Finishing a read schedules the next one and releases the quota")
    func finishingSchedulesTheNext() async throws {
        let instant = Self.start
        let (planner, quotas) = try await makePlanner(now: { instant })
        await planner.begin([quotas[0].id])
        await planner.finish([quotas[0].id])

        let due = try await planner.due(at: instant)
        #expect(!due.contains(quotas[0].id))
        let providerID = try ProviderID("mock")
        let next = try #require(await planner.due(for: providerID))
        #expect(next > instant)
        // Far enough ahead that it is not about to come round again.
        #expect(next.timeIntervalSince(instant) > RefreshConstants.minimumPollInterval / 2)
    }

    @Test("Launching online is treated as a restoration")
    func launchOnlineIsRestoration() {
        #expect(RefreshPlanner.launch(isConnected: true).justRestored)
        #expect(!RefreshPlanner.launch(isConnected: false).justRestored)
    }
}

@Suite("Allocation plan storage")
struct AllocationPlanRepositoryTests {
    private static let start = Date(timeIntervalSince1970: 1_757_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func makePlan(remaining: Double) throws -> AllocationPlan {
        let period = try QuotaPeriod(
            start: Self.start,
            end: calendar.date(byAdding: .day, value: 30, to: Self.start) ?? Self.start
        )
        return try AllocationPlan(
            quotaID: UUID(),
            generatedAt: Self.start,
            totalRemaining: remaining,
            period: period,
            allocations: [Allocation(date: LocalDate(date: Self.start, calendar: calendar), percentage: remaining)],
            validation: .exact
        )
    }

    @Test("Saving a plan twice replaces it rather than accumulating plans")
    func saveIsUpsert() async throws {
        let repository = AllocationPlanRepository(store: CodableStore.inMemory())
        let plan = try makePlan(remaining: 60)
        try await repository.save(plan, accountLabel: "work@example.com")
        try await repository.save(plan, accountLabel: "work@example.com")

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(try await repository.plan(quotaID: plan.quotaID) != nil)
    }

    @Test("Two accounts on one quota keep separate plans")
    func accountsAreSeparate() async throws {
        let repository = AllocationPlanRepository(store: CodableStore.inMemory())
        let plan = try makePlan(remaining: 60)
        try await repository.save(plan, accountLabel: "one@example.com")
        let other = plan
        try await repository.save(other, accountLabel: "two@example.com")

        let stored = try await repository.all()
        #expect(stored.count == 2)
        #expect(Set(stored.map(\.accountLabel)) == ["one@example.com", "two@example.com"])
    }

    @Test("A stored plan reports whether it still describes the quota")
    func matchesItsInputs() throws {
        let plan = try makePlan(remaining: 60)
        let record = AllocationPlanRecord(
            quotaID: plan.quotaID, accountLabel: "work@example.com", plan: plan
        )
        #expect(record.matches(period: plan.period, totalRemaining: 60))
        #expect(!record.matches(period: plan.period, totalRemaining: 40))
        #expect(!record.matches(period: plan.period, totalRemaining: 60.5))
    }

    @Test("Deleting a quota's plan leaves other quotas alone")
    func deleteIsScoped() async throws {
        let repository = AllocationPlanRepository(store: CodableStore.inMemory())
        let first = try makePlan(remaining: 60)
        let second = try makePlan(remaining: 30)
        try await repository.save(first, accountLabel: "a")
        try await repository.save(second, accountLabel: "a")

        try await repository.delete(quotaID: first.quotaID)

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(all.first?.quotaID == second.quotaID)
    }
}
