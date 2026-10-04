import Darwin
import Foundation

/// The newline-delimited JSON framing the host and a plugin speak.
///
/// One JSON document per line, newline-terminated. A length-prefixed frame would
/// work too, but a plugin reading its own stdin with `readLine()` cannot get that
/// wrong, and a plugin author should not have to think about framing at all.
public enum PluginFraming {
    /// The unit of transfer. Lines are bounded so a plugin that writes without a
    /// newline cannot make the host buffer without limit.
    public static let maximumLineLength = PluginProtocolConstants.maximumLineLength

    /// Encodes one message with the newline that terminates it.
    ///
    /// The newline is appended here rather than left to the caller, because a
    /// writer that forgets it produces a message the other side never finishes
    /// reading: the framing has to be impossible to omit at the point where the
    /// message becomes bytes.
    public static func encode(_ value: some Encodable) throws -> Data {
        var data = try PluginJSON.encoder.encode(value)
        data.append(0x0A)
        return data
    }

    /// Pulls one message off a buffer, leaving any partial message behind.
    ///
    /// - Returns: the message and the number of bytes consumed, or nil when the
    ///   buffer does not yet hold a whole message.
    public static func decodeNext(from buffer: inout Data) throws -> (message: Data, consumed: Int)? {
        guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
            guard buffer.count <= maximumLineLength else {
                throw PluginFramingError.lineTooLong(maximumLineLength)
            }
            return nil
        }
        let line = buffer[buffer.startIndex ..< newlineIndex]
        let consumed = buffer.distance(from: buffer.startIndex, to: newlineIndex) + 1
        buffer = Data(buffer[buffer.index(after: newlineIndex)...])
        // A blank line between messages is a plugin writing a stray newline, not
        // a message; skipping it beats failing the call.
        guard !line.isEmpty else { return try decodeNext(from: &buffer) }
        guard line.count <= maximumLineLength else {
            throw PluginFramingError.lineTooLong(maximumLineLength)
        }
        return (Data(line), consumed)
    }
}

/// A line the host or a plugin cannot use.
public enum PluginFramingError: Error, Equatable {
    /// A plugin wrote a line past the cap, with or without a newline.
    ///
    /// Bounded on purpose: an unbounded buffer is a way for a broken plugin to
    /// take the app down with memory.
    case lineTooLong(Int)
}

/// What a plugin needs to speak the protocol, and what a host needs from it.
///
/// The child side of the protocol, so a plugin author writes a loop and nothing
/// else. The host does not use this: it has to track correlations and timeouts
/// across calls, which is a different job from framing.
///
/// A class holding a partial-message buffer, and deliberately not `Sendable`:
/// this is one reader on one pipe, and `serve` is a loop rather than something
/// to call from several tasks. Declaring it `Sendable` would be a claim nothing
/// here can support — a partial line read by two callers is a framing bug, not a
/// race worth tolerating.
public final class PluginSide {
    private let output: FileHandle
    private let standardInputDescriptor: Int32
    private var buffer = Data()

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.output = output
        standardInputDescriptor = input.fileDescriptor
        // Non-blocking, so a read reports "nothing yet" instead of waiting for a
        // full buffer. Restored in `deinit` for a caller that passed its own
        // handle, so a plugin that embeds this does not leave a descriptor
        // surprising whoever owns it.
        let status = fcntl(standardInputDescriptor, F_GETFL)
        _ = fcntl(standardInputDescriptor, F_SETFL, status | O_NONBLOCK)
        originalInputStatus = status
    }

    deinit {
        _ = fcntl(standardInputDescriptor, F_SETFL, originalInputStatus)
    }

    private let originalInputStatus: Int32

    /// Reads requests until end of input.
    ///
    /// Answers whatever arrives, so a plugin's whole main loop is this one call.
    /// Returning on end of input is what lets the plugin exit when the host
    /// closes stdin, rather than needing a separate shutdown path to get right.
    public func serve(_ handle: (PluginRequest) -> PluginResponse) {
        while let request = nextRequest() {
            let response = handle(request)
            do {
                try write(response)
            } catch {
                // The pipe is gone: the host is not listening, so there is
                // nowhere to report this and nothing left to do.
                return
            }
        }
    }

    /// The next request, or nil at end of input.
    ///
    /// Reads non-blockingly. `FileHandle.read(upToCount:)` cannot be used here:
    /// on a pipe it waits until it has the full count or hits end of input, so a
    /// plugin reading a live host's stdin would sit in that call forever and never
    /// see the request already sitting in the pipe. The descriptor is put into
    /// non-blocking mode and polled, which costs a short sleep per empty read and
    /// is why this is a loop rather than a blocking read.
    public func nextRequest() -> PluginRequest? {
        while true {
            if let (message, _) = try? PluginFraming.decodeNext(from: &buffer) {
                // A plugin that emits something the host would not have sent is
                // talking to itself; skipping keeps it running.
                guard let request = try? PluginJSON.decoder.decode(PluginRequest.self, from: message)
                else { continue }
                return request
            }
            switch readAvailableBytes() {
            case .data(let chunk):
                buffer.append(chunk)
            case .wouldBlock:
                Thread.sleep(forTimeInterval: PluginProtocolConstants.idlePollSeconds)
            case .endOfInput:
                return nil
            }
        }
    }

    /// One read from stdin without waiting for more.
    private func readAvailableBytes() -> ReadOutcome {
        var bytes = [UInt8](repeating: 0, count: PluginProtocolConstants.readChunkSize)
        let count = read(standardInputDescriptor, &bytes, bytes.count)
        if count > 0 {
            return .data(Data(bytes[0 ..< count]))
        }
        // 0 is end of input. -1 with EAGAIN or EWOULDBLOCK is the ordinary case
        // that a blocking read would have hidden, and EINTR means a signal
        // arrived, so both are worth another look rather than an exit.
        if count == 0 {
            return .endOfInput
        }
        let code = errno
        if code == EAGAIN || code == EWOULDBLOCK || code == EINTR {
            return .wouldBlock
        }
        return .endOfInput
    }

    private enum ReadOutcome {
        case data(Data)
        case wouldBlock
        case endOfInput
    }

    /// Writes one response, framed, to the plugin's output.
    ///
    /// The single point where anything is written, so a plugin author cannot
    /// frame one reply by hand and another not at all — a message without its
    /// newline would leave the host's buffer waiting for a completion that
    /// never comes.
    public func write(_ response: PluginResponse) throws {
        try output.write(contentsOf: try PluginFraming.encode(response))
    }
}
