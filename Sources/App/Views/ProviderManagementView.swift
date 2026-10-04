import AppKit
import Platform
import SwiftUI

/// Provider area: installed and available, grouped, with per-provider
/// actions.
///
/// The whole list is rendered from catalog metadata. There is no per-provider
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
            SectionTitle(title)
            ForEach(listings) { listing in
                ProviderRow(listing: listing, model: model) {
                    Task { await askAboutRemoving(listing) }
                }
            }
        }
    }

    /// Reads what removing a provider would strand, and offers the dialog.
    ///
    /// A removal nothing depends on is not a decision, so it is not put to
    /// the user as one. A provider with quotas behind it is.
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

/// One provider, as the catalog describes it.
///
/// Every label here is either from the catalog entry or derived from the
/// provider's state, which is itself derived from what the app knows. A row
/// whose text came from anywhere else would be provider-specific logic in the
/// view layer, which is what forbids.
struct ProviderRow: View {
    let listing: ProviderListing
    let model: AppModel
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.rowSpacing) {
                    Text(listing.displayName)
                        .font(.system(size: LayoutMetrics.bodySize, weight: .semibold))
                        .lineLimit(1)
                    statusPill
                }
                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.system(size: LayoutMetrics.captionSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if listing.provider.described != nil { /* no separate unofficial flag now; omitted */ }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: LayoutMetrics.captionSize, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, LayoutMetrics.unit)
            .padding(.vertical, LayoutMetrics.lineSpacing)
            .background(Color.primary.opacity(LayoutMetrics.barTrackOpacity))
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
    }

    private var actions: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            if model.busyProviderID == listing.id {
                Text("Working…")
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(.secondary)
            } else {
                // The prerequisite first, because install and connect are the
                // same two answers wherever they are offered; the states that
                // need no step are then told apart by what else they offer.
                switch listing.state.prerequisite {
                case .installation:
                    installButton
                case .authentication:
                    connectButton
                    uninstallButton
                case .none:
                    switch listing.state {
                    case .updateAvailable, .updateFailed:
                        updateButton
                        uninstallButton
                    case .connected:
                        disconnectButton
                        uninstallButton
                    case .incompatible, .missing, .disabled:
                        Text(unavailableLabel)
                            .font(.system(size: LayoutMetrics.captionSize))
                            .foregroundStyle(.secondary)
                    default:
                        if listing.state.permitsLaunch {
                            uninstallButton
                        }
                    }
                }
            }
        }
        .font(.system(size: LayoutMetrics.footnoteSize))
    }

    /// Each action the row can offer, written once.
    ///
    /// They were inline in five branches of the switch above, each repeating the
    /// same style pair, so a button's appearance and its action could disagree
    /// between two states that both offer it.
    private var installButton: some View {
        Button("Install") {
            Task { await model.install(listing) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var updateButton: some View {
        Button("Update") {
            Task { await model.update(listing) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var disconnectButton: some View {
        Button("Disconnect") {
            Task { await model.disconnect(providerID: listing.id) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Named "Reconnect" once there is an account to reconnect to: a button
    /// reading Connect on a provider that was signed in yesterday is asking the
    /// user to do something they already did.
    private var connectButton: some View {
        Button(listing.state == .authRequired || listing.state == .authExpired
            ? "Reconnect"
            : "Connect")
        {
            Task { await model.connect(providerID: listing.id) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    /// The one destructive action, written once.
    ///
    /// Five branches of the switch above offered it, so a provider state added
    /// later had to remember it — and one that forgot would leave a user able to
    /// install a provider with no way to remove it.
    private var uninstallButton: some View {
        Button("Uninstall", role: .destructive, action: onUninstall)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var statusLabel: String {
        switch listing.state {
        case .notInstalled: "Available"
        case .installing: "Installing"
        case .installed: "Installed"
        case .connected: "Connected"
        case .synchronizing: "Syncing"
        case .installationFailed: "Install failed"
        case .authRequired: "Sign in required"
        case .authExpired: "Session expired"
        case .updateAvailable: "Update available"
        case .updating: "Updating"
        case .updateFailed: "Update failed"
        case .disabled: "Disabled"
        case .incompatible: "Incompatible"
        case .missing: "Missing"
        }
    }

    private var unavailableLabel: String {
        switch listing.state {
        case .incompatible: "Needs a newer Quota"
        case .missing: "Not installed"
        case .disabled: "Integration disabled"
        default: ""
        }
    }
}
