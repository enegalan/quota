import Foundation
import Platform
import PluginKit
import Testing
@testable import App

@Suite("Provider search")
struct ProviderSearchTests {
    @Test("An empty query matches every listing")
    func emptyQueryMatchesAll() {
        let listing = Self.listing(id: "cursor", name: "Cursor", summary: "IDE usage")
        #expect(ProviderSearch.matches(listing, query: ""))
        // Whitespace is what a search box holds after a paste of nothing, and a
        // user who clears the field expects the whole list back.
        #expect(ProviderSearch.matches(listing, query: "   "))
    }

    @Test("A query matches the display name or the summary")
    func matchesNameOrSummary() {
        let listing = Self.listing(id: "cursor", name: "Cursor", summary: "IDE usage")
        #expect(ProviderSearch.matches(listing, query: "cur"))
        #expect(ProviderSearch.matches(listing, query: "IDE"))
        #expect(ProviderSearch.matches(listing, query: "CURSOR"))
        #expect(ProviderSearch.matches(listing, query: "usage"))
        #expect(!ProviderSearch.matches(listing, query: "openai"))
    }

    @Test("Filtering keeps a match in the section it came from")
    func filterKeepsSections() {
        let sections = ProviderSections(
            available: [Self.listing(id: "mock", name: "Mock", summary: "Fake usage")],
            installed: [Self.listing(id: "other", name: "Other", summary: "Elsewhere")],
            connected: [Self.listing(id: "cursor", name: "Cursor", summary: "IDE usage")]
        )
        // The section is what tells the user whether they can use the provider, so
        // a match that lost its heading would read as one available to install
        // when it is already connected.
        let filtered = ProviderSearch.filter(sections, query: "cursor")
        #expect(filtered.connected.map(\.id) == ["cursor"])
        #expect(filtered.installed.isEmpty)
        #expect(filtered.available.isEmpty)
        #expect(!ProviderSearch.isEmpty(filtered))
    }

    @Test("Filtering hides sections with nothing in them")
    func filterHidesEmptySections() {
        let sections = ProviderSections(
            available: [Self.listing(id: "mock", name: "Mock", summary: "Fake usage")],
            installed: [Self.listing(id: "other", name: "Other", summary: "Elsewhere")],
            connected: [Self.listing(id: "cursor", name: "Cursor", summary: "IDE usage")]
        )
        let filtered = ProviderSearch.filter(sections, query: "usage")
        #expect(filtered.available.map(\.id) == ["mock"])
        #expect(filtered.connected.map(\.id) == ["cursor"])
        #expect(filtered.installed.isEmpty)
    }

    @Test("A miss yields an empty catalog")
    func missIsEmpty() {
        let sections = ProviderSections(
            available: [Self.listing(id: "mock", name: "Mock", summary: "Fake usage")],
            installed: [],
            connected: []
        )
        // "no provider matches this search" and "no provider is installed" call
        // for different words on screen, so this is checked rather than assumed.
        let filtered = ProviderSearch.filter(sections, query: "nowhere")
        #expect(ProviderSearch.isEmpty(filtered))
    }

    /// A listing for a provider that has already said what it is.
    ///
    /// The name and summary are the provider's own, through a descriptor, because
    /// that is the only way an interface ever has them — a name invented from the
    /// identifier is a placeholder, and a search that matched on one would be
    /// matching on text no user can see.
    private static func listing(id: String, name: String, summary: String) -> ProviderListing {
        let provider = AvailableProvider(
            id: id,
            version: Version(major: 1),
            described: ProviderDescriptor(
                id: id,
                displayName: name,
                description: summary,
                protocolRange: PluginProtocolConstants.hostRange
            )
        )
        return ProviderListing(provider: provider, state: .notInstalled, installedVersion: nil)
    }
}
