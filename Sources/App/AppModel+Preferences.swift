import Core
import Foundation
import Platform

extension AppModel {
    func updateMenuBarPreferences(_ update: (inout MenuBarPreferences) -> Void) {
        var preferences = menuBarPreferences
        update(&preferences)
        storeMenuBarPreferences(preferences)
        let options = menuBarPreferences
        Task {
            do {
                try await self.savePreferences(restoringMenuBarOnFailure: true) {
                    let current = try await self.environment.preferences.load()
                    try await self.environment.preferences.save(current.withMenuBar(options))
                }
            } catch {
                self.report(error)
            }
        }
    }

    /// Writes the preferences document after any save already in flight.
    ///
    /// Preferences are one document, replaced on every save. Two callers that
    /// each load, change a field, and write will drop whichever field the
    /// earlier load did not see — a menu-bar toggle and a pin, or a pin and a
    /// notification setting. Sharing this queue means each load sees the
    /// previous write.
    ///
    /// The task is cleared only while it is still the latest save. An older
    /// one finishing must not make `load()` treat a newer save as done, or
    /// the reload puts the stored menu bar back over the value the newer save
    /// is still writing. A failed menu-bar save restores the stored value for
    /// the same reason: the screen was updated before the write, and a failed
    /// write must not leave that update on screen.
    func savePreferences(
        restoringMenuBarOnFailure: Bool = false,
        _ write: @escaping @MainActor () async throws -> Void
    ) async throws {
        let token = UUID()
        menuBarSaveToken = token
        let previous = menuBarSaveTask
        let task = Task {
            await previous?.value
            try await write()
        }
        menuBarSaveTask = Task {
            _ = try? await task.value
        }
        do {
            try await task.value
            if menuBarSaveToken == token {
                menuBarSaveTask = nil
            }
        } catch {
            if menuBarSaveToken == token {
                menuBarSaveTask = nil
                if restoringMenuBarOnFailure {
                    await restoreStoredMenuBarPreferences(matching: token)
                }
            }
            throw error
        }
    }

    /// Puts the stored menu-bar preferences back, unless a newer save has started.
    private func restoreStoredMenuBarPreferences(matching token: UUID) async {
        guard menuBarSaveToken == token, let stored = try? await environment.preferences.load(),
              menuBarSaveToken == token else { return }
        storeMenuBarPreferences(stored.menuBar)
    }

    /// Makes one quota the one the menu bar item speaks for.
    ///
    /// Saved rather than held, because the choice has to survive the relaunch
    /// that follows quitting: a menu bar item that showed a different quota each
    /// morning would make the number beside it untrustworthy, and a number the
    /// user cannot rely on is the one thing a menu bar item is for.
    ///
    /// Pinning one quota unpins the previous one — there is no separate unpin
    /// action, because picking another quota is itself the way to change it.
    ///
    /// Not routed through `perform`, which reloads everything: the choice touches
    /// no reading, no plan, and no quota, and a popover that re-read the whole
    /// store on every click would make choosing look like waiting.
    func showInMenuBar(_ presentation: QuotaPresentation) async {
        guard presentation.id != menuBarQuotaID else { return }
        let options = menuBarPreferences
        do {
            try await savePreferences(restoringMenuBarOnFailure: true) {
                let preferences = try await self.environment.preferences.load()
                try await self.environment.preferences.save(
                    preferences
                        .withMenuBarQuotaID(presentation.id)
                        .withMenuBar(options)
                )
                self.storeMenuBarQuotaID(presentation.id)
                self.lastError = nil
            }
        } catch {
            report(error)
        }
    }
}
