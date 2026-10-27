import Foundation
import Testing

enum JetBrainsFixture {
    static func xml(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }
}
