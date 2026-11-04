import CommonCrypto
import Foundation
import PluginKit

/// Why revealing an Electron `safeStorage` value failed.
public enum ElectronSafeStorageError: Error, Equatable, ProviderFailure {
    /// The Keychain has no encryption password for this app.
    case missingPassword

    /// The stored value is not a recognisable safe-storage blob.
    case malformed

    /// The password was present but did not open the ciphertext.
    case decryptFailed

    public var providerError: ProviderError {
        switch self {
        case .missingPassword:
            ProviderError(code: .notAuthenticated)
        case .malformed, .decryptFailed:
            ProviderError(code: .authenticationFailed)
        }
    }
}

/// Chromium / Electron `safeStorage` on macOS: OSCrypt `v10` AES-128-CBC
/// under a Keychain password, wrapped as `<app>-safe-storage:v1:<base64>`.
///
/// Cursor now writes `cursorAuth/accessToken` this way. A plaintext JWT is
/// returned unchanged so older installs keep working.
public enum ElectronSafeStorage {
    /// Chromium's fixed PBKDF2 salt for OSCrypt on desktop.
    private static let salt = Data("saltysalt".utf8)
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    private static let versionPrefix = Data("v10".utf8)
    private static let iv = Data(repeating: UInt8(ascii: " "), count: kCCBlockSizeAES128)

    /// Prefix Cursor writes in front of the base64 OSCrypt blob.
    public static let cursorValuePrefix = "cursor-safe-storage:v1:"

    /// The string Electron would hand to the app, or the input when it was
    /// never encrypted.
    public static func reveal(
        _ value: String,
        password: String?
    ) throws -> String {
        guard value.hasPrefix(cursorValuePrefix) else {
            return value
        }
        guard let password, !password.isEmpty else {
            throw ElectronSafeStorageError.missingPassword
        }
        return try decrypt(value, password: password)
    }

    /// OSCrypt `v10` under the given Keychain password.
    public static func decrypt(_ value: String, password: String) throws -> String {
        guard value.hasPrefix(cursorValuePrefix) else {
            throw ElectronSafeStorageError.malformed
        }
        let encoded = String(value.dropFirst(cursorValuePrefix.count))
        guard let blob = Data(base64Encoded: encoded),
              blob.starts(with: versionPrefix),
              blob.count > versionPrefix.count
        else {
            throw ElectronSafeStorageError.malformed
        }

        let key = try deriveKey(password: password)
        let ciphertext = blob.dropFirst(versionPrefix.count)
        let plaintext = try aes128CBCDecrypt(ciphertext: Data(ciphertext), key: key)
        guard let text = String(data: plaintext, encoding: .utf8), !text.isEmpty else {
            throw ElectronSafeStorageError.decryptFailed
        }
        return text
    }

    private static func deriveKey(password: String) throws -> Data {
        var key = Data(count: keyLength)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withCString { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes,
                        password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ElectronSafeStorageError.decryptFailed
        }
        return key
    }

    private static func aes128CBCDecrypt(ciphertext: Data, key: Data) throws -> Data {
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.bindMemory(to: UInt8.self).baseAddress,
                            key.count,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress,
                            cipherBytes.bindMemory(to: UInt8.self).baseAddress,
                            ciphertext.count,
                            outputBytes.bindMemory(to: UInt8.self).baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ElectronSafeStorageError.decryptFailed
        }
        output.removeSubrange(outputLength ..< output.count)
        return output
    }
}
