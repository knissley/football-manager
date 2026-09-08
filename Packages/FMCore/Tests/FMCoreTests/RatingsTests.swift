import Testing

@testable import FMCore

@Suite("Rating keys")
struct RatingKeyTests {

    /// The bug this guards against: raw values are gapped and run past 64, so a
    /// storage array or presence bitmap sized to the *number* of keys rather
    /// than the *largest* key aliases one rating onto another. Kicking ratings
    /// sit at 70+ and are where it would first bite.
    @Test("Every key fits inside the storage bound")
    func keysFitStorage() {
        for key in RatingKey.allCases {
            #expect(
                Int(key.rawValue) < Ratings.maximumKeyCount,
                "\(key) raw value \(key.rawValue) exceeds storage"
            )
        }
    }

    @Test("Raw values are unique")
    func rawValuesUnique() {
        let raw = RatingKey.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
    }

    @Test("Every position carries the general attributes")
    func generalApplyEverywhere() {
        for position in Position.allCases {
            let keys = Set(RatingKey.keys(for: position))
            for general in RatingKey.general {
                #expect(keys.contains(general), "\(position) missing \(general)")
            }
        }
    }

    @Test("No position declares a positional key twice, or repeats a general one")
    func noDuplicateKeys() {
        for position in Position.allCases {
            let positional = RatingKey.positional(for: position)
            #expect(Set(positional).count == positional.count, "\(position) duplicates a key")
            #expect(
                Set(positional).isDisjoint(with: Set(RatingKey.general)),
                "\(position) repeats a general attribute"
            )
        }
    }

    @Test("Positions carry the attributes their job actually needs")
    func plausibleAssignments() {
        #expect(RatingKey.keys(for: .quarterback).contains(.throwPower))
        #expect(!RatingKey.keys(for: .quarterback).contains(.manCoverage))

        #expect(RatingKey.keys(for: .cornerback).contains(.manCoverage))
        #expect(!RatingKey.keys(for: .cornerback).contains(.throwPower))

        #expect(RatingKey.keys(for: .leftTackle).contains(.passBlock))
        #expect(!RatingKey.keys(for: .leftTackle).contains(.catching))

        #expect(RatingKey.keys(for: .kicker).contains(.kickPower))
        #expect(!RatingKey.keys(for: .punter).contains(.kickPower))
    }
}

@Suite("Ratings storage")
struct RatingsTests {

    @Test("Values round-trip")
    func roundTrip() {
        var ratings = Ratings()
        ratings[.speed] = 88
        ratings[.awareness] = 71
        #expect(ratings[.speed] == 88)
        #expect(ratings[.awareness] == 71)
    }

    @Test("Absent is distinct from zero")
    func absenceIsNotZero() {
        var ratings = Ratings()
        ratings[.speed] = 0
        #expect(ratings[.speed] == 0)
        #expect(ratings.has(.speed))
        #expect(ratings[.manCoverage] == nil)
        #expect(!ratings.has(.manCoverage))
    }

    /// High raw values are the aliasing case. Setting a kicking rating must not
    /// disturb a general one that would collide under a 64-wide bitmap.
    @Test("High-numbered keys do not alias low-numbered ones")
    func noAliasing() {
        var ratings = Ratings()
        ratings[.kickPower] = 91  // raw 70
        #expect(ratings[.kickPower] == 91)
        #expect(ratings[.toughness] == nil)  // raw 6 — would alias under % 64
        #expect(!ratings.has(.toughness))

        ratings[.toughness] = 55
        #expect(ratings[.kickPower] == 91)
        #expect(ratings[.toughness] == 55)
        #expect(ratings.count == 2)
    }

    @Test("Every key can be stored and read back independently")
    func allKeysIndependent() {
        var ratings = Ratings()
        for (offset, key) in RatingKey.allCases.enumerated() {
            ratings[key] = UInt8(offset % 100)
        }
        for (offset, key) in RatingKey.allCases.enumerated() {
            #expect(ratings[key] == UInt8(offset % 100), "\(key) read back wrong")
        }
        #expect(ratings.count == RatingKey.allCases.count)
    }

    @Test("Values clamp into 0...99 rather than trapping")
    func clamping() {
        var ratings = Ratings()
        ratings[.speed] = 200
        #expect(ratings[.speed] == 99)
        ratings[.strength] = 99
        #expect(ratings[.strength] == 99)
    }

    @Test("Assigning nil removes a rating")
    func removal() {
        var ratings = Ratings()
        ratings[.speed] = 80
        ratings[.speed] = nil
        #expect(ratings[.speed] == nil)
        #expect(!ratings.has(.speed))
        #expect(ratings.count == 0)
    }

    @Test("The fallback accessor avoids force-unwrapping an absent rating")
    func fallback() {
        var ratings = Ratings()
        ratings[.speed] = 80
        #expect(ratings.value(.speed) == 80)
        #expect(ratings.value(.manCoverage) == 0)
        #expect(ratings.value(.manCoverage, or: 50) == 50)
    }

    @Test("Keys are reported in stable order")
    func keyOrder() {
        var ratings = Ratings()
        ratings[.kickPower] = 80
        ratings[.awareness] = 70
        ratings[.speed] = 60
        #expect(ratings.keys == [.awareness, .speed, .kickPower])
    }

    @Test("Dictionary and literal construction agree")
    func construction() {
        let fromDictionary = Ratings([.speed: 88, .strength: 70])
        let fromLiteral: Ratings = [.speed: 88, .strength: 70]
        #expect(fromDictionary == fromLiteral)
        #expect(fromLiteral[.speed] == 88)
    }

    @Test("Key-set validation catches missing and surplus ratings")
    func keySetValidation() {
        var complete = Ratings()
        for key in RatingKey.keys(for: .cornerback) {
            complete[key] = 70
        }
        #expect(complete.matchesKeys(for: .cornerback))
        #expect(!complete.matchesKeys(for: .quarterback))

        var surplus = complete
        surplus[.throwPower] = 70
        #expect(!surplus.matchesKeys(for: .cornerback))

        var missing = complete
        missing[.manCoverage] = nil
        #expect(!missing.matchesKeys(for: .cornerback))
    }

    @Test("Ratings are value types")
    func valueSemantics() {
        var original = Ratings()
        original[.speed] = 80
        var copy = original
        copy[.speed] = 90
        #expect(original[.speed] == 80)
        #expect(copy[.speed] == 90)
    }

    @Test("Equal ratings hash together regardless of insertion order")
    func equality() {
        var a = Ratings()
        a[.speed] = 80
        a[.strength] = 70
        var b = Ratings()
        b[.strength] = 70
        b[.speed] = 80
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }
}

/// A weight on a rating the position does not carry would be dropped by
/// `overall`, quietly renormalising and dragging every player at that position
/// off target. Weights that do not sum to one do the same thing less obviously.
@Suite("Position weights")
struct PositionWeightsTests {

    @Test("Every weight set sums to one")
    func weightsSumToOne() {
        for position in Position.allCases {
            let total = PositionWeights.weights(for: position).reduce(0.0) { $0 + $1.1 }
            #expect(abs(total - 1.0) < 0.0001, "\(position) weights sum to \(total)")
        }
    }

    @Test("Weights only reference ratings the position carries")
    func weightsReferenceCarriedRatings() {
        for position in Position.allCases {
            let carried = Set(RatingKey.keys(for: position))
            for (key, _) in PositionWeights.weights(for: position) {
                #expect(
                    carried.contains(key), "\(position) weights \(key), which it does not carry")
            }
        }
    }

    @Test("No weight is duplicated or non-positive")
    func weightsAreWellFormed() {
        for position in Position.allCases {
            let weights = PositionWeights.weights(for: position)
            #expect(Set(weights.map(\.0)).count == weights.count, "\(position) duplicates a key")
            #expect(weights.allSatisfy { $0.1 > 0 }, "\(position) has a non-positive weight")
        }
    }

    @Test("A uniform rating produces that overall at every position")
    func uniformRatingsRoundTrip() {
        for position in Position.allCases {
            var ratings = Ratings()
            for key in RatingKey.keys(for: position) {
                ratings[key] = 74
            }
            #expect(
                PositionWeights.overall(ratings, at: position) == 74,
                "\(position) scored \(PositionWeights.overall(ratings, at: position)) for a flat 74"
            )
        }
    }

    @Test("Overall is driven by the ratings the position values")
    func overallFollowsWeights() {
        var passer = Ratings()
        for key in RatingKey.keys(for: .quarterback) { passer[key] = 60 }
        passer[.throwAccuracyShort] = 95
        passer[.throwAccuracyMedium] = 95
        passer[.awareness] = 95

        var athlete = Ratings()
        for key in RatingKey.keys(for: .quarterback) { athlete[key] = 60 }
        athlete[.speed] = 95
        athlete[.stamina] = 95
        athlete[.toughness] = 95

        #expect(
            PositionWeights.overall(passer, at: .quarterback)
                > PositionWeights.overall(athlete, at: .quarterback))
    }
}
