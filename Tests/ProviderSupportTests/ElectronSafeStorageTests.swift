import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

@Suite("Electron safeStorage")
struct ElectronSafeStorageTests {
    /// OSCrypt v10 under password `test-password`, plaintext a tiny session JWT.
    private let fixture =
        "cursor-safe-storage:v1:djEwsZ4sxFwtHRRXROZDGKqTL2avlNUmv20wtoJP2tDVPFayV5KXkJX7wV8PkhILClfhKZ4VlLQjuT43Zvq3qEAviih8Plr1ungz+Xhbb8Y77O9QA9o8WEwOTavvzFYZcl0X"
    private let fixturePassword = "test-password"
    private let fixturePlain =
        "eyJhbGciOiJIUzI1NiJ9.eyJ0eXBlIjoic2Vzc2lvbiIsInN1YiI6Imdvb2dsZS1vYXV0aDJ8dXNlcl90ZXN0In0.sig"

    @Test("A plaintext value is returned unchanged")
    func plaintextPassthrough() throws {
        let token = "eyJhbGciOiJub25lIn0.eyJ0eXBlIjoic2Vzc2lvbiJ9.sig"
        #expect(try ElectronSafeStorage.reveal(token, password: nil) == token)
        #expect(try ElectronSafeStorage.reveal(token, password: "unused") == token)
    }

    @Test("An encrypted Cursor value opens under the Keychain password")
    func decryptsCursorBlob() throws {
        #expect(try ElectronSafeStorage.decrypt(fixture, password: fixturePassword) == fixturePlain)
        #expect(try ElectronSafeStorage.reveal(fixture, password: fixturePassword) == fixturePlain)
    }

    @Test("A missing password on an encrypted value is a sign-in, not a bad response")
    func missingPassword() {
        #expect(throws: ElectronSafeStorageError.missingPassword) {
            try ElectronSafeStorage.reveal(fixture, password: nil)
        }
        #expect(
            ElectronSafeStorageError.missingPassword.providerError
                == ProviderError(code: .notAuthenticated)
        )
    }

    @Test("A wrong password fails closed as authenticationFailed")
    func wrongPassword() {
        #expect(throws: ElectronSafeStorageError.decryptFailed) {
            try ElectronSafeStorage.decrypt(fixture, password: "wrong")
        }
        #expect(
            ElectronSafeStorageError.decryptFailed.providerError
                == ProviderError(code: .authenticationFailed)
        )
    }

    @Test("Garbage under the Cursor prefix is malformed")
    func malformed() {
        #expect(throws: ElectronSafeStorageError.malformed) {
            try ElectronSafeStorage.decrypt(
                ElectronSafeStorage.cursorValuePrefix + "@@@",
                password: fixturePassword
            )
        }
    }
}
