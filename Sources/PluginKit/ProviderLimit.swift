import Foundation

/// One limit an integration meters, including limits the latest reading omitted.
///
/// Declared by the integration and sent with `describe`. The host does not keep
/// a catalogue of its own: a limit this build has never heard of is still a
/// limit, and a limit removed from an integration disappears with it.
public struct ProviderLimit: Codable, Sendable, Equatable, Identifiable {
    public let id: String

    /// The name shown in settings.
    public let name: String

    /// The name shown in the menu bar. The full name when the integration has
    /// no shorter one.
    public let menuBarLabel: String

    /// Shown in the menu bar as an unknown figure when the latest reading omits
    /// it, until the user hides it.
    public let shownWhenUnavailable: Bool

    public init(
        id: String,
        name: String,
        menuBarLabel: String? = nil,
        shownWhenUnavailable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.menuBarLabel = menuBarLabel ?? name
        self.shownWhenUnavailable = shownWhenUnavailable
    }
}
