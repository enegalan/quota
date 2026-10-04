import Foundation
import PluginKit

/// Cursor provider plugin.
///
/// Credentials are read from Cursor's own local state on every refresh and never
/// cached or logged.
private let descriptor = ProviderDescriptor(
    id: CursorConstants.providerID,
    displayName: CursorConstants.displayName,
    description: CursorConstants.description,
    capabilities: [.automaticUsageRetrieval, .multipleQuotas],
    protocolRange: PluginProtocolConstants.hostRange,
    suggestedRefreshIntervalSeconds: CursorConstants.suggestedRefreshIntervalSeconds
)

private let side = PluginSide()

private func answer(_ request: PluginRequest) -> PluginResponse {
    let result: PluginResult = switch request.method {
    case .describe:
        .success(.describe(descriptor))
    case .connect:
        connect()
    case .disconnect:
        .success(.connect(ConnectResult(accountLabel: nil)))
    case .fetchUsage:
        fetchUsage(request)
    }
    return PluginResponse(id: request.id, result: result)
}

private func connect() -> PluginResult {
    do {
        let resolved = try TokenResolver.resolve()
        // Source name only — never the token.
        fputs("quota-provider-cursor: token source=\(resolved.source.rawValue)\n", stderr)
        return .success(.connect(ConnectResult(accountLabel: resolved.accountLabel)))
    } catch let error as TokenResolverError {
        return .failure(ErrorMapper.providerError(from: error))
    } catch {
        return .failure(ProviderError(code: .pluginError))
    }
}

private func fetchUsage(_ request: PluginRequest) -> PluginResult {
    let day: String = if case .fetchUsage(let payload) = request.payload {
        payload.localDate
    } else {
        "1970-01-01"
    }

    do {
        // Re-read on every refresh; never reuse a previous resolve.
        let resolved = try TokenResolver.resolve()
        let usage = try UsageClient.fetchUsage(token: resolved, localDate: day)
        guard !usage.quotas.isEmpty else {
            return .failure(ProviderError(code: .nothingToReport))
        }
        return .success(.usage(usage))
    } catch let error as TokenResolverError {
        return .failure(ErrorMapper.providerError(from: error))
    } catch let error as UsageClientError {
        return .failure(ErrorMapper.providerError(from: error))
    } catch let error as UsageNormaliserError {
        return .failure(ErrorMapper.providerError(from: error))
    } catch {
        return .failure(ProviderError(code: .pluginError))
    }
}

while let request = side.nextRequest() {
    try side.write(answer(request))
}
