import AppKit
import Core
import Platform
import SwiftUI

/// Quota runs as a menu-bar entry into a management window.
///
/// The status item is the glance surface. Providers, quota creation, the period
/// calendar, and custom policy editing live in the main window, where they have
/// room to work.
@main
struct Main: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var model: AppModel
    @State private var launchFailure: String?

    init() {
        do {
            _model = State(initialValue: AppModel(environment: try AppEnvironment.live()))
        } catch {
            _model = State(initialValue: AppModel(environment: Self.fallback()))
            _launchFailure = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopover(model: model, launchFailure: launchFailure)
                .task {
                    delegate.model = model
                    delegate.onTogglePopover = { togglePopover() }
                    await model.load()
                    await model.refreshOnAppear()
                }
        } label: {
            MenuBarLabel(presentation: model.primaryPresentation)
        }
        .menuBarExtraStyle(.window)

        Window("Quota", id: QuotaWindowID.main) {
            MainWindow(model: model, launchFailure: launchFailure)
        }
        .defaultSize(
            width: LayoutMetrics.mainWindowWidth,
            height: LayoutMetrics.mainWindowHeight
        )
    }

    /// Closes the popover by clicking the status item itself.
    ///
    /// Done through `performClick` rather than by asking SwiftUI to dismiss
    /// it, because the only object that knows whether the popover is showing
    /// is the status item: a dismissal raced against the click that opened
    /// the popover can leave it on screen with no way left to close it.
    private func togglePopover() {
        guard let button = Self.statusBarButton else { return }
        button.performClick(nil)
    }

    private static var statusBarButton: NSStatusBarButton? {
        for window in NSApp.windows where window.level == .statusBar {
            guard let content = window.contentView else { continue }
            for subview in content.subviews {
                if let button = subview as? NSStatusBarButton {
                    return button
                }
            }
        }
        return nil
    }

    /// The environment the app runs in when its own store cannot be opened.
    ///
    /// In memory, with no providers and a fetcher that always fails. The point is
    /// that the app still launches: a store the user cannot reach is a support
    /// question, and the window that explains it has to be the one the user
    /// actually sees.
    ///
    /// Quotas are left empty rather than pre-seeded. Nothing in this environment
    /// survives the session, so a demo quota the user cannot delete would be worse
    /// than an empty list with an error beside it.
    private static func fallback() -> AppEnvironment {
        let store = CodableStore.inMemory()
        return AppEnvironment.preview(
            store: store,
            available: [],
            fetcher: UnavailableFetcher(),
            now: Date()
        )
    }
}

/// The fetcher the fallback environment uses, which reports the store failure.
///
/// Named for what it is rather than for what went wrong. Every read fails
/// with the one message about the data store because that is the actual
/// problem; a plugin that had merely never been installed would name
/// something the user could act on, and here there is nothing to act on.
struct UnavailableFetcher: UsageFetching {
    /// Always a failure carrying the launch error.
    ///
    /// - Returns: an outcome rather than a throw, because a provider being
    /// unreachable is a state the interface shows, not an exceptional
    /// condition every caller has to remember to catch.
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        .failure(
            SyncFailure(
                code: .pluginError,
                message: "Quota could not open its own data store.",
                occurredAt: Date()
            )
        )
    }
}
