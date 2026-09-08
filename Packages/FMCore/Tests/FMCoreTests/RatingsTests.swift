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
