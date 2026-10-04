import Platform
import SwiftUI

/// The providers a quota can be created for, one row each.
///
/// Its own view rather than a loop in the flow, because what a row says and
/// whether it can be pressed are two separate questions the flow answers and the
/// list only reports: the list has no opinion about which providers are
/// available, and a list that grew a rule of its own would be a second place
/// where the rule about what can take a quota lives.
struct ProviderChoices: View {
    /// What can be chosen at all, in the order it is offered.
    let listings: [ProviderListing]
    /// Which one is chosen, if any.
    let selectedID: String?
    /// What each row says beside its name.
    let caption: (ProviderListing) -> String
    /// Whether the row can be pressed.
    let isAvailable: (ProviderListing) -> Bool
    let onSelect: (ProviderListing) -> Void

    @State private var searchQuery = ""

    private var filtered: [ProviderListing] {
        ProviderSearch.filter(listings, query: searchQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            ProviderSearchField(query: $searchQuery)
            if filtered.isEmpty {
                Caption(text: ProviderSearch.emptyMessage(query: searchQuery, hasAnyProviders: !listings.isEmpty))
            } else {
                VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                    ForEach(filtered, id: \.id) { listing in
                        row(for: listing)
                    }
                }
            }
        }
    }

    /// Draws one pressable provider row.
    ///
    /// What a row says and whether it can be pressed arrive as closures, so
    /// the flow stays the only place that knows which providers can take a
    /// quota; a list that answered that for itself would be a second copy of
    /// the rule. The selection ring is drawn inside the button for the same
    /// reason: availability and selection are one answer, and a row that
    /// could be ringed but not pressed would report two states at once.
    private func row(for listing: ProviderListing) -> some View {
        let isSelected = selectedID == listing.id
        return Button {
            onSelect(listing)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                    Text(listing.displayName)
                        .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(caption(listing))
                        .font(.system(size: LayoutMetrics.captionSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Text("Selected")
                        .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, LayoutMetrics.inset)
            .padding(.vertical, LayoutMetrics.rowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: LayoutMetrics.selectionRingWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable(listing))
        .opacity(isAvailable(listing) ? 1 : LayoutMetrics.emptyDayOpacity)
    }
}
