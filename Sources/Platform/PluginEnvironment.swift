import Foundation
import PluginKit

/// The environment a plugin is launched with.
///
/// Built from nothing rather than filtered from the app's own. A filter is only as
/// good as its list of what to exclude, and this process holds a user's provider
/// credentials in its own environment and whatever else the app was launched with;
/// a plugin that inherits any of it is a plugin holding the user's keys for as
/// long as it runs.
public enum PluginEnvironment {
    /// Variables passed through to every plugin, beyond the home directory.
    ///
    /// Small on purpose. `PATH` is here because a plugin's own helper binaries
    /// need it; the language runtime variables are here because a plugin built
    /// with a Swift toolchain is useless without them. Nothing here reveals
    /// anything about the user or the app.
    public static let allowedVariables: [String] = [
        "PATH",
        "HOME",
        "LANG",
        "LC_ALL",
        "TMPDIR",
    ]

    /// The environment for a plugin's child process.
    public static func child(launch: PluginLaunch) -> [String: String] {
        var environment: [String: String] = [:]
        for name in allowedVariables {
            if let value = ProcessInfo.processInfo.environment[name] {
                environment[name] = value
            }
        }
        // Set rather than inherited, so a plugin knows which provider it was
        // launched as without the app having to pass it on stdin before the
        // protocol starts.
        environment["QUOTA_PROVIDER_ID"] = launch.id
        environment["QUOTA_PROVIDER_VERSION"] = launch.version
        environment["QUOTA_PROTOCOL_MIN"] = launch.protocolRange.minimum.description
        environment["QUOTA_PROTOCOL_MAX"] = launch.protocolRange.maximum.description
        return environment
    }

    /// The names the app sets for a plugin, beyond the inherited allowlist.
    public static let providerVariables: [String] = [
        "QUOTA_PROVIDER_ID",
        "QUOTA_PROVIDER_VERSION",
        "QUOTA_PROTOCOL_MIN",
        "QUOTA_PROTOCOL_MAX",
    ]

    /// The names a plugin is allowed to inherit, for a test to assert against.
    public static func permittedNames() -> Set<String> {
        Set(allowedVariables).union(providerVariables)
    }
}
