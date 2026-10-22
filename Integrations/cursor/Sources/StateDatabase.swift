import Foundation
import ProviderSupport

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
        try VSCodeStateDatabase.item(key: CursorConstants.accessTokenKey, at: path)
    }

    static func readCachedEmail(at path: URL = defaultPath) -> String? {
        try? VSCodeStateDatabase.item(key: CursorConstants.cachedEmailKey, at: path)
    }
}
