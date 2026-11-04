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
        let stored = try VSCodeStateDatabase.item(key: CursorConstants.accessTokenKey, at: path)
        // Cursor encrypts the JWT with Electron safeStorage on current builds;
        // older installs still store a plaintext session token. The Keychain
        // password opens only the encrypted form, and reading it for a
        // plaintext token asks for a secret this call does not use.
        let password = stored.hasPrefix(ElectronSafeStorage.cursorValuePrefix)
            ? KeychainReader.password(
                service: CursorConstants.safeStorageKeychainService,
                account: CursorConstants.safeStorageKeychainAccount
            )
            : nil
        return try ElectronSafeStorage.reveal(stored, password: password)
    }

    static func readCachedEmail(at path: URL = defaultPath) -> String? {
        try? VSCodeStateDatabase.item(key: CursorConstants.cachedEmailKey, at: path)
    }
}
