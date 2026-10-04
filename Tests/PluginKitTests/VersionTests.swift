import Foundation
import Testing
@testable import PluginKit

@Suite("Version")
struct VersionTests {
    private func version(_ string: String) throws -> Version {
        try #require(Version(string: string))
    }

    @Test("A version parses, and an ill-formed one does not")
    func parsing() throws {
        #expect(try version("1.2.3") == Version(major: 1, minor: 2, patch: 3))
        #expect(try version("1.2.3").description == "1.2.3")
        // Three components and no others: a version with a missing or extra
        // component is a file that is wrong, not a version with defaults filled
        // in, because a plugin could otherwise name a shape the host never
        // implemented.
        for bad in ["1", "1.2", "1.2.3.4", "1.2.x", "", "v1.2.3", "1..3", "-1.2.3", "1.2.-3"] {
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

    @Test("A version is written as the dotted string a person writes")
    func encodesAsAString() throws {
        let data = try PluginJSON.encoder.encode(Version(major: 1, minor: 2, patch: 3))
        #expect(String(data: data, encoding: .utf8) == "\"1.2.3\"")
        #expect(try PluginJSON.decoder.decode(Version.self, from: data)
            == Version(major: 1, minor: 2, patch: 3))
    }

    /// Round-trips by construction: `description` is exactly what `init?(string:)`
    /// reads, so a version that reached a file comes back the same value.
    @Test("Every version round trips through its string form")
    func roundTrip() throws {
        for string in ["0.0.0", "1.2.3", "10.20.30", "1.0.0"] {
            let original = try version(string)
            #expect(Version(string: original.description) == original)
        }
    }

    @Test("A version that is not one is refused rather than defaulted")
    func unparseableVersionIsRefused() {
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(Version.self, from: Data("\"nope\"".utf8))
        }
        // The stored form is a string, so a number written where one belongs is a
        // file that is wrong rather than a version that happens to parse.
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(Version.self, from: Data("1".utf8))
        }
    }
}
