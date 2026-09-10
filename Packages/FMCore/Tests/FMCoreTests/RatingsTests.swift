import Testing

@testable import FMCore

@Suite("Rating keys")
struct RatingKeyTests {

    /// The bug this guards against: raw values are gapped and run past 64, so a
    /// storage array or presence bitmap sized to the *number* of keys rather
    /// than the *largest* key aliases one rating onto another. Kicking ratings
    /// sit at 70+ and are where it would first bite.
    @Test("Every key fits inside the storage bound", .tags(.unit))
    func keysFitStorage() {
        for key in RatingKey.allCases {
            #expect(
                Int(key.rawValue) < Ratings.maximumKeyCount,
                "\(key) raw value \(key.rawValue) exceeds storage"
            )
        }
    }

    @Test("Raw values are unique", .tags(.unit))
    func rawValuesUnique() {
        let raw = RatingKey.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
    }

    @Test("Every position trains the general attributes", .tags(.unit))
    func generalApplyEverywhere() {
        for position in Position.allCases {
            let keys = Set(RatingKey.keys(for: position))
            for general in RatingKey.general {
                #expect(keys.contains(general), "\(position) missing \(general)")
            }
        }
    }

    @Test("No position declares a positional key twice, or repeats a general one", .tags(.unit))
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

    @Test("Positions train the attributes their job actually needs", .tags(.unit))
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

    /// Raw values are gapped by tens so related keys sit together, and the family a key
    /// reports has to agree with the ten it sits in, or the untrained table draws a
    /// kicking rating from the coverage row.
    @Test(
        "Every key is in exactly one family, and the family is the ten it sits in",
        .tags(.unit))
    func familiesPartitionTheKeys() {
        var counted = 0
        for family in RatingKey.Family.allCases {
            let keys = family.keys
            counted += keys.count
            for key in keys {
                #expect(key.family == family)
                #expect(
                    Int(key.rawValue) / 10 == Int(family.rawValue),
                    "\(key) sits outside \(family)'s ten")
            }
        }
        #expect(counted == RatingKey.allCases.count)
        #expect(RatingKey.Family.general.keys == RatingKey.general)
    }
}

@Suite("Ratings storage")
struct RatingsTests {

    @Test("Values round-trip", .tags(.unit))
    func roundTrip() {
        var ratings = Ratings()
        ratings[.speed] = 88
        ratings[.awareness] = 71
        #expect(ratings[.speed] == 88)
        #expect(ratings[.awareness] == 71)
    }

    @Test("Absent is distinct from zero", .tags(.unit))
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
    @Test("High-numbered keys do not alias low-numbered ones", .tags(.unit))
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

    @Test("Every key can be stored and read back independently", .tags(.unit))
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

    @Test("Values clamp into 0...99 rather than trapping", .tags(.unit))
    func clamping() {
        var ratings = Ratings()
        ratings[.speed] = 200
        #expect(ratings[.speed] == 99)
        ratings[.strength] = 99
        #expect(ratings[.strength] == 99)
    }

    @Test("Assigning nil removes a rating", .tags(.unit))
    func removal() {
        var ratings = Ratings()
        ratings[.speed] = 80
        ratings[.speed] = nil
        #expect(ratings[.speed] == nil)
        #expect(!ratings.has(.speed))
        #expect(ratings.count == 0)
    }

    @Test("The fallback accessor avoids force-unwrapping an absent rating", .tags(.unit))
    func fallback() {
        var ratings = Ratings()
        ratings[.speed] = 80
        #expect(ratings.value(.speed) == 80)
        #expect(ratings.value(.manCoverage) == 0)
        #expect(ratings.value(.manCoverage, or: 50) == 50)
    }

    @Test("Keys are reported in stable order", .tags(.contract))
    func keyOrder() {
        var ratings = Ratings()
        ratings[.kickPower] = 80
        ratings[.awareness] = 70
        ratings[.speed] = 60
        #expect(ratings.keys == [.awareness, .speed, .kickPower])
    }

    @Test("Dictionary and literal construction agree", .tags(.unit))
    func construction() {
        let fromDictionary = Ratings([.speed: 88, .strength: 70])
        let fromLiteral: Ratings = [.speed: 88, .strength: 70]
        #expect(fromDictionary == fromLiteral)
        #expect(fromLiteral[.speed] == 88)
    }

    @Test("Completeness is every key present, and one missing is enough to lose it", .tags(.unit))
    func completeness() {
        #expect(!Ratings().isComplete)

        var complete = Ratings()
        for key in RatingKey.allCases {
            complete[key] = 70
        }
        #expect(complete.isComplete)

        var missing = complete
        missing[.manCoverage] = nil
        #expect(!missing.isComplete)

        var trainedOnly = Ratings()
        for key in RatingKey.keys(for: .cornerback) {
            trainedOnly[key] = 70
        }
        #expect(!trainedOnly.isComplete, "a corner's trained keys are not every key")
    }

    @Test("A uniform set carries every key at that value", .tags(.unit))
    func uniform() {
        let flat = Ratings.uniform(63)
        #expect(flat.isComplete)
        #expect(flat.count == RatingKey.allCases.count)
        for key in RatingKey.allCases {
            #expect(flat[key] == 63, "\(key) is \(String(describing: flat[key]))")
        }
    }

    @Test("Ratings are value types", .tags(.unit))
    func valueSemantics() {
        var original = Ratings()
        original[.speed] = 80
        var copy = original
        copy[.speed] = 90
        #expect(original[.speed] == 80)
        #expect(copy[.speed] == 90)
    }

    @Test("Equal ratings hash together regardless of insertion order", .tags(.unit))
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

/// A weight on a rating the position does not train would score every player at
/// that position on a number generation draws low, dragging the whole position off
/// target. Weights that do not sum to one do the same thing less obviously.
@Suite("Position weights")
struct PositionWeightsTests {

    @Test("Every weight set sums to one", .tags(.unit))
    func weightsSumToOne() {
        for position in Position.allCases {
            let total = PositionWeights.weights(for: position).reduce(0.0) { $0 + $1.1 }
            #expect(abs(total - 1.0) < 0.0001, "\(position) weights sum to \(total)")
        }
    }

    @Test("Weights only reference ratings the position trains", .tags(.unit))
    func weightsReferenceTrainedRatings() {
        for position in Position.allCases {
            let trained = Set(RatingKey.keys(for: position))
            for (key, _) in PositionWeights.weights(for: position) {
                #expect(
                    trained.contains(key), "\(position) weights \(key), which it does not train")
            }
        }
    }

    @Test("No weight is duplicated or non-positive", .tags(.unit))
    func weightsAreWellFormed() {
        for position in Position.allCases {
            let weights = PositionWeights.weights(for: position)
            #expect(Set(weights.map(\.0)).count == weights.count, "\(position) duplicates a key")
            #expect(weights.allSatisfy { $0.1 > 0 }, "\(position) has a non-positive weight")
        }
    }

    @Test("A uniform rating produces that overall at every position", .tags(.unit))
    func uniformRatingsRoundTrip() {
        let ratings = Ratings.uniform(74)
        for position in Position.allCases {
            #expect(
                PositionWeights.overall(ratings, at: position) == 74,
                "\(position) scored \(PositionWeights.overall(ratings, at: position)) for a flat 74"
            )
        }
    }

    @Test("Overall is driven by the ratings the position values", .tags(.unit))
    func overallFollowsWeights() {
        var passer = Ratings.uniform(60)
        passer[.throwAccuracyShort] = 95
        passer[.throwAccuracyMedium] = 95
        passer[.awareness] = 95

        var athlete = Ratings.uniform(60)
        athlete[.speed] = 95
        athlete[.stamina] = 95
        athlete[.toughness] = 95

        #expect(
            PositionWeights.overall(passer, at: .quarterback)
                > PositionWeights.overall(athlete, at: .quarterback))
    }

    /// The arithmetic the mover tests in generation rest on: a key he carries low counts
    /// at its weight, so a quarterback with every coverage rating at 20 is scored at
    /// cornerback on those 20s, whatever his awareness.
    @Test("A rating carried low counts at its weight away from home", .tags(.unit))
    func lowKeysCountAwayFromHome() {
        var passer = Ratings.uniform(75)
        for key in RatingKey.Family.coverage.keys { passer[key] = 20 }
        let atCorner = PositionWeights.overall(passer, at: .cornerback)
        // Coverage is 0.54 of a corner: 0.54 × 20 + 0.46 × 75 = 45.3.
        #expect(atCorner == 45, "a passer covering at 20 rated \(atCorner) at corner")
        #expect(PositionWeights.overall(passer, at: .quarterback) == 75)
    }

    #if DEBUG
    /// A weight on a rating the player lacks used to be dropped and the rest
    /// renormalised over what he had, which scored a receiver at quarterback on his
    /// awareness and speed alone and made him a better quarterback than a receiver.
    /// Generation fills every key, so an incomplete set is a hand-built one, and an
    /// overall read from it is a mistake to catch rather than a number to return.
    ///
    /// Debug only: the catch is an assertion, and a release build reads the floor
    /// instead of trapping.
    @Test(
        "contract: an incomplete rating set is a caught mistake, not a renormalised overall",
        .tags(.contract))
    func incompleteSetIsCaught() async {
        await #expect(processExitsWith: .failure) {
            var passer = Ratings()
            for key in RatingKey.general { passer[key] = 70 }
            _ = PositionWeights.overall(passer, at: .quarterback)
        }
        await #expect(processExitsWith: .failure) {
            var passer = Ratings()
            for key in RatingKey.general { passer[key] = 70 }
            _ = SchemeFit.effectiveOverall(
                passer, at: .quarterback,
                in: TeamScheme(offense: .westCoast, defense: .nickelMatch))
        }
    }
    #endif
}
