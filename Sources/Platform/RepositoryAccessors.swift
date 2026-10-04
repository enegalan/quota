import Foundation

// The typed accessors for a store.
//
// Named for what they do so a caller reaches for a repository
// by role rather than by a type it has to construct. Each one is a thin
// view over the same `QuotaStore`, so choosing an accessor cannot change what
// gets persisted.

/// The quota accessor, for what a user has asked to keep an eye on.
public func quotaRepository(_ store: any QuotaStore) -> QuotaRepository {
    QuotaRepository(store: store)
}

/// The snapshot accessor, for the latest reading per quota, bucket, and account.
public func snapshotRepository(_ store: any QuotaStore) -> SnapshotRepository {
    SnapshotRepository(store: store)
}

/// The timeline accessor, for the recorded history a chart draws.
public func timelineRepository(_ store: any QuotaStore) -> TimelineRepository {
    TimelineRepository(store: store)
}

/// The provider accessor, for what the app knows without contacting one.
public func providerRepository(_ store: any QuotaStore) -> ProviderRepository {
    ProviderRepository(store: store)
}

/// The preferences accessor, for settings not tied to a single quota.
public func preferencesRepository(_ store: any QuotaStore) -> PreferencesRepository {
    PreferencesRepository(store: store)
}

/// The allocation-plan accessor, for what the engine decided to spend where.
public func allocationPlanRepository(_ store: any QuotaStore) -> AllocationPlanRepository {
    AllocationPlanRepository(store: store)
}

/// The installed-provider accessor, for what the installer recorded on disk.
public func installedProviderRepository(_ store: any QuotaStore) -> InstalledProviderRepository {
    InstalledProviderRepository(store: store)
}
