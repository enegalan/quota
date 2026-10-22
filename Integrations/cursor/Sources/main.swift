import Foundation
import PluginKit
import ProviderSupport

//  Cursor provider plugin.
//
//  Everything Cursor's own lives in this file: what it is, where its
//  credentials are, and how its payloads become readings. The loop, the HTTP,
//  the credential walk and the failure translation are `ProviderSupport`'s.

struct CursorProvider: ProviderPluginHandler {
    private let log = ProviderLog(providerID: CursorConstants.providerID)

    let descriptor = ProviderDescriptor(
        id: CursorConstants.providerID,
        displayName: CursorConstants.displayName,
        description: CursorConstants.description,
        capabilities: [.automaticUsageRetrieval, .multipleQuotas],
        suggestedRefreshIntervalSeconds: CursorConstants.suggestedRefreshIntervalSeconds
    )

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        let resolved = try TokenResolver.resolve()
        // Which source answered, never the token: this line outlives the call
        // and ends up wherever the user pastes their log.
        log.note("token source=\(resolved.source.rawValue)")
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

//  Credentials are read from Cursor's own local state on every refresh and
//  never cached or logged.
ProviderPlugin(handler: CursorProvider()).serve()
