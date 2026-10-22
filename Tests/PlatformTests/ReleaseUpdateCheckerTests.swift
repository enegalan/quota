import Foundation
import PluginKit
import Testing
@testable import Platform

/// Returns a fixed JSON body instead of talking to GitHub.
private struct StubReleaseFetcher: LatestReleaseFetching {
    let json: Data
    let error: Error?

    init(json: Data, error: Error? = nil) {
        self.json = json
        self.error = error
    }

    func fetchLatestReleaseJSON() async throws -> Data {
        if let error {
            throw error
        }
        return json
    }
}

@Suite("ReleaseUpdateChecker")
struct ReleaseUpdateCheckerTests {
    private let current = Version(major: 1, minor: 3, patch: 11)

    @Test("A newer tag is reported as available")
    func newerReleaseIsAvailable() throws {
        let json = Data("""
        {
          "tag_name": "v1.4.0",
          "html_url": "https://github.com/enegalan/quota/releases/tag/v1.4.0"
        }
        """.utf8)
        let outcome = ReleaseUpdateChecker.outcome(current: current, json: json)
        #expect(
            outcome == .available(
                version: Version(major: 1, minor: 4, patch: 0),
                releaseURL: try #require(URL(string: "https://github.com/enegalan/quota/releases/tag/v1.4.0"))
            )
        )
    }

    @Test("The same version is up to date")
    func sameVersionIsUpToDate() {
        let json = Data("""
        {
          "tag_name": "v1.3.11",
          "html_url": "https://github.com/enegalan/quota/releases/tag/v1.3.11"
        }
        """.utf8)
        #expect(ReleaseUpdateChecker.outcome(current: current, json: json) == .upToDate)
    }

    @Test("An older tag is up to date")
    func olderReleaseIsUpToDate() {
        let json = Data("""
        {
          "tag_name": "v1.0.0",
          "html_url": "https://github.com/enegalan/quota/releases/tag/v1.0.0"
        }
        """.utf8)
        #expect(ReleaseUpdateChecker.outcome(current: current, json: json) == .upToDate)
    }

    @Test("A tag without a v prefix still parses")
    func tagWithoutPrefix() {
        let json = Data("""
        {
          "tag_name": "2.0.0",
          "html_url": "https://github.com/enegalan/quota/releases/tag/2.0.0"
        }
        """.utf8)
        let outcome = ReleaseUpdateChecker.outcome(current: current, json: json)
        guard case .available(let version, _) = outcome else {
            Issue.record("expected available, got \(outcome)")
            return
        }
        #expect(version == Version(major: 2, minor: 0, patch: 0))
    }

    @Test("An invalid tag fails rather than guessing")
    func invalidTagFails() {
        let json = Data("""
        {
          "tag_name": "nightly",
          "html_url": "https://github.com/enegalan/quota/releases/tag/nightly"
        }
        """.utf8)
        guard case .failed = ReleaseUpdateChecker.outcome(current: current, json: json) else {
            Issue.record("expected failure for an unparseable tag")
            return
        }
    }

    @Test("A fetcher failure becomes a failed outcome")
    func fetcherFailure() async {
        let fetcher = StubReleaseFetcher(
            json: Data(),
            error: UpdateCheckError.httpStatus(500)
        )
        let outcome = await ReleaseUpdateChecker.check(current: current, fetcher: fetcher)
        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
    }

    @Test("A successful fetch compares through the fetcher")
    func fetcherSuccess() async {
        let json = Data("""
        {
          "tag_name": "v9.9.9",
          "html_url": "https://github.com/enegalan/quota/releases/tag/v9.9.9"
        }
        """.utf8)
        let outcome = await ReleaseUpdateChecker.check(
            current: current,
            fetcher: StubReleaseFetcher(json: json)
        )
        guard case .available(let version, _) = outcome else {
            Issue.record("expected available, got \(outcome)")
            return
        }
        #expect(version == Version(major: 9, minor: 9, patch: 9))
    }
}
