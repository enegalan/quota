import Foundation
import Platform
import Testing
@testable import App

@Suite("Settings preference reload")
@MainActor
struct SettingsReloadCoordinatorTests {
    @Test("A loadGeneration change mid-reload leaves the form unready until the newer reload finishes")
    func staleReloadDoesNotMarkReadyBeforeNewerFinishes() async {
        let model = AppModel(
            environment: AppEnvironment.preview(
                store: CodableStore.inMemory(),
                available: [],
                fetcher: UnconnectedFetcher(),
                now: SummaryFixture.reference,
                calendar: SummaryFixture.calendar
            )
        )
        var reload = SettingsReloadCoordinator()
        let first = reload.begin()

        // What SettingsView does when loadGeneration moves during the first
        // reload: start another pass rather than letting the stale one finish
        // as ready with values the newer pass has not applied yet.
        let generationBefore = model.loadGeneration
        await model.load()
        #expect(model.loadGeneration == generationBefore + 1)
        let second = reload.begin()

        #expect(reload.finish(first) == .ignore)
        #expect(!reload.isReady)

        #expect(reload.finish(second) == .apply)
        #expect(reload.isReady)
    }

    @Test("A user edit during the current reload marks ready without applying")
    func userEditDiscardsCurrentReload() {
        var reload = SettingsReloadCoordinator()
        let ticket = reload.begin()
        reload.noteUserEdit()

        #expect(reload.finish(ticket) == .discard)
        #expect(reload.isReady)
    }
}
