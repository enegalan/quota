import Core
import Platform
import SwiftUI

/// One provider's page: what it is, what it offers, and what reads it.
///
/// Everything on it comes from the provider's own answers and from what the app
/// has recorded about it, so the page reads the same for every provider: there
/// is no branch here that names one.
struct ProviderDetailView: View {
    let detail: ProviderDetail
    let model: AppModel
    let onUninstall: () -> Void

    private let formatter = PercentageFormatter()

    var body: some View {
        ScrollView {
            content
        }
    }

    /// The page itself, without the scroll view around it.
    ///
    /// Separate because a sheet wants the content and the scroll view is the
    /// window's business: a renderer asked for the whole view would draw
    /// nothing at all, and a picture of the page is worth having.
    var content: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            header
            status
            pools
        }
        .padding(LayoutMetrics.windowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
            HStack(alignment: .center, spacing: LayoutMetrics.rowSpacing) {
                ProviderMark(
                    providerID: detail.id,
                    size: LayoutMetrics.headlineFigureSize,
                    fallbackColor: detail.state.tint
                )
                VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                    Text(detail.displayName)
                        .font(.system(size: LayoutMetrics.headlineFigureSize, weight: .semibold))
                    if !detail.summary.isEmpty {
                        Text(detail.summary)
                            .font(.system(size: LayoutMetrics.footnoteSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: LayoutMetrics.rowSpacing)
                ProviderStatusPill(state: detail.state)
            }
            ProviderActions(listing: detail.listing, model: model, onUninstall: onUninstall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    // MARK: Sections

    private var status: some View {
        SectionCard("Status") {
            VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                DetailRow(label: "State", value: detail.state.statusLabel)
                DetailRow(
                    label: "Account",
                    value: detail.accountLabel ?? QuotaPresentation.disconnectedAccountCaption
                )
                DetailRow(label: "Last update", value: detail.syncCaption)
                DetailRow(label: "Version", value: detail.versionCaption)
                if let speaks = detail.protocolCaption {
                    DetailRow(label: "Protocol", value: speaks)
                }
                if let refresh = detail.refreshCaption {
                    DetailRow(label: "Refresh", value: refresh)
                }
                if let failure = detail.failureCaption {
                    Caption(text: failure, isWarning: true)
                }
            }
        }
    }

    private var pools: some View {
        SectionCard("Limits") {
            if detail.pools.isEmpty {
                Caption(text: "No reading yet.")
            } else {
                VStack(alignment: .leading, spacing: LayoutMetrics.rowSpacing) {
                    ForEach(detail.pools) { pool in
                        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(pool.name)
                                    .font(.system(size: LayoutMetrics.footnoteSize, weight: .medium))
                                Spacer(minLength: LayoutMetrics.rowSpacing)
                                Text(formatter.string(pool.usagePercentage))
                                    .font(.system(size: LayoutMetrics.footnoteSize))
                                    .monospacedDigit()
                            }
                            if let reset = pool.resetCaption {
                                Caption(text: reset)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A label and the value it describes, in one row.
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.rowSpacing) {
            Text(label)
                .font(.system(size: LayoutMetrics.footnoteSize))
                .foregroundStyle(.secondary)
            Spacer(minLength: LayoutMetrics.rowSpacing)
            Text(value)
                .font(.system(size: LayoutMetrics.footnoteSize))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The provider's page, in a sheet, loaded when it opens.
///
/// The page is built from what the app has stored, so opening it is a read of
/// the store rather than a request to the provider — and a provider that
/// cannot be reached has a page too, saying so.
struct ProviderDetailSheet: View {
    /// The provider whose page is open.
    ///
    /// The identifier and not the listing the page was opened with: that
    /// listing is a fact about the moment the page opened, and an update
    /// changes it — the version, the state, the account — while the page is on
    /// screen. The page is about the provider, and the provider is the one the
    /// app knows about now.
    let providerID: String
    let model: AppModel
    let onUninstall: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ProviderDetail?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    ProviderDetailView(
                        detail: detail,
                        model: model,
                        onUninstall: onUninstall
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(detail?.displayName ?? listing?.displayName ?? "")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(
            minWidth: LayoutMetrics.sheetWidth,
            idealWidth: LayoutMetrics.sheetWidth,
            maxWidth: LayoutMetrics.sheetWidth,
            maxHeight: LayoutMetrics.sheetMaxHeight,
            alignment: .top
        )
        // Keyed by the load that has just finished, not by the instant the load
        // started: a reload that runs while the load is still reading reads what
        // was there before it, and the page would show the state its own action
        // had just replaced — which is what made an update inside this page look
        // as though it had done nothing.
        .task(id: model.loadGeneration) {
            await reload()
        }
    }

    /// The provider as the app knows it now.
    private var listing: ProviderListing? {
        model.sections.listing(id: providerID)
    }

    /// Reads the page again from the store.
    ///
    /// The old figures stay on screen until the new ones arrive, so a reload
    /// does not blank the page while it happens.
    private func reload() async {
        guard let listing else { return }
        detail = await model.providerDetail(for: listing)
    }
}
