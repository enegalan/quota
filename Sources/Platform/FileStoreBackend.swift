import Foundation

/// The filesystem backend.
///
/// Every write goes to a temporary file in the same directory and is then moved
/// into place, so a crash part-way through leaves either the previous file or
/// the new one and never a half-written mixture. The temporary file has to be in
/// the same directory because a rename across filesystems is not atomic, which
/// would defeat the point.
public actor FileStoreBackend: StoreBackend {
    private let directory: URL
    private let now: @Sendable () -> Date

    /// A quarantine name has to be unique per occurrence, so a second corrupt
    /// file with the same name does not overwrite the first.
    private var quarantineCount = 0

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// `FileManager` is not `Sendable`, so it is created per call rather than
    /// stored on the actor.
    private let fileManager = FileManager.default

    /// Reads one family's bytes.
    ///
    /// - Returns: nil when the file is not there. Absence is checked before
    ///   the read so that a family nothing has written to and a family whose
    ///   file has been removed are the same ordinary state, rather than one
    ///   of them being an error the caller has to handle separately.
    public func read(_ fileName: String) throws -> Data? {
        let url = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Writes one family's bytes, atomically.
    ///
    /// Protection is applied to the temporary file before it is moved, not
    /// after: set on the destination alone there would be a window in which
    /// the bytes were already in place and still unencrypted, which is the
    /// window a keychain-adjacent file gets read in.
    public func write(_ data: Data, to fileName: String) throws {
        try createDirectoryIfNeeded()

        let target = directory.appendingPathComponent(fileName)
        let temporary = directory.appendingPathComponent(
            "\(fileName).\(ProcessInfo.processInfo.processIdentifier).tmp"
        )

        try data.write(to: temporary)
        try applyProtection(to: temporary)

        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: target)
        }
        try applyProtection(to: target)
    }

    /// Sets one family's bytes aside under a timestamped name.
    ///
    /// The original file is left where it is rather than removed. A file that
    /// would not decode is also evidence: deleting it discards the only copy
    /// of whatever the user had before the app wrote over it, and a copy kept
    /// in the same directory is something support can actually be sent.
    ///
    /// The data is written from memory, not moved, so the bytes preserved are
    /// exactly the ones that failed to decode — not whatever a later recovery
    /// has since put in their place.
    public func quarantine(_ data: Data, from fileName: String) throws {
        quarantineCount += 1
        let stamp = Int(now().timeIntervalSince1970)
        let name = "\(fileName).\(stamp).\(quarantineCount)\(PersistenceConstants.quarantineSuffix)"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        try applyProtection(to: url)
    }

    /// Creates the store directory if it is not already there.
    ///
    /// On write rather than in the initialiser, so constructing a store is
    /// free and cannot fail, and so asking a read-only question never creates
    /// an empty directory on a machine that has nothing stored yet.
    private func createDirectoryIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            return
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// Applies complete-until-first-unlock protection, so the contents are
    /// encrypted at rest until the user has logged in once after boot.
    private func applyProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: PersistenceConstants.fileProtection],
            ofItemAtPath: url.path
        )
    }
}
