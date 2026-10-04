import Core
import Foundation

/// Supplies the bytes of a provider that ships inside the application.
///
/// A protocol so the installer's own steps can be tested against a directory of
/// fixtures, and so the app's bundle and a test's temporary directory are
/// reached the same way.
public protocol BundledArtifacts: Sendable {
    /// The identifiers of the providers this build packages, in a stable order.
    ///
    /// Read once at launch to decide what the application offers. It is the whole
    /// of that decision, which is why nothing else in the application keeps a list:
    /// a second list would be able to disagree with the bundle about what exists.
    func providers() throws -> [String]

    /// The packaged provider for `id`, or nil when the application does not ship
    /// one under that name.
    func artifact(for id: String) throws -> Data?
}

/// A provider packaged as a gzipped tar, read from a directory on disk.
///
/// A tarball rather than a shipped directory, because the app bundle is
/// read-only: copying a provider out of it and staging it is the same code path a
/// downloaded provider takes, so there is one install to reason about instead of
/// two that drift apart.
public struct DirectoryBundledArtifacts: BundledArtifacts {
    private let directory: URL?

    /// - Parameter directory: where the packaged providers are. Nil means the
    ///   application ships none, which is a valid state for a build with no
    ///   providers rather than a reason to refuse every request.
    public init(directory: URL?) {
        self.directory = directory
    }

    /// The providers packaged in an application bundle.
    ///
    /// One place to look, because the manager that offers a provider and the
    /// installer that unpacks it must read the same directory: if they resolved
    /// it separately, a build where the two disagreed would offer providers it
    /// then refused to install.
    ///
    /// Falls back to the directory beside the bundle so `swift run` finds the
    /// tarballs `Scripts/bundle.sh` wrote, and nil when there is nowhere to look
    /// at all, which leaves the build offering no providers rather than failing.
    public static func live(in bundle: Bundle = .main) -> DirectoryBundledArtifacts {
        let root = bundle.resourceURL ?? bundle.bundleURL.deletingLastPathComponent()
        return DirectoryBundledArtifacts(
            directory: root.appendingPathComponent(
                BundleConstants.providersDirectoryName,
                isDirectory: true
            )
        )
    }

    /// Every packaged provider in the directory, by the id it is filed under.
    ///
    /// A file that is not named like a provider is passed over rather than
    /// offered: the identifier has to be one the store can hold, and a stray file
    /// in a directory the build owns should not turn into a row in the interface.
    public func providers() throws -> [String] {
        guard let directory else { return [] }
        let suffix = BundleConstants.artifactFileExtension
        return
            try FileManager.default
                .contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".\(suffix)") }
                .compactMap { name in
                    let id = String(name.dropLast(suffix.count + 1))
                    return (try? ProviderID(id)) == nil ? nil : id
                }
                .sorted()
    }

    /// The packaged provider named `id`, read out of the directory.
    ///
    /// Keyed by the id in the file name, the same id `providers()` hands back, so
    /// discovering a provider and reading it cannot disagree about where it is.
    public func artifact(for id: String) throws -> Data? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(
            "\(id).\(BundleConstants.artifactFileExtension)"
        )
        // A missing file is "not shipped", not a failure: a caller can be holding
        // an id from an older build, and it already has a way to say so. Anything
        // else going wrong is a real error worth surfacing.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}
