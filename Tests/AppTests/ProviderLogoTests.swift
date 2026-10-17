import AppKit
import Foundation
import Testing
@testable import App

/// How the interface finds a provider's own mark in the bundle.
///
/// The images themselves live with their providers and the build script files
/// them under each identifier, so what is checked here is the lookup: a mark
/// present is loaded, and a provider this build ships none for falls back rather
/// than drawing nothing. Where the files are filed in the application bundle is
/// checked where the build is, in `ShippedFileTests`.
@Suite("Provider marks")
@MainActor
struct ProviderLogoTests {
    @Test("A provider with a mark is loaded, and one without falls back")
    func resolutionReadsTheBundle() throws {
        let bundle = try Self.bundle(holding: ["cursor"])
        #expect(ProviderLogo.image(for: "cursor", in: bundle) != nil)
        #expect(ProviderLogo.image(for: "a-provider-with-no-mark", in: bundle) == nil)
    }

    // MARK: - Fixtures

    /// A temporary bundle holding a logo directory with the named providers.
    private static func bundle(holding marks: [String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-logo-\(UUID().uuidString)", isDirectory: true)
        let directory = root
            .appendingPathComponent(ProviderLogo.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for id in marks {
            let url = directory
                .appendingPathComponent(id)
                .appendingPathExtension(ProviderLogo.fileExtension)
            try png().write(to: url)
        }
        return try #require(Bundle(path: root.path), "could not read the fixture as a bundle")
    }

    /// A small valid PNG, so the loader is exercised on real image bytes.
    private static func png() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return Data() }
        return data
    }
}
