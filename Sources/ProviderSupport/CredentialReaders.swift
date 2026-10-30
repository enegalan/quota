import Foundation

/// Reading a credential out of the user's keychain.
///
/// Foreign items (Claude Code, Codex, Cursor, …) carry a classic macOS ACL.
/// Reading them with `SecItemCopyMatching` from an unsigned or ad-hoc plugin
/// binary puts up a consent dialog on every refresh, and "Always Allow" does
/// not stick: the plugin's code signature is not a stable trusted-application
/// identity. `/usr/bin/security` is Apple-signed; once the user allows it,
/// that grant survives plugin updates and background refreshes.
///
/// A missing item, a denied prompt, or a tool failure all return nil so the
/// plugin's next credential source can be tried.
public enum KeychainReader {
    /// Absolute path of Apple's keychain tool. Stable across macOS releases.
    public static let securityToolPath = "/usr/bin/security"

    /// The password stored for a service, or nil when there is none to be had.
    public static func password(service: String, account: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityToolPath)
        process.arguments = securityArguments(service: service, account: account)

        let stdout = Pipe()
        process.standardOutput = stdout
        // Leave stderr unread and it can fill the pipe and stall `security`
        // the same way a full stdout pipe can; discard it instead.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stdout before waiting: a full pipe blocks the child, and
        // waiting first then leaves this process wedged on both sides.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Arguments for `security find-generic-password … -w`.
    ///
    /// `-w` prints only the password, so the plugin never has to parse the
    /// attribute dump `security` emits without it.
    public static func securityArguments(service: String, account: String? = nil) -> [String] {
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments.append(contentsOf: ["-a", account])
        }
        arguments.append("-w")
        return arguments
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
