import Foundation
import PluginKit

public enum PluginLayout {
    /// `<plugins>/<id>/` holds every version of one provider.
    public static func providerDirectory(_ id: String, in plugins: URL) -> URL {
        plugins.appendingPathComponent(id, isDirectory: true)
    }

    /// `<plugins>/<id>/<version>/` holds one version's files.
    public static func versionDirectory(_ id: String, _ version: Version, in plugins: URL) -> URL {
        providerDirectory(id, in: plugins)
            .appendingPathComponent(version.description, isDirectory: true)
    }

    /// `<plugins>/<id>/current` points at the version in use.
    ///
    /// A symlink rather than a recorded path, because activation has to be
    /// atomic: replacing a symlink is one `rename`, where overwriting a
    /// recorded path is a write that a crash can leave half done.
    public static func activeLink(_ id: String, in plugins: URL) -> URL {
        providerDirectory(id, in: plugins).appendingPathComponent("current")
    }

    /// The symlink's target, or nil when nothing is active.
    public static func activeVersionDirectory(_ id: String, in plugins: URL) -> URL? {
        let link = activeLink(id, in: plugins)
        guard
            let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: link.path
            )
        else { return nil }
        // A link written by an older build, or by hand, can hold an absolute
        // path; resolving it as one is better than appending it to the link
        // and producing a path that is neither.
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return link.deletingLastPathComponent().appendingPathComponent(destination)
    }

    /// What a provider's executable is called, in the tarball, in the version
    /// directory, and on the host's path to it.
    ///
    /// A convention rather than a declaration, so it is written down in exactly one
    /// place: a plugin cannot say what it is called, and the installer and the host
    /// cannot disagree about it. `Scripts/bundle.sh` and each plugin's
    /// `Package.swift` name the same thing, and `ShippedFileTests` checks that
    /// they do.
    public static func executableName(for id: String) -> String {
        "quota-provider-\(id)"
    }

    /// How to start a provider whose files are in `directory`.
    ///
    /// The one place a launch is built from, so the describe, fetch, connect and
    /// update paths cannot each assemble a slightly different one. Staged files
    /// are not an installed version and are reached through here too: they have
    /// the same layout and the same executable name, and a second builder for
    /// them is a second thing to keep in step.
    ///
    /// The launch carries the host's own protocol range, because there is nothing
    /// else to carry. A packaged provider's real range arrives in its descriptor,
    /// which is checked the moment the plugin answers.
    public static func launch(
        for provider: AvailableProvider, version: Version, in directory: URL
    ) -> PluginLaunch {
        PluginLaunch(
            id: provider.id,
            displayName: provider.displayName,
            version: version.description,
            executablePath: directory
                .appendingPathComponent(executableName(for: provider.id))
                .path,
            protocolRange: PluginProtocolConstants.hostRange
        )
    }

    /// How to start an installed provider, or nil when none is active.
    public static func installedLaunch(
        for provider: AvailableProvider, version: Version, in plugins: URL
    ) -> PluginLaunch? {
        guard let directory = activeVersionDirectory(provider.id, in: plugins) else { return nil }
        return launch(for: provider, version: version, in: directory)
    }
}
