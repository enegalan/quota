import Foundation
import Platform
import SwiftUI

/// Case-insensitive match of a provider listing against a search query.
enum ProviderSearch {
    /// Whether one listing satisfies the query.
    ///
    /// A query of only whitespace matches everything, so a search box that has
    /// been cleared — or pasted into and emptied — restores the full list rather
    /// than showing nothing. The identifier is deliberately not searched: it is
    /// shown to nobody in this window, so matching on it would surface a provider
    /// through a word the user cannot see on screen.
    static func matches(_ listing: ProviderListing, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let haystack = (listing.displayName + " " + listing.summary).lowercased()
        return haystack.contains(needle)
    }

    /// Narrows every section at once, keeping each listing in its own section.
    ///
    /// Sections are filtered separately rather than pooled into one result,
    /// because the section a provider sits in is what tells the user whether they
    /// can use it, and a match that lost its heading would read as a provider
    /// available to install when it is already connected.
    static func filter(_ sections: ProviderSections, query: String) -> ProviderSections {
        ProviderSections(
            available: filter(sections.available, query: query),
            installed: filter(sections.installed, query: query),
            connected: filter(sections.connected, query: query)
        )
    }

    /// The subset of one section that satisfies the query.
    static func filter(_ listings: [ProviderListing], query: String) -> [ProviderListing] {
        listings.filter { matches($0, query: query) }
    }

    /// Whether a search left nothing to show.
    ///
    /// - Returns: whether every section came back empty. Checked after filtering
    ///   rather than before, because "no provider matches this search" and "no
    ///   provider is installed" call for different words on screen.
    static func isEmpty(_ sections: ProviderSections) -> Bool {
        sections.available.isEmpty && sections.installed.isEmpty && sections.connected.isEmpty
    }

    /// What a list with nothing to show says.
    ///
    /// Two sentences rather than one, because they are two different problems: a
    /// build that bundles no providers is a fact about the app, and a search that
    /// matched nothing is a fact about what was typed. One message for both leaves
    /// a user who mistyped a provider believing the app cannot see any.
    static func emptyMessage(query: String, hasAnyProviders: Bool) -> String {
        guard hasAnyProviders else {
            return "No providers are available in this build."
        }
        return "No providers match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
    }
}

/// The search box both provider lists are filtered by.
///
/// One field rather than two hand-written ones, so the two lists cannot disagree
/// about what a query matches or about what the field is announced as.
struct ProviderSearchField: View {
    @Binding var query: String

    var body: some View {
        TextField("Search providers", text: $query)
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .accessibilityLabel("Search providers")
    }
}
