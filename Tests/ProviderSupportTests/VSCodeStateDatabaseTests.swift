import Foundation
import SQLite3
import Testing
@testable import ProviderSupport

@Suite("The editor's state database")
struct VSCodeStateDatabaseTests {
    /// A database with the editor's own shape, in the test's own directory.
    private func withDatabase(
        items: [String: String],
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-state-db-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("state.vscdb")
        try writeDatabase(at: url, items: items)
        try body(url)
    }

    private func writeDatabase(at url: URL, items: [String: String]) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            == SQLITE_OK,
            let database = handle
        else {
            Issue.record("could not create the test database")
            return
        }
        defer { sqlite3_close(database) }

        exec(database, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        for (key, value) in items {
            let sql = "INSERT INTO ItemTable (key, value) VALUES (?, ?)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let prepared = statement
            else { continue }
            defer { sqlite3_finalize(prepared) }
            sqlite3_bind_text(prepared, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(prepared, 2, (value as NSString).utf8String, -1, nil)
            _ = sqlite3_step(prepared)
        }
    }

    private func exec(_ database: OpaquePointer?, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            sqlite3_free(error)
            return
        }
    }

    @Test("The stored value comes back for the key it was filed under")
    func readsStoredItem() throws {
        try withDatabase(items: [
            "cursorAuth/accessToken": "tok-123",
            "cursorAuth/cachedEmail": "user@example.com",
        ]) { url in
            let token = try VSCodeStateDatabase.item(key: "cursorAuth/accessToken", at: url)
            let email = try VSCodeStateDatabase.item(key: "cursorAuth/cachedEmail", at: url)
            #expect(token == "tok-123")
            #expect(email == "user@example.com")
        }
    }

    @Test("A key the editor has never stored is a sign-in the user has never done")
    func missingKey() throws {
        try withDatabase(items: [:]) { url in
            do {
                _ = try VSCodeStateDatabase.item(key: "cursorAuth/accessToken", at: url)
                Issue.record("expected a failure")
            } catch VSCodeStateDatabaseError.missingItem {
                // The reading a plugin reports from this is "sign in", which is
                // the one thing a user can do about it.
                #expect(
                    VSCodeStateDatabaseError.missingItem.providerError.code == .notAuthenticated
                )
            } catch {
                Issue.record("expected missingItem, got \(error)")
            }
        }
    }

    @Test("A file that is not a database at all cannot be read as one")
    func notADatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-state-db-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("state.vscdb")
        try "not a database".write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: VSCodeStateDatabaseError.self) {
            try VSCodeStateDatabase.item(key: "anything", at: url)
        }
    }

    @Test("A database without the editor's table cannot answer as one")
    func wrongShape() throws {
        try withDatabase(items: [:]) { url in
            // Re-create the file with a table the reader does not know.
            try writeOtherShape(at: url)
            #expect(throws: VSCodeStateDatabaseError.self) {
                try VSCodeStateDatabase.item(key: "anything", at: url)
            }
        }
    }

    private func writeOtherShape(at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database = handle
        else {
            Issue.record("could not rewrite the test database")
            return
        }
        defer { sqlite3_close(database) }
        exec(database, "DROP TABLE IF EXISTS ItemTable")
        exec(database, "CREATE TABLE SomethingElse (k TEXT)")
    }
}
