import Core
import Foundation

struct PopoverProviderGroup: Identifiable {
    struct Identity: Hashable {
        let providerID: String
        let accountLabel: String?
    }

    let id: Identity
    var presentations: [QuotaPresentation]
    var unplanned: UnplannedProvider?

    var providerID: String {
        id.providerID
    }

    var accountLabel: String? {
        id.accountLabel
    }

    var orderKey: String {
        PopoverOrder.key(providerID: providerID, account: accountLabel)
    }

    var latestPresentation: QuotaPresentation? {
        presentations
            .max { ($0.summary.snapshot?.updatedAt ?? .distantPast) < ($1.summary.snapshot?.updatedAt ?? .distantPast) }
    }

    var snapshot: UsageSnapshot? {
        latestPresentation?.summary.snapshot ?? unplanned?.snapshot
    }

    func quotas(for bucketID: String) -> [QuotaPresentation] {
        presentations.filter { ($0.summary.quota.bucketID ?? $0.summary.snapshot?.primaryBucket?.id) == bucketID }
    }

    var unmatchedQuotas: [QuotaPresentation] {
        presentations.filter { presentation in
            let bucketID = presentation.summary.quota.bucketID ?? presentation.summary.snapshot?.primaryBucket?.id
            return !((snapshot?.buckets ?? []).contains { $0.id == bucketID })
        }
    }

    static func group(
        _ presentations: [QuotaPresentation],
        unplanned: [UnplannedProvider] = []
    ) -> [PopoverProviderGroup] {
        var groups: [PopoverProviderGroup] = []
        for presentation in presentations {
            let id = Identity(
                providerID: presentation.summary.quota.providerID.rawValue,
                accountLabel: presentation.accountLabel
            )
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].presentations.append(presentation)
            } else {
                groups.append(PopoverProviderGroup(id: id, presentations: [presentation]))
            }
        }
        for provider in unplanned {
            let id = Identity(providerID: provider.providerID, accountLabel: provider.accountLabel)
            guard !groups.contains(where: { $0.id == id }) else { continue }
            groups.append(PopoverProviderGroup(id: id, presentations: [], unplanned: provider))
        }
        return groups
    }
}
