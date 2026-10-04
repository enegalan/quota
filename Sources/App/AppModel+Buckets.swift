import Core
import Foundation
import Platform

/// The limits a provider meters, and which of them are already spoken for.
///
/// Its own file because this is the one reading the app takes before a quota
/// exists: it is how the creation flow knows which windows there are to offer,
/// and it is the only place the interface is told that two limits on one provider
/// may each have a quota of their own.
extension AppModel {
    /// The limits a connected provider meters, each with the window it resets
    /// over.
    ///
    /// Empty when the provider cannot be read, which is not the same as metering
    /// nothing: the creation flow falls back to the provider's primary limit and
    /// says nothing about which, rather than a picker with an empty list in it
    /// looking like an answer.
    ///
    /// Asked for before the quota exists, so this is the only reading a provider
    /// gets that is not filed against a quota. The snapshot it produces is thrown
    /// away rather than stored, because storing a reading against no quota would
    /// put a figure on disk that no panel explains and the next refresh cannot
    /// attribute.
    func buckets(forProviderID providerID: String) async -> [UsageBucket] {
        do {
            let provider = try ProviderID(providerID)
            guard let account = try await environment.providers.provider(provider)?
                .authenticatedAccountLabel
            else { return [] }
            let outcome = await environment.fetcher.fetchUsage(
                providerID: provider,
                accountLabel: account,
                localDate: LocalDate(date: reference, calendar: userCalendar)
            )
            guard case .success(let snapshot) = outcome.result else { return [] }
            return snapshot.buckets
        } catch {
            return []
        }
    }

    /// Whether a provider already has a quota that was not tied to a named pool.
    ///
    /// This is the one quota that closes a provider off. A quota naming no pool
    /// watches whatever the provider calls primary, so a second quota on the same
    /// provider could only be reporting the same numbers, which is the pair of
    /// panels disagreeing about one reading that the repository refuses. A quota
    /// that *does* name a pool does not close the provider off, because a provider
    /// metering several limits is entitled to a quota for each of them.
    func hasUnboundQuota(forProviderID providerID: String) -> Bool {
        isWatched(providerID: providerID, bucketID: nil)
    }

    /// Whether some quota watches this provider's pool.
    ///
    /// One predicate for both questions, because the two answers are the same
    /// question asked with a different pool: "is the provider itself spoken for"
    /// is this with a nil pool. Written twice, the two could drift, and a
    /// provider would be closed off by one and open by the other.
    private func isWatched(providerID: String, bucketID: String?) -> Bool {
        presentations.contains {
            $0.summary.quota.providerID.rawValue == providerID
                && $0.summary.quota.bucketID == bucketID
        }
    }

    /// Whether this provider already has a quota watching that pool.
    ///
    /// The second half of the rule `hasUnboundQuota` starts: a provider is only
    /// closed off once every limit it meters is spoken for, and the picker is
    /// where that is decided, because a row cannot know which pools exist without
    /// reading the provider.
    func isWatched(providerID: String, bucketID: String) -> Bool {
        isWatched(providerID: providerID, bucketID: .some(bucketID))
    }
}
