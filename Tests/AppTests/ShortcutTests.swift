import Foundation
import Testing
@testable import App

/// The shortcuts are declared in `Info.plist` and do not collide.
///
/// The clash that matters is not between Quota's own shortcuts — those are checked
/// by construction — but between a shortcut the user already uses elsewhere and
/// one Quota has quietly taken. So the reserved list below is the set System
/// Settings and the common applications claim, and a shortcut landing on one of
/// them fails here rather than in a bug report.
@Suite("Keyboard shortcuts")
struct ShortcutTests {
    /// Chords a user already has bound somewhere that matters.
    ///
    /// Chosen from what the system and the applications a user would have open at
    /// the same time as a menu bar app claim. ⌘Q is here deliberately: Quota uses
    /// it too, and that is correct rather than a clash, because every application
    /// is expected to answer ⌘Q with Quit.
    private static let reserved: Set<String> = [
        "⌘Q", // Quit — universal
        "⌘W", // Close window
        "⌘N", // New
        "⌘T", // New tab
        "⌘M", // Minimise
        "⌘H", // Hide
        "⌘/", // Help
        "⌘,", // Settings
        "⌘U", // View source, in browsers
        "⌘Y", // History, in browsers
        "⌘P", // Print
        "⌘F", // Find
        "⌘S", // Save
        "⌘⇧A", // Dictation
        "⌘⌥I", // Web inspector
        "⌘⌥D", // Dock
        "⌘⇧K", // Emoji and symbols
        "⌃⌘Space", // Input source
        "⌃⌘Q", // Lock screen
        "⌃⌘F", // Toggle full screen
        "⌥⌘E", // Emoji picker
        "⇧⌘3", // Screenshots
        "⇧⌘4", // Screenshots
        "⇧⌘5", // Screenshots
        "F11", // Show desktop
    ]

    @Test("Quota's shortcuts do not take one another or a reserved chord")
    func noClashes() {
        var seen: Set<String> = []
        for shortcut in Shortcut.all {
            #expect(!seen.contains(shortcut.key), "\(shortcut.key) is claimed twice")
            seen.insert(shortcut.key)
        }
        // ⌘Q is exempt because every application answers it with Quit; the rest
        // must avoid the reserved set entirely.
        for shortcut in Shortcut.all where shortcut.key != Shortcut.quitKey {
            #expect(
                !Self.reserved.contains(shortcut.key),
                "\(shortcut.key) is already bound elsewhere"
            )
        }
    }

    @Test("Every shortcut is a command chord, so a bare letter is never swallowed")
    func allUseCommand() {
        for shortcut in Shortcut.all {
            #expect(shortcut.modifiers == "command", "\(shortcut.key) has no modifier")
        }
    }

    @Test("The plist declares the shortcuts the menu installs")
    func plistAgreesWithTheCode() throws {
        let declared = try Self.declaredShortcuts()
        for shortcut in Shortcut.all where shortcut.key != Shortcut.quitKey {
            #expect(
                declared.contains(shortcut.keyEquivalent),
                "\(shortcut.key) is in the code but not in Info.plist"
            )
        }
        // Nothing may be declared in the plist that the code does not install,
        // or the system will offer a shortcut that does nothing.
        for entry in declared {
            #expect(
                Shortcut.all.contains { $0.keyEquivalent == entry },
                "\(entry) is declared in Info.plist but never installed"
            )
        }
    }

    @Test("The plist gives every declared item a command modifier")
    func plistItemsAreModified() throws {
        for item in try Self.declaredMenuItems() {
            #expect(
                item["NSMenuItemKeyEquivalentModifierMask"] as? String == "command",
                "\(item["NSMenuItemTitle"] ?? "?") has no modifier"
            )
            #expect(item["NSMenuItemKeyEquivalent"] is String)
        }
    }

    // MARK: - Reading the bundle

    /// The repository root, derived from this file's own path.
    ///
    /// The shipped `Info.plist` is read from the repository rather than from
    /// `Bundle.main`, because under `swift test` the main bundle is the test
    /// runner and reports nothing about the application. The claim under test is
    /// about the file that gets shipped, so that is the file to read.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root

    /// The key equivalents the plist declares, as AppKit reads them.
    private static func declaredShortcuts() throws -> Set<String> {
        Set(try declaredMenuItems().compactMap { $0["NSMenuItemKeyEquivalent"] as? String })
    }

    private static func declaredMenuItems() throws -> [[String: Any]] {
        let plistURL = repositoryRoot
            .appendingPathComponent("App")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let menu = try #require(plist["NSMainMenu"] as? [String: Any])
        let quota = try #require(menu["Quota"] as? [String: Any])
        return try #require(quota["NSMenuItems"] as? [[String: Any]])
    }
}
