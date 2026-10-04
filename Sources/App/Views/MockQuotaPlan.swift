import Core
import Foundation
import Platform

/// One quota a mock world is built from.
///
/// The plan is the whole arrangement of a quota: who meters it, what it is
/// called, which account, and how much of it is spent. Written as a value rather
/// than as a function with a level parameter so a world with several quotas is a
/// list of them and a world with one is a list of one — the same code builds
/// both, and a two-quota arrangement is a second entry rather than a second
/// arrangement.
struct MockQuotaPlan {
    let providerID: String
    let providerName: String
    let bucketID: String
    let account: String
    let quotaName: String
    let level: MockUsageLevel

    /// The single quota the level worlds have always had.
    ///
    /// The values it carries are the ones `MockUsageWorld` published, unchanged,
    /// so a snapshot of one level is the same picture it was before a world of
    /// several quotas existed.
    static func mock(level: MockUsageLevel) -> MockQuotaPlan {
        MockQuotaPlan(
            providerID: MockUsageWorld.providerID,
            providerName: MockUsageWorld.providerName,
            bucketID: MockUsageWorld.bucketID,
            account: MockUsageWorld.account,
            quotaName: MockUsageWorld.quotaName,
            level: level
        )
    }

    /// Several quotas, one per provider, at levels chosen to be told apart.
    ///
    /// Under, on pace, and over, so the rows are three different stories rather
    /// than three copies of one: a list whose rows are indistinguishable is a
    /// list that cannot be used to pick anything.
    static let several: [MockQuotaPlan] = [
        MockQuotaPlan.mock(level: .onPace),
        MockQuotaPlan(
            providerID: "quota.mock.second",
            providerName: "Second Provider",
            bucketID: "usage",
            account: "second@example.com",
            quotaName: "Second Quota",
            level: .over
        ),
        MockQuotaPlan(
            providerID: "quota.mock.third",
            providerName: "Third Provider",
            bucketID: "usage",
            account: "third@example.com",
            quotaName: "Third Quota",
            level: .under
        ),
    ]

    /// The quota this plan describes, over the mock world's month.
    func quota() throws -> Quota {
        try Quota(
            name: quotaName,
            providerID: try ProviderID(providerID),
            bucketID: bucketID,
            period: try QuotaPeriod.month(containing: MockUsageWorld.reference, calendar: MockUsageWorld.calendar),
            policy: .even,
            createdAt: MockUsageWorld.reference,
            updatedAt: MockUsageWorld.reference
        )
    }
}
