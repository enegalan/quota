/// A semantic version, used for a provider's version, the application's own, and
/// both ends of a protocol range.
///
/// Hand-rolled rather than taken from a dependency: the whole type is a
/// comparable tuple, and the core and the plugin contract must not share a
/// package that a provider could also pull in.
///
/// One type for all three uses on purpose. There were two — one for versions and
/// one for protocol versions — and they differed only in how forgiving their
/// parsers were, which meant a string one accepted and the other refused, and two
/// places to fix any change to what a version is allowed to look like.
public struct Version: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `major.minor.patch` and nothing else.
    ///
    /// Returns nil for anything else rather than trapping, because this parses
    /// values arriving from a packaged file, a process's environment, or another
    /// process's JSON.
    public init?(string: String) {
        var parts = string.split(separator: ".", omittingEmptySubsequences: false)
        // Exactly three components, and digits only — not `Int.init`, whose
        // `Int("-1")` succeeds and whose `split` drops an empty component, so
        // `"1..3"` and `"-1.2.3"` would each parse as a real version. A version of
        // `-1.2.3` sorts below every other version and quietly widens whatever
        // range it appeared in.
        //
        // Consumed with `removeFirst` rather than indexed, so the order the three
        // components are read in is the order they are checked in.
        guard parts.count == VersionConstants.componentCount,
              let major = Version.component(parts.removeFirst()),
              let minor = Version.component(parts.removeFirst()),
              let patch = Version.component(parts.removeFirst())
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// One numeric component, or nil if it is not one.
    private static func component(_ substring: Substring) -> Int? {
        guard !substring.isEmpty, substring.allSatisfy(\.isNumber) else { return nil }
        return Int(substring)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

/// Encoded as a string, not as three fields, because a version is written by hand
/// in a build script and passed to a plugin as an environment variable. `1.2.3`
/// is how a person writes it; `{major: 1, minor: 2, patch: 3}` is how a struct
/// would.
///
/// The same reason it is the only version shape on the wire: a plugin compiled
/// against an older host and a newer one both have to read the same three
/// characters.
extension Version: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Version(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(raw)\" is not a version"
            )
        }
        self = parsed
    }

    /// Encodes the dotted form, which is the form the parser accepts.
    ///
    /// Round-trips by construction: `description` is exactly what `init?(string:)`
    /// reads, so a version that reached a file comes back the same value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
