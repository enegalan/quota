import Foundation
import Testing
@testable import Core

@Suite("Quota")
struct QuotaTests {
    private func makeQuota(bucketID: String? = nil) throws -> Quota {
        try Quota(
            name: "Cursor",
            providerID: ProviderID("mock"),
            bucketID: bucketID,
            period: quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            policy: .even,
            createdAt: quotaInstant(2026, 9, 1),
            updatedAt: quotaInstant(2026, 9, 1)
        )
    }

    @Test("A quota with no bucket reference is valid")
    func allowsMissingBucket() throws {
        #expect(try makeQuota().bucketID == nil)
    }

    @Test("A quota rejects a blank bucket reference")
    func rejectsBlankBucket() throws {
        #expect(throws: QuotaDomainError.self) { try makeQuota(bucketID: "") }
        #expect(throws: QuotaDomainError.self) { try makeQuota(bucketID: "has space") }
    }

    /// The deliberate deviation from . lists
    /// `currentUsagePercentage` and `usageUpdatedAt` among a quota's fields;
    /// require actual usage to stay separate from planned
    /// allocation. This test is the assertion of that choice, and it fails if
    /// somebody later adds the fields back.
    @Test("A quota stores no usage figure and no reading timestamp")
    func storesNoUsage() throws {
        let encoded = try JSONEncoder().encode(makeQuota())
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("currentUsagePercentage"))
        #expect(!json.contains("usageUpdatedAt"))
        #expect(!json.contains("usagePercentage"))
    }

    @Test("A quota round trips through Codable")
    func codableRoundTrip() throws {
        let quota = try makeQuota(bucketID: "models")
        let data = try JSONEncoder().encode(quota)
        #expect(try JSONDecoder().decode(Quota.self, from: data) == quota)
    }
}

@Suite("QuotaSummary")
struct QuotaSummaryTests {
    private func makeQuota(bucketID: String? = nil) throws -> Quota {
        try Quota(
            name: "Cursor",
            providerID: try ProviderID("mock"),
            bucketID: bucketID,
            period: try quotaPeriod(from: "2026-09-01", to: "2026-09-30"),
            policy: .even,
            createdAt: quotaInstant(2026, 9, 1),
            updatedAt: quotaInstant(2026, 9, 1)
        )
    }

    private func makeSnapshot(at updatedAt: Date, models: Double) throws -> UsageSnapshot {
        let window = try quotaPeriod(from: "2026-09-01", to: "2026-09-30")
        return try UsageSnapshot(
            updatedAt: updatedAt,
            buckets: [
                try UsageBucket(
                    id: "models", displayName: "Models", usagePercentage: models, period: window
                ),
                try UsageBucket(
                    id: "other", displayName: "Other", usagePercentage: 1, period: window
                ),
            ]
        )
    }

    @Test("A summary without a snapshot resolves to no usage")
    func withoutSnapshot() throws {
        let quota = try makeQuota()
        let summary = QuotaSummary(quota: quota)
        #expect(summary.usage == nil)
        #expect(summary.snapshot == nil)
    }

    @Test("A quota with no bucket reference reads the primary bucket")
    func readsPrimaryBucket() throws {
        let snapshot = try makeSnapshot(at: quotaInstant(2026, 9, 15), models: 30)
        let quota = try makeQuota()
        let summary = QuotaSummary(quota: quota, snapshot: snapshot)
        #expect(summary.usage?.id == "models")
        #expect(summary.usage?.usagePercentage == 30)
    }

    @Test("A quota naming a bucket reads that bucket, not the primary one")
    func readsNamedBucket() throws {
        let snapshot = try makeSnapshot(at: quotaInstant(2026, 9, 15), models: 30)
        let quota = try makeQuota(bucketID: "other")
        let summary = QuotaSummary(quota: quota, snapshot: snapshot)
        #expect(summary.usage?.id == "other")
        #expect(summary.usage?.usagePercentage == 1)
    }

    @Test("A reading younger than the threshold is not stale")
    func freshReading() throws {
        let now = try quotaInstant(2026, 9, 15, hour: 12)
        let snapshot = try makeSnapshot(at: now.addingTimeInterval(-60), models: 30)
        let quota = try makeQuota()
        let summary = QuotaSummary(quota: quota, snapshot: snapshot)
        #expect(summary.isOutOfDate(asOf: now) == false)
    }

    @Test("A reading older than the threshold is stale")
    func staleReading() throws {
        let now = try quotaInstant(2026, 9, 15, hour: 12)
        let snapshot = try makeSnapshot(at: now.addingTimeInterval(-3600), models: 30)
        let quota = try makeQuota()
        let summary = QuotaSummary(quota: quota, snapshot: snapshot)
        #expect(summary.isOutOfDate(asOf: now))
    }

    @Test("A summary with no reading is not called stale")
    func absenceIsNotStaleness() throws {
        let quota = try makeQuota()
        // Hoisted: `try` does not cross the autoclosure `#expect` expands to.
        let now = try quotaInstant(2026, 9, 15, hour: 12)
        let summary = QuotaSummary(quota: quota)
        #expect(summary.isOutOfDate(asOf: now) == false)
    }

    @Test("A quota whose bucket the reading no longer carries names it")
    func unavailableBucket() throws {
        let updated = try quotaInstant(2026, 9, 15, hour: 12)
        let onlyOther = try UsageSnapshot(
            updatedAt: updated,
            buckets: [
                try UsageBucket(
                    id: "other", displayName: "Other", usagePercentage: 1,
                    period: quotaPeriod(from: "2026-09-01", to: "2026-09-30")
                ),
            ]
        )
        let summary = QuotaSummary(quota: try makeQuota(bucketID: "models"), snapshot: onlyOther)

        #expect(summary.usage == nil)
        #expect(summary.unavailableBucketID == "models")
    }

    @Test("A quota reading the primary is never waiting for a bucket")
    func primaryBucketCannotBeUnavailable() throws {
        let updated = try quotaInstant(2026, 9, 15, hour: 12)
        let snapshot = try makeSnapshot(at: updated, models: 30)
        // Both the unnamed quota and one naming the primary resolve to a bucket
        // the reading has, so neither is reported as waiting.
        #expect(QuotaSummary(quota: try makeQuota(), snapshot: snapshot).unavailableBucketID == nil)
        #expect(
            QuotaSummary(quota: try makeQuota(bucketID: "models"), snapshot: snapshot)
                .unavailableBucketID == nil
        )
    }

    @Test("A quota never read is not waiting for a bucket")
    func noReadingIsNotAWaitingBucket() throws {
        let summary = QuotaSummary(quota: try makeQuota(bucketID: "models"))
        #expect(summary.unavailableBucketID == nil)
    }
}
