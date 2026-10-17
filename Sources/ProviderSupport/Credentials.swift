import Foundation
import PluginKit

/// Where a provider's credential came from, under a name that can be logged.
///
/// A name rather than an enum: a provider may have a source nobody else has,
/// and the point is that the sources every provider has in common are spelled
/// the same way — `stateDatabase` in one provider's log is the same idea as in
/// another's.
public struct CredentialSource: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let stateDatabase = CredentialSource(rawValue: "stateDatabase")
    public static let keychain = CredentialSource(rawValue: "keychain")
    public static let credentialsFile = CredentialSource(rawValue: "credentialsFile")
    public static let environment = CredentialSource(rawValue: "environment")
}

/// One credential, resolved: what it is, where it came from, and the token as
/// read — kept because the plugin has to send it, and never because it may be
/// logged.
public struct ResolvedCredential<Value> {
    public let value: Value
    public let source: CredentialSource
    public let rawToken: String
}

/// Trying a provider's credential sources in the order the plugin trusts them:
/// the first token that validates wins.
///
/// Sources are read afresh on every call and nothing is cached — a provider
/// that re-reads picks up a rotated credential on the next refresh. A source
/// that throws is a source that is not there and the walk continues; a token
/// that is read and then refused is remembered, so a walk that finds nothing
/// usable reports *why* the last one failed instead of that nothing was tried.
public enum CredentialResolver {
    /// No source produced a token, or none validated. `rejected` carries the
    /// last refusal, which is the most specific thing known.
    public enum ResolutionError: Error {
        case notFound
        case rejected(any Error)
    }

    public static func resolve<Value>(
        sources: [(CredentialSource, () throws -> String?)],
        validate: (String) throws -> Value
    ) throws -> ResolvedCredential<Value> {
        var lastRejection: (any Error)?

        for (source, read) in sources {
            guard let token = try? read(), !token.isEmpty else { continue }
            do {
                return ResolvedCredential(
                    value: try validate(token),
                    source: source,
                    rawToken: token
                )
            } catch {
                lastRejection = error
            }
        }

        if let lastRejection {
            throw ResolutionError.rejected(lastRejection)
        }
        throw ResolutionError.notFound
    }
}

extension CredentialResolver.ResolutionError: ProviderFailure {
    /// Written here rather than per provider: *no credential exists on this
    /// machine* and *the credential there was refused* are the two ways every
    /// provider's walk ends, and both are always reported this way.
    public var providerError: ProviderError {
        switch self {
        case .notFound:
            ProviderError(code: .notAuthenticated)
        case .rejected:
            ProviderError(code: .authenticationFailed)
        }
    }
}
