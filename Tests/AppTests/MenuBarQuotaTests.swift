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

/// Preferences saves share one document, so they have to share one queue.
@Suite("Menu bar preference saves")
@MainActor
struct MenuBarPreferenceSaveTests {
    @Test("A finished save lets the next load read what was stored")
    func finishedSaveLetsLoadReadTheStore() async throws {
        let store = CodableStore.inMemory()
        let model = MenuBarQuotaFixture.model(store: store)
        model.updateMenuBarPreferences { $0.showLogos = false }
        // Joins the menu-bar save, and must not write the logos change away.
        await model.setNotificationsEnabled(false)

        var stored = try await preferencesRepository(store).load()
        #expect(!stored.menuBar.showLogos)
        #expect(!stored.notificationsEnabled)
        var menuBar = stored.menuBar
        menuBar.showLogos = true
        stored = stored.withMenuBar(menuBar)
        try await preferencesRepository(store).save(stored)
        await model.load()

        #expect(model.menuBarPreferences.showLogos)
    }

    @Test("A failed save puts the stored menu bar back")
    func failedSaveRestoresTheStoredMenuBar() async throws {
        let store = CodableStore(backend: FailingPreferencesBackend(failuresRemaining: 1))
        let model = MenuBarQuotaFixture.model(store: store)
        await model.load()

        model.updateMenuBarPreferences { $0.showLogos = false }
        #expect(!model.menuBarPreferences.showLogos)

        try await waitUntil { model.menuBarPreferences.showLogos }
        #expect(model.lastError != nil)
        #expect(model.menuBarPreferences.showLogos)
    }

    @Test("An older save does not let a load drop a newer one")
    func olderSaveDoesNotClearANewerOne() async throws {
        let backend = BlockingPreferencesBackend()
        let store = CodableStore(backend: backend)
        let model = MenuBarQuotaFixture.model(store: store)
        await backend.blockNextPreferencesWrite(skipping: 1)

        model.updateMenuBarPreferences { $0.showLogos = false }
        model.updateMenuBarPreferences { $0.showDailyQuota = false }
        await backend.waitUntilWriteBlocked()
        await model.load()

        #expect(!model.menuBarPreferences.showLogos)
        #expect(!model.menuBarPreferences.showDailyQuota)
        await backend.releaseBlockedWrite()
        try await waitUntil {
            let stored = try await preferencesRepository(store).load()
            return !stored.menuBar.showLogos && !stored.menuBar.showDailyQuota
        }
    }

    @Test("A pin waits for the menu-bar save already in flight")
    func pinWaitsForTheMenuBarSave() async throws {
        let backend = BlockingPreferencesBackend()
        let store = CodableStore(backend: backend)
        let model = MenuBarQuotaFixture.model(store: store)
        await MenuBarQuotaFixture.seed(model, names: ["First", "Second"])
        let second = try #require(model.presentations.first { $0.summary.quota.name == "Second" })
        await backend.blockNextPreferencesWrite()

        model.updateMenuBarPreferences { $0.showLogos = false }
        let pin = Task { await model.showInMenuBar(second) }
        await backend.waitUntilWriteBlocked()
        for _ in 0 ..< 30 {
            await Task.yield()
        }

        #expect(model.menuBarQuotaID == nil)
        await backend.releaseBlockedWrite()
        await pin.value

        let stored = try await preferencesRepository(store).load()
        let integrationID = second.summary.quota.providerID.rawValue
        #expect(model.menuBarQuotaID == second.id)
        #expect(!stored.menuBar.showLogos)
        #expect(stored.menuBarQuotaID == second.id)
        #expect(stored.menuBar.selectedQuotas[integrationID] == second.id)
    }

    private func waitUntil(_ ready: @MainActor () async throws -> Bool) async throws {
        for _ in 0 ..< 500 {
            if try await ready() {
                return
            }
            await Task.yield()
        }
        Issue.record("timed out waiting for a preference save")
    }
}

/// Preferences writes fail a fixed number of times, then behave as memory.
private actor FailingPreferencesBackend: StoreBackend {
    private let inner = InMemoryStoreBackend()
    private var failuresRemaining: Int

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func read(_ fileName: String) async throws -> Data? {
        await inner.read(fileName)
    }

    func write(_ data: Data, to fileName: String) async throws {
        if fileName == PersistenceConstants.FileName.preferences, failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        await inner.write(data, to: fileName)
    }

    func quarantine(_ data: Data, from fileName: String) async throws {
        await inner.quarantine(data, from: fileName)
    }
}

/// Holds the next preferences write, so a test can see what a later save does.
private actor BlockingPreferencesBackend: StoreBackend {
    private let inner = InMemoryStoreBackend()
    private var writesToSkip = 0
    private var blockNext = false
    private var isBlocked = false
    private var entered: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func blockNextPreferencesWrite(skipping: Int = 0) {
        writesToSkip = skipping
        blockNext = true
    }

    func waitUntilWriteBlocked() async {
        if isBlocked {
            return
        }
        await withCheckedContinuation { entered = $0 }
    }

    func releaseBlockedWrite() {
        blocked?.resume()
        blocked = nil
    }

    func read(_ fileName: String) async throws -> Data? {
        await inner.read(fileName)
    }

    func write(_ data: Data, to fileName: String) async throws {
        if fileName == PersistenceConstants.FileName.preferences, blockNext {
            if writesToSkip > 0 {
                writesToSkip -= 1
            } else {
                blockNext = false
                isBlocked = true
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    blocked = continuation
                    entered?.resume()
                    entered = nil
                }
                isBlocked = false
            }
        }
        await inner.write(data, to: fileName)
    }

    func quarantine(_ data: Data, from fileName: String) async throws {
        await inner.quarantine(data, from: fileName)
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
