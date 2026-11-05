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

    /// Whether the integration suggests keeping this limit visible when the
    /// latest reading omits it. The user's choice decides which limits are
    /// drawn, so this is only a hint; it stays on the wire so descriptors
    /// still round-trip between builds.
    public let shownWhenUnavailable: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case menuBarLabel
        case shownWhenUnavailable
    }

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

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        menuBarLabel = try values.decodeIfPresent(String.self, forKey: .menuBarLabel) ?? name
        shownWhenUnavailable = try values.decodeIfPresent(Bool.self, forKey: .shownWhenUnavailable) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(menuBarLabel, forKey: .menuBarLabel)
        try values.encode(shownWhenUnavailable, forKey: .shownWhenUnavailable)
    }
}
