import Foundation
import PluginKit

/// Where a provider is in its lifecycle.
///
/// The states the flow passes through, plus the three that are conditions rather
/// than stages: `incompatible` and `missing` describe a provider that cannot be
/// used however long one waits, and `disabled` is a decision someone made. The
/// interface shows a state and offers the action it permits, so a state that is
/// not in this list has no meaning anywhere else either.
public enum ProviderState: String, Codable, Sendable, Equatable, CaseIterable {
    /// Not on this machine. The starting state for every provider, always.
    case notInstalled
    /// Being fetched, verified, and unpacked.
    case installing
    /// On this machine and runnable, but not connected.
    case installed
    /// Connected, with credentials the provider accepted.
    case connected
    /// Being asked for usage right now.
    case synchronizing
    /// The install did not complete. Nothing was activated.
    case installationFailed
    /// Installed and reachable, but it wants credentials the user has not given.
    case authRequired
    /// Was connected, and the provider no longer accepts what it has.
    case authExpired
    /// A newer version exists in the catalog than the one installed.
    case updateAvailable
    /// Being replaced by the newer version.
    case updating
    /// The update did not complete; the previous version is still active.
    case updateFailed
    /// Switched off, by preference or by the kill switch.
    case disabled
    /// Needs a newer application than this one.
    case incompatible
    /// Referenced by a quota, but no longer on this machine.
    case missing

    /// Whether the plugin behind this state can be launched.
    ///
    /// `missing` and `incompatible` say the code is not there or will not run, and
    /// `disabled` says it should not run, so all three keep the host off it. The
    /// rest are stages the host can enter.
    public var permitsLaunch: Bool {
        switch self {
        case .notInstalled, .missing, .incompatible, .disabled: false
        case .installing, .installed, .connected, .synchronizing, .authRequired,
             .authExpired, .updateAvailable, .updating, .installationFailed, .updateFailed:
            true
        }
    }

    // Whether the user should be offered a retry.

    /// What has to happen before this provider can be given a quota.
    ///
    /// One answer for three callers that each used to group the states
    /// themselves. Install and Connect are decided by the same rule wherever they
    /// are offered, and a state added to this enum has to be placed by hand at
    /// every site that groups — which is how a provider ends up with a Connect
    /// button it does not need, or a creation trail that asks for an install it
    /// already has.
    public enum Prerequisite {
        /// Not on this machine yet.
        case installation
        /// On this machine, but nobody is signed in.
        case authentication
        /// Nothing stands between the provider and a quota.
        case none
    }

    public var prerequisite: Prerequisite {
        switch self {
        case .notInstalled: .installation
        // Signed out, never signed in, and a session that lapsed are the same
        // step to a user: put the credentials in.
        case .installed, .authRequired, .authExpired: .authentication
        default: .none
        }
    }

    // Whether the interface lists this state under a failure heading.
}

/// A provider as it exists on this machine.
///
/// Not the catalog's claim about a provider and not the running plugin's
/// description of itself: this is what the installer recorded and the host acts on.
public struct InstalledProvider: Codable, Sendable, Equatable {
    public let id: String
    public let version: Version

    /// Where the plugin lives, relative to the plugins directory.
    ///
    /// Relative on purpose. A stored absolute path would break the moment the
    /// application moved, and a path outside the plugins directory is not something
    /// this type should be able to express.
    public let relativePath: String

    public let state: ProviderState
    public let installedAt: Date

    /// The hash actually verified at install time, so a later read can tell
    /// whether the bytes on disk are still the bytes that were checked.
    public let contentHash: String

    /// The most recent failure, as a code rather than a message, so it survives a
    /// language change and cannot leak a path or a credential into a label.
    public let lastError: ProviderErrorCode?

    public init(
        id: String,
        version: Version,
        relativePath: String,
        state: ProviderState = .installed,
        installedAt: Date,
        contentHash: String,
        lastError: ProviderErrorCode? = nil
    ) {
        self.id = id
        self.version = version
        self.relativePath = relativePath
        self.state = state
        self.installedAt = installedAt
        self.contentHash = contentHash
        self.lastError = lastError
    }

    /// The same record with a different state or a different error.
    ///
    /// The properties are `let` on purpose — an installed record is a fact about
    /// disk, and a half-edited one is a fact that was never true — so moving from
    /// one state to another is a new value rather than a mutation.
    public func with(
        state: ProviderState? = nil,
        lastError: ProviderErrorCode? = nil
    ) -> InstalledProvider {
        InstalledProvider(
            id: id,
            version: version,
            relativePath: relativePath,
            state: state ?? self.state,
            installedAt: installedAt,
            contentHash: contentHash,
            lastError: lastError ?? self.lastError
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, relativePath, state, installedAt, contentHash, lastError
    }
}
