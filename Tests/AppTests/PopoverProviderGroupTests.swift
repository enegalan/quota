import Core
import Foundation
import Testing
@testable import App

@Suite("Popover provider grouping")
struct PopoverProviderGroupTests {
    @Test("A connected provider without a quota has its own overview group")
    func includesProviderWithoutQuota() {
        let provider = UnplannedProvider(providerID: "claude", accountLabel: "account")
        let groups = PopoverProviderGroup.group([], unplanned: [provider, provider])
        #expect(groups.count == 1)
        #expect(groups[0].providerID == "claude")
        #expect(groups[0].accountLabel == "account")
        #expect(groups[0].presentations.isEmpty)
        #expect(groups[0].orderKey == provider.orderKey)
    }
    @Test("Quotas stay with their provider, account, and reported limit")
    func groupsQuotasByLimit() throws {
        let now = MockUsageWorld.reference
        let period = try QuotaPeriod.month(containing: now, calendar: MockUsageWorld.calendar)
        let buckets = try ["plan", "api"].map {
            try UsageBucket(id: $0, displayName: $0, usagePercentage: 20, period: period)
        }
        let snapshot = try UsageSnapshot(updatedAt: now, buckets: buckets)
        func presentation(_ name: String, _ bucket: String, _ account: String) throws -> QuotaPresentation {
            let quota = try Quota(
                name: name, providerID: ProviderID("cursor"), bucketID: bucket,
                period: period, policy: .even, createdAt: now, updatedAt: now
            )
            return QuotaPresentation(summary: QuotaSummary(quota: quota, snapshot: snapshot), accountLabel: account)
        }
        let plan = try presentation("Plan", "plan", "one")
        let api = try presentation("API", "api", "one")
        let missing = try presentation("Missing", "missing", "one")
        let otherAccount = try presentation("Other", "plan", "two")
        let groups = PopoverProviderGroup.group([plan, api, missing, otherAccount])

        #expect(groups.count == 2)
        #expect(groups[0].quotas(for: "plan").map(\.id) == [plan.id])
        #expect(groups[0].quotas(for: "api").map(\.id) == [api.id])
        #expect(groups[0].unmatchedQuotas.map(\.id) == [missing.id])
        #expect(groups[1].quotas(for: "plan").map(\.id) == [otherAccount.id])
    }
}
