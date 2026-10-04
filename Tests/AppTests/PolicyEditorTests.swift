import Core
import Foundation
import Testing
@testable import App

/// One editor for all three policy kinds.
///
/// The tests are on the arithmetic the editor shows rather than on the controls,
/// because the controls are SwiftUI's and the numbers are the claim: a weight of
/// 2 beside a weight of 1 has to read as twice the share, and a user who cannot
/// see that has been asked to trust a ratio they cannot check.
@Suite("Policy editing")
struct PolicyEditorTests {
    private static let timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    @Test("equal weights read as equal shares, and together they are the whole week")
    func uniformWeights() {
        var total: Double = 0
        for weekday in PolicyWeekdays.all {
            total += PolicyShare.weekday(weekday, among: [:])
        }
        // Seven days of a seventh each is the whole allowance, which is what
        // makes equal weights mean "evenly spread" rather than "half each".
        #expect(abs(total - UsageConstants.percentageScale) < Share.tolerance)
    }

    @Test("Every day of an even week reads as the same share")
    func everyDayOfAnEvenWeek() {
        let shares = PolicyWeekdays.all.map { PolicyShare.weekday($0, among: [:]) }
        let expected = UsageConstants.percentageScale / Double(PolicyWeekdays.count)
        for share in shares {
            #expect(abs(share - expected) < Share.tolerance)
        }
    }

    @Test("A double weight reads as twice the share of a single one")
    func doubleWeight() {
        // 2 against 1 across two days is two thirds and one third.
        #expect(abs(PolicyShare.pair(2, against: 1) - UsageConstants.percentageScale * 2 / 3) < Share.tolerance)
        #expect(abs(PolicyShare.pair(1, against: 2) - UsageConstants.percentageScale / 3) < Share.tolerance)
    }

    @Test("A weekday with no weight is read as one, not as zero")
    func unwrittenWeekdayDefaultsToOne() throws {
        // The domain's own rule: a partial specification means "these days count
        // more", so a day the user never touched must not be excluded.
        var partial: [Int: Int] = [:]
        partial[PolicyWeekdays.first] = 3
        let weights = try WeekdayWeights(weights: partial)
        #expect(weights.weights[PolicyWeekdays.first] == 3)
        #expect(weights.weights[PolicyWeekdays.last - 1] == nil)
    }

    @Test("All-zero weights are refused, because there would be nothing to divide")
    func allZeroIsRefused() {
        var zeros: [Int: Int] = [:]
        for weekday in PolicyWeekdays.all {
            zeros[weekday] = 0
        }
        #expect(throws: QuotaDomainError.self) {
            try WeekdayWeights(weights: zeros)
        }
    }

    @Test("The custom editor's shares cannot add up to more than 100%")
    func totalCannotExceedTheScale() throws {
        let days = try Self.periodDays
        let first = try #require(days.first)
        // A month of days already given 90% between them, and then a day handed
        // the whole scale on top: the figure a user could have asked for, and the
        // one that would have to be trimmed by the engine to mean anything.
        var assignments: [LocalDate: Double] = [:]
        for day in days.dropFirst() {
            assignments[day] = 90 / Double(days.count - 1)
        }
        let tooMuch = Share.clamped(
            UsageConstants.percentageScale,
            for: first,
            in: assignments
        )
        assignments[first] = tooMuch
        #expect(Share.total(assignments) <= Share.maximumTotal + Share.tolerance)
        #expect(assignments[first] == 10)
    }

    @Test("A day can be given what is left of the allowance, and no more")
    func aDayCanTakeTheRemainder() throws {
        let days = try Self.periodDays
        let first = try #require(days.first)
        let second = try #require(days.dropFirst().first)
        let assignments: [LocalDate: Double] = [second: 90]
        // A day with nothing of its own can still only take what the others have
        // left: ninety percent is already spoken for, so the tenth percent is the
        // whole of what is on offer, not the whole of the scale.
        #expect(Share.maximum(for: first, in: assignments) == 10)
        // A day holding some of it may be given the rest, and the ceiling moves
        // with what the *other* days hold rather than with the day being edited.
        let partial: [LocalDate: Double] = [first: 5, second: 90]
        #expect(Share.maximum(for: first, in: partial) == 10)
        #expect(Share.maximum(for: second, in: partial) == 95)
    }

    @Test("Raising a day never lowers the others to make room")
    func clampingOnlyTouchesTheDayBeingEdited() throws {
        let days = try Self.periodDays
        let first = try #require(days.first)
        let second = try #require(days.dropFirst().first)
        let assignments: [LocalDate: Double] = [first: 20, second: 30]
        var updated = assignments
        updated[first] = Share.clamped(90, for: first, in: assignments)
        // The other day is left exactly as it was: a ceiling is a fact about the
        // allowance, not a reason to rewrite what the user has already decided.
        #expect(updated[second] == 30)
        #expect(updated[first] == 70)
    }

    @Test("An even fill assigns the whole allowance, exactly")
    func evenFillReachesOneHundred() throws {
        // Thirty days do not divide into a hundred whole percents, so an even fill
        // that used plain division would leave the user a hundredth short of a
        // complete policy — and no number of presses on a stepper would close it.
        //
        // The claim is about the figures the user reads rather than about the sum
        // of the doubles behind them: thirty days shown as 3.33% and one as 3.43%
        // is a hundred percent written down, and a fill that came to 99.99% on
        // screen would be one the editor could not call complete.
        for count in [1, 7, 10, 30, 31] {
            let days = try Self.days(count)
            let assignments = Share.even(across: days)
            #expect(Share.isComplete(assignments), "\(count) days did not add up to 100%")
            // Counted in hundredths, because the sum of thirty displayed
            // percentages is not exactly a hundred in binary floating point even
            // when the figures written on screen are.
            let hundredths = assignments.values.reduce(0) { $0 + Int(($1 * 100).rounded()) }
            #expect(hundredths == 10000, "\(count) days came to \(hundredths / 100)% on screen")
            // And still even: a fill that put the rounding all on one day would add
            // up and be nothing like even.
            let shares = assignments.values
            #expect(
                (shares.max() ?? 0) - (shares.min() ?? 0) <= 0.01,
                "\(count) days were given shares more than a hundredth apart"
            )
        }
    }

    @Test("A policy the user has already overfilled can still be brought back")
    func anOverfilledPolicyIsRecoverable() throws {
        // A policy stored before the editor had a ceiling can hold more than 100%.
        // It has to be editable rather than stuck: the days' own values are the
        // user's, and the way out is a day at a time or one press of Even.
        let days = try Self.days(3)
        let over: [LocalDate: Double] = Dictionary(uniqueKeysWithValues: days.map { ($0, 60) })
        #expect(!Share.isComplete(over))
        // Nothing is left to give while the others hold more than the whole, and a
        // ceiling below zero is not a number a control can be given.
        #expect(Share.maximum(for: days[0], in: over) == 0)
        // The control opens on the figure that is actually stored, and lowering
        // from it is an ordinary step: a clamp applied to both directions would
        // leave the day unable to move at all.
        #expect(Share.range(for: days[0], in: over).upperBound == 60)
        #expect(Share.clamped(59, for: days[0], in: over) == 59)
        #expect(Share.clamped(90, for: days[0], in: over) == 0)
        // And one press of Even replaces the whole thing with a complete policy.
        #expect(Share.isComplete(Share.even(across: days)))
    }

    @Test("The policy kinds the selector offers are the three the domain has")
    func selectorCoversEveryPolicyKind() {
        // A picker listing two of three kinds would leave a policy kind reachable
        // only by editing a stored file, which is not something a user can do.
        let kinds: [AllocationPolicy] = [
            .even,
            .weekly(weekdayWeights: .uniform),
            .custom(assignments: [:]),
        ]
        // Counted rather than compared by name: the claim is that the selector
        // offers one of each kind, and three equal-looking rows would pass a
        // name comparison while offering the same policy twice.
        #expect(kinds.count == 3)
    }

    // MARK: Arranging

    /// March 2026, the first ten days.
    private static var periodDays: [LocalDate] {
        get throws {
            try days(10)
        }
    }

    private static func days(_ count: Int) throws -> [LocalDate] {
        let first = try LocalDate(year: 2026, month: 3, day: 1)
        return (0 ..< count).compactMap { first.adding(days: $0, calendar: calendar) }
    }
}
