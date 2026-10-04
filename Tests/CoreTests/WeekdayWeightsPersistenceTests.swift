import Foundation
import Testing
@testable import Core

/// Weights are stored, and a stored policy has to come back.
///
/// The reason this file exists: a `[Int: Int]` encodes to a JSON object whose
/// keys are strings, and the synthesised decoding of `[Int: Int]` demands
/// integers. So every weekly policy could be written and none could be read
/// back — and because a store that cannot decode sets the file aside rather than
/// crashing, that failure looked like nothing at all until a user reopened the
/// app and found their quota gone.
@Suite("WeekdayWeights · persistence")
struct WeekdayWeightsPersistenceTests {
    @Test("Every policy kind survives a round trip")
    func roundTripsEveryKind() throws {
        let policies: [AllocationPolicy] = [
            .even,
            .weekly(weekdayWeights: .uniform),
            .weekly(weekdayWeights: .weekdaysOnly),
            .custom(assignments: [try LocalDate(year: 2026, month: 3, day: 20): 40]),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for policy in policies {
            let data = try encoder.encode(policy)
            #expect(try decoder.decode(AllocationPolicy.self, from: data) == policy)
        }
    }

    @Test("A weekly policy decodes from the bytes it wrote")
    func weeklyDecodesFromItsOwnBytes() throws {
        // Written out longhand, because the failure was only visible in the
        // stored form: a weekly policy written as
        // `{"kind":"weekly","weekdayWeights":{"1":1,...}}` and read back.
        let json = #"{"kind":"weekly","weekdayWeights":{"1":1,"2":1,"3":1,"4":1,"5":1,"6":1,"7":1}}"#

        let policy = try JSONDecoder().decode(AllocationPolicy.self, from: Data(json.utf8))

        #expect(policy == .weekly(weekdayWeights: .uniform))
    }

    @Test("A weekday a weight names is restored as that weekday")
    func restoresTheRightWeekdays() throws {
        // Asymmetric on purpose: a decoder that shifted the numbering by one
        // would still round-trip a uniform set, and would silently give Monday's
        // weight to Sunday.
        let weights = try WeekdayWeights(weights: [1: 3, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1])
        let data = try JSONEncoder().encode(weights)

        let restored = try JSONDecoder().decode(WeekdayWeights.self, from: data)

        #expect(restored.weights[1] == 3)
        #expect(restored.weights[7] == 1)
        #expect(restored == weights)
    }

    @Test("A weight of zero is kept, because a zeroed day is a decision")
    func keepsZeroWeights() throws {
        let weights = try WeekdayWeights(weights: [1: 0, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 0])
        let data = try JSONEncoder().encode(weights)

        let restored = try JSONDecoder().decode(WeekdayWeights.self, from: data)

        #expect(restored == weights)
        #expect(restored.weights[1] == 0)
    }

    @Test("The stored form is an object a person could read")
    func storedFormIsReadable() throws {
        // The reason for an object rather than an array of pairs: someone
        // debugging a policy in the file should not have to count array
        // positions to find out which day a weight belongs to.
        let data = try JSONEncoder().encode(try WeekdayWeights(weights: [1: 2, 2: 1]))
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(json.contains(#""1":2"#))
        #expect(json.contains(#""2":1"#))
    }

    @Test("A stored weight the domain would reject is refused on the way back in")
    func decodingValidates() throws {
        // Every weight zero: a file that said so would plan nothing, and reading
        // it must fail rather than hand the engine a policy with no ratio.
        let json = #"{"1":0,"2":0}"#

        #expect(throws: QuotaDomainError.self) {
            try JSONDecoder().decode(WeekdayWeights.self, from: Data(json.utf8))
        }
    }

    @Test("A weekday that is not a number is refused")
    func nonNumericWeekdayIsRefused() throws {
        let json = #"{"monday":1,"2":1}"#

        #expect(throws: QuotaDomainError.self) {
            try JSONDecoder().decode(WeekdayWeights.self, from: Data(json.utf8))
        }
    }
}
