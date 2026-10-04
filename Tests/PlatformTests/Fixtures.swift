import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Values every Platform test needs to agree on.
///
/// A test that builds its own calendar, its own reference instant, and its own
/// quota would eventually stop matching what the store and the manager read, and
/// the difference would show up as a test failing for a reason nobody can see.
/// One namespace, one copy of each, imported by every suite in this target.
enum ProviderFixture {
    /// The version packaged fixtures install as.
    ///
    /// Several tests assert on the version directory's name literally
    /// (`"mock/1.0.0"`), so it is named here rather than written per fixture.
    static let version = Version(major: 1, minor: 0, patch: 0)

    /// The application's own version, for the checks that compare against it.
    static let applicationVersion = Version(major: 1, minor: 2, patch: 0)

    /// A fixed instant, so a test that stores a date and reads it back compares
    /// two of the same date rather than two of "now".
    static let referenceInstant = Date(timeIntervalSince1970: 1_757_000_000)
}

/// The calendar every Platform test builds dates in.
///
/// `Calendar.current` would follow the machine the suite runs on, and a test that
/// passes on one and fails on another is a test that is testing the environment.
enum TestCalendar {
    static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// Midnight on a day, in `gmt`.
    static func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(gmt.date(from: DateComponents(year: year, month: month, day: day)))
    }

    static func instant(at offset: TimeInterval) -> Date {
        ProviderFixture.referenceInstant.addingTimeInterval(offset)
    }
}

/// The period every fixture quota is given: September 2026, start to end.
///
/// Named rather than written into each test because a quota is unusable without
/// one, and the tests that assert on a plan's day count are asserting about this
/// window.
enum QuotaFixture {
    static let start = fixturesOnlyDay(2026, 9, 1)
    static let end = fixturesOnlyDay(2026, 9, 30)

    /// - Parameter bucketID: nil reads the provider's primary bucket, which is what
    ///   most of these tests want; only the multi-bucket suites name one.
    static func quota(
        id: UUID = UUID(),
        name: String,
        providerID: String = "mock",
        bucketID: String? = nil,
        policy: AllocationPolicy = .even
    ) throws -> Quota {
        try Quota(
            id: id,
            name: name,
            providerID: try ProviderID(providerID),
            bucketID: bucketID,
            period: try QuotaPeriod(start: start, end: end),
            policy: policy,
            createdAt: start,
            updatedAt: start
        )
    }
}

/// A temporary directory that removes itself.
///
/// Every suite that needs one wrote the same three lines, and every one of them
/// could get the `defer` wrong and leak a directory into `/tmp`.
func withTemporaryDirectory<T>(
    _ label: String,
    _ body: (URL) async throws -> T
) async throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

/// A disk-backed store together with the backend behind it.
///
/// The two arrive as a pair because a test asserting on the files has to reach
/// the backend: `CodableStore.onDisk()` hides it, and what such a test is
/// usually checking is the file the app would have been left with.
struct DiskStoreFixture {
    let backend: FileStoreBackend
    let store: CodableStore
    private let directory: URL

    init(
        directory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        migrator: SchemaMigrator = .current
    ) {
        let backend = FileStoreBackend(directory: directory, now: now)
        self.backend = backend
        self.directory = directory
        store = CodableStore(backend: backend, migrator: migrator)
    }

    /// Every file in the store directory, for asserting a write left nothing
    /// behind and that a bad file was set aside rather than deleted.
    ///
    /// Read here rather than through the backend, because nothing outside the
    /// tests wants it: the backend's own writes are verified by what loads.
    func directoryContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }
}

/// A fixed calendar day, for a fixture's constants.
///
/// The month and day are arguments, so an invalid one is a typo in a fixture and
/// not a runtime condition: `fatalError` says which date was wrong, where a force
/// try says only that something was.
private func fixturesOnlyDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
    do {
        return try TestCalendar.day(year, month, day)
    } catch {
        fatalError("Fixture date \(year)-\(month)-\(day) is not a real date: \(error)")
    }
}
