import Core
import SwiftUI

/// One quota in the list: its name, whose it is, and how much of it is gone.
///
/// The bar and the account are here so that picking a quota is a decision the
/// list can answer on its own. A list of names makes the user open each quota to
/// find out which one they are looking at, which is the work the list exists to
/// save.
struct QuotaListRow: View {
    let presentation: QuotaPresentation

    private let formatter = PercentageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.unit) {
                Text(presentation.summary.quota.name)
                    .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(formatter.string(presentation.usagePercentage))
                    .font(.system(size: LayoutMetrics.captionSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: LayoutMetrics.unit) {
                ProviderMark(
                    providerID: presentation.summary.quota.providerID.rawValue,
                    size: LayoutMetrics.footnoteSize
                )
                Caption(presentation.accountCaption)
                    .lineLimit(1)
            }
            UsageBar(
                value: presentation.usagePercentage ?? 0,
                maximum: UsageConstants.percentageScale,
                tint: ShareTint.color(for: presentation.usagePercentage, of: UsageConstants.percentageScale)
            )
            .padding(.top, LayoutMetrics.lineSpacing)
        }
        .padding(.vertical, LayoutMetrics.unit)
        .accessibilityElement(children: .combine)
    }
}
