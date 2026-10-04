import Foundation
import PluginKit

//  A fake provider plugin, run as a real process by PluginHostTests.
//
//  A real process on purpose. The host's job is to cope with things that only
//  happen to real processes — dying mid-handshake, never answering, writing
//  nonsense to stdout, filling stderr — and a mock returning a canned reply
//  cannot fail in any of those ways, so every test written against a mock is a
//  test of the mock. This one can, and is asked to.
//
//  The behaviour is chosen by the first argument, so one executable covers every
//  way a plugin can misbehave and a test can name the misbehaviour it exercises.

/// The misbehaviours this fake can be asked for.
private enum Behaviour: String {
    /// Answers every method correctly.
    case wellBehaved = "well-behaved"
    /// Reads requests and never answers.
    case silent
    /// Exits before answering anything.
    case exitsImmediately = "exits-immediately"
    /// Answers with a line that is not JSON.
    case malformed
    /// Writes a line longer than the host will accept.
    case overlongLine = "overlong-line"
    /// Sends a message nobody asked for, then answers correctly.
    case unsolicited
    /// Answers a call the host is not waiting for, then answers correctly.
    case misidentified
    /// Holds the first two requests and answers them in the opposite order.
    case reverseOrder = "reverse-order"
    /// Answers `describe`, then exits before the next call.
    case exitsBetweenCalls = "exits-between-calls"
    /// Claims a protocol range the host cannot speak.
    case incompatibleProtocol = "incompatible-protocol"
    /// Claims to be a different provider.
    case wrongIdentity = "wrong-identity"
    /// Answers correctly, after writing a lot to stderr.
    case noisyStderr = "noisy-stderr"
}

private let behaviour = Behaviour(
    rawValue: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "well-behaved"
) ?? .wellBehaved

/// The protocol range this fake claims.
private let claimedRange: ProtocolRange = behaviour == .incompatibleProtocol
    ? ProtocolRange(
        minimum: Version(major: 2, minor: 0, patch: 0),
        maximum: Version(major: 2, minor: 9, patch: 0)
    )
    : PluginProtocolConstants.hostRange

/// The identifier this fake claims.
private let claimedID = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "mock"

/// How many requests `reverseOrder` holds before answering.
private let reverseOrderBatch = 2

private func writeRaw(_ bytes: Data) {
    FileHandle.standardOutput.write(bytes)
}

private func descriptor() -> ProviderDescriptor {
    ProviderDescriptor(
        id: behaviour == .wrongIdentity ? "somebody-else" : claimedID,
        displayName: "Fake",
        description: "A fake provider used by tests.",
        capabilities: [.automaticUsageRetrieval, .multipleQuotas],
        protocolRange: claimedRange
    )
}

private func answer(_ request: PluginRequest) -> PluginResponse {
    let result: PluginResult = switch request.method {
    case .describe:
        .success(.describe(descriptor()))
    case .connect:
        .success(.connect(ConnectResult(accountLabel: "work")))
    case .disconnect:
        .success(.connect(ConnectResult()))
    case .fetchUsage:
        .success(.usage(UsageResult(quotas: [
            ProviderUsage(
                externalID: "ext-1",
                displayName: "Fake Quota",
                bucketID: "models",
                bucketDisplayName: "Models",
                usagePercentage: 12.5,
                periodStart: "2026-09-01",
                periodEnd: "2026-09-30",
                updatedAt: "2026-09-25T10:00:00Z"
            ),
        ])))
    }
    return PluginResponse(id: request.id, result: result)
}

if behaviour == .exitsImmediately {
    exit(0)
}

if behaviour == .noisyStderr {
    // Enough stderr to overflow a pipe buffer, which a real plugin does by
    // accident. The host must not be blocked waiting on it.
    for index in 0 ..< 2000 {
        FileHandle.standardError.write(
            Data("a plugin talking at length about something: \(index)\n".utf8)
        )
    }
}

let side = PluginSide()
var heldForReversal: [PluginRequest] = []

while let request = side.nextRequest() {
    switch behaviour {
    case .silent:
        // Keep reading, so the host sees a hang rather than a crash.
        continue

    case .malformed:
        writeRaw(Data("{not json at all\n".utf8))
        continue

    case .overlongLine:
        writeRaw(Data(String(repeating: "x", count: PluginProtocolConstants.maximumLineLength * 2).utf8))
        writeRaw(Data([0x0A]))
        continue

    case .unsolicited:
        if request.method == .describe {
            // A log line shaped like a response, with no id to match.
            writeRaw(Data(#"{"id":null,"result":{"kind":"success","value":{"kind":"connect","value":{}}}}"#.utf8))
            writeRaw(Data([0x0A]))
        }
        try? side.write(answer(request))

    case .misidentified:
        if request.method == .describe {
            var response = answer(request)
            // Answers someone else's call, correctly shaped. The host must keep
            // waiting for its own rather than take this one.
            if case .success(let payload) = response.result {
                response = PluginResponse(id: "req-someone-else", result: .success(payload))
            }
            try? side.write(response)
        }
        try? side.write(answer(request))

    case .reverseOrder:
        heldForReversal.append(request)
        if heldForReversal.count == reverseOrderBatch {
            // Both are in flight at once. Answering the later one first is what
            // makes an order-based host misattribute them.
            for held in heldForReversal.reversed() {
                try? side.write(answer(held))
            }
            heldForReversal.removeAll()
        }

    case .exitsBetweenCalls:
        if request.method == .describe {
            try? side.write(answer(request))
            continue
        }
        exit(0)

    case .incompatibleProtocol, .wrongIdentity, .wellBehaved, .noisyStderr:
        try? side.write(answer(request))

    case .exitsImmediately:
        // Already handled above, before a single request was read. Spelled out
        // here so the switch stays exhaustive if that ever moves.
        exit(0)
    }
}
