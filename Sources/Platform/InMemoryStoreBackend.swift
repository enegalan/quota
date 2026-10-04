import Foundation

/// Keeps a store's bytes here, with no filesystem and no clock.
///
/// Used by `CodableStore.inMemory()`: a test world gets the real encoding rules
/// without a disk, and cannot accidentally pass because of a real file left over
/// from an earlier run.
public actor InMemoryStoreBackend: StoreBackend {
    private var files: [String: Data] = [:]
    private var quarantined: [String] = []

    public init(seed: [String: Data] = [:]) {
        files = seed
    }

    /// Returns the bytes for a family, or nil when nothing has been written.
    public func read(_ fileName: String) -> Data? {
        files[fileName]
    }

    /// Replaces a family's bytes.
    public func write(_ data: Data, to fileName: String) {
        files[fileName] = data
    }

    /// Drops a family's bytes and remembers the name.
    ///
    /// Dropping rather than keeping the bytes is what lets a test prove the
    /// store does not go on reading a file it has given up on: the next read
    /// returns nil exactly as it would for a family that was never written.
    public func quarantine(_ data: Data, from fileName: String) {
        files[fileName] = nil
        quarantined.append(fileName)
    }

    /// The names set aside so far, for tests to assert on.
    public func quarantinedFileNames() -> [String] {
        quarantined
    }

    /// The names a backend currently holds, for tests to assert on.
    ///
    /// In dictionary order rather than sorted: these names are written by the
    /// store itself and carry no secrets, so a test comparing them is
    /// asserting on which families exist, not on anything that has to be kept
    /// out of a log.
    public func storedFileNames() -> [String] {
        Array(files.keys)
    }
}
