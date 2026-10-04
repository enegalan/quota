import Foundation
import Testing
@testable import PluginKit

@Suite("Protocol range")
struct ProtocolRangeTests {
    private func version(_ string: String) throws -> Version {
        try #require(Version(string: string))
    }

    @Test("A version parses, and an ill-formed one does not")
    func parsing() throws {
        #expect(try version("1.2.3") == Version(major: 1, minor: 2, patch: 3))
        #expect(try version("1.2.3").description == "1.2.3")
        for bad in ["1.2", "1.2.3.4", "1.2.x", "", "v1.2.3", "1..3", "-1.2.3"] {
            #expect(Version(string: bad) == nil, "\(bad) should not parse")
        }
    }

    /// The reason this is a type and not a string: `1.10.0` is newer than
    /// `1.9.0`, and a string compare says otherwise.
    @Test("Versions order numerically, not lexically")
    func ordering() throws {
        #expect(try version("1.10.0") > version("1.9.0"))
        #expect(try version("2.0.0") > version("1.99.99"))
        #expect(try version("1.0.1") > version("1.0.0"))
        #expect(try version("1.0.0") == version("1.0.0"))
    }

    @Test("A range includes both of its ends")
    func containment() throws {
        let range = try ProtocolRange(from: "1.0.0..<1.5.0")
        #expect(range.contains(try version("1.0.0")))
        #expect(range.contains(try version("1.4.9")))
        #expect(range.contains(try version("1.5.0")))
        #expect(!range.contains(try version("0.9.9")))
        #expect(!range.contains(try version("1.5.1")))
    }

    @Test("A range that starts after it ends is refused")
    func invertedRangeIsRefused() {
        #expect(throws: ProtocolRangeError.inverted("1.5.0..<1.0.0")) {
            try ProtocolRange(from: "1.5.0..<1.0.0")
        }
    }

    @Test("A string that is not a range is refused")
    func malformedRangeIsRefused() {
        for bad in ["1.0.0", "1.0.0..1.5.0", "a..<b", "..<", "1.0.0..<1.5.0..<2.0.0"] {
            #expect(throws: (any Error).self, "\(bad) should not parse") {
                try ProtocolRange(from: bad)
            }
        }
    }

    @Test("A range round trips through its string form")
    func roundTrip() throws {
        let range = try ProtocolRange(from: "1.0.0..<1.9.0")
        #expect(range.description == "1.0.0..<1.9.0")
        let reparsed = try ProtocolRange(from: range.description)
        #expect(reparsed == range)
    }

    // MARK: Compatibility

    @Test("A plugin inside the host's range is accepted")
    func containedRangeIsAccepted() throws {
        let host = try ProtocolRange(from: "1.0.0..<1.9.0")
        let plugin = try ProtocolRange(from: "1.2.0..<1.4.0")
        #expect(plugin.isCompatible(with: host))
        #expect(plugin.firstCommonVersion(with: host) == (try version("1.2.0")))
    }

    @Test("A plugin whose range runs past the host's is rejected")
    func overshootingRangeIsRejected() throws {
        let host = try ProtocolRange(from: "1.0.0..<1.9.0")
        let plugin = try ProtocolRange(from: "1.2.0..<2.0.0")
        #expect(!plugin.isCompatible(with: host))
        #expect(plugin.firstCommonVersion(with: host) == nil)
    }

    @Test("A plugin older than the host is rejected")
    func undershootingRangeIsRejected() throws {
        let host = try ProtocolRange(from: "1.0.0..<1.9.0")
        let plugin = try ProtocolRange(from: "0.9.0..<1.4.0")
        #expect(!plugin.isCompatible(with: host))
    }

    @Test("A major version apart is rejected, even where the numbers overlap")
    func majorVersionIsRejected() throws {
        let host = try ProtocolRange(from: "1.0.0..<1.9.0")
        let plugin = try ProtocolRange(from: "2.0.0..<2.5.0")
        #expect(!plugin.isCompatible(with: host))
    }

    /// Overlap is deliberately not enough. Accepting a plugin that merely
    /// overlaps would let it be asked to speak a version it never implemented, and
    /// that failure would show up as a malformed answer to a real call — after a
    /// user had connected the provider.
    @Test("Overlap alone is not compatibility")
    func overlapIsNotCompatibility() throws {
        let host = try ProtocolRange(from: "1.0.0..<1.5.0")
        let plugin = try ProtocolRange(from: "1.4.0..<1.9.0")
        let overlapping = try version("1.4.5")
        #expect(plugin.contains(overlapping))
        #expect(host.contains(overlapping))
        #expect(!plugin.isCompatible(with: host))
    }

    @Test("The host's own range covers the version it negotiates")
    func hostRangeIsSelfConsistent() {
        #expect(PluginProtocolConstants.hostRange.contains(PluginProtocolConstants.negotiatedVersion))
    }

    @Test("A range round trips through JSON")
    func jsonRoundTrip() throws {
        let range = try ProtocolRange(from: "1.0.0..<1.9.0")
        let data = try PluginJSON.encoder.encode(range)
        #expect(try PluginJSON.decoder.decode(ProtocolRange.self, from: data) == range)
    }
}

@Suite("Framing")
struct FramingTests {
    @Test("A message round trips through a line")
    func messageRoundTrip() throws {
        let request = PluginRequest(id: "req-1", method: .describe)
        var data = try PluginFraming.encode(request)
        #expect(data.last == 0x0A)
        let encodedLength = data.count

        let (message, consumed) = try #require(try PluginFraming.decodeNext(from: &data))
        #expect(consumed == encodedLength)
        #expect(try PluginJSON.decoder.decode(PluginRequest.self, from: message) == request)
        #expect(data.isEmpty)
    }

    @Test("Two messages in one buffer come out one at a time")
    func twoMessagesInOneBuffer() throws {
        var buffer = Data()
        for index in 0 ..< 3 {
            buffer.append(try PluginFraming.encode(
                PluginRequest(id: "req-\(index)", method: .describe)
            ))
        }
        for index in 0 ..< 3 {
            let (message, _) = try #require(try PluginFraming.decodeNext(from: &buffer))
            let request = try PluginJSON.decoder.decode(PluginRequest.self, from: message)
            #expect(request.id == "req-\(index)")
        }
        #expect(buffer.isEmpty)
    }

    /// The reason a partial read is not an error: a pipe hands over whatever
    /// happened to be in it, which is rarely a whole line.
    @Test("A partial message is left in the buffer, not lost or misread")
    func partialMessageStaysBuffered() throws {
        let full = try PluginFraming.encode(PluginRequest(id: "req-1", method: .describe))
        var buffer = full.prefix(10)
        #expect(try PluginFraming.decodeNext(from: &buffer) == nil)

        buffer.append(full.dropFirst(10))
        let (message, _) = try #require(try PluginFraming.decodeNext(from: &buffer))
        #expect(try PluginJSON.decoder.decode(PluginRequest.self, from: message).id == "req-1")
    }

    @Test("A blank line between messages is skipped, not treated as a message")
    func blankLineIsSkipped() throws {
        var buffer = Data([0x0A])
        buffer.append(try PluginFraming.encode(PluginRequest(id: "req-1", method: .describe)))
        let (message, _) = try #require(try PluginFraming.decodeNext(from: &buffer))
        #expect(try PluginJSON.decoder.decode(PluginRequest.self, from: message).id == "req-1")
    }

    /// A broken plugin must not be able to make the host allocate without bound.
    @Test("A line with no newline past the cap is refused rather than buffered")
    func overlongLineIsRefused() {
        var buffer = Data(repeating: 0x41, count: PluginFraming.maximumLineLength + 1)
        #expect(throws: PluginFramingError.lineTooLong(PluginFraming.maximumLineLength)) {
            _ = try PluginFraming.decodeNext(from: &buffer)
        }
    }

    @Test("A line past the cap is refused even when it does end")
    func overlongCompleteLineIsRefused() {
        var buffer = Data(repeating: 0x41, count: PluginFraming.maximumLineLength + 1)
        buffer.append(0x0A)
        #expect(throws: PluginFramingError.lineTooLong(PluginFraming.maximumLineLength)) {
            _ = try PluginFraming.decodeNext(from: &buffer)
        }
    }

    @Test("An empty buffer yields nothing")
    func emptyBuffer() throws {
        var buffer = Data()
        #expect(try PluginFraming.decodeNext(from: &buffer) == nil)
    }
}
