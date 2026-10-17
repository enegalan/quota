import Foundation
import PluginKit

/// A failure that knows how it appears to the host.
///
/// The translation ladder exists once: a `ProviderError` passes through
/// untouched, a `ProviderFailure` says how it maps, and anything else is a
/// fault in the plugin reported as `.pluginError`.
public protocol ProviderFailure: Error {
    /// Never the credential and never a raw provider body — this is shown to
    /// a user and filed in stored sync metadata.
    var providerError: ProviderError { get }
}

/// What a provider implements: the host's four calls, in the host's vocabulary.
///
/// Framing, routing and error translation are `ProviderPlugin`'s job; a plugin
/// author writes this and a one-line `main.swift`.
public protocol ProviderPluginHandler: Sendable {
    /// What the plugin is. A constant, not a method: the host reads it before
    /// it has run anything.
    var descriptor: ProviderDescriptor { get }

    /// Establish credentials; answer a label for the account in use — never
    /// the credential itself, which stays on this side of the pipe.
    func connect(_ request: ConnectRequest) throws -> ConnectResult

    /// Drop held credentials, answered as `connect` is: an absent account.
    /// The default drops nothing, which is right for a plugin whose
    /// credentials are the operating system's and not its own to drop.
    func disconnect() -> ConnectResult

    /// Current usage for the local day the host asked about. An empty result
    /// is a failure to the host: report `nothingToReport`, not no quotas.
    func fetchUsage(_ request: FetchUsageRequest) throws -> UsageResult
}

public extension ProviderPluginHandler {
    func disconnect() -> ConnectResult {
        ConnectResult(accountLabel: nil)
    }
}

public extension ProviderDescriptor {
    /// The common shape: a provider speaks the protocol its own `PluginKit`
    /// was built with, which is the protocol its host speaks — one value
    /// decided by the toolchain, rather than a range each plugin copies and
    /// can get wrong. Use the full initializer only when a plugin genuinely
    /// knows it speaks an older contract.
    init(
        id: String,
        displayName: String,
        description: String,
        capabilities: ProviderCapabilities = [],
        suggestedRefreshIntervalSeconds: Double? = nil
    ) {
        self.init(
            id: id,
            displayName: displayName,
            description: description,
            capabilities: capabilities,
            protocolRange: PluginProtocolConstants.hostRange,
            suggestedRefreshIntervalSeconds: suggestedRefreshIntervalSeconds
        )
    }
}

/// Serves a handler over the host's pipe.
///
/// The loop, the routing of the four methods and the translation of a thrown
/// error are written once so every provider answers identically; what varies
/// between providers is a descriptor and three methods. Not `Sendable`, like
/// `PluginSide`: one reader, one loop.
public struct ProviderPlugin {
    private let handler: any ProviderPluginHandler
    private let side: PluginSide
    private let log: ProviderLog

    /// - Parameter side: injected so a test can drive the loop with handles of
    ///   its own instead of standing on the process's own stdin.
    public init(handler: any ProviderPluginHandler, side: PluginSide = PluginSide()) {
        self.handler = handler
        self.side = side
        log = ProviderLog(providerID: handler.descriptor.id)
    }

    /// Answers requests until the host closes the input: a plugin's entire
    /// main function.
    public func serve() {
        side.serve { answer($0) }
    }

    /// One request, answered. Public so the routing can be exercised without
    /// a pipe.
    public func answer(_ request: PluginRequest) -> PluginResponse {
        PluginResponse(id: request.id, result: result(for: request))
    }

    private func result(for request: PluginRequest) -> PluginResult {
        switch request.method {
        case .describe:
            return .success(.describe(handler.descriptor))
        case .connect:
            // A connect whose payload never arrived is a connect with no
            // credentials: the payload's only field is optional, so the two
            // are the same message.
            let payload = if case .connect(let payload) = request.payload {
                payload
            } else {
                ConnectRequest()
            }
            return answered { try .connect(handler.connect(payload)) }
        case .disconnect:
            // Answered in `connect`'s shape on purpose: both calls ask which
            // account this plugin is acting for, and this one answers none.
            return .success(.connect(handler.disconnect()))
        case .fetchUsage:
            guard case .fetchUsage(let payload) = request.payload else {
                // The day is part of the request, not a courtesy: one that
                // never arrived cannot be replaced by inventing a date,
                // because the reading would be filed against the wrong day as
                // though it were real.
                return .failure(ProviderError(
                    code: .invalidResponse,
                    message: "The host asked for usage without naming a day."
                ))
            }
            return answered { try .usage(handler.fetchUsage(payload)) }
        }
    }

    /// One handler call, turned into the wire's idea of an outcome — the
    /// single translation point, so no plugin author has to remember the
    /// ladder.
    private func answered(_ work: () throws -> PluginResponsePayload) -> PluginResult {
        do {
            return .success(try work())
        } catch let error as ProviderError {
            return .failure(error)
        } catch let error as ProviderFailure {
            return .failure(error.providerError)
        } catch {
            log.note("unhandled error: \(error)")
            return .failure(ProviderError(code: .pluginError))
        }
    }
}
