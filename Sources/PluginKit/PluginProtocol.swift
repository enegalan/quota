import Foundation

/// The calls a host can make on a plugin.
///
/// A closed set rather than a string, so a plugin asked for a method the host does
/// not have gets `pluginError` instead of being sent a method name it has never
/// heard of and answering whatever it likes.
public enum PluginMethod: String, Codable, Sendable, CaseIterable {
    /// "What are you?" — the handshake, and the only call made before the host
    /// trusts a plugin enough to talk normally.
    case describe

    /// Establish credentials. Answers whether it worked; never returns the
    /// credential itself, which stays on the plugin's side.
    case connect

    /// Drop credentials held by the plugin.
    case disconnect

    /// Ask for current usage.
    case fetchUsage
}

/// One message from a host to a plugin.
public struct PluginRequest: Codable, Sendable, Equatable {
    /// Ties the answer to the question.
    ///
    /// The host is free to have several calls in flight, and a plugin is free to
    /// answer in whatever order it finishes. Without this the host would have to
    /// assume replies arrive in order, and one slow call would misattribute
    /// another's answer.
    public let id: String

    public let method: PluginMethod

    /// Method-specific arguments. Absent rather than empty so a method with no
    /// arguments has one representation, not two.
    public let payload: PluginRequestPayload?

    public init(id: String, method: PluginMethod, payload: PluginRequestPayload? = nil) {
        self.id = id
        self.method = method
        self.payload = payload
    }
}

/// What a host can ask for, by method.
///
/// A typed payload per method rather than free-form JSON, so a plugin and the host
/// cannot agree on a shape by accident: changing what `fetchUsage` takes is a
/// compile error in the plugin, not a runtime surprise.
public enum PluginRequestPayload: Codable, Sendable, Equatable {
    case fetchUsage(FetchUsageRequest)
    case connect(ConnectRequest)
    case disconnect(DisconnectRequest)

    /// The `kind`/`value` keys, spelled out because the tags are part of the wire
    /// format and cannot be renamed without breaking every plugin.
    private enum PayloadTag: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: any Decoder) throws {
        // Tagged by `kind`, not trial-decoded. `ConnectRequest` has one optional
        // field, so it matches *any* object — which meant a `disconnect` request,
        // whose payload is `{}`, arrived at the plugin as a `connect` with no
        // credentials, and a plugin that stored credentials on connect would store
        // them again instead of dropping them.
        let container = try decoder.container(keyedBy: PayloadTag.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "fetchUsage":
            self = .fetchUsage(
                try container.decode(FetchUsageRequest.self, forKey: .value)
            )
        case "connect":
            self = .connect(try container.decode(ConnectRequest.self, forKey: .value))
        case "disconnect":
            self = .disconnect(try container.decode(DisconnectRequest.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "unknown request payload \"\(other)\""
            )
        }
    }

    /// Writes the same tag the decoder reads, on every case.
    ///
    /// Hand-written to match `init(from:)` exactly. A plugin author reading this
    /// file should see the tags they have to send, and a synthesised encoding
    /// would hide both the tag and the key the payload travels under.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PayloadTag.self)
        switch self {
        case .fetchUsage(let request):
            try container.encode("fetchUsage", forKey: .kind)
            try container.encode(request, forKey: .value)
        case .connect(let request):
            try container.encode("connect", forKey: .kind)
            try container.encode(request, forKey: .value)
        case .disconnect(let request):
            try container.encode("disconnect", forKey: .kind)
            try container.encode(request, forKey: .value)
        }
    }
}

/// Arguments for `fetchUsage`.
public struct FetchUsageRequest: Codable, Sendable, Equatable {
    /// The local day to report on, as `yyyy-MM-dd`. A date rather than an instant
    /// so a plugin in another time zone answers for the user's day and not for
    /// wherever the plugin happens to run.
    public let localDate: String

    public init(localDate: String) {
        self.localDate = localDate
    }
}

/// Arguments for `connect`.
public struct ConnectRequest: Codable, Sendable, Equatable {
    /// Passed by the user to the plugin, which is responsible for turning it into
    /// whatever it needs. The host never interprets it.
    public let credentials: String?

    public init(credentials: String? = nil) {
        self.credentials = credentials
    }
}

/// Arguments for `disconnect`.
public struct DisconnectRequest: Codable, Sendable, Equatable {
    public init() {}
}

/// What a plugin sends back.
///
/// One shape for success and failure rather than two, so a host waiting on a
/// correlation id has one place to look and cannot miss a failure because it
/// arrived in a different envelope.
public struct PluginResponse: Codable, Sendable, Equatable {
    /// The `id` of the request this answers. Absent only for a message the plugin
    /// sends unasked, which the host drops.
    public let id: String?

    public let result: PluginResult

    public init(id: String?, result: PluginResult) {
        self.id = id
        self.result = result
    }
}

/// Whether a call worked, carried on the wire.
public enum PluginResultKind: String, Codable, Sendable {
    case success
    case failure
}

/// The outcome of a call.
///
/// Encoded as a keyed object with an explicit `kind` rather than by trying the
/// failure case and falling back to the success case. Two reasons, both learned
/// the hard way: a success payload whose fields all happen to be optional would
/// decode as a failure, and reading one `SingleValueContainer` twice asks the
/// decoder to rewind itself.
///
/// The tag is a keyed field rather than a wrapper struct holding the enum,
/// because such a struct encodes its `value` by calling this same function again
/// — the encode recurses into itself until the stack runs out.
public enum PluginResult: Codable, Sendable, Equatable {
    case success(PluginResponsePayload)
    case failure(ProviderError)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PluginResultKind.self, forKey: .kind) {
        case .success:
            self = .success(try container.decode(PluginResponsePayload.self, forKey: .value))
        case .failure:
            self = .failure(try container.decode(ProviderError.self, forKey: .value))
        }
    }

    /// Writes the discriminant and the payload it wraps.
    ///
    /// Hand-written to stay the exact inverse of `init(from:)`. The `kind` tag is
    /// the entire discriminant on this wire, so a success whose payload happens
    /// to look like an error must still be tagged as a success.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let payload):
            try container.encode(PluginResultKind.success, forKey: .kind)
            try container.encode(payload, forKey: .value)
        case .failure(let error):
            try container.encode(PluginResultKind.failure, forKey: .kind)
            try container.encode(error, forKey: .value)
        }
    }
}

/// Which answer a payload is, carried on the wire.
///
/// Trial-decoding payloads is the obvious shortcut and it is wrong: a payload
/// whose fields are all optional — `ConnectResult` with a nil account label, say
/// — matches any object at all, and the first case tried silently wins. A
/// discriminant makes decoding exact, and means a new payload case cannot be
/// misread as an existing one by a plugin built against an older contract.
public enum PluginPayloadKind: String, Codable, Sendable {
    case describe
    case connect
    case usage
}

/// The answer to `connect`.
public struct ConnectResult: Codable, Sendable, Equatable {
    /// A name for the account, so the UI can show which one is connected and the
    /// cache can be keyed per account. Never the credential.
    public let accountLabel: String?

    public init(accountLabel: String? = nil) {
        self.accountLabel = accountLabel
    }
}

/// One quota as a provider reports it.
///
/// Deliberately its own type rather than the core's: a plugin is written against
/// this contract, and `PluginKit` must not depend on `Core`. The host maps this
/// onto the core's model at the boundary, which is the one place that
/// translation is allowed to fail loudly.
public struct ProviderUsage: Codable, Sendable, Equatable {
    /// The provider's name for the quota, used to keep a plugin's quota
    /// identified across calls.
    public let externalID: String

    public let displayName: String

    /// Which pool it is, where a provider meters several.
    public let bucketID: String

    public let bucketDisplayName: String

    /// Percentage used, 0...100.
    public let usagePercentage: Double

    /// The period the percentage is measured over, as `yyyy-MM-dd`.
    public let periodStart: String
    public let periodEnd: String

    /// When the provider last refreshed its own number.
    public let updatedAt: String

    public init(
        externalID: String,
        displayName: String,
        bucketID: String,
        bucketDisplayName: String,
        usagePercentage: Double,
        periodStart: String,
        periodEnd: String,
        updatedAt: String
    ) {
        self.externalID = externalID
        self.displayName = displayName
        self.bucketID = bucketID
        self.bucketDisplayName = bucketDisplayName
        self.usagePercentage = usagePercentage
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.updatedAt = updatedAt
    }
}

/// The answer to `fetchUsage`.
public struct UsageResult: Codable, Sendable, Equatable {
    public let quotas: [ProviderUsage]

    /// Whether the provider can also report past days, and so whether the host
    /// should ask again for yesterday.
    public let supportsHistorical: Bool

    public init(quotas: [ProviderUsage], supportsHistorical: Bool = false) {
        self.quotas = quotas
        self.supportsHistorical = supportsHistorical
    }
}

/// What a successful call carries, by method.
///
/// Tagged by `kind`, for the same reasons `PluginResult` is: trial-decoding this
/// enum made `ConnectResult` — whose only field is optional — match any JSON
/// object at all, so the first case tried silently won.
///
/// `disconnect` is answered with a `connect` payload, and that is not an oversight.
/// Both calls answer the same question — which account this plugin is now acting
/// for — so they answer it in the same shape, and the answer to a disconnect is an
/// absent account rather than a separate structure. A fourth kind would be a
/// distinct wire shape carrying one optional field and nothing else.
public enum PluginResponsePayload: Codable, Sendable, Equatable {
    case describe(ProviderDescriptor)
    case connect(ConnectResult)
    case usage(UsageResult)

    /// The tag this payload carries.
    public var kind: PluginPayloadKind {
        switch self {
        case .describe: .describe
        case .connect: .connect
        case .usage: .usage
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PluginPayloadKind.self, forKey: .kind) {
        case .describe:
            self = .describe(try container.decode(ProviderDescriptor.self, forKey: .value))
        case .connect:
            self = .connect(try container.decode(ConnectResult.self, forKey: .value))
        case .usage:
            self = .usage(try container.decode(UsageResult.self, forKey: .value))
        }
    }

    /// Writes the tag this payload carries, then the payload itself.
    ///
    /// One `kind` write before the switch rather than one per case, so the three
    /// arms cannot drift apart and produce two different tags for one wire
    /// shape. The tag comes from `kind` rather than from a literal, which is what
    /// keeps a renamed case from being encoded under its old name.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .describe(let descriptor): try container.encode(descriptor, forKey: .value)
        case .connect(let result): try container.encode(result, forKey: .value)
        case .usage(let result): try container.encode(result, forKey: .value)
        }
    }
}
