import Foundation
import Testing
@testable import Core

@Suite("UsageSnapshot")
struct UsageSnapshotTests {
    private func window() throws -> QuotaPeriod {
        try quotaPeriod(from: "2026-09-01", to: "2026-09-30")
    }

    private func bucket(_ id: String, _ percentage: Double) throws -> UsageBucket {
        try UsageBucket(
            id: id, displayName: id, usagePercentage: percentage, period: window()
        )
    }

    private func snapshot(_ buckets: [UsageBucket], updatedAt: Date? = nil) throws -> UsageSnapshot {
        try UsageSnapshot(
            updatedAt: updatedAt ?? quotaInstant(2026, 9, 15, hour: 12),
            buckets: buckets
        )
    }

    @Test("A snapshot with no buckets is rejected")
    func rejectsEmptyBuckets() throws {
        #expect(throws: QuotaDomainError.self) { try snapshot([]) }
    }

    @Test("Duplicate bucket identifiers are rejected and the collision is named")
    func rejectsDuplicateBuckets() throws {
        let buckets = try [
            bucket("models", 10),
            bucket("other", 20),
            bucket("models", 30),
        ]
        do {
            _ = try snapshot(buckets)
            Issue.record("expected a duplicateBucketID error")
        } catch let error as QuotaDomainError {
            guard case .duplicateBucketID(let id) = error else {
                Issue.record("expected duplicateBucketID, got \(error)")
                return
            }
            #expect(id == "models")
        }
    }

    @Test("The primary bucket is the first one, not the largest")
    func primaryBucketIsFirst() throws {
        let value = try snapshot([
            bucket("small", 1),
            bucket("large", 99),
        ])
        #expect(value.primaryBucket?.id == "small")
    }

    @Test("A bucket lookup falls back to the primary one")
    func bucketLookup() throws {
        let value = try snapshot([
            bucket("models", 10),
            bucket("other", 20),
        ])
        #expect(value.bucket(id: "other")?.usagePercentage == 20)
        #expect(value.bucket(id: nil)?.id == "models")
        #expect(value.bucket(id: "absent") == nil)
    }

    @Test("Remaining percentage is the complement of usage")
    func remainingPercentage() throws {
        #expect(try snapshot([bucket("a", 25)]).remainingPercentage == 75)
        #expect(try snapshot([bucket("a", 0)]).remainingPercentage == 100)
        #expect(try snapshot([bucket("a", 100)]).remainingPercentage == 0)
    }

    @Test("Decoding rejects a snapshot with duplicate buckets")
    func decodingValidates() throws {
        let json = """
        {"updatedAt":1757956800,
         "buckets":[
           {"id":"a","displayName":"A","usagePercentage":1.0,
            "period":{"start":1756684800,"end":1759190399}},
           {"id":"a","displayName":"A","usagePercentage":2.0,
            "period":{"start":1756684800,"end":1759190399}}]}
        """
        #expect(throws: QuotaDomainError.self) {
            try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test("A snapshot round trips through Codable")
    func codableRoundTrip() throws {
        let value = try snapshot([
            bucket("models", 10.5),
            bucket("other", 20.25),
        ])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == value)
    }
}
