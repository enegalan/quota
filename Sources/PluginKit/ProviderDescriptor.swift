import Foundation

/// What a plugin says it is, sent in answer to `describe`.
///
/// The only thing the host knows about a provider before it has run a call, and
/// the thing the catalog is built from.
public struct ProviderDescriptor: Codable, Sendable, Equatable {
    /// Stable across releases and unique among installed providers. The core
    /// stores sync metadata under it, so it must not change when a provider is
    /// renamed.
    public let id: String

    /// The name shown to a user.
    public let displayName: String

    /// One line about what the provider meters, shown in a catalog.
    public let description: String

    public let capabilities: ProviderCapabilities

    /// What the plugin can speak.
    public let protocolRange: ProtocolRange

    /// How long the provider would rather not be asked again, in seconds.
    ///
    /// Optional because a provider may have no opinion, and because a plugin
    /// built before this field said nothing at all — which is the same thing.
    /// The host clamps it to its own minimum and maximum rather than trusting
    /// it: a provider asking to be polled every second is a bug on its side, and
    /// the app is the one that has to answer for the requests.
    public let suggestedRefreshIntervalSeconds: Double?

    public init(
        id: String,
        displayName: String,
        description: String,
        capabilities: ProviderCapabilities = [],
        protocolRange: ProtocolRange,
        suggestedRefreshIntervalSeconds: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.capabilities = capabilities
        self.protocolRange = protocolRange
        self.suggestedRefreshIntervalSeconds = suggestedRefreshIntervalSeconds
    }
}

/// Everything the host needs to start one installed provider.
///
/// Built by the host out of the catalog and the installed layout, and never read
/// out of the artifact: a provider that named its own executable could talk the
/// host into running something else, and everything the provider says about itself
/// arrives anyway, in the descriptor, after the process is already running.
public struct PluginLaunch: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let version: String

    /// The executable, absolute.
    public let executablePath: String

    public let protocolRange: ProtocolRange

    public init(
        id: String,
        displayName: String,
        version: String,
        executablePath: String,
        protocolRange: ProtocolRange
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.executablePath = executablePath
        self.protocolRange = protocolRange
    }
}
