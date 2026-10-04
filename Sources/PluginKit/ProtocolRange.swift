import Foundation

/// The range of protocol versions a plugin can speak.
///
/// Compares as two bounds rather than a spec string, because a plugin is not
/// allowed to send the host a range to evaluate — the host has to know what it
/// accepts before it runs the plugin at all. The plugin declares what it speaks;
/// the host decides whether that is a subset of what it can talk.
public struct ProtocolRange: Codable, Sendable, Equatable, CustomStringConvertible {
    public let minimum: Version
    public let maximum: Version

    public init(minimum: Version, maximum: Version) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(from string: String) throws {
        let parts = string.split(separator: "..<", omittingEmptySubsequences: false)
        guard parts.count == VersionConstants.rangeComponentCount,
              let minimum = Version(string: String(parts[0])),
              let maximum = Version(string: String(parts[1]))
        else {
            throw ProtocolRangeError.malformed(string)
        }
        guard minimum <= maximum else {
            throw ProtocolRangeError.inverted(string)
        }
        self.init(minimum: minimum, maximum: maximum)
    }

    public var description: String {
        "\(minimum)..<\(maximum)"
    }

    /// Whether a version falls inside this range, both ends included.
    ///
    /// Both ends count even though the printed form reads `..<`: the bounds name
    /// the oldest and newest versions the declaring side can speak, and the
    /// newest is one it is entitled to speak too. Compatibility checks are built
    /// on this, so the edges have to be decided here rather than at each call
    /// site, where a host and a plugin would drift apart.
    public func contains(_ version: Version) -> Bool {
        version >= minimum && version <= maximum
    }

    /// Whether two ranges share any version.
    ///
    /// Used to decide whether this build can talk to a provider: the provider's
    /// range and the host's have to meet somewhere, and two ranges that do not
    /// overlap mean there is no protocol version both sides speak. Comparing only
    /// the provider's minimum against the host's would accept a range that ends
    /// before this build starts.
    public func overlaps(_ other: ProtocolRange) -> Bool {
        contains(other.minimum) || contains(other.maximum) || other.contains(minimum)
            || other.contains(maximum)
    }
}

/// A range that is not a range, or not in the order a range has to be in.
public enum ProtocolRangeError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case inverted(String)

    public var description: String {
        switch self {
        case .malformed(let string): "\(string) is not a version range"
        case .inverted(let string): "\(string) starts after it ends"
        }
    }
}

public extension ProtocolRange {
    /// Whether every version this plugin speaks is one the host can also speak.
    ///
    /// Overlap is not enough, and the difference matters. A host that accepted
    /// any overlap would launch a plugin that may then be asked to speak a
    /// version it never implemented — and the failure would surface as a
    /// malformed response to a real call, after a user had already connected the
    /// provider. Refusing at the handshake costs one failed launch instead.
    func isCompatible(with host: ProtocolRange) -> Bool {
        minimum >= host.minimum && maximum <= host.maximum
    }

    /// The first version both sides speak, or nil when the pair is not
    /// compatible.
    ///
    /// Nil for an incompatible pair even where one version happens to fall in
    /// both ranges. Reporting a usable version for a pair `isCompatible` rejects
    /// would leave a caller to pick which of the two answers to believe, and the
    /// one it wanted to believe is the one that gets a plugin launched that cannot
    /// finish the handshake.
    func firstCommonVersion(with host: ProtocolRange) -> Version? {
        guard isCompatible(with: host) else { return nil }
        return max(minimum, host.minimum)
    }
}
