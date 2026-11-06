import Core
import Foundation

struct UnplannedProvider {
    let providerID: String
    let accountLabel: String
    var snapshot: UsageSnapshot?
    var failed = false
    var orderKey: String { PopoverOrder.key(providerID: providerID, account: accountLabel) }
}

enum PopoverItem: Identifiable {
    case bucket(UsageBucket)
    case quota(QuotaPresentation)

    var id: String {
        switch self {
        case .bucket(let bucket): "bucket:\(bucket.id)"
        case .quota(let quota): "quota:\(quota.id.uuidString)"
        }
    }
}

enum PopoverOrder {
    static func arranged(_ ids: [String], accordingTo saved: [String]) -> [String] {
        let available = Set(ids)
        var seen: Set<String> = []
        return (saved + ids).filter { available.contains($0) && seen.insert($0).inserted }
    }

    static func moving(_ id: String, to target: String, in ids: [String]) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        guard let destination = result.firstIndex(of: target) else { return ids }
        result.insert(id, at: from < to ? destination + 1 : destination)
        return result
    }

    static func key(providerID: String, account: String?) -> String {
        providerID + ":" + Data((account ?? "").utf8).base64EncodedString()
    }
}
