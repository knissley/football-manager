import FMCore
import FMRandom
import Testing

@testable import FMGeneration

/// A world generated from a seed must be the same world tomorrow.
///
/// The companion to `FMSimulation`'s golden seed test, and here for the same reason: the
/// bug that motivated both was a floating-point sum taken while iterating a dictionary,
/// and Swift randomises its hash seed per process — so every test that compares two runs
/// *inside one process* agrees with itself and disagrees with yesterday. Only a
/// checked-in constant can fail that way.
@Suite("Golden world")
struct GoldenWorldTests {

    /// FNV-1a rather than `Hasher`, whose seed is randomised per process — using it here
    /// would make this test unable to detect the thing it exists to detect.
    private struct Checksum {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(_ number: some BinaryInteger) {
            let bits = UInt64(bitPattern: Int64(number))
            for shift in stride(from: 0, through: 56, by: 8) {
                value ^= UInt64((bits >> UInt64(shift)) & 0xff)
                value = value &* 0x100_0000_01b3
            }
        }

        mutating func mix(_ text: String) {
            for byte in text.utf8 {
                value ^= UInt64(byte)
                value = value &* 0x100_0000_01b3
            }
        }
    }

    private func rosterChecksum(seed: UInt64) -> UInt64 {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let roster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)

        var sum = Checksum()
        sum.mix(roster.count)
        for player in roster {
            sum.mix(player.id.rawValue)
            sum.mix(player.position.rawValue)
            sum.mix(player.overall)
            sum.mix(player.birthSeason)
            sum.mix(player.name.family)
            sum.mix(player.college.name)
            sum.mix(player.physical.weightPounds)
            for key in RatingKey.allCases {
                sum.mix(player.ratings[key] ?? 255)
            }
            // Scheme fit is the value that was actually wrong: it is a rounded weighted
            // average, and the weighting used to be summed in hash order.
            sum.mix(player.schemeFit(TeamScheme(offense: .westCoast, defense: .fourThreeUnder)))
            sum.mix(player.schemeFit(TeamScheme(offense: .airRaid, defense: .nickelMatch)))
        }
        return sum.value
    }

    /// Regenerating these to make a red test pass is forbidden. If generation changed on
    /// purpose they are regenerated in the same commit with the change described; if it
    /// did not, generation is non-deterministic and that is the bug.
    @Test(
        "A seed produces the same roster in every process",
        arguments: [
            (UInt64(1), UInt64(16_042_663_817_893_197_423)),
            (UInt64(5), UInt64(9_917_351_961_824_915_079)),
        ])
    func goldenRosters(seed: UInt64, expected: UInt64) {
        #expect(rosterChecksum(seed: seed) == expected)
    }
}
