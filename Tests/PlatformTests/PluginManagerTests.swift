import Foundation
import Testing
@testable import Core
@testable import Platform
@testable import PluginKit

@Suite("Plugin manager")
struct PluginManagerTests {
    // MARK: Nothing installed to begin with

    @Test("No provider is installed on a fresh machine")
    func nothingIsInstalledAtFirstLaunch() async throws {
        let (manager, _) = try await ManagerFixture.manager(available: [ManagerFixture.provider()])
        #expect(try await manager.state(of: ManagerFixture.provider(), preferences: .default)
            == .notInstalled)
    }

    @Test("Asking about a provider does not create a quota")
    func readingStateCreatesNoQuota() async throws {
        let (manager, store) = try await ManagerFixture.manager(
            available: [ManagerFixture.provider()]
        )
        _ = try await manager.state(of: ManagerFixture.provider(), preferences: .default)
        #expect(try await quotaRepository(store).all().isEmpty)
    }

    // MARK: State

    @Test("A provider a quota still names but that is gone reports missing")
    func missingWhenAQuotaStillNamesIt() async throws {
        let (manager, _) = try await ManagerFixture.manager(
            available: [ManagerFixture.provider()],
            quotas: [try ManagerFixture.quota(name: "Models")]
        )
        // Not a generic failure and not a fresh install: the difference is what
        // the user has to be told, that existing history cannot be refreshed.
        #expect(try await manager.state(of: ManagerFixture.provider(), preferences: .default)
            == .missing)
    }

    @Test("A newer packaged version than the installed one offers an update")
    func updateIsDetectedByVersionComparison() async throws {
        let provider = ManagerFixture.provider(version: Version(major: 1, minor: 4, patch: 2))
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider],
            installed: [ManagerFixture.installed(version: Version(major: 1, minor: 0, patch: 0))]
        )
        #expect(try await manager.state(of: provider, preferences: .default) == .updateAvailable)
    }

    @Test("An installed version matching what this build packages is just installed")
    func matchingVersionIsNotAnUpdate() async throws {
        let provider = ManagerFixture.provider()
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider], installed: [ManagerFixture.installed()]
        )
        #expect(try await manager.state(of: provider, preferences: .default) == .installed)
    }

    @Test("A version older than the one installed is not offered as an update")
    func olderPackagedVersionIsNotAnUpdate() async throws {
        // Rollback: the older directory stays launchable, but this build does not
        // claim there is anything to upgrade to.
        let provider = ManagerFixture.provider(version: Version(major: 1, minor: 0, patch: 0))
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider],
            installed: [ManagerFixture.installed(version: Version(major: 2, minor: 0, patch: 0))]
        )
        #expect(try await manager.state(of: provider, preferences: .default) == .installed)
    }

    // MARK: Compatibility

    @Test("An installed provider this host cannot speak is incompatible")
    func protocolRangeOutsideTheHostIsIncompatible() async throws {
        let provider = ManagerFixture.provider()
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider], installed: [ManagerFixture.installed()]
        )
        #expect(try await manager.state(
            of: provider, described: descriptor(id: "mock", range: .tooNew), preferences: .default
        ) == .incompatible)
    }

    @Test("An installed provider this host can speak keeps its own state")
    func protocolRangeInsideTheHostKeepsState() async throws {
        let provider = ManagerFixture.provider()
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider],
            installed: [ManagerFixture.installed(state: .connected)]
        )
        #expect(try await manager.state(
            of: provider, described: descriptor(id: "mock", range: .compatible),
            preferences: .default
        ) == .connected)
    }

    @Test("A provider that has never been asked is not judged either way")
    func undescribedProviderIsNotJudged() async throws {
        let (manager, _) = try await ManagerFixture.manager(available: [ManagerFixture.provider()])
        #expect(try await manager.state(of: ManagerFixture.provider(), preferences: .default)
            == .notInstalled)
    }

    // MARK: The kill switch

    @Test("A provider switched off in preferences is disabled")
    func killSwitchDisables() async throws {
        let provider = ManagerFixture.provider()
        let preferences = Preferences(disabledProviders: ["mock"])
        let (manager, _) = try await ManagerFixture.manager(
            available: [provider], installed: [ManagerFixture.installed()], preferences: preferences
        )
        #expect(try await manager.state(of: provider, preferences: preferences) == .disabled)
    }

    @Test("A disabled provider is never one the host would launch")
    func disabledProvidersAreNotLaunchable() {
        // The switch has to mean the same thing to the providers screen and to the
        // host, and the two ask different questions of a state.
        for state in [ProviderState.disabled, .missing, .incompatible, .notInstalled] {
            #expect(state.permitsLaunch == false, "\(state) should not launch")
        }
    }

    // MARK: Sections

    @Test("Providers are grouped from state, not from separate lists")
    func sectionsFollowState() async throws {
        let (manager, _) = try await ManagerFixture.manager(
            available: ["connected", "plain", "missing"].map { ManagerFixture.provider(id: $0) },
            installed: [
                ManagerFixture.installed(id: "connected", state: .connected),
                ManagerFixture.installed(id: "plain", state: .installed),
            ],
            quotas: [try ManagerFixture.quota(name: "Orphan", providerID: "missing")]
        )
        let sections = try await manager.sections(preferences: .default)
        #expect(sections.connected.map(\.id) == ["connected"])
        #expect(sections.installed.map(\.id) == ["plain"])
        #expect(sections.available.map(\.id) == ["missing"])
    }

    @Test("A provider appears in exactly one section")
    func sectionsDoNotOverlap() async throws {
        let (manager, _) = try await ManagerFixture.manager(
            available: [ManagerFixture.provider(), ManagerFixture.provider(id: "other")],
            installed: [ManagerFixture.installed(), ManagerFixture.installed(id: "other")]
        )
        let sections = try await manager.sections(preferences: .default)
        let everyID = sections.connected.map(\.id) + sections.installed.map(\.id)
            + sections.available.map(\.id)
        #expect(Set(everyID).count == everyID.count)
    }

    // MARK: Providers this build no longer packages

    @Test("An installed provider this build does not package keeps its record")
    func unlistedProvidersAreKept() async throws {
        let (manager, _) = try await ManagerFixture.manager(
            available: [ManagerFixture.provider()], installed: [ManagerFixture.installed(id: "gone")]
        )
        // The code is on disk and the record is the only thing that knows where.
        // Forgetting it because the tarball left the bundle would orphan a
        // directory nobody could find again.
        #expect(try await manager.unlisted().map(\.id) == ["gone"])
    }
}

/// A descriptor for `id`, speaking one of two ranges.
///
/// Named rather than written inline so the only thing that varies between the
/// compatibility tests is the range, which is the thing under test.
private func descriptor(id: String, range: ProtocolRange) -> ProviderDescriptor {
    ProviderDescriptor(
        id: id,
        displayName: "Mock",
        description: "Meters a mock thing.",
        protocolRange: range
    )
}

private extension ProtocolRange {
    /// The range this host negotiates.
    static var compatible: ProtocolRange {
        PluginProtocolConstants.hostRange
    }

    /// A major version past anything this host speaks.
    static var tooNew: ProtocolRange {
        ProtocolRange(
            minimum: Version(major: 4, minor: 0, patch: 0),
            maximum: Version(major: 4, minor: 9, patch: 0)
        )
    }
}
