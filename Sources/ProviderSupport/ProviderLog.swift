import Foundation

/// The one way a plugin writes a diagnostic: one prefixed line to stderr.
///
/// stderr and never stdout — stdout is the protocol, and a stray line there is
/// a message the host has to skip. The text must never contain a credential:
/// a log line outlives the call that wrote it.
public struct ProviderLog: Sendable {
    private let prefix: String

    public init(providerID: String) {
        prefix = "quota-provider-\(providerID): "
    }

    public func note(_ message: String) {
        FileHandle.standardError.write(Data(line(message).utf8))
    }

    /// The line as `note` would write it, so its shape is testable.
    func line(_ message: String) -> String {
        prefix + message + "\n"
    }
}
