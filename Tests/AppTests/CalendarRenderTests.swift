import AppKit
import Core
import Foundation
import SwiftUI
import Testing
@testable import App

/// The two calendars in the window, rendered rather than asserted on the values
/// underneath.
///
/// The claims here are the ones a layout gets wrong without saying so: a month
/// whose days are drawn in the wrong columns, a grid that grows past the width it
/// was given and quietly loses its last column, an editor that draws at all for a
/// policy the engine would refuse. All of them render successfully while being
/// wrong, and only the picture shows it.
///
/// As in the popover snapshots, without a golden-image library the honest claims
/// are reproducibility and difference: the same world twice, the same month under
/// two first weekdays, a policy within the allowance and one beyond it. The PNGs
/// left in `.build/snapshots` are what a person looks at to judge an appearance
/// change.
@Suite("Calendar renders")
@MainActor
struct CalendarRenderTests {
    static var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/snapshots", directoryHint: .isDirectory)
    }

    // MARK: The plan's calendar

    @Test("The plan's calendar renders a month of days with figures in them")
    func planCalendarRenders() throws {
        let image = try renderPlan()
        #expect(image.width > 0, "The calendar rendered no width")
        #expect(image.height > 0, "The calendar rendered no height")
        // A picture of nothing at all still has a width, so the check that means
        // something is whether any of it is ink.
        #expect(try ink(image) > 0.01, "The calendar rendered an empty picture")
    }

    @Test("The first weekday changes where the month's days are drawn")
    func firstWeekdayMovesTheDays() throws {
        // The strongest available statement about leading blanks: the same month,
        // the same days, the same figures — and a different picture, because every
        // day has moved a column. Two calendars that ignored the setting would
        // render identically, and the first of the month would sit under the
        // wrong heading in one of them.
        let monday = try renderPlan(firstWeekday: 2)
        let sunday = try renderPlan(firstWeekday: 1)
        #expect(
            try difference(monday, sunday) >= Self.distinctThreshold,
            "A Monday-first and a Sunday-first March rendered the same picture"
        )
    }

    @Test("The same month renders the same picture every time")
    func renderingIsStable() throws {
        let first = try renderPlan()
        let second = try renderPlan()
        #expect(
            try difference(first, second) <= Self.noiseThreshold,
            "The calendar differed from itself between renders"
        )
    }

    @Test("The grid fills the width it is given")
    func gridFillsGivenWidth() throws {
        // Flexible columns expand to the frame: a render narrower than the pane
        // would leave empty gutters the plan exists to remove. Allow a pixel of
        // rounding from the rasteriser.
        let width = LayoutMetrics.calendarPreferredWidth
        let image = try renderPlan(width: width)
        #expect(
            CGFloat(image.width) >= width - LayoutMetrics.snapshotWidthTolerance,
            "The calendar rendered \(image.width) wide, short of the \(width) it was given"
        )
        #expect(
            CGFloat(image.width) <= width + LayoutMetrics.snapshotWidthTolerance,
            "The calendar rendered \(image.width) wide, past the \(width) it was given"
        )
    }

    // MARK: The custom policy editor

    @Test("The custom editor renders a policy that fits inside 100%")
    func customEditorRendersACompletePolicy() throws {
        let image = try renderCustom(overTotal: false)
        #expect(image.width > 0, "The editor rendered no width")
        #expect(try ink(image) > 0.01, "The editor rendered an empty picture")
    }

    @Test("A stored policy above 100% still renders, and renders differently")
    func customEditorRendersAnOverfilledPolicy() throws {
        // Policies written before the editor had a ceiling are on disk, and the
        // window has to open on one. The claim is not that it looks right — it is
        // that a policy the user must bring back down is legible while they do
        // it, and visibly not the same as a finished one.
        let complete = try renderCustom(overTotal: false)
        let overfilled = try renderCustom(overTotal: true)
        #expect(overfilled.width > 0, "An overfilled policy rendered no width")
        #expect(
            try difference(complete, overfilled) >= Self.distinctThreshold,
            "An overfilled policy rendered the same picture as a complete one"
        )
    }

    @Test("The rendered calendars are written where they can be looked at")
    func writesPngs() throws {
        let pictures = [
            "plan-monday-first": try renderPlan(),
            "plan-sunday-first": try renderPlan(firstWeekday: 1),
            "custom-complete": try renderCustom(overTotal: false),
            "custom-overfilled": try renderCustom(overTotal: true),
        ]
        try FileManager.default.createDirectory(
            at: Self.snapshotDirectory,
            withIntermediateDirectories: true
        )
        for (name, image) in pictures {
            let url = Self.snapshotDirectory.appending(path: "\(name).png")
            let rep = NSBitmapImageRep(cgImage: image)
            let data = try #require(rep.representation(using: .png, properties: [:]), "\(name) wrote no PNG")
            try data.write(to: url)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(name) wrote nothing to \(url.path)")
        }
    }

    // MARK: Thresholds

    /// How much of a picture may differ between two renders of the same world.
    ///
    /// The same floor the popover snapshots use, for the same reason: the
    /// rasteriser moves a few antialiased edge pixels between processes, and
    /// asserting zero would fail intermittently for a reason the app cannot fix.
    private static let noiseThreshold: Double = 0.0012

    /// How much must differ for two pictures to count as different.
    ///
    /// Every pair compared here differs by a whole column or a whole row of
    /// figures, so this is far below the real difference and only guards against
    /// a render that ignores the thing being varied.
    private static let distinctThreshold: Double = 0.01

    // MARK: Arranging

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// March 2026 with an even plan over it, as the plan's calendar would show it.
    private func renderPlan(firstWeekday: Int = 2, width: CGFloat? = nil) throws -> CGImage {
        let calendar = calendar(firstWeekday: firstWeekday)
        let plan = try Self.marchPlan(calendar: calendar)
        let reference = try #require(LocalDate(year: 2026, month: 3, day: 15).date(calendar: calendar))
        let presenter = CalendarPresenter(
            plan: plan,
            timeline: nil,
            allowance: nil,
            bucketID: "primary",
            calendar: calendar,
            reference: reference
        )
        return try render(
            MonthCalendarView(
                presenter: presenter,
                calendar: calendar,
                selected: LocalDate(year: 2026, month: 3, day: 15),
                onSelect: { _ in }
            )
            .frame(width: width ?? LayoutMetrics.calendarPreferredWidth)
        )
    }

    /// The custom editor over March 2026, either even-filled or overfilled.
    private func renderCustom(overTotal: Bool) throws -> CGImage {
        let calendar = calendar(firstWeekday: 2)
        let period = try Self.marchPeriod(calendar: calendar)
        let days = period.localDates(in: calendar)
        // An even fill is what the editor's own button produces; the overfilled
        // policy is what a stored file from before the ceiling could hold.
        let assignments = overTotal
            ? Dictionary(uniqueKeysWithValues: days.map { ($0, 60) })
            : Share.even(across: days)
        let reference = try #require(LocalDate(year: 2026, month: 3, day: 15).date(calendar: calendar))
        return try render(
            CustomAssignmentsEditor(
                assignments: .constant(assignments),
                period: period,
                calendar: calendar,
                reference: reference
            )
            .frame(width: LayoutMetrics.calendarPreferredWidth)
        )
    }

    private func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage, "The view produced no image")
    }

    private static func marchPeriod(calendar: Calendar) throws -> QuotaPeriod {
        let start = try #require(LocalDate(year: 2026, month: 3, day: 1).date(calendar: calendar))
        let end = try #require(LocalDate(year: 2026, month: 3, day: 31).date(calendar: calendar))
        return try QuotaPeriod(start: start, end: end)
    }

    private static func marchPlan(calendar: Calendar) throws -> AllocationPlan {
        try AllocationEngine(calendar: calendar).plan(
            quotaID: UUID(uuidString: "00000000-0000-0000-0000-0000-0000000000C2") ?? UUID(),
            policy: .even,
            period: try marchPeriod(calendar: calendar),
            totalRemaining: 100,
            asOf: try #require(LocalDate(year: 2026, month: 3, day: 1).date(calendar: calendar))
        )
    }

    // MARK: Reading pictures

    private func bytes(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return Data(bytes: try #require(rep.bitmapData), count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// The share of bytes that differ between two pictures, as a fraction of the
    /// whole.
    private func difference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
        let left = [UInt8](try bytes(lhs))
        let right = [UInt8](try bytes(rhs))
        guard left.count == right.count, !left.isEmpty else { return 1 }
        let differing = zip(left, right).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 0 : 1)
        }
        return Double(differing) / Double(left.count)
    }

    /// The share of a picture that is not its background.
    ///
    /// A picture of an empty view is a picture of one flat colour, and it has a
    /// width and a height like any other. What tells it apart from a rendered
    /// calendar is that it is uniformly that colour.
    private func ink(_ image: CGImage) throws -> Double {
        let rep = NSBitmapImageRep(cgImage: image)
        let data = try #require(rep.bitmapData)
        let stride = rep.bytesPerRow
        let pixelCount = rep.pixelsWide * rep.pixelsHigh
        guard pixelCount > 0 else { return 0 }
        var differing = 0
        for row in 0 ..< rep.pixelsHigh {
            let start = row * stride
            let background = (0 ..< 4).map { data[start + $0] }
            var column = 0
            while column < rep.pixelsWide {
                let offset = start + column * 4
                let pixel = (0 ..< 4).map { data[offset + $0] }
                if pixel != background {
                    differing += 1
                }
                column += 1
            }
        }
        return Double(differing) / Double(pixelCount)
    }
}
