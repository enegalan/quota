@testable import QuotaPluginClaude
import Foundation
import Testing

@Suite("Claude timestamps")
struct TimestampTests {
    @Test("An instant in UTC is read")
    func readsUTC() throws {
        let instant = try #require(
            ClaudeTimestamp.instant(from: "2026-04-08T18:59:59Z")
        )
        #expect(instant == Date(timeIntervalSince1970: 1_775_674_799))
    }

    @Test("A fraction of a second is read, and dropped")
    func readsFractionalSeconds() throws {
        let instant = try #require(
            ClaudeTimestamp.instant(from: "2025-11-04T04:59:59.943648+00:00")
        )
        #expect(instant == Date(timeIntervalSince1970: 1_762_232_399))
    }

    @Test("An offset is applied")
    func readsAnOffset() throws {
        let instant = try #require(
            ClaudeTimestamp.instant(from: "2026-04-08T13:59:59-05:00")
        )
        #expect(instant == Date(timeIntervalSince1970: 1_775_674_799))
    }

    @Test("An offset without a colon is read")
    func readsAnOffsetWithoutAColon() throws {
        let instant = try #require(
            ClaudeTimestamp.instant(from: "2026-04-08T13:59:59-0500")
        )
        #expect(instant == Date(timeIntervalSince1970: 1_775_674_799))
    }

    @Test("Text that is not a timestamp is not one")
    func refusesNonsense() {
        #expect(ClaudeTimestamp.instant(from: "tomorrow") == nil)
        #expect(ClaudeTimestamp.instant(from: "") == nil)
        #expect(ClaudeTimestamp.instant(from: "2026-04-08") == nil)
    }
}
