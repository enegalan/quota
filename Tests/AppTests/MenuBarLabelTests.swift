import Core
import Foundation
import Testing
@testable import App

/// The menu bar label's wording.
///
/// The label is the one line of Quota a user reads without asking for it, so
/// what it says is the claim worth testing: how much of today's plan has been
/// spent, out of that plan, and a dash where a figure is not a number rather
/// than a zero that would look like good news. The spacing between the two
/// figures is part of the wording — they are two claims, not one fraction.
@Suite("Menu bar label")
@MainActor
struct MenuBarLabelTests {
    /// Pinned, because an assertion about wording cannot be made against
    /// whatever locale the machine running it happens to use.
    private let formatter = PercentageFormatter(locale: Locale(identifier: "en_US"))

    @Test("The label shows what has been used out of today's planned allowance")
    func usedOverSuggested() {
        #expect(text(used: 2, suggested: 8) == "Quota · 2% / 8%")
        #expect(text(used: 0, suggested: 8) == "Quota · 0% / 8%")
    }

    @Test("A day with no plan shows nothing to be a share of")
    func noAllowance() {
        #expect(MenuBarLabel.text(for: nil, formatter: formatter) == "Quota · —")
    }

    @Test("Today's spending being unknown is a dash, not a whole allowance")
    func unknownUsed() {
        // The plan is still worth showing: it is known, and the dash says what
        // is missing.
        #expect(text(used: nil, suggested: 8) == "Quota · — / 8%")
    }

    @Test("A sub-one-percent spend is not rounded away to nothing")
    func subOnePercentSpend() {
        #expect(text(used: 0.4, suggested: 3) == "Quota · 0.4% / 3%")
    }

    @Test("A spend that would round into the plan keeps a decimal instead")
    func usedStaysDistinctFromPlan() {
        // 2.5% used of a 3% plan rounds to "3%" on its own; shown beside the
        // plan that must stay "3%", so the label would claim the whole day was
        // spent. A decimal on the used figure is what keeps the difference.
        #expect(text(used: 2.5, suggested: 3) == "Quota · 2.5% / 3%")
    }

    private func text(used: Double?, suggested: Double) -> String {
        MenuBarLabel.text(
            for: TodayAllowance(
                date: LocalDate(date: Date(timeIntervalSince1970: 0), calendar: .current),
                suggested: suggested,
                usedToday: used
            ),
            formatter: formatter
        )
    }
}
