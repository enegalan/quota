import Foundation
import PluginKit

/// Runs plugins and talks to them.
///
/// The one place the app executes third-party code. Everything a plugin can do
/// wrong — crash, hang, answer nonsense, go away between calls — is turned into a
/// `ProviderError` here, so nothing above this line has to reason about processes,
/// pipes, or exit codes.
public actor PluginHost {
    private let launch: PluginLaunch
    private let launcher: any ProcessLaunching
    private let logDirectory: URL
    private let hostRange: ProtocolRange
    private let timeout: TimeInterval

    private var handle: (any ProcessHandle)?
    private var buffer = Data()
    /// Answers that have arrived and are not yet claimed, by the id they answer.
    ///
    /// Keyed rather than queued because arrival order is not the caller's order: a
    /// plugin may answer the second of two requests first, and whoever drained the
    /// pipe first would otherwise take an answer meant for someone else.
    private var pending: [String: PluginResult] = [:]
    private var readerTask: Task<Void, Never>?
    private var outputClosed = false
    private var framingFailed = false
    private var descriptor: ProviderDescriptor?
    private var nextRequestIndex = 0

    public init(
        launch: PluginLaunch,
        launcher: any ProcessLaunching,
        logDirectory: URL,
        hostRange: ProtocolRange = PluginProtocolConstants.hostRange,
        timeout: TimeInterval = PluginProtocolConstants.callTimeout
    ) {
        self.launch = launch
        self.launcher = launcher
        self.logDirectory = logDirectory
        self.hostRange = hostRange
        self.timeout = timeout
    }

    // MARK: - Lifecycle

    /// Launches the plugin and checks that it can be talked to.
    ///
    /// The protocol range is checked before the handshake, from what the host
    /// knows about the provider, because a host that cannot speak a plugin's
    /// protocol has no business running it. And a plugin that dies in the
    /// handshake is reported as `pluginError`, never as whatever system error the
    /// spawn produced: a missing executable is a fact about the plugin, not about
    /// the app.
    public func launch() async throws -> ProviderDescriptor {
        try checkProtocolCompatibility(launch.protocolRange)

        let environment = PluginEnvironment.child(launch: launch)
        do {
            handle = try launcher.launch(
                executable: URL(fileURLWithPath: launch.executablePath),
                environment: environment,
                // Empty in production: a plugin is configured by the environment it
                // is given and nothing else, so the app never builds an argv for
                // code it did not write.
                arguments: []
            )
        } catch {
            // Every way a spawn can fail — missing, not executable, refused — is a
            // fact about the plugin, not about the app, so none of them reach a
            // caller as a system error.
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) could not be started."
            )
        }

        startReader()
        let response = try await call(.describe, payload: nil)
        guard case .success(.describe(let described)) = response else {
            await shutdown()
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) did not describe itself."
            )
        }
        // The packaged name is the host's to trust; the descriptor is the
        // plugin's claim. Where they disagree the plugin is not one to trust with
        // a call — something answering to a name it was not launched under is not
        // the plugin that was installed.
        guard described.id == launch.id else {
            await shutdown()
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) introduced itself as \(described.id)."
            )
        }
        try checkProtocolCompatibility(of: described)
        descriptor = described
        return described
    }

    /// Refuses a plugin whose protocol the host cannot speak.
    ///
    /// Checked before the plugin is run, from the host's own record of the
    /// provider, because a host that cannot speak a plugin's protocol has no
    /// business starting it. Checked again on the descriptor, because the
    /// plugin's own claim is what it will actually speak, and what the host
    /// expects is not proof.
    private func checkProtocolCompatibility(_ range: ProtocolRange) throws {
        guard range.isCompatible(with: hostRange) else {
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) speaks protocol \(range), "
                    + "and this app speaks \(hostRange)."
            )
        }
    }

    /// The same check, against the range the plugin claimed for itself.
    ///
    /// A separate name rather than a second argument, so the two
    /// checks cannot be reached in the wrong order: one is about what
    /// the build promised and runs before anything is started, the
    /// other is about what this process will actually speak and runs
    /// on an answer that could say anything.
    private func checkProtocolCompatibility(of described: ProviderDescriptor) throws {
        try checkProtocolCompatibility(described.protocolRange)
    }

    /// The descriptor from the last successful handshake.
    public func currentDescriptor() -> ProviderDescriptor? {
        descriptor
    }

    /// Asks the plugin to finish, then makes sure it has.
    ///
    /// Closing stdin first is the whole protocol for a well-behaved plugin: it is
    /// reading lines, and end of input is how it learns to stop. The kill is
    /// there for the plugin that does not, and for the one that ignores the
    /// polite request as well.
    public func shutdown() async {
        guard let handle else { return }
        try? handle.closeInput()
        await handle.terminate()
        self.handle = nil
        readerTask?.cancel()
        readerTask = nil
        descriptor = nil
        buffer = Data()
        pending = [:]
        outputClosed = false
        framingFailed = false
    }

    // MARK: - Calls

    /// Asks the plugin to connect an account, with what the user supplied.
    ///
    /// The credential travels in the framed request and nowhere else —
    /// not the argv, not the environment — because both of those are
    /// readable by anything else on the machine for as long as the
    /// plugin runs. The host never interprets the string: what counts as
    /// a credential belongs to the plugin, which is the side that has to
    /// be right about it.
    public func connect(credentials: String?) async throws -> ConnectResult {
        let result = try await call(.connect, payload: .connect(ConnectRequest(credentials: credentials)))
        switch result {
        case .success(.connect(let connectResult)): return connectResult
        case .success: throw ProviderError(code: .invalidResponse)
        case .failure(let error): throw error
        }
    }

    /// Asks the plugin to stop acting for the connected account.
    ///
    /// Nothing comes back worth having: a disconnect is answered with
    /// the same payload a connect is, so the most it can report is which
    /// account the plugin is now acting for, and after a disconnect that
    /// is none. The call still has to succeed, because a plugin that
    /// ignored it has not stopped.
    public func disconnect() async throws {
        _ = try await call(.disconnect, payload: .disconnect(DisconnectRequest()))
    }

    /// Asks the plugin what it has measured, for the day the caller named.
    ///
    /// The day is named rather than inferred, and the account is not:
    /// the caller has already established which account is connected, so
    /// the request carries only what the plugin cannot work out for
    /// itself. An answer of the wrong kind is refused rather than read
    /// as a usage result, because the host has no way to tell which of
    /// the three payload shapes it was handed.
    public func fetchUsage(localDate: String) async throws -> UsageResult {
        let result = try await call(
            .fetchUsage, payload: .fetchUsage(FetchUsageRequest(localDate: localDate))
        )
        switch result {
        case .success(.usage(let usage)): return usage
        case .success: throw ProviderError(code: .invalidResponse)
        case .failure(let error): throw error
        }
    }

    /// Whether a plugin is running, for the manager to show before it is used.
    public func isRunning() -> Bool {
        handle?.isRunning ?? false
    }

    // MARK: - The call itself

    /// Sends one request and waits for the answer to that request.
    ///
    /// Correlation by identifier rather than by order, because the host may have
    /// calls in flight at once and a plugin may finish them in any order.
    /// Anything that arrives without a matching id in flight is dropped: a plugin
    /// that logs to stdout, or answers a request it was never sent, must not have
    /// its output mistaken for an answer.
    private func call(
        _ method: PluginMethod,
        payload: PluginRequestPayload?
    ) async throws -> PluginResult {
        guard let handle, handle.isRunning else {
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) is not running."
            )
        }

        nextRequestIndex += 1
        let request = PluginRequest(id: "req-\(nextRequestIndex)", method: method, payload: payload)
        do {
            try handle.writeLine(try PluginFraming.encode(request))
        } catch {
            await shutdown()
            throw ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) stopped listening."
            )
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while true {
            if let result = takeResponse(matching: request.id) {
                return result
            }
            if let failure = unrecoverable() {
                await shutdown()
                throw failure
            }
            // A deadline, not a retry. A plugin that has not answered once will not
            // answer on the second attempt, and a hung plugin must not be able to
            // hold the app — so the process goes, not just the call.
            guard ContinuousClock.now < deadline else {
                await shutdown()
                throw ProviderError(
                    code: .pluginError,
                    message: "\(launch.displayName) did not answer in time."
                )
            }
            try? await Task.sleep(for: .milliseconds(PluginHostConstants.pollIntervalMilliseconds))
        }
    }

    /// Reads the plugin's output for as long as it runs.
    ///
    /// One reader for the whole process, because the stream it consumes can only be
    /// consumed once. Every call in flight shares this reader and claims from what
    /// it decodes, which is also what keeps two concurrent calls from each taking
    /// the other's answer.
    private func startReader() {
        guard let handle else { return }
        let chunks = handle.output()
        readerTask = Task { [weak self] in
            do {
                for try await chunk in chunks {
                    await self?.ingest(chunk)
                }
            } catch {
                // The pipe broke. The calls waiting on it fail on `outputClosed`.
            }
            await self?.noteOutputClosed()
        }
    }

    /// Adds a chunk from the pipe to the byte buffer, and decodes
    /// whatever is now complete.
    ///
    /// Split out of the reader loop so the loop reads as "take chunks,
    /// hand them here", and so the two questions a chunk raises — is a
    /// message finished, and is what arrived a message — have one place
    /// that can answer both. Both are answered by dropping everything
    /// after the failure, not by attempting to resynchronise: past a
    /// framing error there is no way to know where the next message
    /// begins.
    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        drainBuffer()
    }

    /// Moves every complete message out of the byte buffer and into `pending`.
    ///
    /// On the reader, so a message is decoded once and held for whichever call asked
    /// for that id — rather than being consumed by whoever happened to be awake.
    private func drainBuffer() {
        while true {
            let framed: (message: Data, consumed: Int)
            do {
                guard let decoded = try PluginFraming.decodeNext(from: &buffer) else { return }
                framed = decoded
            } catch {
                // A framing failure is the plugin breaking the one rule of the
                // protocol, and the buffer is no longer trustworthy past this point,
                // so this is fatal to the process rather than to one call.
                framingFailed = true
                return
            }
            guard
                let response = try? PluginJSON.decoder.decode(
                    PluginResponse.self, from: framed.message
                )
            else {
                framingFailed = true
                return
            }
            // No id means a log line or a stray write; an id for a call that is no
            // longer waiting means a late answer. Dropping both is the only safe
            // reading — attributing either to the current call would let it
            // overwrite the right answer with the wrong one.
            guard let id = response.id else { continue }
            pending[id] = response.result
        }
    }

    /// Records that the plugin's output has ended for good.
    ///
    /// Set once and never cleared for the life of the handle, because a
    /// pipe cannot reopen: every call waiting on the stream learns from
    /// this that nothing further is coming. Waiting on a stream that has
    /// already finished is the difference between a call that fails and
    /// one that sits until its deadline and then blames the plugin for
    /// the silence.
    private func noteOutputClosed() {
        outputClosed = true
    }

    /// The answer waiting for `id`, if it has arrived, claiming it.
    private func takeResponse(matching id: String) -> PluginResult? {
        pending.removeValue(forKey: id)
    }

    /// Why waiting cannot pay off, if it cannot.
    ///
    /// Output that stopped making sense, output that ended, or a process that has
    /// gone: none of those turn into an answer with more waiting, and a call that
    /// kept waiting would be spending a deadline it will not be given.
    private func unrecoverable() -> ProviderError? {
        if framingFailed {
            return ProviderError(
                code: .invalidResponse,
                message: "\(launch.displayName) sent something unreadable."
            )
        }
        if outputClosed || handle?.isRunning != true {
            return ProviderError(
                code: .pluginError,
                message: "\(launch.displayName) stopped before answering."
            )
        }
        return nil
    }
}
