import Platform
import SwiftUI

/// The actions a provider's state permits, in one place.
///
/// Extracted from the row so the provider's own page can offer the same ones.
/// Actions decided in two places are two sets of buttons that can disagree
/// about what a state permits, and a provider ends up with a Connect button on
/// one screen and not on the other.
struct ProviderActions: View {
    let listing: ProviderListing
    let model: AppModel
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: LayoutMetrics.actionSpacing) {
            if model.isUpdatingAll {
                Text("Updating…")
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(.secondary)
            } else if model.busyProviderID == listing.id {
                Text("Working…")
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(.secondary)
            } else {
                actions
            }
        }
        .font(.system(size: LayoutMetrics.footnoteSize))
    }

    /// The buttons a state offers, in the order they make sense.
    ///
    /// The prerequisite first, because install and connect are the same two
    /// answers wherever they are offered; the states that need no step are then
    /// told apart by what else they offer.
    @ViewBuilder
    private var actions: some View {
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
                Text(listing.state.unavailableLabel)
                    .font(.system(size: LayoutMetrics.captionSize))
                    .foregroundStyle(.secondary)
            default:
                if listing.state.permitsLaunch {
                    uninstallButton
                }
            }
        }
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
}
