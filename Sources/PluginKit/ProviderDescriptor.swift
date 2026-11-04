import Foundation

/// What a plugin says it is, sent in answer to `describe`.
///
/// The only thing the host knows about a provider before it has run a call, and
/// the thing a build's provider list is made of.
public struct ProviderDescriptor: Codable, Sendable, Equatable {
    /// Stable across releases and unique among installed providers. The core
    /// stores sync metadata under it, so it must not change when a provider is
    /// renamed.
    public let id: String

    /// The name shown to a user.
    public let displayName: String

    /// One line about what the provider meters, shown in the provider list.
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

    /// Every limit this integration meters, including ones a reading may omit.
    ///
    /// Empty for a plugin built before it had any to declare. A missing key is
    /// that case, not a plugin that failed to answer.
    public let limits: [ProviderLimit]

    public init(
        id: String,
        displayName: String,
        description: String,
        capabilities: ProviderCapabilities = [],
        protocolRange: ProtocolRange,
        suggestedRefreshIntervalSeconds: Double? = nil,
        limits: [ProviderLimit] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.capabilities = capabilities
        self.protocolRange = protocolRange
        self.suggestedRefreshIntervalSeconds = suggestedRefreshIntervalSeconds
        self.limits = limits
    }
}

public extension ProviderDescriptor {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case capabilities
        case protocolRange
        case suggestedRefreshIntervalSeconds
        case limits
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            displayName: values.decode(String.self, forKey: .displayName),
            description: values.decode(String.self, forKey: .description),
            capabilities: values.decode(ProviderCapabilities.self, forKey: .capabilities),
            protocolRange: values.decode(ProtocolRange.self, forKey: .protocolRange),
            suggestedRefreshIntervalSeconds: values.decodeIfPresent(
                Double.self,
                forKey: .suggestedRefreshIntervalSeconds
            ),
            limits: values.decodeIfPresent([ProviderLimit].self, forKey: .limits) ?? []
        )
    }

    /// Inverse of `init(from:)`, including limits added after the first descriptor.
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(description, forKey: .description)
        try values.encode(capabilities, forKey: .capabilities)
        try values.encode(protocolRange, forKey: .protocolRange)
        try values.encodeIfPresent(
            suggestedRefreshIntervalSeconds,
            forKey: .suggestedRefreshIntervalSeconds
        )
        try values.encode(limits, forKey: .limits)
    }
}

/// Everything the host needs to start one installed provider.
///
/// Built by the host out of the packaged list and the installed layout, and never read
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
