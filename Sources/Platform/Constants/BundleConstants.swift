import Foundation
import PluginKit

/// The application's own fixed values.
public enum BundleConstants {
    /// Where packaged providers sit inside the application bundle.
    ///
    /// A directory of tarballs is the whole list of providers: what a build offers
    /// is what it shipped, so adding one is packaging it and there is no second
    /// file that has to be told about it.
    public static let providersDirectoryName = "Providers"

    /// What a packaged provider's file name ends in.
    public static let artifactFileExtension = "tar.gz"

    /// The version a packaged provider installs as.
    ///
    /// Read from the bundle rather than hard-coded, so a release build and a debug
    /// build of the same source cannot disagree about which is newer.
    public static var applicationVersion: Version {
        let raw =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Version(string: raw ?? "0.0.0") ?? Version(major: 0)
    }
}
