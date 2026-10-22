import Foundation

/// Fixed values for asking GitHub whether a newer Quota build exists.
///
/// Named here rather than in the checker or the settings view, so the repository
/// the app asks about and the throttle on how often it asks are one decision.
public enum UpdateConstants {
    /// Owner of the public releases repository.
    public static let repositoryOwner = "enegalan"

    /// Name of the public releases repository.
    public static let repositoryName = "quota"

    /// GitHub API endpoint for the newest published release.
    public static let latestReleaseURL: URL = {
        let path = "/repos/\(repositoryOwner)/\(repositoryName)/releases/latest"
        guard let url = URL(string: "https://api.github.com\(path)") else {
            preconditionFailure("UpdateConstants.latestReleaseURL is not a valid URL.")
        }
        return url
    }()

    /// Shortest gap between two automatic update checks.
    public static let minimumCheckInterval: TimeInterval = 24 * 60 * 60

    /// Refresh intervals the settings picker offers, in seconds.
    ///
    /// Each value sits inside `RefreshConstants`'s clamp bounds. The list is the
    /// UI's vocabulary; the scheduler still clamps anything else that arrives.
    public static let refreshIntervalChoices: [TimeInterval] = [
        60,
        5 * 60,
        15 * 60,
        30 * 60,
        60 * 60,
    ]
}
