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
///
/// Checksummed over the *whole* world rather than one roster: the league's structure, its
/// teams, every roster, the strength each team was drawn at, the draft pipeline and the
/// rivalries. A determinism bug in any stage of `WorldGenerator` fails here, and a change
/// in the *order* the stages draw in fails here too.
@Suite("Golden world")
struct GoldenWorldTests {

    /// FNV-1a rather than `Hasher`, whose seed is randomised per process — using it here
    /// would make this test unable to detect the thing it exists to detect.
    private struct Checksum {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(bits: UInt64) {
            for shift in stride(from: 0, through: 56, by: 8) {
                value ^= UInt64((bits >> UInt64(shift)) & 0xff)
                value = value &* 0x100_0000_01b3
            }
        }

        mutating func mix(_ number: some BinaryInteger) {
            mix(bits: UInt64(bitPattern: Int64(number)))
        }

        mutating func mix(_ text: String) {
            for byte in text.utf8 {
                value ^= UInt64(byte)
                value = value &* 0x100_0000_01b3
            }
        }

        /// Strength is a `Double`, and the value that matters is the one the roster
        /// generator saw — so it is mixed by its exact bit pattern, not by a rounding of
        /// it. A world drawn a thousandth of a point differently is a different world.
        /// Via `mix(bits:)` rather than the integer overload, which would trap on a bit
        /// pattern with the sign bit set.
        mutating func mix(_ value: Double) {
            mix(bits: value.bitPattern)
        }
    }

    private func worldChecksum(seed: UInt64) -> UInt64 {
        guard
            let world = try? WorldGenerator.generate(
                seed: seed, shape: .standard, season: 2030
            ).get()
        else {
            Issue.record("seed \(seed) did not produce a world")
            return 0
        }

        var sum = Checksum()
        sum.mix(world.league.id.rawValue)
        sum.mix(world.league.name)
        sum.mix(world.teams.count)
        sum.mix(world.colleges.count)

        for conference in world.league.conferences {
            sum.mix(conference.id.rawValue)
            sum.mix(conference.name)
            for division in conference.divisions {
                sum.mix(division.id.rawValue)
                sum.mix(division.name)
                for team in division.teams { sum.mix(team.rawValue) }
            }
        }

        // `world.teams` is ordered by identifier, so this walk is stable.
        for team in world.teams {
            sum.mix(team.id.rawValue)
            sum.mix(team.identity.fullName)
            sum.mix(team.identity.abbreviation)
            sum.mix(team.stadium.name)
            sum.mix(team.stadium.noise)
            sum.mix(team.region.rawValue)
            sum.mix(world.strength(of: team.id).offset)

            let identity = world.identity(of: team.id)
            sum.mix(identity?.played.offense.passLean ?? -1)
            sum.mix(identity?.builtFor.offense.passLean ?? -1)

            for player in world.roster(of: team.id) {
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
                sum.mix(player.schemeFit(team.scheme))
            }

            // The depth chart is a projection over the roster, so it is checksummed
            // separately: a chart that stopped agreeing with the overalls would not move
            // any of the numbers above.
            let chart = world.depthChart(of: team.id)
            for position in Position.allCases {
                for id in chart[position] { sum.mix(id.rawValue) }
            }
        }

        for generated in world.draftPipeline {
            sum.mix(generated.draftClass.season)
            sum.mix(generated.draftClass.prospects.count)
            for player in generated.players {
                sum.mix(player.id.rawValue)
                sum.mix(player.overall)
                sum.mix(player.hidden.ceiling)
            }
        }

        for rivalry in world.rivalries {
            sum.mix(rivalry.pair.lower.rawValue)
            sum.mix(rivalry.pair.higher.rawValue)
            sum.mix(rivalry.origin.rawValue)
            for event in rivalry.history {
                sum.mix(event.season)
                sum.mix(event.kind.rawValue)
            }
        }

        return sum.value
    }

    /// Regenerating these to make a red test pass is forbidden. If generation changed on
    /// purpose they are regenerated in the same commit with the change described; if it
    /// did not, generation is non-deterministic and that is the bug.
    @Test(
        "A seed produces the same world in every process",
        arguments: [
            (UInt64(1), UInt64(12_206_648_183_704_183_677)),
            (UInt64(5), UInt64(10_085_084_855_821_522_147)),
            (UInt64(7), UInt64(17_159_367_310_507_637_788)),
        ])
    func goldenWorlds(seed: UInt64, expected: UInt64) {
        #expect(worldChecksum(seed: seed) == expected)
    }

    /// Two runs in one process, which is the weaker check — but it distinguishes "the
    /// world moved because generation changed" from "the world moves every time", which
    /// is the first question to ask when the constants above go red.
    @Test("contract: a world is identical to itself, seed by seed")
    func selfConsistent() {
        for seed in UInt64(1)...4 {
            #expect(worldChecksum(seed: seed) == worldChecksum(seed: seed))
        }
    }
}
