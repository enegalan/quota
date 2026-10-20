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
}
