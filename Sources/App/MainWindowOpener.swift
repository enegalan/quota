import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the management window should appear (menu, Dock, or popover).
    static let openMainWindow = Notification.Name("QuotaOpenMainWindow")
}

/// Brings the management window forward after SwiftUI creates or reveals it.
enum MainWindowOpener {
    /// Asks for the window from whoever cannot open it directly.
    ///
    /// A notification rather than a direct call because the menu and the Dock
    /// both live in `AppDelegate`, which is created before the SwiftUI scene
    /// and so has no `OpenWindowAction` to hand.
    ///
    /// Existing management windows are revealed here: a Dock click must not
    /// wait on SwiftUI when the window is only miniaturised or ordered out.
    @MainActor
    static func request() {
        let existing = NSApp.windows.filter(isManagementWindow)
        if !existing.isEmpty {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for window in existing {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    /// Whether a titled management window is already on screen.
    ///
    /// Used instead of AppKit's `hasVisibleWindows`: that flag is true for the
    /// MenuBarExtra panel alone, so a Dock click would otherwise only activate
    /// the app and never reopen the dashboard.
    @MainActor
    static func hasVisibleManagementWindow() -> Bool {
        NSApp.windows.contains { window in
            isManagementWindow(window) && window.isVisible && !window.isMiniaturized
        }
    }

    /// Opens the management window and puts it in front.
    ///
    /// Activation is explicit because a window opened from a menu bar item
    /// does not come forward by itself: the app that stays active is the one
    /// the shortcut was sent from, and the window would open behind it.
    ///
    /// The window is then ordered to the front twice — once now, for a window
    /// SwiftUI has already created, and once after the delay, for one it has
    /// not, since `openWindow` returns before the window exists.
    @MainActor
    static func open(using openWindow: OpenWindowAction) {
        openWindow(id: QuotaWindowID.main)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            frontMostQuotaWindow()
        }
        // A second pass after SwiftUI has had time to materialise a new window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            frontMostQuotaWindow()
        }
    }

    /// Orders every management window to the front.
    ///
    /// All of them rather than the first: a second window opened from the
    /// Dock while the first is minimised should be revealed by the same
    /// click, and stopping at one would leave the other behind what the user
    /// had just sent away.
    @MainActor
    private static func frontMostQuotaWindow() {
        for window in NSApp.windows where isManagementWindow(window) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Titled document windows only — not the MenuBarExtra panel.
    @MainActor
    private static func isManagementWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return window.level == .normal
    }
}

/// Forwards Dock / menu open requests from a view that stays mounted.
///
/// The MenuBarExtra label is always in the hierarchy; the popover content is
/// not. Listening here is what makes `MainWindowOpener.request()` reach
/// `openWindow` before the user has ever opened the status item.
struct MainWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                MainWindowOpener.open(using: openWindow)
            }
    }
}
