import Foundation
import PluginKit
import Testing

@Suite("Error mapping")
struct ErrorMappingTests {
    @Test("Missing token maps to notAuthenticated")
    func missingToken() {
        #expect(ProviderError(code: .notAuthenticated).code == .notAuthenticated)
    }

    @Test("Rejected or expired token maps to authenticationFailed")
    func rejectedToken() {
        #expect(ProviderError(code: .authenticationFailed).code == .authenticationFailed)
    }

    @Test("Rate limited maps to rateLimited")
    func rateLimited() {
        let error = ProviderError(code: .rateLimited, message: "Rate limited; retry after 60 seconds.")
        #expect(error.code == .rateLimited)
        #expect(error.message.contains("60"))
    }

    @Test("Network failure maps to networkUnavailable")
    func network() {
        #expect(ProviderError(code: .networkUnavailable).code == .networkUnavailable)
    }

    @Test("Unreadable body maps to invalidResponse")
    func invalid() {
        #expect(ProviderError(code: .invalidResponse).code == .invalidResponse)
    }

    @Test("Empty quotas map to nothingToReport")
    func nothing() {
        #expect(ProviderError(code: .nothingToReport).code == .nothingToReport)
    }

    @Test("Plugin fault maps to pluginError")
    func plugin() {
        #expect(ProviderError(code: .pluginError).code == .pluginError)
    }

    @Test("Provider-authored fault maps to providerError")
    func provider() {
        #expect(ProviderError(code: .providerError).code == .providerError)
    }

    @Test("Not installed maps to notInstalled")
    func notInstalled() {
        #expect(ProviderError(code: .notInstalled).code == .notInstalled)
    }
}
