import Foundation
import PluginKit
import ProviderSupport

//  Antigravity provider plugin.
//
//  Everything Antigravity's own lives in this file: what it is, where its
//  credentials are, and how its payloads become readings. The loop, the HTTP,
//  the credential walk and the failure translation are `ProviderSupport`'s.

struct AntigravityProvider: ProviderPluginHandler {
    private let log = ProviderLog(providerID: AntigravityConstants.providerID)

    let descriptor = ProviderDescriptor(
        id: AntigravityConstants.providerID,
        displayName: AntigravityConstants.displayName,
        description: AntigravityConstants.description,
        capabilities: [.automaticUsageRetrieval, .multipleQuotas],
        suggestedRefreshIntervalSeconds: AntigravityConstants.suggestedRefreshIntervalSeconds
    )

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        let resolved = try TokenResolver.resolve()
        // Which source answered, never the token: this line outlives the call
        // and ends up wherever the user pastes their log.
        log.note("token source=credentials")
        return ConnectResult(accountLabel: resolved.accountLabel)
    }

    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult {
        // Resolved again on every refresh rather than remembered, so a token
        // rotated by a new sign-in is picked up on the next reading.
        let resolved = try TokenResolver.resolve()
        let usage = try UsageClient.fetchUsage(token: resolved, localDate: request.localDate)
        guard !usage.quotas.isEmpty else {
            throw ProviderError(code: .nothingToReport)
        }
        return usage
    }
}

//  Credentials are read from known locations on every refresh and
//  never cached or logged.
ProviderPlugin(handler: AntigravityProvider()).serve()
