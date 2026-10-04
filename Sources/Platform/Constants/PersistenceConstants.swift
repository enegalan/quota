import Foundation
import Security

/// Where Quota keeps its data on disk, and the identifiers it uses for the
/// pieces that are not domain values.
public enum PersistenceConstants {
    /// Directory name under Application Support.
    public static let directoryName = "Quota"

    /// One JSON file per record family, so a single corrupt file cannot take
    /// down unrelated state.
    public enum FileName {
        public static let quotas = "quotas.json"
        public static let snapshots = "snapshots.json"
        public static let timelines = "timelines.json"
        /// The plan the engine last produced, one per quota.
        ///
        /// Separate from the timeline because the two have opposite lifetimes:
        /// a plan is derived and replaced wholesale on every reading, so a file
        /// that grew by appending would be a log of plans the app never shows.
        public static let allocationPlans = "allocationPlans.json"
        public static let providers = "providers.json"
        public static let preferences = "preferences.json"
        /// What the installer recorded about providers on this machine.
        ///
        /// Separate from `providers.json` because the two change for different
        /// reasons and have different lifetimes: that one is a connection the user
        /// has, and losing it loses an account label; this one is code on disk, and
        /// losing it is a repairable fact about a directory.
        public static let installedProviders = "installedProviders.json"
    }

    /// Keychain service owning every provider credential. Credentials are
    /// stored under `<providerID>.<keyName>` accounts within this service and
    /// nowhere else.
    public static let keychainService = "com.quota.app"

    /// The key name every provider's credential is filed under, so one provider
    /// can hold more than one secret and the app and the Keychain agree on where
    /// it is without either inventing a name at the call site.
    public static let credentialKeyName = "credential"

    /// Directory name, under the data root, holding installed providers.
    public static let pluginsDirectoryName = "plugins"

    /// Directory name, under the data root, holding plugins' captured output.
    public static let pluginLogDirectoryName = "plugin-logs"

    /// When a credential is readable: only while the device is unlocked, and
    /// never synchronised to another device or backed up in an unencrypted
    /// archive. A provider token is usable by whoever holds it, so it is not
    /// treated as data worth migrating to a new Mac.
    ///
    /// Computed rather than stored: a `CFString` is not `Sendable`, so a stored
    /// static of this type is shared mutable state as far as the compiler is
    /// concerned. A computed property has none, and returns the same constant
    /// `Security` defines.
    public static var keychainAccessibility: CFString {
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    /// File protection applied to every written file: readable after the first
    /// unlock following boot, and encrypted before that.
    public static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// Suffix used when quarantining a corrupt file so it can be inspected
    /// rather than silently deleted.
    public static let quarantineSuffix = ".corrupt"
}
