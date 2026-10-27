import Foundation
import PluginKit
import ProviderSupport

//  JetBrains AI Assistant provider plugin.
//
//  Quota is read from the IDE's local `AIAssistantQuotaManager2.xml` cache —
//  the same file the AI widget is backed by. There is no personal public API
//  for remaining credits; organisation Analytics APIs report consumption only.

struct JetBrainsProvider: ProviderPluginHandler {
    private let log = ProviderLog(providerID: JetBrainsConstants.providerID)

    let descriptor = ProviderDescriptor(
        id: JetBrainsConstants.providerID,
        displayName: JetBrainsConstants.displayName,
        description: JetBrainsConstants.description,
        capabilities: [.automaticUsageRetrieval, .multipleQuotas, .automaticPeriodDetection],
        suggestedRefreshIntervalSeconds: JetBrainsConstants.suggestedRefreshIntervalSeconds
    )

    func connect(_ request: ConnectRequest) throws -> ConnectResult {
        let ide = try IDEDetector.latest()
        log.note("ide=\(ide.displayName)")
        return ConnectResult(accountLabel: ide.displayName)
    }

    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult {
        let ide = try IDEDetector.latest()
        let snapshot = try QuotaFileParser.parse(fileAt: ide.quotaFileURL)
        let usage = try UsageNormaliser.usageResult(
            from: snapshot,
            updatedAtDay: request.localDate
        )
        guard !usage.quotas.isEmpty else {
            throw ProviderError(code: .nothingToReport)
        }
        return usage
    }
}

ProviderPlugin(handler: JetBrainsProvider()).serve()
