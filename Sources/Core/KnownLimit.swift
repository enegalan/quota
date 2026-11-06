import Foundation

/// A limit an integration declared, kept with the reading that carried it.
///
/// The wire type stays in the plugin contract. This is the copy the app stores,
/// so a menu bar drawn before the next refresh still knows which limits exist
/// and how the integration wants them labelled.
public struct KnownLimit: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let menuBarLabel: String

    /// The integration's hint about a missing limit. The user's own choice
    /// decides what the menu bar draws.
    public let shownWhenUnavailable: Bool

    public init(
        id: String,
        name: String,
        menuBarLabel: String,
        shownWhenUnavailable: Bool
    ) {
        self.id = id
        self.name = name
        self.menuBarLabel = menuBarLabel
        self.shownWhenUnavailable = shownWhenUnavailable
    }
}
