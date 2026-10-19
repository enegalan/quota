import AppKit
import Platform
import SwiftUI

/// Provider area: installed and available, grouped, with per-provider
/// actions.
///
/// The whole list is rendered from packaged metadata. There is no per-provider
/// conditional anywhere in this file, and there cannot be one: the app does not
/// know which providers exist, and a branch naming one would be a branch that
/// silently omits every provider added after it was written.
struct ProviderManagementView: View {
    let sections: ProviderSections
    let model: AppModel

    /// The removal waiting to be confirmed, and what it would cost.
    ///
    /// The impact is read when the row is tapped rather than when the list is
    /// drawn, so the number in the dialog is the number as it is at the moment
    /// the user decides — a count taken at launch would be a count of a world
    /// that has since changed.
    @State private var pendingRemoval: PendingRemoval?

    /// The provider whose page is open, if one is.
    @State private var opened: ProviderListing?
    @State private var searchQuery = ""

    private var filtered: ProviderSections {
        ProviderSearch.filter(sections, query: searchQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            if let removal = pendingRemoval {
                // Inline rather than `confirmationDialog`: a MenuBarExtra has no
                // real window for a system sheet, so the dialog never appears and
                // Uninstall looks broken.
                UninstallConfirmation(
                    listing: removal.listing,
                    impact: removal.impact,
                    onConfirm: {
                        let listing = removal.listing
                        pendingRemoval = nil
                        Task { await model.uninstall(listing) }
                    },
                    onCancel: { pendingRemoval = nil }
                )
            } else {
                ProviderSearchField(query: $searchQuery)
                listingBody
            }
        }
        .sheet(item: $opened) { listing in
            ProviderDetailSheet(
                providerID: listing.id,
                model: model,
                onUninstall: {
                    opened = nil
                    Task { await askAboutRemoving(listing) }
                }
            )
        }
        .frame(maxWidth: LayoutMetrics.providerListWidth, alignment: .leading)
    }

    @ViewBuilder
    private var listingBody: some View {
        if ProviderSearch.isEmpty(filtered) {
            Caption(
                text: ProviderSearch.emptyMessage(
                    query: searchQuery,
                    hasAnyProviders: !ProviderSearch.isEmpty(sections)
                )
            )
        } else {
            if !filtered.connected.isEmpty {
                group("Connected", listings: filtered.connected)
            }
            if !filtered.installed.isEmpty {
                group("Installed", listings: filtered.installed)
            }
            if !filtered.available.isEmpty {
                group("Available", listings: filtered.available)
            }
        }
    }

    /// One titled run of listings.
    ///
    /// The emptiness check is left to the caller on purpose: which sections may
    /// come back empty without the window looking broken is a decision about the
    /// screen, not about how a group is drawn.
    private func group(_ title: String, listings: [ProviderListing]) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.titleSpacing) {
            HStack(spacing: LayoutMetrics.rowSpacing) {
                SectionTitle(title)
                Text("\(listings.count)")
                    .font(.system(size: LayoutMetrics.captionSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, LayoutMetrics.unit)
                    .padding(.vertical, LayoutMetrics.lineSpacing)
                    .background(Color.primary.opacity(LayoutMetrics.barTrackOpacity))
                    .clipShape(Capsule())
            }
            ForEach(listings) { listing in
                ProviderRow(
                    listing: listing,
                    model: model,
                    onUninstall: { Task { await askAboutRemoving(listing) } },
                    onShowDetails: { opened = listing }
                )
            }
        }
    }

    /// Reads what removing a provider would strand, and offers the dialog.
    ///
    /// A removal nothing depends on is not a decision, so it is not put to the
    /// user as one. A provider with quotas behind it is.
    private func askAboutRemoving(_ listing: ProviderListing) async {
        guard let impact = await model.impact(ofUninstalling: listing) else { return }
        guard impact.needsConfirmation else {
            await model.uninstall(listing)
            return
        }
        pendingRemoval = PendingRemoval(listing: listing, impact: impact)
    }
}

private struct PendingRemoval {
    let listing: ProviderListing
    let impact: UninstallImpact
}

/// One provider, as the packaged metadata describes it.
///
/// Every label here is either from the packaged entry or derived from the
/// provider's state, which is itself derived from what the app knows. A row
/// whose text came from anywhere else would be provider-specific logic in the
/// view layer, which is what forbids.
struct ProviderRow: View {
    let listing: ProviderListing
    let model: AppModel
    let onUninstall: () -> Void
    let onShowDetails: () -> Void

    /// Whether the pointer is over the row, which is how the row answers it.
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.rowSpacing) {
            mark
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.rowSpacing) {
                    Text(listing.displayName)
                        .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                        .lineLimit(1)
                    ProviderStatusPill(state: listing.state)
                }
                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.system(size: LayoutMetrics.captionSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProviderActions(listing: listing, model: model, onUninstall: onUninstall)
            detailsButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
        // The whole card is the way into the provider's page, the mark and the
        // gaps included: a row that only answers in one place is a row the user
        // has to aim at.
        .contentShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius))
        .onTapGesture { onShowDetails() }
        .overlay(hoverOutline)
        .onHover { isHovered = $0 }
    }

    /// The outline the row takes while the pointer is over it.
    ///
    /// A line and not a wash of colour: the row is opened by being pressed, and
    /// the figures on it are the reason it is worth opening.
    private var hoverOutline: some View {
        RoundedRectangle(cornerRadius: LayoutMetrics.cardRadius)
            .strokeBorder(
                Color(nsColor: .controlAccentColor)
                    .opacity(isHovered ? LayoutMetrics.hoverOutlineOpacity : 0),
                lineWidth: 1
            )
            .allowsHitTesting(false)
            .animation(.easeOut(duration: LayoutMetrics.hoverAnimation), value: isHovered)
    }

    /// The provider's mark, on a tile of its own.
    ///
    /// The tile is what gives the row its left edge: a mark floating in the
    /// white of a card has nothing to sit on, and a rounded square is the
    /// shape a user already reads as an icon.
    private var mark: some View {
        ProviderMark(
            providerID: listing.id,
            size: LayoutMetrics.headlineFigureSize,
            fallbackColor: listing.state.tint
        )
        .padding(LayoutMetrics.unit * 2)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius + 2)
                .fill(Color.primary.opacity(LayoutMetrics.hoverTintOpacity * 2))
        )
        .allowsHitTesting(false)
    }

    /// The way into the provider's own page.
    ///
    /// A button and not only a tap on the row, so the page is reachable from
    /// the keyboard and from a screen reader, and so the row says it opens
    /// something rather than looking like a row that happens to be clickable.
    ///
    /// It moves a little to the right under the pointer, the way a disclosure
    /// does in a list: the row answers the pointer without flooding itself with
    /// colour, which is a claim the figures on it do not need to make.
    private var detailsButton: some View {
        Button(action: onShowDetails) {
            Image(systemName: "chevron.right")
                .font(.system(size: LayoutMetrics.captionSize))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .offset(x: isHovered ? LayoutMetrics.unit : 0)
        .animation(.easeOut(duration: LayoutMetrics.hoverAnimation), value: isHovered)
        .help("Show \(listing.displayName) details")
        .accessibilityLabel("Show \(listing.displayName) details")
    }
}
