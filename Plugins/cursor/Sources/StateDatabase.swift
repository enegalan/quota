import Foundation
import SQLite3

enum StateDatabaseError: Error, Equatable {
    case openFailed
    case prepareFailed
    case missingAccessToken
}

enum StateDatabase {
    static var defaultPath: URL {
        if let override = ProcessInfo.processInfo.environment[
            CursorConstants.stateDatabasePathEnvironment
        ], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(CursorConstants.stateDatabaseRelativePath)
    }

    static func readAccessToken(at path: URL = defaultPath) throws -> String {
        try readString(key: CursorConstants.accessTokenKey, at: path)
    }

    static func readCachedEmail(at path: URL = defaultPath) -> String? {
        try? readString(key: CursorConstants.cachedEmailKey, at: path)
    }

    private static func readString(key: String, at path: URL) throws -> String {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path.path, &handle, flags, nil) == SQLITE_OK,
              let database = handle
        else {
            if handle != nil {
                sqlite3_close(handle)
            }
            throw StateDatabaseError.openFailed
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, Int32(CursorConstants.busyTimeoutMilliseconds))

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement
        else {
            throw StateDatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(prepared) }

        let keyValue = key as NSString
        sqlite3_bind_text(prepared, 1, keyValue.utf8String, -1, nil)
        guard sqlite3_step(prepared) == SQLITE_ROW,
              let bytes = sqlite3_column_text(prepared, 0)
        else {
            throw StateDatabaseError.missingAccessToken
        }
        return String(cString: bytes)
    }
}
