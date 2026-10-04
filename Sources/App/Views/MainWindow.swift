import AppKit
import Core
import Platform
import SwiftUI

/// Window identifiers the menu bar and the main window share.
enum QuotaWindowID {
    static let main = "main"
}

/// The management window: quotas, providers, create flow, calendar, policy.
///
/// Editing lives here rather than in the menu-bar popover: a status item has no
/// room for a period calendar or a custom policy, and stuffing them in made both
/// unusable.
///
/// Three columns, each answering one question: what exists, what is selected, and
/// everything there is to say about it. The quota list carries a bar and an
/// account for each quota because choosing between four quotas by name alone
/// means opening each one to find out which is which.
struct MainWindow: View {
    let model: AppModel
    let launchFailure: String?

    enum SidebarItem: Hashable {
        case quotas
        case providers
    }

    @State private var sidebar: SidebarItem = .quotas
    @State private var selectedQuotaID: UUID?
    @State private var isCreating = false

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Label("Quotas", systemImage: "chart.bar")
                    .tag(SidebarItem.quotas)
                Label("Providers", systemImage: "puzzlepiece.extension")
                    .tag(SidebarItem.providers)
            }
            .navigationTitle("Quota")
            .frame(minWidth: LayoutMetrics.sidebarWidth)
        } detail: {
            Group {
                if let launchFailure {
                    LaunchFailureView(message: launchFailure)
                } else {
                    switch sidebar {
                    case .quotas:
                        quotasDetail
                    case .providers:
                        providersDetail
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                QuotaCreationFlow(model: model)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isCreating = false }
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
            .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var quotasDetail: some View {
        if model.presentations.isEmpty {
            ContentUnavailableView {
                Label("No Quotas", systemImage: "chart.bar")
            } description: {
                Text("Create a quota after connecting a provider.")
            } actions: {
                Button {
                    isCreating = true
                } label: {
                    Label("Add Quota", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                quotaList
                    .frame(
                        minWidth: LayoutMetrics.quotaListWidth,
                        maxWidth: LayoutMetrics.quotaListWidth * 1.5
                    )
                detail
                    .frame(minWidth: LayoutMetrics.detailMinWidth)
            }
            .toolbar { quotaToolbar }
            .onAppear {
                if selectedQuotaID == nil {
                    selectedQuotaID = model.presentations.first?.id
                }
            }
            .onChange(of: model.presentations.map(\.id)) { _, ids in
                if let selectedQuotaID, !ids.contains(selectedQuotaID) {
                    self.selectedQuotaID = ids.first
                } else if selectedQuotaID == nil {
                    selectedQuotaID = ids.first
                }
            }
        }
    }

    private var quotaList: some View {
        List(selection: $selectedQuotaID) {
            ForEach(model.presentations) { presentation in
                QuotaListRow(presentation: presentation)
                    .tag(presentation.id)
            }
        }
        .listStyle(.sidebar)
    }

    /// The toolbar's refresh, written once.
    ///
    /// It was written twice in this file, and the two were free to drift: a
    /// refresh the quota list offers and a refresh the providers pane offers
    /// have to be the same action with the same shortcut, or ⌘R means one thing
    /// on one tab and another on the next.
    private var refreshButton: some View {
        Button {
            Task { await model.refreshAll() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.isRefreshing)
        .help("Ask every provider for a new reading (⌘R)")
    }

    @ToolbarContentBuilder
    private var quotaToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            refreshButton
            Button {
                isCreating = true
            } label: {
                Label("Add Quota", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Create a quota (⌘N)")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let presentation = selectedPresentation {
            ScrollView {
                QuotaDetailView(
                    presentation: presentation,
                    calendar: model.calendar(for: presentation),
                    calendarGrid: model.userCalendar,
                    reference: model.reference,
                    model: model
                )
                .padding(LayoutMetrics.windowPadding)
            }
        } else {
            ContentUnavailableView("Select a quota", systemImage: "chart.bar")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedPresentation: QuotaPresentation? {
        guard let selectedQuotaID else { return model.presentations.first }
        return model.presentations.first { $0.id == selectedQuotaID }
    }

    private var providersDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Providers")
                    .font(.title2.weight(.semibold))
                ProviderManagementView(sections: model.sections, model: model)
                if let lastError = model.lastError {
                    ErrorBanner(message: lastError)
                }
            }
            .padding(LayoutMetrics.windowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                refreshButton
            }
        }
    }
}
