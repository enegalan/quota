import Core
import Foundation
import Platform
import PluginKit
import Testing
@testable import App

/// What the app says when a provider action fails.
///
/// The failure has to survive the reload that follows the action, and the
/// provider list has to be up to date whether or not the quota panels could be
/// built: a provider whose state is stale is a provider the user is offered an
/// action for that has already happened.
@Suite("A provider action that fails")
@MainActor
struct ProviderActionFailureTests {
    @Test("The reason a provider action failed is still on screen afterwards")
    func failureSurvivesTheReload() async {
        let model = AppModel(
            environment: AppEnvironment.preview(
                store: CodableStore.inMemory(),
                available: [],
                fetcher: UnconnectedFetcher(),
                now: SummaryFixture.reference,
                calendar: SummaryFixture.calendar
            )
        )
        await model.load()
        #expect(model.lastError == nil)

        // An update of a provider that is not installed fails, and the reason
        // has to reach the user: the reload that follows the action clears the
        // banner, and a failure with the reason wiped is a failure with no
        // reason at all.
        await model.update(ProviderListing(
            provider: AvailableProvider(id: "absent", version: Version(major: 1, minor: 0, patch: 0)),
            state: .notInstalled,
            installedVersion: nil
        ))

        #expect(model.lastError != nil)
    }

    @Test("Update All updates every provider that has an update waiting")
    func updateAllUpdatesEveryOutdatedProvider() async throws {
        let store = CodableStore.inMemory()
        try await installedProviderRepository(store).save(InstalledProvider(
            id: "alpha",
            version: Version(major: 0, minor: 9, patch: 0),
            relativePath: "alpha/0.9.0",
            state: .installed,
            installedAt: SummaryFixture.reference,
            contentHash: "hash"
        ))
        try await installedProviderRepository(store).save(InstalledProvider(
            id: "beta",
            version: Version(major: 0, minor: 9, patch: 0),
            relativePath: "beta/0.9.0",
            state: .installed,
            installedAt: SummaryFixture.reference,
            contentHash: "hash"
        ))
        let environment = AppEnvironment.preview(
            store: store,
            available: [
                AvailableProvider(id: "alpha", version: Version(major: 1, minor: 0, patch: 0)),
                AvailableProvider(id: "beta", version: Version(major: 1, minor: 0, patch: 0)),
            ],
            fetcher: UnconnectedFetcher(),
            now: SummaryFixture.reference,
            calendar: SummaryFixture.calendar
        )
        let model = AppModel(environment: environment)
        await model.load()

        #expect(model.hasUpdatesAvailable == true)
        #expect(model.sections.all.contains { $0.id == "alpha" && $0.state == .updateAvailable })
        #expect(model.sections.all.contains { $0.id == "beta" && $0.state == .updateAvailable })

        await model.updateAll()

        #expect(model.isUpdatingAll == false)
        #expect(model.lastError != nil)
        let alphaRecord = try await installedProviderRepository(store).provider("alpha")
        let betaRecord = try await installedProviderRepository(store).provider("beta")
        #expect(alphaRecord?.lastError != nil)
        #expect(betaRecord?.lastError != nil)
    }

    @Test("Update All does nothing when no provider has an update waiting")
    func updateAllDoesNothingWhenCurrent() async {
        let model = AppModel(
            environment: AppEnvironment.preview(
                store: CodableStore.inMemory(),
                available: [],
                fetcher: UnconnectedFetcher(),
                now: SummaryFixture.reference,
                calendar: SummaryFixture.calendar
            )
        )
        await model.load()

        #expect(model.hasUpdatesAvailable == false)
        #expect(model.isUpdatingAll == false)
        #expect(model.lastError == nil)

        await model.updateAll()

        #expect(model.isUpdatingAll == false)
        #expect(model.lastError == nil)
    }

    @Test("A load is counted, so a view waiting for fresh data waits for it")
    func loadsAreCounted() async {
        let model = AppModel(
            environment: AppEnvironment.preview(
                store: CodableStore.inMemory(),
                available: [],
                fetcher: UnconnectedFetcher(),
                now: SummaryFixture.reference,
                calendar: SummaryFixture.calendar
            )
        )
        let before = model.loadGeneration

        await model.load()
        #expect(model.loadGeneration == before + 1)

        // And again: the count is what a view keys on to reload, so each load
        // has to move it.
        await model.load()
        #expect(model.loadGeneration == before + 2)
    }

    @Test("The load is counted only after it has read everything")
    func theCountComesAfterTheData() async throws {
        let store = CodableStore.inMemory()
        let environment = AppEnvironment.preview(
            store: store,
            available: [AvailableProvider(id: "mock", version: Version(major: 1, minor: 0, patch: 0))],
            fetcher: UnconnectedFetcher(),
            now: SummaryFixture.reference,
            calendar: SummaryFixture.calendar
        )
        let model = AppModel(environment: environment)
        await model.load()

        // The provider is installed between two loads, so the list of providers
        // is different after the second one than after the first.
        try await installedProviderRepository(store).save(InstalledProvider(
            id: "mock",
            version: Version(major: 1, minor: 0, patch: 0),
            relativePath: "mock/1.0.0",
            state: .installed,
            installedAt: SummaryFixture.reference,
            contentHash: "hash"
        ))

        // What the model looked like at the moment the load was counted. A view
        // that reloads then reads the data the load has just read; a view that
        // reloads when the load *starts* reads what was there before it, which
        // is how a provider's page kept showing the state its own update had
        // just replaced.
        let seen = Recorder()
        withObservationTracking {
            _ = model.loadGeneration
        } onChange: {
            // The change happens on the model's own actor, so the model can be
            // read here.
            MainActor.assumeIsolated {
                seen.record(model.sections)
            }
        }
        await model.load()

        // The provider is installed in what the count saw: the count came after
        // the load had read the store, not before it started.
        #expect(seen.sections?.installed.contains { $0.id == "mock" } == true)
    }
}

/// Remembers what the model looked like at the moment it was asked.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ProviderSections?

    func record(_ sections: ProviderSections) {
        lock.lock()
        defer { lock.unlock() }
        stored = sections
    }

    var sections: ProviderSections? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
