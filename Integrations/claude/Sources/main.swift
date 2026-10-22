import Foundation
import PluginKit
import ProviderSupport

//  Claude provider plugin.
//
//  Everything Claude's own lives in this file: what it is, where its
//  credentials are, and how its payloads become readings. The loop, the HTTP,
//  the credential walk and the failure translation are `ProviderSupport`'s.

struct ClaudeProvider: ProviderPluginHandler {
    private let log = ProviderLog(providerID: ClaudeConstants.providerID)

    let descriptor = ProviderDescriptor(
        id: ClaudeConstants.providerID,
        displayName: ClaudeConstants.displayName,
        description: ClaudeConstants.description,
        capabilities: [.automaticUsageRetrieval, .multipleQuotas, .automaticPeriodDetection],
        suggestedRefreshIntervalSeconds: ClaudeConstants.suggestedRefreshIntervalSeconds
    )

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        let resolved = try TokenResolver.resolve()
        // Which source answered, never the token: this line outlives the call
        // and ends up wherever the user pastes their log.
        log.note("token source=\(resolved.source.rawValue)")
        return ConnectResult(accountLabel: TokenResolver.accountLabel(for: resolved.value))
    }

    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult {
        // Resolved again on every refresh rather than remembered, so a token
        // Claude Code has rotated is picked up on the next reading.
        let resolved = try TokenResolver.resolve()
        let usage = try UsageClient.fetchUsage(
            credential: resolved.value,
            localDate: request.localDate
        )
        guard !usage.quotas.isEmpty else {
            throw ProviderError(code: .nothingToReport)
        }
        return usage
    }
}

//  Credentials are read from Claude Code's own state on every refresh and
//  never cached or logged.
ProviderPlugin(handler: ClaudeProvider()).serve()
