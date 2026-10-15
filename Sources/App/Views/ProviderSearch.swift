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
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { return true }
        // Everything the user can actually see on a row is searchable: name,
        // summary, and the state the row announces. The identifier stays out,
        // for the same reason as before — matching invisible text would surface
        // a provider the user has no word to account for.
        let haystack = (
            listing.displayName + " " +
                listing.summary + " " +
                listing.state.statusLabel + " " +
                listing.state.unavailableLabel
        ).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        // A query is read as several words rather than as one literal string, so
        // typing "cursor ide" still finds a provider whose name and summary each
        // carry one of the words. Every word has to appear; the order does not.
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// A query split into lowercased, diacritic-free tokens.
    ///
    /// Whitespace separates terms; empty input yields no tokens, so clearing the
    /// field restores the whole list instead of hiding everything.
    private static func normalizedTokens(_ query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
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
        HStack(spacing: LayoutMetrics.rowSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search providers", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search providers")
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LayoutMetrics.inset)
        .padding(.vertical, LayoutMetrics.rowSpacing)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                .strokeBorder(Color.primary.opacity(LayoutMetrics.barTrackOpacity), lineWidth: 1)
        )
    }
}
