import Foundation
import Testing

/// The fixture the normaliser tests read.
///
/// Loaded from the bundle rather than written out in the test, so the payload
/// the tests read is the payload the plugin would read.
enum ClaudeFixture {
    static func json(_ name: String) throws -> [String: Any] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
