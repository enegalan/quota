import Core
import Foundation
import PluginKit

/// One provider as the interface shows it, with the state that decides where it
/// sits.
///
/// The interface needs both together — a name and a heading — and deriving the
/// heading here means no view ever has to work it out, or get it subtly wrong.
public struct ProviderListing: Sendable, Equatable, Identifiable {
    public let provider: AvailableProvider
    public let state: ProviderState
    public let installedVersion: Version?

    public var id: String {
        provider.id
    }

    public init(provider: AvailableProvider, state: ProviderState, installedVersion: Version?) {
        self.provider = provider
        self.state = state
        self.installedVersion = installedVersion
    }

    // The provider's own answers, named once here rather than reached through
    // `provider` at every use. A view that writes `listing.provider.displayName`
    // everywhere is a view that knows how a provider is put together; these are
    // what let the interface be written against a provider without naming one.

    public var displayName: String {
        provider.displayName
    }

    public var summary: String {
        provider.summary
    }
}

/// The providers, split into available, installed, and connected.
///
/// Available, installed, and connected are the three headings. A provider sits in
/// exactly one, chosen from its state rather than from which list it was put in:
/// a provider that has been connected and then has its provider uninstalled moves
/// headings on its own, with nothing to keep in step.
public struct ProviderSections: Sendable, Equatable {
    public let available: [ProviderListing]
    public let installed: [ProviderListing]
    public let connected: [ProviderListing]

    public init(
        available: [ProviderListing],
        installed: [ProviderListing],
        connected: [ProviderListing]
    ) {
        self.available = available
        self.installed = installed
        self.connected = connected
    }

    public static let empty = ProviderSections(available: [], installed: [], connected: [])
}

/// What this build offers, what is installed, and the rules that relate them.
///
/// Read-only over the two sources. Everything that changes what is installed goes
/// through the installer, so there is one place that writes code to disk and one
/// place that decides what the interface is allowed to offer.
public struct PluginManager: Sendable {
    /// What the application offers, read once from the bundle's packaged providers.
    /// Public because the providers screen renders it directly, and a copy handed
    /// out by a method would only be a way for that copy to go stale.
    public let available: [AvailableProvider]
    private let installed: InstalledProviderRepository
    private let preferences: PreferencesRepository
    private let quotas: QuotaRepository

    public init(
        available: [AvailableProvider],
        installed: InstalledProviderRepository,
        preferences: PreferencesRepository,
        quotas: QuotaRepository
    ) {
        self.available = available
        self.installed = installed
        self.preferences = preferences
        self.quotas = quotas
    }

    /// The provider with `id`, or nil when this build does not package one.
    ///
    /// Nil is an answer, not a lookup failure: an installed record is kept
    /// precisely because the provider that made it may be gone from this build.
    public func provider(id: String) -> AvailableProvider? {
        available.first { $0.id == id }
    }

    /// Whether a provider is switched off by preference.
    ///
    /// A user's or a support's decision about code already on their machine, which
    /// is enough to stop it being launched.
    public func isDisabled(_ id: String, preferences: Preferences) -> Bool {
        preferences.disabledProviders.contains(id)
    }

    /// The state a provider is in, given what this build packages and what is
    /// installed.
    ///
    /// One function, because state that is computed in two places eventually
    /// disagrees: the providers screen, the host, and the synchronizer each need
    /// this answer and none of them may form their own.
    ///
    /// - Parameter described: what the provider said about itself, once something
    ///   has run it. Nil when nothing has, and then nothing is claimed about it.
    public func state(
        of provider: AvailableProvider,
        described: ProviderDescriptor? = nil,
        preferences: Preferences
    ) async throws -> ProviderState {
        if isDisabled(provider.id, preferences: preferences) {
            return .disabled
        }
        if let described, !isCompatible(described) {
            return .incompatible
        }
        if let record = try await installed.provider(provider.id) {
            // This build ships a newer one than the machine has. The comparison is
            // against what the bundle holds, not against a number in a file about
            // what it holds.
            if provider.version > record.version {
                return .updateAvailable
            }
            return record.state
        }
        // A provider nobody installed and that some quota still points at is a
        // different thing from a provider nobody installed. The quota's data is
        // still there and still shown; it just cannot be refreshed.
        if try await isReferencedByAQuota(provider.id) {
            return .missing
        }
        return .notInstalled
    }

    /// Whether this host can talk to a provider that has said what it speaks.
    ///
    /// The provider's own claim, checked the same way `PluginHost` checks it: the
    /// range it says it speaks has to be one this host speaks, rather than merely
    /// crossing it somewhere. A provider that has not been asked is not judged
    /// either way — the question has no answer until it runs.
    public func isCompatible(_ described: ProviderDescriptor) -> Bool {
        described.protocolRange.isCompatible(with: PluginProtocolConstants.hostRange)
    }

    /// Whether any quota still points at this provider.
    ///
    /// The only thing standing between `.missing` and `.notInstalled`, and it is a
    /// question about the user's data rather than about what this build ships.
    /// Readings for a provider nobody installed are still on disk and still worth
    /// showing, so reporting it as simply absent is what makes the interface throw
    /// them away.
    private func isReferencedByAQuota(_ id: String) async throws -> Bool {
        try await quotas.all().contains { $0.providerID.rawValue == id }
    }

    /// Every provider this build packages, in its three sections.
    ///
    /// - Parameter described: what each provider has said about itself, by id, for
    ///   the ones that have been asked. Absent for the rest, which is not an error:
    ///   the row shows the name it can be given and fills in when it can.
    public func sections(
        preferences: Preferences,
        described: [String: ProviderDescriptor] = [:]
    ) async throws -> ProviderSections {
        var availableSection: [ProviderListing] = []
        var installedSection: [ProviderListing] = []
        var connectedSection: [ProviderListing] = []
        for provider in available {
            let record = try await installed.provider(provider.id)
            let state = try await state(
                of: provider, described: described[provider.id], preferences: preferences
            )
            let listing = ProviderListing(
                provider: provider, state: state, installedVersion: record?.version
            )
            switch state {
            case .connected, .synchronizing, .authRequired, .authExpired:
                connectedSection.append(listing)
            case .notInstalled, .missing, .incompatible, .disabled:
                availableSection.append(listing)
            default:
                installedSection.append(listing)
            }
        }
        return ProviderSections(
            available: availableSection,
            installed: installedSection,
            connected: connectedSection
        )
    }

    /// Installed providers this build does not package.
    ///
    /// Kept, because the directory is still on disk and the record is still true.
    /// A provider from an older build was installed by this application and is
    /// still launchable; dropping its record because the tarball left the bundle
    /// would throw away the only thing that knows where the code is.
    public func unlisted() async throws -> [InstalledProvider] {
        let records = try await installed.all()
        return records.filter { provider(id: $0.id) == nil }
    }
}
