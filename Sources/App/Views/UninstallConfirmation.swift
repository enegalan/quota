import AppKit
import Platform
import SwiftUI

/// Uninstall confirmation: what is affected, and what happens to it.
///
/// The count is the point of the dialog. A provider can back several quotas, and
/// a user who removes one without being told would come back to find their
/// quotas still listed with numbers that will never update again — the app would
/// be showing a plan derived from a provider it can no longer ask.
struct UninstallConfirmation: View {
    let listing: ProviderListing
    let impact: UninstallImpact
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NoticeCard(title: "Uninstall \(listing.displayName)?", message: consequence) {
            HStack(spacing: LayoutMetrics.actionSpacing) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Uninstall", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
    }

    /// What removing this provider does to the user's data.
    ///
    /// Says the readings are kept, because they are: the quotas stay, and a quota
    /// naming a provider that is no longer installed is a state the app knows how
    /// to show. A dialog that implied the history would be deleted would push
    /// users into keeping a provider they meant to remove.
    private var consequence: String {
        switch impact.unrefreshableCount {
        case 0:
            "This provider is not used by any quota."
        case 1:
            "One quota will stop updating. Its last reading is kept."
        default:
            "\(impact.unrefreshableCount) quotas will stop updating. Their last readings are kept."
        }
    }
}
