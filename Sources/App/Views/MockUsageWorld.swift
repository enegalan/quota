import Core
import Foundation
import Platform
import PluginKit
import SwiftUI

/// The three usage levels the popover has to be right at, and a world that puts
/// the app into each of them.
///
/// In the app rather than only in the test target, because the previews and the
/// snapshot tests are asking the same question of the same view: wants a
/// preview *and* a snapshot at three levels, and two separately-arranged worlds
/// would drift and then disagree about what "on pace" looks like.
///
/// Arranged through the real engine rather than a hand-written plan, so what the
/// preview shows is what the app would compute — a mock that invented a plan
/// would only prove the mock renders.
enum MockUsageLevel: String, CaseIterable, Hashable {
    /// Behind pace: days left, allowance left.
    case under
    /// On pace: what is spent matches what the day is worth.
    case onPace
    /// Over pace: the period's usage is spent before the period ends.
    case over

    var title: String {
        switch self {
        case .under: "Under"
        case .onPace: "On Pace"
        case .over: "Over"
        }
    }

    /// How much of the period's usage has been spent, as a percentage.
    var usagePercentage: Double {
        switch self {
        case .under: MockUsageLevels.under
        case .onPace: MockUsageLevels.onPace
        case .over: MockUsageLevels.over
        }
    }
}

/// A popover, arranged at one usage level.
///
/// The one place that knows how to stand the app up on mock data, so a preview
/// and a snapshot of "over" are the same screen by construction.
enum MockUsageWorld {
    static let providerID = "quota.mock.provider"
    static let providerName = "Mock Provider"
    static let bucketID = "usage"
    static let account = "mock@example.com"
    static let quotaName = "Mock Quota"

    /// The mock world's instant: 15 March 2026, midday.
    static var reference: Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        guard let date = try? LocalDate(
            year: MockUsageInstant.year,
            month: MockUsageInstant.month,
            day: MockUsageInstant.day
        ) else {
            return Date(timeIntervalSince1970: 0)
        }
        guard let midnight = date.date(calendar: calendar),
              let noon = calendar.date(
                  bySettingHour: MockUsageInstant.hour,
                  minute: 0,
                  second: 0,
                  of: midnight
              )
        else {
            return Date(timeIntervalSince1970: 0)
        }
        return noon
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static var timeZone: TimeZone {
        TimeZone(identifier: "Europe/Madrid") ?? .current
    }

    /// An environment holding one quota at `level`, planned by the real engine.
    static func environment(level: MockUsageLevel) async throws -> AppEnvironment {
        try await environment(plans: [MockQuotaPlan.mock(level: level)])
    }

    /// An environment holding several quotas, one per provider, planned by the
    /// real engine.
    ///
    /// The arrangement the one-quota world cannot show: what the popover looks
    /// like when the menu bar item is speaking for one of several quotas and the
    /// rest are listed beside it. Distinct providers rather than distinct buckets
    /// on one provider, because that is the shape a user arrives at — one quota
    /// per thing they pay for.
    static func severalQuotaEnvironment() async throws -> AppEnvironment {
        try await environment(plans: MockQuotaPlan.several)
    }

    /// An environment holding a set of quotas, planned by the real engine.
    ///
    /// One function for both worlds rather than one per arrangement, so a quota
    /// is stored, read, and planned by the same code whichever world it is in:
    /// a second arrangement written separately would be a second answer to
    /// "what does a quota look like", and the two would drift.
    static func environment(plans: [MockQuotaPlan]) async throws -> AppEnvironment {
        let store = CodableStore.inMemory()
        let quotas = QuotaRepository(store: store)
        let providers = ProviderRepository(store: store)
        var readings: [String: SnapshotRecord] = [:]
        for plan in plans {
            let quota = try plan.quota()
            try await quotas.save(quota)
            try await providers.save(
                ProviderRecord(
                    providerID: try ProviderID(plan.providerID),
                    displayName: plan.providerName,
                    installedVersion: "1.0.0",
                    authenticatedAccountLabel: plan.account
                )
            )
            let reading = try reading(for: quota, plan: plan)
            readings[plan.providerID] = reading
            try await SnapshotRepository(store: store).save(reading)
            // Two timeline points, because a day's spending is the rise from where
            // the day started; one reading cannot establish it and the panel would
            // have no today to show.
            try await TimelineRepository(store: store).append(
                try history(for: quota, plan: plan),
                keepingAtMost: MockUsageLevels.timelineDays
            )
        }

        let environment = AppEnvironment.preview(
            store: store,
            available: available(plans),
            fetcher: MockUsageFetcher(readings: readings),
            now: reference,
            calendar: calendar
        )
        _ = try await environment.planner.plan(for: .manual)
        return environment
    }

    /// The popover at `level`, loaded, as the menu bar shows it.
    ///
    /// Loaded rather than merely built: `AppModel` starts empty and fills itself
    /// on a load, so a preview handed an unloaded model would render the
    /// onboarding screen while claiming to show a quota.
    @MainActor
    static func model(level: MockUsageLevel) async throws -> AppModel {
        let model = await AppModel(environment: try environment(level: level))
        await model.load()
        return model
    }

    /// The popover with several quotas, loaded, as the menu bar shows it.
    @MainActor
    static func severalQuotaModel() async throws -> AppModel {
        let model = await AppModel(environment: try severalQuotaEnvironment())
        await model.load()
        return model
    }

    private static let version = Version(major: 1, minor: 0, patch: 0)

    /// The providers this scripted world offers, in the shape the real screen reads.
    ///
    /// One fixed version for every plan, so the mock exercises the same code path
    /// as a real provider — including the version negotiation the installer does
    /// — instead of handing the creation flow pre-baked state it would otherwise
    /// have to assemble for itself.
    static func available(_ plans: [MockQuotaPlan]) -> [AvailableProvider] {
        let version = version
        return plans.map { plan in
            AvailableProvider(id: plan.providerID, version: version)
        }
    }

    /// The current measurement for one mock quota, as the world arranged it.
    ///
    /// Stamped at the world's reference instant rather than at whatever
    /// moment the world happened to be built, so a preview and a snapshot of
    /// the same level carry the same reading and a picture that moves on its
    /// own can still be compared with anything.
    ///
    /// One bucket carrying the level's whole percentage over the quota's own
    /// period. Both details are load-bearing: a reading has to be a reading
    /// of the quota's period, or the pacing verdict the preview exists to
    /// show would be computed against the wrong clock and "behind pace" would
    /// mean something the app never says.
    ///
    /// - Throws: whatever the bucket or the snapshot rejects, which is the
    ///   domain refusing an arrangement it could not store.
    private static func reading(
        for quota: Quota,
        plan: MockQuotaPlan
    ) throws -> SnapshotRecord {
        let bucket = try UsageBucket(
            id: plan.bucketID,
            displayName: "Usage",
            usagePercentage: plan.level.usagePercentage,
            period: quota.period
        )
        return SnapshotRecord(
            quotaID: quota.id,
            bucketID: plan.bucketID,
            accountLabel: plan.account,
            snapshot: try UsageSnapshot(updatedAt: reference, buckets: [bucket])
        )
    }

    /// The day's two timeline points for one mock quota.
    ///
    /// Midnight at nothing, then the reference at the level's share of the
    /// day, because a day's spending is the rise from where the day began.
    /// One point cannot establish that anything happened today, and the panel
    /// would have no today to draw.
    ///
    /// The second figure is the level's percentage scaled by how much of the
    /// day has passed, not the level's percentage again. The level is the
    /// month's figure, and reusing it for one day would say the user has
    /// spent half their allowance before lunch — a preview contradicting the
    /// number printed a few inches above it.
    ///
    /// - Throws: `QuotaDomainError.invalidDate` when the world's calendar
    ///   cannot place the reference hour on the reference day, and whatever
    ///   `TimelinePoint` rejects about the two figures.
    private static func history(
        for quota: Quota,
        plan: MockQuotaPlan
    ) throws -> TimelineRecord {
        let midnight = calendar.startOfDay(for: reference)
        guard let noon = calendar.date(
            bySettingHour: MockUsageInstant.hour,
            minute: 0,
            second: 0,
            of: reference
        ) else {
            throw QuotaDomainError.invalidDate(
                year: MockUsageInstant.year,
                month: MockUsageInstant.month,
                day: MockUsageInstant.day
            )
        }
        // Half the day's reading at noon: the level's figure is the month's, and
        // today's share is what the day is worth, so the two are not the same
        // number and a snapshot that reused one for both would misstate today.
        let elapsed = MockUsageLevels.elapsedShare
        return TimelineRecord(
            quotaID: quota.id,
            bucketID: plan.bucketID,
            accountLabel: plan.account,
            timeline: UsageTimeline(
                points: [
                    try TimelinePoint(recordedAt: midnight, bucketID: plan.bucketID, usagePercentage: 0),
                    try TimelinePoint(
                        recordedAt: noon,
                        bucketID: plan.bucketID,
                        usagePercentage: plan.level.usagePercentage * elapsed / UsageConstants.percentageScale
                    ),
                ]
            )
        )
    }
}

/// Reports the reading the world was arranged with, per provider.
///
/// So a refresh in a preview changes nothing, which is what makes the rendered
/// picture reproducible: a preview whose figures moved on its own between
/// renders could not be compared with anything.
///
/// Keyed by provider because that is all a `UsageFetching` call is told, and a
/// world with several providers needs each of its own answer — a fetcher that
/// reported one provider's reading for every request would have shown the same
/// figure on every row of the list.
struct MockUsageFetcher: UsageFetching {
    let readings: [String: SnapshotRecord]

    /// Reports the reading the world was arranged with, for the provider
    /// asked about.
    ///
    /// The local date is not consulted. The world holds one reading per
    /// provider, fixed at its reference instant, so a refresh during a
    /// preview or a snapshot hands back the figures the world was built with.
    /// A fetcher that recomputed anything here would let the numbers drift
    /// between renders, and a picture that drifts is not a reproduction of
    /// anything.
    ///
    /// A provider with no arranged reading is reported as a failure rather
    /// than given a fabricated zero, and through the same channel a real
    /// provider would use: an arrangement that is missing then shows as a
    /// failed sync instead of as a quota nobody has touched.
    func fetchUsage(
        providerID: ProviderID,
        accountLabel: String,
        localDate: LocalDate
    ) async -> UsageFetchOutcome {
        guard let reading = readings[providerID.rawValue] else {
            return .failure(
                SyncFailure(
                    code: .notInstalled,
                    message: "The mock world has no reading for this provider.",
                    occurredAt: MockUsageWorld.reference
                )
            )
        }
        return .success(reading.snapshot)
    }
}

#Preview("Under") {
    PreviewHost(title: "Under") { try await MockUsageWorld.model(level: .under) }
}

#Preview("On Pace") {
    PreviewHost(title: "On Pace") { try await MockUsageWorld.model(level: .onPace) }
}

#Preview("Over") {
    PreviewHost(title: "Over") { try await MockUsageWorld.model(level: .over) }
}

#Preview("Several Quotas") {
    PreviewHost(title: "Several Quotas") { try await MockUsageWorld.severalQuotaModel() }
}

/// A popover over a mock world, or the reason that world could not be built.
///
/// The failure is shown rather than swallowed: a preview that silently rendered
/// something else is worse than one that says the arrangement is broken — and a
/// preview whose world was never built is a preview of the failure screen that
/// looks exactly like a working one.
///
/// The world is built on appear rather than handed in, because building one
/// writes to a store, and a store built inside a `#Preview` body is rebuilt on
/// every re-render.
struct PreviewHost: View {
    /// What the preview is of, used to say which arrangement broke.
    let title: String
    let world: @MainActor () async throws -> AppModel

    @State private var model: AppModel?

    var body: some View {
        content
            .task {
                model = try? await world()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            MainPopover(model: model, launchFailure: nil)
        } else {
            LaunchFailureView(message: "The mock world for \(title) could not be built.")
        }
    }
}
