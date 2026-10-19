import Foundation
import PluginKit

/// Why an install did not complete.
///
/// The single set of reasons the interface has to be able to word, and the
/// reasons an install refuses for rather than a failure it recovers from.
public enum InstallError: Error, Equatable, LocalizedError {
    /// The archive is not readable as an archive.
    case extractionFailed(String)
    /// The archive holds no executable where the host will look for one.
    case missingExecutable(String)
    /// This build does not package that provider.
    case notShipped(String)
    /// Something about the plugins directory stopped this.
    case fileSystem(String)
    /// A provider with that id is already installed at that version.
    case alreadyInstalled(String, String)

    /// What the user is told, in the app's own words.
    ///
    /// Without it, a failure reached the interface as the system's words for an
    /// error it has never heard of — "the operation could not be completed" —
    /// which says less than the failure did.
    public var errorDescription: String? {
        switch self {
        case .extractionFailed:
            "The provider's package could not be unpacked."
        case .missingExecutable(let id):
            "The package for \(id) holds no program to run."
        case .notShipped(let id):
            "This version of Quota does not ship \(id)."
        case .fileSystem(let detail):
            detail
        case .alreadyInstalled(let id, let version):
            "\(id) \(version) is already installed."
        }
    }
}
