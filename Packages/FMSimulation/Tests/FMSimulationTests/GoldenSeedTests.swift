import FMCore
import Testing

@testable import FMSimulation

/// The same seed must produce the same game — in a different process, on a different day,
/// after a rebuild.
///
/// Every determinism test in this repo used to compare two runs *inside one process*, and
/// that is exactly the check a hash-order bug walks through: Swift randomises its hash
/// seed per process, so two runs in one process agree with each other and disagree with
/// yesterday's. `SchemeFit.effectiveOverall` summed its weights while iterating a
/// dictionary, floating-point addition is not associative, and the sum was rounded to a
/// whole overall point — so a player near a boundary was a point better in one process and
/// a point worse in the next, and the same seed produced a different season.
///
/// A checked-in constant is the only form of this test that can fail for that reason,
/// which is why the number below is written down rather than computed twice.
/// ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md))
///
/// The game is built by `TestWorld`, which is
/// `WorldGenerator.generate(seed:shape:franchises:season:)` — so this pins the whole path
/// from seed to final whistle, world generation included, and not merely the engine's
/// half of it.
@Suite("Golden seed")
struct GoldenSeedTests {

    /// FNV-1a. Deliberately *not* `Hasher`, whose seed is randomised per process — using
    /// it here would make this test unable to detect the thing it exists to detect.
    private struct Checksum {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(_ number: UInt64) {
            for shift in stride(from: 0, through: 56, by: 8) {
                value ^= UInt64((number >> UInt64(shift)) & 0xff)
                value = value &* 0x100_0000_01b3
            }
        }

        mutating func mix(_ number: some BinaryInteger) { mix(UInt64(bitPattern: Int64(number))) }
    }

    private func checksum(seed: UInt64) -> UInt64 {
        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(TestWorld.setup(seed: seed))
        var sum = Checksum()
        sum.mix(result.homeScore)
        sum.mix(result.awayScore)
        sum.mix(result.plays.count)
        for play in result.plays {
            sum.mix(play.schemaVersion)
            sum.mix(play.calls.offense.concept.rawValue)
            sum.mix(play.situation.ballOn)
            sum.mix(play.situation.distance)
            sum.mix(play.situation.down.rawValue)
            sum.mix(play.situation.offensePersonnel.code)
            sum.mix(play.situation.defensePackage.rawValue)
            sum.mix(play.outcome.kind.rawValue)
            sum.mix(play.outcome.endedIn.rawValue)
            sum.mix(play.outcome.yards)
            sum.mix(play.outcome.clockRunoff)
            sum.mix(play.outcome.finalSpot ?? 200)
            sum.mix(play.outcome.passResult?.rawValue ?? 200)
            sum.mix(play.outcome.pointsScored)
            for entry in play.onField { sum.mix(entry) }
            for participant in play.outcome.participants {
                sum.mix(participant.player.rawValue)
                sum.mix(participant.role.rawValue)
                sum.mix(participant.slot.rawValue)
            }
            for decision in play.decisions {
                sum.mix(decision.kind.rawValue)
                sum.mix(decision.value)
                sum.mix(decision.tick)
            }
        }
        for injury in result.injuries {
            sum.mix(injury.player.rawValue)
            sum.mix(injury.gamesOut)
            sum.mix(injury.occurredOn.index)
        }
        return sum.value
    }

    /// Regenerating these to make a red test pass is forbidden: if the engine changed on
    /// purpose, they are regenerated in the same commit and the behaviour change is
    /// described in the message. If it did not, the engine is non-deterministic and that
    /// is the bug.
    @Test(
        "A seed produces the same game in every process", .tags(.contract),
        arguments: [
            // What moves these numbers. The checksum is taken over whole simulated
            // games, so three different causes land on it and they are not the same
            // claim — say which one in the commit message.
            //
            // **The world moved, not the engine.** `TestWorld` is
            // `WorldGenerator.generate`, so anything that changes the clubs, their
            // grounds, their schemes or their rosters changes the game these seeds play.
            // Nothing in `FMSimulation` has to change for all three constants to move.
            //
            // **The record moved, not the game.** The checksum mixes the record's fields,
            // so a new field, a schema version bump, or the same fact hashed under a new
            // name moves every constant while `Tools/gamelog --seed 7 --home 3 --away 11`
            // prints the identical play-by-play. That equality is the evidence, and it is
            // worth taking: it is the difference between wider coverage and a changed
            // engine, and the two are told apart nowhere else.
            //
            // **The engine moved.** Then the play-by-play differs too, and the harness
            // rows owe an explanation. The trap here is draw *order*: a stage that spends
            // a draw earlier or later than it did shifts every stream after it, so a
            // change with no football in it at all — moving where the lineup is drawn —
            // can move every constant, or move none, depending only on order.
            //
            // Regenerating any of them to make a red test pass is forbidden (CLAUDE.md
            // rule 9). What each past move was is in the git log.
            (UInt64(1), UInt64(4_372_911_798_832_149_273)),
            (UInt64(5), UInt64(10_467_495_408_351_583_217)),
            (UInt64(12), UInt64(12_411_116_499_503_396_195)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
