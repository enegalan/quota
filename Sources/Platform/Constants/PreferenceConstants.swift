import Core
import Foundation

/// Defaults for the settings a user has not chosen yet.
///
/// Named here rather than defaulted at each use site, so "what the app does when
/// the user has not answered yet" is one decision with one place to change. Each
/// value is read from the thing it stands in for rather than written out: a
/// number here that disagreed with the scheduler or with the policy it names
/// would be a second answer to the same question.
public enum PreferenceConstants {
    /// The policy a new quota gets when the user has not picked one.
    public static let defaultPolicyKind = AllocationPolicy.even.kind
}
