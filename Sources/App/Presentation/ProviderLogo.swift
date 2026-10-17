import AppKit
import Foundation
import Platform

/// The mark a provider is drawn with, when this build ships one.
///
/// Keyed by the provider's identifier rather than held in a table of known
/// providers, for the same reason the provider list is read off the bundle: the
/// application does not know which providers exist, so the only question it can
/// ask is whether one has a mark. A build that ships a provider without an image
/// draws the generic symbol rather than an empty space, so adding a provider is
/// adding its image and nothing else has to learn about it.
@MainActor
enum ProviderLogo {
    /// Where marks live inside a bundle: one image per provider, named for the
    /// identifier it belongs to.
    static let directoryName = BundleConstants.providerLogosDirectoryName

    /// What a packaged mark's file is.
    static let fileExtension = "png"

    /// The image for `providerID`, or nil when this build ships none.
    ///
    /// Cached per bundle and identifier: a list redraws its rows on every pass,
    /// and decoding the same PNG each time is work the picture cannot change.
    /// Only hits are remembered, because a build ships a provider's mark or it
    /// does not, and the misses are the fallback the view draws anyway.
    static func image(for providerID: String, in bundle: Bundle = .main) -> NSImage? {
        let key = "\(bundle.bundlePath)#\(providerID)"
        if let cached = cache[key] {
            return cached
        }
        guard let url = url(for: providerID, in: bundle),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[key] = image
        return image
    }

    /// Where a provider's mark is packaged, or nil when none is.
    static func url(for providerID: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: providerID,
            withExtension: fileExtension,
            subdirectory: directoryName
        )
    }

    private static var cache: [String: NSImage] = [:]
}
