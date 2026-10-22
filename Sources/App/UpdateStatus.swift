import Foundation

/// What settings shows about asking GitHub for a newer build.
enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed(String)
}
