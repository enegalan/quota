import Foundation
import PluginKit
import SQLite3

/// Why reading the editor's own state failed.
public enum VSCodeStateDatabaseError: Error, Equatable, ProviderFailure {
    /// The file could not be opened, or is not the database this code expects.
    case openFailed

    /// The statement could not be prepared — a different shape of database
    /// than the one this reader knows how to ask.
    case prepareFailed

    /// The editor has no such key: the plugin is looking for a credential the
    /// user's copy of it has never stored.
    case missingItem

    public var providerError: ProviderError {
        switch self {
        case .missingItem:
            // Nothing to sign in *with* is not a failure to reach the provider,
            // and reporting it as one would blame a network that is fine.
            ProviderError(code: .notAuthenticated)
        case .openFailed, .prepareFailed:
            ProviderError(code: .invalidResponse)
        }
    }
}

/// The state database a VS Code–derived editor keeps.
///
/// One reader, rather than one per provider, because every editor in this
/// family stores its local sign-in the same way: a SQLite file holding a
/// string table, under a key that names what is stored.
public enum VSCodeStateDatabase {
    /// How long the reader waits for the editor's own lock to clear.
    ///
    /// Bounded because the editor writes while it runs: an unbounded wait is
    /// this plugin hanging on someone else's lock, and the host kills a plugin
    /// that hangs and calls it a plugin's fault.
    private static let busyTimeoutMilliseconds: Int32 = 5000

    private static let selectItemSQL = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"

    /// One string out of the table, read-only.
    ///
    /// Opened read-only so a plugin can never be the thing that corrupts a
    /// file the user's editor is holding open.
    ///
    /// - Parameters:
    ///   - key: the item's key.
    ///   - databasePath: the database file, absolute.
    public static func item(key: String, at databasePath: URL) throws -> String {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath.path, &handle, flags, nil) == SQLITE_OK,
              let database = handle
        else {
            if handle != nil {
                sqlite3_close(handle)
            }
            throw VSCodeStateDatabaseError.openFailed
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, selectItemSQL, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement
        else {
            throw VSCodeStateDatabaseError.prepareFailed
        }
        defer { sqlite3_finalize(prepared) }

        let keyValue = key as NSString
        sqlite3_bind_text(prepared, 1, keyValue.utf8String, -1, nil)

        guard sqlite3_step(prepared) == SQLITE_ROW,
              let bytes = sqlite3_column_text(prepared, 0)
        else {
            throw VSCodeStateDatabaseError.missingItem
        }
        return String(cString: bytes)
    }
}
