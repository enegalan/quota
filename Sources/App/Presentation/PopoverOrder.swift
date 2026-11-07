import Core
import Foundation

struct UnplannedIntegration {
    let integrationID: String
    let accountLabel: String
    var snapshot: UsageSnapshot?
    var failed = false
    var orderKey: String {
        PopoverOrder.key(integrationID: integrationID, account: accountLabel)
    }
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
    /// Saved order first, then any new ids in the order they arrived.
    static func arranged(_ ids: [String], accordingTo saved: [String]) -> [String] {
        let available = Set(ids)
        var seen: Set<String> = []
        return (saved + ids).filter { available.contains($0) && seen.insert($0).inserted }
    }

    /// Moves `id` to sit after `target` when dragged down, or before it when dragged up.
    static func moving(_ id: String, to target: String, in ids: [String]) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        guard let destination = result.firstIndex(of: target) else { return ids }
        result.insert(id, at: from < to ? destination + 1 : destination)
        return result
    }

    /// Stable key for one integration account across the popover and menu bar.
    static func key(integrationID: String, account: String?) -> String {
        integrationID + ":" + Data((account ?? "").utf8).base64EncodedString()
    }
}
