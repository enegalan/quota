import Core
import SwiftUI

/// The form rows for one integration, in the order they are shown.
@MainActor
struct IntegrationLimitItem: Identifiable {
    enum Kind {
        case identity
        case dailyHeader
        case daily(QuotaPresentation)
        case limitsHeader
        case limit(UsageBucket)
        case unavailable
        case noLimits
    }

    let id: String
    let presentation: QuotaPresentation
    let kind: Kind
    /// Extra space above a later integration, so two providers do not read as one list.
    let separates: Bool

    static func rows(
        model: AppModel,
        presentation: QuotaPresentation,
        separates: Bool
    ) -> [IntegrationLimitItem] {
        let slice = IntegrationSlice(model: model, presentation: presentation)
        let prefix = slice.integrationID
        var built = [
            IntegrationLimitItem(
                id: "\(prefix)-identity",
                presentation: presentation,
                kind: .identity,
                separates: separates
            ),
        ]
        guard slice.isShownInMenuBar else { return built }
        if model.menuBarPreferences.showDailyQuota {
            if slice.quotas.count > 1 {
                built.append(item(prefix, "daily-header", presentation, .dailyHeader))
            }
            for quota in slice.quotas {
                built.append(item(prefix, "daily-\(quota.id.uuidString)", presentation, .daily(quota)))
            }
        }
        if model.menuBarPreferences.showAvailableLimits {
            if slice.buckets.isEmpty {
                built.append(item(prefix, "no-limits", presentation, .noLimits))
            } else {
                built.append(item(prefix, "limits-header", presentation, .limitsHeader))
                for bucket in slice.buckets {
                    built.append(item(prefix, "limit-\(bucket.id)", presentation, .limit(bucket)))
                }
            }
            if !slice.unavailable.isEmpty {
                built.append(item(prefix, "unavailable", presentation, .unavailable))
            }
        }
        return built
    }

    /// One row that does not open a gap above it. The identity row is the one
    /// that separates a later integration.
    private static func item(
        _ prefix: String,
        _ suffix: String,
        _ presentation: QuotaPresentation,
        _ kind: Kind
    ) -> IntegrationLimitItem {
        IntegrationLimitItem(
            id: "\(prefix)-\(suffix)",
            presentation: presentation,
            kind: kind,
            separates: false
        )
    }
}
