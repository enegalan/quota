import Foundation

/// Unpacks a provider's artifact.
///
/// A protocol so the installer's ordering can be tested without shelling out, and
/// so a different format could be added without touching the steps around it.
public protocol ArchiveFormat: Sendable {
    /// Writes the artifact's contents into `directory`, which must not exist.
    func unarchive(_ artifact: Data, to directory: URL) throws
}

/// Unpacks a gzipped tar, the format a plugin is published in.
///
/// `tar` rather than a dependency: it is on every macOS, it is the format a plugin
/// author will have used anyway, and a provider is a directory with an executable
/// in it, which is exactly what a tarball is good at.
public struct TarArchiveFormat: ArchiveFormat {
    public init() {}

    /// Unpacks a gzipped tar into a directory of its own.
    ///
    /// The artifact is untrusted input, so the guarantee this step makes is
    /// containment: nothing a provider published can be written outside the
    /// directory being staged into. Naming the destination and refusing absolute
    /// paths inside the archive together buy that, and everything else here —
    /// the scratch copy, the stripped leading directory, the exit status — is
    /// about unpacking the right bytes into the right place.
    public func unarchive(_ artifact: Data, to directory: URL) throws {
        let fileManager = FileManager.default
        // The archive is written outside the destination, so a failure part way
        // through extraction cannot leave a half-written tarball inside the
        // version directory that a later run would treat as plugin contents.
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("quota-unarchive-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let archiveURL = scratch.appendingPathComponent("artifact.tar.gz")
        try artifact.write(to: archiveURL)

        // The destination is created rather than assumed, because extraction has
        // to land in it: with `--strip-components 1` tar writes the members into
        // the directory it is told to write into, and extracting into the parent
        // and then looking for the child is a way to unpack a working plugin into
        // the wrong place.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: InstallerConstants.tarPath)
        // `-C` so extraction cannot escape the destination by way of a `..` in an
        // archive member, and no `-P` so absolute paths inside an archive are
        // refused rather than obeyed.
        tar.arguments = [
            "-x", "-f", archiveURL.path, "-C", directory.path,
            "--strip-components", String(ArchiveFormatConstants.stripComponents),
        ]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw TarArchiveError.unarchiveFailed(status: tar.terminationStatus)
        }
        // A tar of nothing, or one that unpacked somewhere other than here, is a
        // failure the exit status alone does not describe.
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw TarArchiveError.emptyArchive }
    }
}

public enum TarArchiveError: Error, Equatable {
    case unarchiveFailed(status: Int32)
    case emptyArchive
}

/// Fixed values for unpacking.
public enum ArchiveFormatConstants {
    /// Path components removed from the front of every archive member.
    ///
    /// One, because a published plugin is a single top-level directory and
    /// stripping it means the executable sits at the root of the version directory
    /// whatever the author called theirs.
    public static let stripComponents = 1
}
