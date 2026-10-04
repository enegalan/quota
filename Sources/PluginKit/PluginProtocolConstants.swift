import Foundation

/// The numbers the protocol depends on, named so no side has to guess.
public enum PluginProtocolConstants {
    /// The protocol version this build of the host speaks.
    ///
    /// A host advertises what it can talk rather than a single version, so a
    /// plugin written against a slightly older contract still runs: adding a
    /// method extends the range rather than forcing every plugin to be rebuilt.
    public static let hostRange = ProtocolRange(
        minimum: Version(major: 1, minor: 0, patch: 0),
        maximum: Version(major: 1, minor: 9, patch: 0)
    )

    /// The version used when nothing has negotiated a narrower one.
    public static let negotiatedVersion = Version(major: 1, minor: 0, patch: 0)

    /// How long a single call may take before the plugin is killed.
    ///
    /// A deadline rather than a retry: a plugin that does not answer is not going
    /// to answer on the second attempt, and a hung plugin must not be able to hold
    /// the core.
    public static let callTimeout: TimeInterval = 10

    /// How long to wait for a plugin to exit after being asked to.
    public static let shutdownTimeout: TimeInterval = 2

    /// The longest a single message may be.
    public static let maximumLineLength = 1 << 20

    /// How much to read from a pipe at a time.
    public static let readChunkSize = 64 * 1024

    /// How long a plugin waits before looking at its stdin again.
    ///
    /// Small enough that answering is not noticeably delayed, large enough that a
    /// plugin sitting idle between requests is not spinning a core.
    public static let idlePollSeconds: TimeInterval = 0.002

    /// The longest a plugin's stderr is kept.
    public static let maximumLogLength = 1 << 20
}

/// The JSON coding used on both sides of the boundary.
///
/// Deliberately not the app's store coding. `JSONEncoder.quota` sorts keys and
/// stamps dates as seconds, which is right for files that are compared and wrong
/// for a wire where a plugin is written by someone else and expects ISO dates.
public enum PluginJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Wire layout

/// The bit each `ProviderCapabilities` member occupies.
///
/// Spelled out as values rather than left as `1 << 3` at the use site, because
/// these are the wire: a plugin compiled elsewhere sets these bits, and a shift
/// expression hides which bit it is until someone counts.
public enum CapabilityValue {
    public static let automaticUsageRetrieval = 1
    public static let automaticPeriodDetection = 2
    public static let multipleQuotas = 4
    public static let historicalUsage = 8
    public static let backgroundRefresh = 16
    public static let localAuthentication = 32
}
