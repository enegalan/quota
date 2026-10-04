import Foundation

/// What a provider offers, as a set of independent abilities.
///
/// An option set rather than a list of strings because the core branches on these
/// to decide what to show a user, and a string the core does not recognise would
/// have to be handled as "unknown" at every branch. A bit the core does not
/// recognise decodes to nothing, so a newer plugin advertising a newer ability
/// still works — it just does not unlock anything.
public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The provider can report usage without the user doing anything.
    public static let automaticUsageRetrieval = Self(
        rawValue: CapabilityValue.automaticUsageRetrieval
    )

    /// The provider can tell the app which period it meters.
    public static let automaticPeriodDetection = Self(
        rawValue: CapabilityValue.automaticPeriodDetection
    )

    /// The provider meters more than one quota for one account.
    public static let multipleQuotas = Self(
        rawValue: CapabilityValue.multipleQuotas
    )

    /// The provider can report usage for past days, not just today.
    public static let historicalUsage = Self(
        rawValue: CapabilityValue.historicalUsage
    )

    /// The provider can be polled while the app is not in front.
    public static let backgroundRefresh = Self(
        rawValue: CapabilityValue.backgroundRefresh
    )

    /// The provider authenticates against something on this machine, such as a
    /// token in a local file, rather than against a remote sign-in.
    public static let localAuthentication = Self(
        rawValue: CapabilityValue.localAuthentication
    )
}

extension ProviderCapabilities: Codable {
    /// A bare integer on the wire.
    ///
    /// Written out rather than taking the compiler's synthesised form, because
    /// the synthesised one for an `OptionSet` is an implementation detail that has
    /// changed between Swift versions — and this is a boundary a plugin
    /// compiled by someone else has to agree with. A bare integer is also what a
    /// plugin author writing JSON by hand would guess.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    /// A bare integer on the wire.
    ///
    /// Written out for the same reason as the decoder: the synthesised
    /// `OptionSet` encoding is an implementation detail that has changed between
    /// Swift versions, and both directions have to agree with a plugin compiled
    /// by someone else.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The abilities, spelled out, for a user and for a screen.
///
/// The raw set is what the wire carries; this is what the UI reads, so the app
/// never has to decide what a bit means.
public struct ProviderCapabilitiesDescription: Codable, Sendable, Equatable {
    public let automaticUsageRetrieval: Bool
    public let automaticPeriodDetection: Bool
    public let multipleQuotas: Bool
    public let historicalUsage: Bool
    public let backgroundRefresh: Bool
    public let localAuthentication: Bool

    public init(
        automaticUsageRetrieval: Bool,
        automaticPeriodDetection: Bool,
        multipleQuotas: Bool,
        historicalUsage: Bool,
        backgroundRefresh: Bool,
        localAuthentication: Bool
    ) {
        self.automaticUsageRetrieval = automaticUsageRetrieval
        self.automaticPeriodDetection = automaticPeriodDetection
        self.multipleQuotas = multipleQuotas
        self.historicalUsage = historicalUsage
        self.backgroundRefresh = backgroundRefresh
        self.localAuthentication = localAuthentication
    }

    public init(_ capabilities: ProviderCapabilities) {
        self.init(
            automaticUsageRetrieval: capabilities.contains(.automaticUsageRetrieval),
            automaticPeriodDetection: capabilities.contains(.automaticPeriodDetection),
            multipleQuotas: capabilities.contains(.multipleQuotas),
            historicalUsage: capabilities.contains(.historicalUsage),
            backgroundRefresh: capabilities.contains(.backgroundRefresh),
            localAuthentication: capabilities.contains(.localAuthentication)
        )
    }

    public var raw: ProviderCapabilities {
        var capabilities: ProviderCapabilities = []
        if automaticUsageRetrieval {
            capabilities.insert(.automaticUsageRetrieval)
        }
        if automaticPeriodDetection {
            capabilities.insert(.automaticPeriodDetection)
        }
        if multipleQuotas {
            capabilities.insert(.multipleQuotas)
        }
        if historicalUsage {
            capabilities.insert(.historicalUsage)
        }
        if backgroundRefresh {
            capabilities.insert(.backgroundRefresh)
        }
        if localAuthentication {
            capabilities.insert(.localAuthentication)
        }
        return capabilities
    }
}
