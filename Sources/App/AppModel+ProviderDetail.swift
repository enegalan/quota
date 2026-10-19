import Core
import Foundation
import Platform
import PluginKit

/// Everything there is to say about one provider, gathered for its page.
///
/// Read from what the app already knows rather than by asking the provider
/// again: opening a provider's page should show the same figures the rest of
/// the window is showing, not a second reading of them.
extension AppModel {
    func providerDetail(for listing: ProviderListing) async -> ProviderDetail {
        let record = try? await environment.providers.provider(ProviderID(listing.id))
        let pools = await pools(reading: listing.id)
        return ProviderDetail(
            listing: listing,
            accountLabel: record?.authenticatedAccountLabel,
            syncCaption: syncCaption(for: record),
            failureCaption: failureCaption(for: record),
            versionCaption: versionCaption(for: listing),
            protocolCaption: protocolCaption(for: listing),
            refreshCaption: refreshCaption(for: listing, record: record),
            pools: pools
        )
    }

    /// The limits a provider meters, as its most recent reading described them.
    ///
    /// From the stored reading rather than a fresh one: a page about a provider
    /// that asks the provider for its numbers turns a click into a request, and
    /// shows figures that may disagree with the ones beside it.
    private func pools(reading providerID: String) async -> [ProviderPool] {
        let ids = Set(quotas(reading: providerID))
        let records = await storedSnapshots()
        let latest = records
            .filter { ids.contains($0.quotaID) }
            .max { $0.snapshot.updatedAt < $1.snapshot.updatedAt }?
            .snapshot
        return (latest?.buckets ?? []).map { bucket in
            ProviderPool(
                id: bucket.id,
                name: bucket.displayName,
                usagePercentage: bucket.usagePercentage,
                resetCaption: ResetCaption.caption(
                    for: bucket.period, asOf: reference, calendar: userCalendar
                )
            )
        }
    }

    /// The quotas that read from one provider.
    ///
    /// Only the identifiers: the page is about the provider, and the quotas are
    /// the way the app finds the reading that describes what it meters.
    private func quotas(reading providerID: String) -> [UUID] {
        presentations
            .filter { $0.summary.quota.providerID.rawValue == providerID }
            .map(\.id)
    }

    /// Every stored reading, or none when the store cannot be read.
    ///
    /// A provider's page without its pools is still a page, and a store that
    /// cannot be read is not a reason to refuse the one thing that could be
    /// said about the provider.
    private func storedSnapshots() async -> [SnapshotRecord] {
        do {
            return try await environment.snapshots.all()
        } catch {
            return []
        }
    }

    /// When the provider last answered, in the interface's own words.
    private func syncCaption(for record: ProviderRecord?) -> String {
        guard let last = record?.lastSyncAt else { return "Never updated." }
        let age = RelativeTime(calendar: userCalendar).describe(since: last, now: reference)
        return "Updated \(age)."
    }

    /// What went wrong the last time the provider was asked, if anything did.
    private func failureCaption(for record: ProviderRecord?) -> String? {
        guard let failure = record?.lastFailure else { return nil }
        let title = ProviderFailureTranslator.presentation(for: failure).title
        let count = record?.consecutiveFailures ?? 0
        guard count > 1 else { return "Last attempt failed: \(title)." }
        return "Last attempt failed: \(title) (\(count) in a row)."
    }

    /// The version on this machine, and the one this build carries.
    private func versionCaption(for listing: ProviderListing) -> String {
        let packaged = listing.provider.version
        guard let installed = listing.installedVersion else {
            return "\(packaged) in this build"
        }
        guard installed != packaged else { return "\(installed) installed" }
        return "\(installed) installed · \(packaged) in this build"
    }

    /// The protocol the provider says it speaks.
    private func protocolCaption(for listing: ProviderListing) -> String? {
        guard let range = listing.provider.described?.protocolRange else { return nil }
        return "Speaks protocol \(range.minimum) to \(range.maximum)."
    }

    /// How often the provider would rather not be asked.
    private func refreshCaption(
        for listing: ProviderListing,
        record: ProviderRecord?
    ) -> String? {
        let seconds = record?.suggestedRefreshInterval
            ?? listing.provider.described?.suggestedRefreshIntervalSeconds
        guard let seconds else { return nil }
        return "Asked every \(Self.interval(seconds))."
    }

    /// An interval in the words a person would use for it.
    private static func interval(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            let whole = max(1, Int(seconds.rounded()))
            return "\(whole) second\(whole == 1 ? "" : "s")"
        }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}
