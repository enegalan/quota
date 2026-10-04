import AppKit
import Foundation

/// The keyboard shortcuts the settings panel is reachable by.
///
/// The menu is built in code rather than left to the plist because a status-item
/// application has no menu of its own: without one, ⌘-key equivalents are not
/// routed anywhere at all, whatever `Info.plist` claims. The plist still declares
/// them, so the shortcuts are visible to the system and to a reader of the bundle,
/// and `ShortcutTests` checks the two agree.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    ///
    /// Held weakly and set late because the delegate is created by SwiftUI before
    /// the scene is, and a delegate that reached for a model during launch would
    /// be reading a half-built object.
    weak var model: AppModel? {
        didSet {
            if let model {
                backgroundRefresh.start(model: model)
            }
        }
    }

    /// The open-popover action, in charge of turning the status item on and off.
    var onTogglePopover: (() -> Void)?

    private let backgroundRefresh = BackgroundRefreshController()

    /// Shows the Dock icon, without which the management window cannot be
    /// found again.
    ///
    /// Set here rather than in the bundle's declaration because the delegate
    /// is the only part of the app guaranteed to run for a menu-bar-only
    /// launch, and a window opened from a Dock icon that is not there is not
    /// a shortcut anyone can take back.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular policy so the Dock icon can reopen the management window.
        NSApp.setActivationPolicy(.regular)
    }

    /// Treats a second Dock click as a request for the management window.
    ///
    /// Only when nothing is already visible: clicking the icon of an app
    /// whose window is on screen should do what every other app does,
    /// which is bring that window forward — and `NSApp` does that on its
    /// own once the reopen is accepted, so opening a second window here
    /// would be the surprising outcome.
    ///
    /// - Returns: always true, so AppKit treats the reopen as handled and
    ///   leaves the existing windows alone rather than restoring state of
    ///   its own.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            MainWindowOpener.request()
        }
        return true
    }

    /// Installs the menu, the only route a ⌘-key equivalent has here.
    ///
    /// Set before the app finishes launching rather than after: a shortcut
    /// pressed while the window is still opening would otherwise be
    /// dropped, because there is nothing yet for AppKit to route it to.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
    }

    /// Stops the refresh timer before the process goes away.
    ///
    /// The controller holds the model weakly, so nothing leaks without this —
    /// but the tick is the one thing that would wake a terminating process
    /// back up, and there is no work left for it to do.
    func applicationWillTerminate(_ notification: Notification) {
        backgroundRefresh.stop()
    }

    /// The application's menu: the two shortcuts, diagnostics, and a way to quit.
    func makeMenu() -> NSMenu {
        let root = NSMenu()

        let quota = NSMenuItem()
        quota.title = "Quota"
        let quotaMenu = NSMenu()
        quotaMenu.addItem(
            item(
                title: "Open Quota",
                key: Shortcut.openKey,
                action: #selector(openMainWindow),
                keyEquivalent: Shortcut.openKeyEquivalent
            )
        )
        quotaMenu.addItem(
            item(
                title: "Refresh Now",
                key: Shortcut.refreshKey,
                action: #selector(refresh),
                keyEquivalent: Shortcut.refreshKeyEquivalent
            )
        )
        quotaMenu.addItem(
            item(
                title: "Copy Diagnostic Dump",
                key: "Diagnostics",
                action: #selector(copyDiagnostics),
                keyEquivalent: "d"
            )
        )
        quotaMenu.addItem(.separator())
        let quit = item(
            title: "Quit Quota",
            key: Shortcut.quitKey,
            action: #selector(quit),
            keyEquivalent: Shortcut.quitKeyEquivalent
        )
        quit.keyEquivalentModifierMask = Shortcut.quitModifiers
        quotaMenu.addItem(quit)
        quota.submenu = quotaMenu
        root.addItem(quota)

        return root
    }

    /// One menu item, wired to the delegate and carrying ⌘.
    ///
    /// The target is set here rather than left nil because a nil target
    /// routes through the responder chain, and the first thing in that chain
    /// to claim an unrecognised action is whatever view happens to be key —
    /// so the same item would fire from the management window and do nothing
    /// from the menu bar.
    ///
    /// `key` is unused by the item but kept so every caller reads the same
    /// way, naming both the chord it displays and the character AppKit
    /// matches; it is the former the plist and the test compare against.
    private func item(
        title: String,
        key: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = Shortcut.commandModifiers
        return item
    }

    @objc private func openMainWindow() {
        MainWindowOpener.request()
    }

    @objc private func togglePopover() {
        onTogglePopover?()
    }

    @objc private func refresh() {
        guard let model else { return }
        Task { await model.refreshAll() }
    }

    @objc private func copyDiagnostics() {
        guard let model else { return }
        Task {
            let dump = await model.diagnosticDump()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(dump, forType: .string)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// The shortcuts themselves, in one place.
///
/// The plist, the menu, and the test all read these names, so a shortcut cannot
/// be declared in one and spelled differently in another — the failure that
/// makes a documented shortcut do nothing.
enum Shortcut {
    /// ⌘O opens the management window.
    ///
    /// Not ⌘Q, which is Quit everywhere else on the platform, and not ⌘U or ⌘Y,
    /// which other applications use for view-source and undo-history. ⌘O is
    /// unused by any system application.
    static let openKeyEquivalent = "o"
    static let openKey = "⌘O"

    /// ⌘R refreshes.
    ///
    /// The same chord a browser reloads with, which is the word the interface
    /// already uses.
    static let refreshKeyEquivalent = "r"
    static let refreshKey = "⌘R"

    /// ⌘Q quits, and is expected to.
    static let quitKeyEquivalent = "q"
    static let quitKey = "⌘Q"

    /// Every shortcut the app claims, for the test that checks they do not collide.
    static let all: [ShortcutBinding] = [
        ShortcutBinding(key: openKey, keyEquivalent: openKeyEquivalent, modifiers: commandModifierName),
        ShortcutBinding(
            key: refreshKey,
            keyEquivalent: refreshKeyEquivalent,
            modifiers: commandModifierName
        ),
        ShortcutBinding(key: quitKey, keyEquivalent: quitKeyEquivalent, modifiers: commandModifierName),
    ]

    /// The modifier mask as `Info.plist` spells it, so the test can compare the
    /// plist's wording against the code's without a translation table.
    static let commandModifierName = "command"

    /// The modifier every shortcut but Quit carries.
    static let commandModifiers: NSEvent.ModifierFlags = .command

    static let quitModifiers: NSEvent.ModifierFlags = .command
}

/// One shortcut: how it is written, and how the plist spells it.
struct ShortcutBinding: Equatable {
    /// How a menu shows it, such as `⌘R`.
    let key: String
    /// The character AppKit matches, such as `r`.
    let keyEquivalent: String
    /// The modifier mask as `Info.plist` names it.
    let modifiers: String
}
