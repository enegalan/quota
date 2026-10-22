import Foundation
import PluginKit

/// What asking for a newer release produced.
public enum UpdateCheckOutcome: Sendable, Equatable {
    /// The installed build is at least as new as the latest release.
    case upToDate

    /// A newer release exists and can be opened in a browser.
    case available(version: Version, releaseURL: URL)

    /// The check could not be completed.
    case failed(message: String)
}

/// Fetches the JSON body of the latest GitHub release.
public protocol LatestReleaseFetching: Sendable {
    /// The raw JSON for the latest release, or throws when the request fails.
    func fetchLatestReleaseJSON() async throws -> Data
}

/// Reads GitHub's releases API over a session.
public struct GitHubLatestReleaseFetcher: LatestReleaseFetching {
    private let session: URLSession
    private let userAgent: String
    private let url: URL

    public init(
        session: URLSession = .shared,
        userAgent: String,
        url: URL = UpdateConstants.latestReleaseURL
    ) {
        self.session = session
        self.userAgent = userAgent
        self.url = url
    }

    public func fetchLatestReleaseJSON() async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }
        return data
    }
}

/// Failures that stop a release check before a version can be compared.
public enum UpdateCheckError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case missingTag
    case invalidTag(String)
    case missingReleaseURL
}

/// Compares the installed build to the latest GitHub release.
public enum ReleaseUpdateChecker {
    /// Parses a latest-release JSON body and compares it to the installed version.
    public static func outcome(current: Version, json: Data) -> UpdateCheckOutcome {
        do {
            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: json)
            let tag = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            guard let version = Version(string: tag) else {
                return .failed(message: UpdateCheckError.invalidTag(release.tagName).localizedDescription)
            }
            guard let releaseURL = URL(string: release.htmlURL) else {
                return .failed(message: UpdateCheckError.missingReleaseURL.localizedDescription)
            }
            if version > current {
                return .available(version: version, releaseURL: releaseURL)
            }
            return .upToDate
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Fetches the latest release and compares it to the installed version.
    public static func check(
        current: Version,
        fetcher: any LatestReleaseFetching
    ) async -> UpdateCheckOutcome {
        do {
            let json = try await fetcher.fetchLatestReleaseJSON()
            return outcome(current: current, json: json)
        } catch let error as UpdateCheckError {
            return .failed(message: error.localizedDescription)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

extension UpdateCheckError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The update server returned an unreadable response."
        case .httpStatus(let code):
            "The update server responded with status \(code)."
        case .missingTag:
            "The latest release has no version tag."
        case .invalidTag(let tag):
            "The latest release tag \"\(tag)\" is not a version."
        case .missingReleaseURL:
            "The latest release has no page to open."
        }
    }
}

/// The fields of a GitHub latest-release payload this checker needs.
private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
