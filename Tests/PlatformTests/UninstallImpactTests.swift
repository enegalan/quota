import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

/// Checks what removing a provider costs, and what removing it leaves behind.
///
/// Uninstalling is the one operation in this application a user cannot undo, and
/// it is the one whose cost is invisible until it has happened. These tests hold
/// the two lines to: say what would stop refreshing before anything is removed,
/// and never remove a user's readings while removing the code that reads them.
@Suite("Uninstall impact")
struct UninstallImpactTests {
    @Test("An uninstall reports every quota that would stop refreshing")
    func impactListsAffectedQuotas() async throws {
        let store = CodableStore.inMemory()
        let first = try QuotaFixture.quota(name: "One")
        let second = try QuotaFixture.quota(name: "Two")
        let other = try QuotaFixture.quota(name: "Other", providerID: "cursor")
        try await store.saveQuotas([first, second, other].map(QuotaRecord.init(quota:)))

        let impact = try await installer(store).impact(ofUninstalling: "mock")
        #expect(impact.unrefreshableCount == 2)
        #expect(Set(impact.affectedQuotas) == [first.id.uuidString, second.id.uuidString])
        #expect(impact.needsConfirmation)
    }

    @Test("Uninstalling a provider nothing depends on needs no confirmation")
    func noImpactNeedsNoConfirmation() async throws {
        let store = CodableStore.inMemory()
        let impact = try await installer(store).impact(ofUninstalling: "mock")
        #expect(impact == UninstallImpact.none)
        #expect(impact.needsConfirmation == false)
    }

    @Test("Uninstalling leaves every quota in place")
    func uninstallPreservesQuotaRecords() async throws {
        let store = CodableStore.inMemory()
        let quota = try QuotaFixture.quota(name: "Kept")
        try await store.saveQuotas([QuotaRecord(quota: quota)])
        let plugins = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plugins) }

        try await installer(store, in: plugins).uninstall("mock")

        // The record survives because the user still has history for it, and the
        // only thing lost is the ability to refresh it — a state the rest of the
        // application knows how to show.
        #expect(try await quotaRepository(store).all() == [quota])
    }

    /// An installer that never launches anything, over the directory given.
    ///
    /// Nothing here installs or launches: the tests below are about the two
    /// questions asked either side of a removal, so the launcher and the log
    /// directory only have to be somewhere legal.
    private func installer(
        _ store: CodableStore,
        in directory: URL = FileManager.default.temporaryDirectory
    ) -> PluginInstaller {
        PluginInstaller(
            pluginsDirectory: directory,
            repository: installedProviderRepository(store),
            quotas: quotaRepository(store),
            launcher: TestPluginLauncher(),
            logDirectory: directory.appendingPathComponent("logs", isDirectory: true)
        )
    }
}
