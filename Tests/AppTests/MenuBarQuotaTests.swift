import Core
import Foundation
import Platform
import Testing
@testable import App

/// Which quota the menu bar item speaks for.
///
/// A menu bar item has room for one number, and with several quotas the only
/// honest answer to which one that number belongs to is the user's own. What
/// these tests pin down is that the answer is remembered, that it is remembered
/// across a relaunch, and that a remembered answer about a quota that has since
/// been removed leaves a number in the menu bar rather than a blank.
@Suite("Menu bar quota")
@MainActor
struct MenuBarQuotaTests {
    @Test("With no choice stored, the menu bar shows the first quota")
    func defaultsToTheFirst() async {
        let model = MenuBarQuotaFixture.model()

        await MenuBarQuotaFixture.seed(model, names: ["First", "Second"])

        #expect(model.menuBarQuotaID == nil)
        #expect(model.primaryPresentation?.summary.quota.name == "First")
    }

    @Test("The quota the user chose is the one the menu bar shows")
    func choiceIsShown() async throws {
        let model = MenuBarQuotaFixture.model()
        await MenuBarQuotaFixture.seed(model, names: ["First", "Second", "Third"])

        let second = try #require(model.presentations.first { $0.summary.quota.name == "Second" })
        await model.showInMenuBar(second)

        #expect(model.primaryPresentation?.id == second.id)
        #expect(model.primaryPresentation?.summary.quota.name == "Second")
    }

    @Test("The choice is stored, so it is still there after a relaunch")
    func choiceSurvivesRelaunch() async throws {
        // The failure this guards: a choice held in a view, or in the model only,
        // that resets to the first quota on the next launch. A menu bar item
        // that names a different quota each morning makes its own number
        // untrustworthy, which is the one thing it is for.
        let store = CodableStore.inMemory()
        let model = MenuBarQuotaFixture.model(store: store)
        await MenuBarQuotaFixture.seed(model, names: ["First", "Second"])

        let second = try #require(model.presentations.first { $0.summary.quota.name == "Second" })
        await model.showInMenuBar(second)

        // A second model over the same store is the relaunch: nothing in memory
        // carries over, so anything still resolved came off disk.
        let relaunched = MenuBarQuotaFixture.model(store: store)
        await relaunched.load()

        #expect(relaunched.menuBarQuotaID == second.id)
        #expect(relaunched.primaryPresentation?.summary.quota.name == "Second")
    }

    @Test("A choice naming a deleted quota falls back instead of showing nothing")
    func deletedChoiceFallsBack() async throws {
        // A menu bar item with no number in it says the app is broken, and the
        // first quota is a figure the user can check against the window.
        let store = CodableStore.inMemory()
        let model = MenuBarQuotaFixture.model(store: store)
        await MenuBarQuotaFixture.seed(model, names: ["First", "Second"])

        let second = try #require(model.presentations.first { $0.summary.quota.name == "Second" })
        await model.showInMenuBar(second)
        await model.deleteQuota(second.id)

        #expect(model.presentations.count == 1)
        #expect(model.primaryPresentation?.summary.quota.name == "First")
    }

    @Test("Choosing again replaces the choice rather than keeping the first one")
    func choosingAgainReplacesTheChoice() async throws {
        // A choice that only ever recorded the first pick would leave a user who
        // changed their mind stuck with the quota they started with, with no way
        // to say so — and the popover would be marking a quota as the one in the
        // menu bar that the menu bar item is not showing.
        let model = MenuBarQuotaFixture.model()
        await MenuBarQuotaFixture.seed(model, names: ["First", "Second", "Third"])

        #expect(model.presentations.map(\.summary.quota.name) == ["First", "Second", "Third"])
        let byName = Dictionary(uniqueKeysWithValues: model.presentations.map { ($0.summary.quota.name, $0) })
        let second = try #require(byName["Second"])
        let third = try #require(byName["Third"])

        await model.showInMenuBar(second)
        await model.showInMenuBar(third)

        #expect(model.menuBarQuotaID == third.id)
        #expect(model.primaryPresentation?.summary.quota.name == "Third")
    }
}

/// The world a menu-bar-quota test runs against.
///
/// Several quotas on several providers, because the claim under test only exists
/// when there is something to choose between: a model with one quota would
/// agree with every answer.
enum MenuBarQuotaFixture {
    static let providerIDs = [
        "quota.test.first",
        "quota.test.second",
        "quota.test.third",
    ]

    @MainActor
    static func model(store: any QuotaStore = CodableStore.inMemory()) -> AppModel {
        AppModel(environment: QuotaCreationFixture.environment(store: store))
    }

    /// Creates one quota per provider, in the order named.
    ///
    /// Through `createQuota` rather than by writing to the store, so the tests
    /// arrive at these quotas the way the app does, and a change to what
    /// creation refuses is a change these tests feel.
    static func seed(_ model: AppModel, names: [String]) async {
        for (name, providerID) in zip(names, providerIDs) {
            _ = await model.createQuota(
                named: name,
                providerID: providerID,
                bucketID: nil,
                period: nil,
                policy: .even
            )
        }
    }
}
