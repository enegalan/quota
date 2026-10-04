import Foundation
import PluginKit

enum ErrorMapper {
    static func providerError(from resolver: TokenResolverError) -> ProviderError {
        switch resolver {
        case .notFound:
            ProviderError(code: .notAuthenticated)
        case .rejected(.expiredToken):
            ProviderError(code: .authenticationFailed)
        case .rejected(.apiKeyToken), .rejected(.malformedJWT), .rejected(.missingSubject):
            ProviderError(code: .authenticationFailed)
        }
    }

    static func providerError(from client: UsageClientError) -> ProviderError {
        switch client {
        case .networkUnavailable:
            return ProviderError(code: .networkUnavailable)
        case .rateLimited(let retry):
            let message = if let retry {
                "Rate limited; retry after \(Int(retry)) seconds."
            } else {
                "This provider asked for less traffic."
            }
            return ProviderError(code: .rateLimited, message: message)
        case .authenticationFailed:
            return ProviderError(code: .authenticationFailed)
        case .invalidResponse:
            return ProviderError(code: .invalidResponse)
        case .nothingToReport:
            return ProviderError(code: .nothingToReport)
        }
    }

    static func providerError(from normaliser: UsageNormaliserError) -> ProviderError {
        switch normaliser {
        case .missingField, .invalidPeriod, .noUsableMeter:
            ProviderError(code: .invalidResponse)
        }
    }
}
