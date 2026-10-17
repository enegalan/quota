import Foundation
import LocalAuthentication
import Security

/// Reading a credential out of the user's keychain.
///
/// Never interactive, on purpose: an item owned by another application's code
/// signature can ask for consent on every read, so a read allowed to prompt
/// may put up a dialog nobody is watching on a background refresh. A read that
/// would need the user simply fails, and the plugin's next source is tried.
public enum KeychainReader {
    /// The password stored for a service, or nil when there is none to be had.
    public static func password(service: String, account: String? = nil) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Reading a credential out of a file on disk — the shape a CLI leaves behind
/// after its first sign-in.
///
/// Nil rather than thrown when the file is absent, unreadable, or has none of
/// the keys: a missing file is a source that is not there, and the next source
/// may well have what is needed.
public enum CredentialsFileReader {
    /// The first non-empty string among `keys`. Tried in order rather than
    /// requiring one name, because there is no single name — `accessToken`,
    /// `access_token` and `token` are all in use by tools worth reading.
    public static func token(at url: URL, keys: [String]) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
