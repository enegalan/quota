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

    /// Where a provider's own logo sits in the application bundle.
    ///
    /// One image per provider, filed under the provider's identifier. The
    /// interface reads a mark from here and falls back to a generic symbol when
    /// there is none, so a provider added without one still draws something.
    public static let providerLogosDirectoryName = "ProviderLogos"

    /// What a provider's logo is called inside its own package.
    ///
    /// The build script reads it from `Plugins/<id>/` and files it in the bundle
    /// under the provider's identifier, so nothing at runtime reads the source
    /// package and this name exists only to keep the script and the check that
    /// keeps it in step.
    public static let providerLogoSourceFileName = "logo.png"

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
