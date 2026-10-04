import Darwin
import Foundation
import PluginKit

/// The result of trying to start and talk to a plugin.
///
/// A test, not a production path. Injection is not a testing nicety here: the only
/// way to know a timeout actually kills the process is to run a process and watch
/// the clock, and a test that mocks the process out cannot tell the difference
/// between "the host gave up" and "the host pretended to give up".
public protocol ProcessLaunching: Sendable {
    /// Starts a plugin.
    ///
    /// `arguments` is here because a launcher is the one place that knows how to
    /// build an argv, and the test fixture needs to be told how to misbehave. It
    /// is empty in production: a real plugin is launched with no arguments at all,
    /// so there is nothing in the app's hands to smuggle into a plugin's argv.
    func launch(
        executable: URL,
        environment: [String: String],
        arguments: [String]
    ) throws -> any ProcessHandle
}

/// The host's side of one running plugin.
public protocol ProcessHandle: Sendable {
    /// Writes one line to the plugin's stdin.
    func writeLine(_ data: Data) throws

    /// The plugin's stdout, as chunks arrive.
    ///
    /// A stream rather than a poll. `FileHandle.availableData` on a pipe has no
    /// dependable non-blocking behaviour across Foundation versions — it can sit
    /// until something arrives, which is indistinguishable from a plugin that has
    /// stopped, and it cannot be combined with a deadline. One blocking reader on
    /// its own task, feeding a stream, is both predictable and interruptible: a
    /// call that times out stops waiting on the stream, and the reader notices the
    /// process is gone when the pipe closes.
    func output() -> AsyncThrowingStream<Data, any Error>

    /// Closes stdin, which is how the host asks a plugin to finish.
    func closeInput() throws

    /// Asks the process to stop, then waits briefly and kills it if it has not.
    func terminate() async

    /// Whether the process is still running.
    var isRunning: Bool { get }

    /// The exit status, once it has exited.
    var terminationStatus: Int32? { get }
}

/// Why a launch did not produce a usable process.
public enum ProcessLaunchError: Error, Equatable {
    /// No executable at that path.
    case notFound(String)

    /// The path is not something this host will run.
    case notExecutable(String)

    /// The spawn itself failed.
    case spawnFailed(String)
}

/// A `Process`, made usable as a `ProcessHandle`.
///
/// The three pipes are the whole protocol: stdin for requests, stdout for
/// responses, stderr for whatever the plugin wants to say about itself. The last
/// one goes to a file rather than a pipe on purpose — nobody reads it, and a pipe
/// nobody reads fills up and blocks the plugin forever, which would present as a
/// plugin that stopped answering.
public struct SystemProcessHandle: ProcessHandle {
    private let process: Process
    private let outputPipe: Pipe
    private let reader = OutputReader()

    public init(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String],
        standardErrorURL: URL
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = try FileHandle(forWritingTo: standardErrorURL)

        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ProcessLaunchError.notExecutable(executable.path)
        }
        do {
            try process.run()
        } catch {
            throw ProcessLaunchError.spawnFailed(executable.path)
        }
        self.process = process
        outputPipe = output
    }

    /// Writes one framed request to the plugin's stdin.
    ///
    /// Through the pipe the process was launched with, so the bytes the
    /// host believes it sent are the bytes the plugin receives. There is
    /// no other stdin to write to, and its absence is reported rather
    /// than skipped: a request that quietly went nowhere would leave
    /// the call waiting out its deadline for an answer to something
    /// never asked.
    public func writeLine(_ data: Data) throws {
        guard let input = process.standardInput as? Pipe else {
            throw ProcessLaunchError.spawnFailed("no stdin")
        }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    /// The plugin's stdout as chunks arrive, finishing when the pipe closes.
    ///
    /// Each request for a stream builds its own reader over the same
    /// descriptor, and whoever asks first reads the bytes. That is why
    /// the host takes one stream for the life of the process and hands
    /// it out: two readers on one pipe split every message in half
    /// between them rather than one of them seeing all of it.
    public func output() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            // Non-blocking by construction. `FileHandle.read(upToCount:)` and
            // `availableData` both look like they can report "nothing yet" on a
            // pipe, and neither can: the first blocks until it has the whole count
            // or hits EOF, and the second's behaviour has varied between
            // Foundation versions. Both look like a hung plugin.
            //
            // So the descriptor is put into non-blocking mode and read directly,
            // driven by a dispatch source that fires when there is something to
            // read. `EAGAIN` means nothing yet, `0` means the plugin closed its
            // stdout, and anything else is data.
            let descriptor = outputPipe.fileHandleForReading.fileDescriptor
            let originalStatus = fcntl(descriptor, F_GETFL)
            _ = fcntl(descriptor, F_SETFL, originalStatus | O_NONBLOCK)

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global())
            source.setEventHandler {
                var buffer = [UInt8](repeating: 0, count: PluginProtocolConstants.readChunkSize)
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    continuation.yield(Data(buffer[0 ..< count]))
                } else if count == 0 {
                    // End of stdout: the plugin is finished.
                    source.cancel()
                    continuation.finish()
                }
                // count < 0 with EAGAIN or EINTR means nothing to read right now,
                // which is the case the dispatch source exists to make cheap.
            }
            source.setCancelHandler {
                _ = fcntl(descriptor, F_SETFL, originalStatus)
            }
            reader.adopt(source)
            source.resume()
        }
    }

    /// Closes stdin, which is how a plugin is asked to finish.
    ///
    /// Failure to close is dropped rather than thrown: a plugin that has
    /// already closed its own end, or that has died, has been asked to
    /// stop either way. Failing the shutdown because the polite request
    /// could not be delivered would leave a live process behind, held
    /// by nothing but the one signal that reliably stops it.
    public func closeInput() throws {
        guard let input = process.standardInput as? Pipe else { return }
        try? input.fileHandleForWriting.close()
    }

    /// Stops the process: asks, waits, then kills.
    ///
    /// The reader is stopped first because it holds a dispatch source on
    /// the pipe, which would otherwise keep firing against a descriptor
    /// the process is on its way back from owning. The wait is bounded
    /// because a plugin is third-party code and a plugin that ignores the
    /// polite request is a case that will happen: a shutdown with no
    /// deadline hands the app's whole remaining lifetime to code it did
    /// not write.
    public func terminate() async {
        // The reader holds a dispatch source on the pipe; stopping it first means
        // a dead process cannot leave one firing on a closed descriptor.
        reader.cancel()
        guard process.isRunning else { return }
        process.terminate()
        // A polite request first, so a plugin can tidy up; then a kill, because a
        // plugin that ignores the first request must not hold the app open.
        let deadline = ContinuousClock.now.advanced(
            by: .seconds(PluginProtocolConstants.shutdownTimeout)
        )
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(PluginHostConstants.terminatePollMilliseconds))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public var terminationStatus: Int32? {
        guard !process.isRunning else { return nil }
        return process.terminationStatus
    }
}

/// Launches plugins as real processes.
public struct SystemProcessLauncher: ProcessLaunching {
    /// Where a plugin's stderr goes.
    public let logDirectory: URL

    public init(logDirectory: URL) {
        self.logDirectory = logDirectory
    }

    /// Starts a plugin, with its stderr redirected to a log file of its own.
    ///
    /// Existence is checked before anything is created or launched, so a
    /// path that is not there is reported as what it is rather than as a
    /// spawn failure the caller has to work backwards from. The three
    /// refusals stay separate — absent, not executable, refused — because
    /// they are three different answers and only one of them says anything
    /// about the file the plugin was installed from.
    public func launch(
        executable: URL,
        environment: [String: String],
        arguments: [String] = []
    ) throws -> any ProcessHandle {
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw ProcessLaunchError.notFound(executable.path)
        }
        try FileManager.default.createDirectory(
            at: logDirectory, withIntermediateDirectories: true
        )
        let logURL = logDirectory.appendingPathComponent(
            "\(executable.deletingPathExtension().lastPathComponent).log"
        )
        // Created, not just opened: `FileHandle(forWritingTo:)` fails on a path
        // that does not exist yet, and a plugin's stderr has to have somewhere to
        // go before the process starts.
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        return try SystemProcessHandle(
            executable: executable,
            arguments: arguments,
            environment: environment,
            standardErrorURL: logURL
        )
    }
}

/// Owns the dispatch source reading one process's stdout.
///
/// A box because a `Process` handle is a value that gets copied, and the source
/// has to be one object: cancelling a copy while another copy kept reading would
/// leave a handler firing on a closed descriptor.
private final class OutputReader: @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceRead?

    /// Replaces any current source, cancelling the old one.
    func adopt(_ new: DispatchSourceRead) {
        lock.lock()
        let previous = source
        source = new
        lock.unlock()
        previous?.cancel()
    }

    /// Cancels the source being read, if there is one, and forgets it.
    ///
    /// Also called from `deinit`, so a handle that is released mid-read
    /// does not leave a dispatch source alive against a pipe that is
    /// about to be closed underneath it.
    func cancel() {
        lock.lock()
        let previous = source
        source = nil
        lock.unlock()
        previous?.cancel()
    }

    deinit {
        cancel()
    }
}
