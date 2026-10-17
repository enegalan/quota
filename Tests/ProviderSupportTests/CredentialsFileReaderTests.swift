import Foundation
import Testing
@testable import ProviderSupport

@Suite("Credential files")
struct CredentialsFileReaderTests {
    /// A file in the test's own temporary directory, removed afterwards.
    private func withFile(
        named name: String,
        contents: String,
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-credential-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try body(url)
    }

    @Test("The first non-empty among the keys the plugin asked for")
    func firstMatchingKey() throws {
        try withFile(named: "auth.json", contents: #"{"access_token": "", "token": "abc"}"#) { url in
            #expect(CredentialsFileReader.token(at: url, keys: ["accessToken", "token"]) == "abc")
        }
    }

    @Test("Keys are tried in the order the plugin named them, not alphabetically")
    func keyOrder() throws {
        try withFile(
            named: "auth.json",
            contents: #"{"token": "second", "accessToken": "first"}"#
        ) { url in
            #expect(CredentialsFileReader.token(at: url, keys: ["token", "accessToken"]) == "second")
            #expect(
                CredentialsFileReader.token(at: url, keys: ["accessToken", "token"]) == "first"
            )
        }
    }

    @Test("A file that is not JSON, or not there, is a source that has nothing")
    func unreadableIsAbsent() throws {
        try withFile(named: "auth.json", contents: "not json") { url in
            #expect(CredentialsFileReader.token(at: url, keys: ["token"]) == nil)
        }

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-no-such-\(UUID().uuidString).json")
        #expect(CredentialsFileReader.token(at: missing, keys: ["token"]) == nil)
    }

    @Test("A file that holds a number where a token was expected is not a token")
    func nonStringIsNotAToken() throws {
        try withFile(named: "auth.json", contents: #"{"token": 42}"#) { url in
            #expect(CredentialsFileReader.token(at: url, keys: ["token"]) == nil)
        }
    }
}
