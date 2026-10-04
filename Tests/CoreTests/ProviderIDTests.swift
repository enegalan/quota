import Foundation
import Testing
@testable import Core

@Suite("ProviderID")
struct ProviderIDTests {
    @Test("A plain identifier is accepted")
    func acceptsPlainIdentifier() throws {
        #expect(try ProviderID("mock").rawValue == "mock")
    }

    @Test("Empty identifiers are rejected")
    func rejectsEmpty() {
        #expect(throws: QuotaDomainError.self) { try ProviderID("") }
    }

    @Test("Identifiers containing whitespace are rejected")
    func rejectsWhitespace() {
        for value in ["two words", " leading", "trailing ", "tab\there", "new\nline"] {
            #expect(throws: QuotaDomainError.self) { try ProviderID(value) }
        }
    }

    @Test("A rejected identifier reports why")
    func errorDescription() {
        let error = QuotaDomainError.invalidIdentifier("bad id")
        #expect(error.description.contains("bad id"))
    }

    @Test("Identifiers round trip through Codable")
    func codableRoundTrip() throws {
        let identifier = try ProviderID("mock")
        let data = try JSONEncoder().encode(identifier)
        #expect(String(data: data, encoding: .utf8) == "\"mock\"")
        #expect(try JSONDecoder().decode(ProviderID.self, from: data) == identifier)
    }

    @Test("Decoding rejects an invalid identifier instead of accepting it")
    func decodingValidates() {
        let invalid = Data("\"has space\"".utf8)
        #expect(throws: QuotaDomainError.self) {
            try JSONDecoder().decode(ProviderID.self, from: invalid)
        }
    }

    @Test("Identifiers are hashable so they can key a dictionary")
    func hashable() throws {
        let first = try ProviderID("mock")
        let second = try ProviderID("mock")
        var counts: [ProviderID: Int] = [:]
        counts[first, default: 0] += 1
        counts[second, default: 0] += 1
        #expect(counts[first] == 2)
    }
}
