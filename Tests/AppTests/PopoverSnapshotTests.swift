import AppKit
import Core
import Foundation
import SwiftUI
import Testing
@testable import App

/// The popover at three usage levels, against mock provider data.
///
/// Rendered rather than asserted on the values underneath, because the task is
/// about the panel a user sees: a summary can hold the right numbers while the
/// popover shows them clipped, in the wrong colour, or off the bottom of the
/// frame. Comparing rendered pixels is the only way to notice that.
///
/// Without a golden-image library the two claims available are the honest ones:
/// the same world renders the same picture twice, and three different worlds
/// render three different pictures. A regression that makes a level look like
/// another one fails; a change to a level's appearance fails the review that
/// looks at the written PNGs.
@Suite("Popover snapshots")
@MainActor
struct PopoverSnapshotTests {
    /// Where the rendered PNGs are written, so a change can be looked at rather
    /// than inferred. Inside `.build` because they are output, not source.
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/snapshots", directoryHint: .isDirectory)
    }

    @Test("Each level's world holds a quota the popover can show")
    func eachLevelHasAQuotaToShow() async throws {
        // A snapshot of the onboarding screen would satisfy every rendering test
        // below while showing none of the eleven elements lists, so the world
        // is checked before it is photographed.
        for level in MockUsageLevel.allCases {
            let model = try await MockUsageWorld.model(level: level)
            #expect(
                model.presentations.count == 1,
                "\(level.title) world showed \(model.presentations.count) quotas"
            )
        }
    }

    @Test("The popover renders at every usage level")
    func rendersAtEveryLevel() async throws {
        for level in MockUsageLevel.allCases {
            let image = try await render(level: level)
            #expect(image.width > 0, "\(level.title) rendered no width")
            #expect(image.height > 0, "\(level.title) rendered no height")
        }
    }

    @Test("The same world renders the same picture every time")
    func renderingIsStable() async throws {
        // The claim that makes a snapshot comparable at all: a picture of one
        // fixed instant has to be reproducible, or every run is a new baseline.
        //
        // Compared by how much of the picture differs rather than byte for byte,
        // because `ImageRenderer` rasterises with antialiasing that is not
        // bit-stable across processes — asserting equality would be asserting
        // something the renderer does not promise, and it would fail
        // intermittently for a reason that has nothing to do with the app.
        //
        // What this catches is a world that varies per render: an unstable clock
        // or a figure recomputed from the wall clock would show up here as a
        // level disagreeing with itself.
        for level in MockUsageLevel.allCases {
            let first = try await pixels(level: level)
            let second = try await pixels(level: level)
            let difference = Self.differenceRatio(first, second)
            #expect(
                difference <= Self.noiseThreshold,
                "\(level.title) differed from itself by \(difference) of its pixels"
            )
        }
    }

    @Test("Each usage level renders differently from the others")
    func levelsLookDifferent() async throws {
        // Levels that rendered alike would be a set of snapshots agreeing with
        // each other and all being wrong: the panel would say the same thing
        // about a quota with a week left and one that is finished.
        //
        // The bar is set well above the renderer's own noise, so a difference
        // this size cannot be an artefact of antialiasing.
        for level in MockUsageLevel.allCases {
            for other in MockUsageLevel.allCases where level != other {
                let difference = await Self.differenceRatio(
                    try pixels(level: level),
                    try pixels(level: other)
                )
                #expect(
                    difference >= Self.distinctThreshold,
                    "\(level.title) and \(other.title) differ by only \(difference) of their pixels"
                )
            }
        }
    }

    @Test("The popover is wide enough for its own contents")
    func popoverIsNotClipped() async throws {
        // A fixed width with contents that overflow it renders without error and
        // simply loses the end of the line, so the only way to catch it is to
        // look at the picture.
        for level in MockUsageLevel.allCases {
            let image = try await render(level: level)
            let expected = LayoutMetrics.popoverWidth
            #expect(
                abs(CGFloat(image.width) - expected) <= LayoutMetrics.snapshotWidthTolerance,
                "\(level.title) rendered \(image.width) wide, not \(expected)"
            )
        }
    }

    @Test("The rendered pictures are written where they can be looked at")
    func writesPngs() async throws {
        for level in MockUsageLevel.allCases {
            let data = try await png(for: try render(level: level))
            let url = Self.directory.appending(path: "popover-\(level.rawValue).png")
            try FileManager.default.createDirectory(
                at: Self.directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - Several quotas

    @Test("A world of several quotas holds all of them")
    func severalQuotaWorldHasEveryQuota() async throws {
        // The world is checked before it is photographed, for the same reason as
        // the single-quota worlds above: a popover that listed one quota would
        // satisfy every rendering test below while failing the only claim they
        // exist for.
        let model = try await MockUsageWorld.severalQuotaModel()
        #expect(model.presentations.count == MockQuotaPlan.several.count)
    }

    @Test("The popover with several quotas renders, and is still the popover's width")
    func severalQuotasRender() async throws {
        let model = try await MockUsageWorld.severalQuotaModel()
        let image = try render(MainPopover(model: model, launchFailure: nil))

        #expect(image.width > 0)
        #expect(image.height > 0)
        // A list that grew past the fixed width would push the right-hand figure
        // off the end of every row, and the width is the one thing about the
        // popover's box that is guaranteed rather than content-shaped.
        #expect(abs(CGFloat(image.width) - LayoutMetrics.popoverWidth) <= LayoutMetrics.snapshotWidthTolerance)
    }

    @Test("The popover with several quotas renders the same picture every time")
    func severalQuotasAreStable() async throws {
        let difference = await Self.differenceRatio(
            try pixels(MainPopover(model: try MockUsageWorld.severalQuotaModel(), launchFailure: nil)),
            try pixels(MainPopover(model: try MockUsageWorld.severalQuotaModel(), launchFailure: nil))
        )
        #expect(difference <= Self.noiseThreshold)
    }

    @Test("The several-quota popover is written where it can be looked at")
    func writesSeveralQuotaPng() async throws {
        let model = try await MockUsageWorld.severalQuotaModel()
        let data = try png(for: try render(MainPopover(model: model, launchFailure: nil)))
        let url = Self.directory.appending(path: "popover-several.png")
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try data.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Rendering

    private func render(level: MockUsageLevel) async throws -> CGImage {
        try await render(MainPopover(model: try MockUsageWorld.model(level: level), launchFailure: nil))
    }

    private func render(_ popover: MainPopover) throws -> CGImage {
        let renderer = ImageRenderer(
            content: popover.frame(width: LayoutMetrics.popoverWidth)
        )
        renderer.scale = 1
        return try #require(renderer.cgImage, "The popover produced no image")
    }

    /// A popover's picture as raw bytes, so two pictures can be compared without
    /// an image library and without a compression step that could differ.
    private func pixels(level: MockUsageLevel) async throws -> Data {
        try await pixels(for: try render(level: level))
    }

    private func pixels(_ popover: MainPopover) throws -> Data {
        try pixels(for: try render(popover))
    }

    private func pixels(for image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        let bytes = try #require(rep.bitmapData, "The popover produced no pixels")
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// How much of a picture may differ between two renders of the same world.
    ///
    /// Measured, not guessed. Two renders of the same world are usually
    /// byte-identical, but the rasteriser occasionally moves a handful of edge
    /// pixels — around 0.0006 of the picture's bytes was seen doing so inside a
    /// single process. Asserting zero would therefore fail intermittently for a
    /// reason the app cannot fix, so the floor sits above the jitter.
    private static let noiseThreshold: Double = 0.0012

    /// How much must differ between two levels for them to count as different.
    ///
    /// Measured rather than guessed: of the three pairs, the closest — on-pace
    /// against over, which differ only in a digit and a colour — comes to about
    /// 0.0018 of the picture's bytes. The floor sits between that and the
    /// rasteriser's jitter above.
    ///
    /// The window between the two thresholds is narrow, and honestly so: most of
    /// this panel is static text, so two levels that differ only in a figure
    /// differ in a small part of the picture. The test therefore earns its keep
    /// by catching levels that collapsed into one another, not by detecting any
    /// change. The rendered PNGs left in `.build/snapshots` are what a person
    /// looks at to judge an appearance change.
    private static let distinctThreshold: Double = 0.0015

    private func png(for image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// The share of bytes that differ, as a fraction of the whole.
    ///
    /// Counted over bytes rather than pixels because a pixel whose one channel
    /// moved is still a difference worth seeing, and counting per pixel would
    /// need a stride this does not have to reason about.
    private static func differenceRatio(_ lhs: Data, _ rhs: Data) -> Double {
        let left = [UInt8](lhs)
        let right = [UInt8](rhs)
        guard left.count == right.count, !left.isEmpty else { return 1 }
        let differing = zip(left, right).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 0 : 1)
        }
        return Double(differing) / Double(left.count)
    }
}
