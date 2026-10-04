import Foundation
import PluginKit

/// A provider this build can offer.
///
/// Discovery reads one fact off the application bundle — the name of a packaged
/// provider — so this is deliberately thin: an identifier, the version it installs
/// as, and what the provider has said about itself once it has been asked.
/// Everything else an interface wants to show comes from the descriptor when one
/// exists, because a hand-written claim about a plugin is a second answer to a
/// question the plugin answers better.
public struct AvailableProvider: Sendable, Equatable, Identifiable {
    /// Matches `ProviderID`, and is the name of the packaged file it was read from.
    public let id: String

    /// The version it installs as, which is this build's own.
    ///
    /// A packaged provider is built and shipped with the application, so there is
    /// no independent version of it: what the user gets is what came in the
    /// bundle. The directory it lands in is still versioned, because an upgrade of
    /// the application has to be able to leave the older one launchable for as long
    /// as it takes to roll back.
    public let version: Version

    /// What the provider calls itself, or nil until it has been asked.
    ///
    /// Nil is an answer rather than a gap to paper over: nothing has run this
    /// provider yet, and a name invented here that outlived the real one would be
    /// shown to the user as though the provider had said it.
    public let described: ProviderDescriptor?

    public init(id: String, version: Version, described: ProviderDescriptor? = nil) {
        self.id = id
        self.version = version
        self.described = described
    }

    /// The name to show, which is the provider's own as soon as it has spoken.
    public var displayName: String {
        described?.displayName ?? Self.name(fromIdentifier: id)
    }

    /// One line about what it meters, empty until the provider has said.
    public var summary: String {
        described?.description ?? ""
    }

    /// A readable name from an identifier, for a provider nobody has run.
    ///
    /// A placeholder the descriptor replaces the moment there is one, and no more
    /// than a name: there is nothing to say about what an unrun provider meters,
    /// and inventing it is the thing this design stopped doing.
    static func name(fromIdentifier id: String) -> String {
        id
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }
}
