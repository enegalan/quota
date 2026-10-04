/// A validated provider identifier.
///
/// Providers are named by data, never by literals in application code: the
/// catalog supplies the display name and the identifier alike, and the
/// application must not branch on either. Wrapping the value keeps
/// that rule enforceable at the type level, because a raw `String` has no
/// validity invariant to preserve.
public struct ProviderID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// - Throws: `QuotaDomainError.invalidIdentifier` when the value is empty or
    ///   contains whitespace, either of which would break the catalog key and the
    ///   installed directory name that are derived from it.
    public init(_ rawValue: String) throws {
        let isEmpty = rawValue.isEmpty
        let hasWhitespace = rawValue.contains { $0.isWhitespace }
        guard !isEmpty, !hasWhitespace else {
            throw QuotaDomainError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    /// Decoding validates too, so a corrupted catalog fails loudly instead of
    /// producing a provider that can never be installed.
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes as the bare identifier string.
    ///
    /// A single value rather than an object, because this value is a catalog key
    /// and half of a directory name that a user could be looking at; wrapping it
    /// in a field would make both harder to match by eye.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}
