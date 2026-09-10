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
            // Moved by #69, and by the world rather than by the engine: nothing in
            // `FMSimulation` changed. `TestWorld` is `WorldGenerator.generate`, so the
            // eight clubs it plays between are now `FranchiseSet`'s curated ones
            // ([decision 215](../../../../docs/design-decisions.md)). Three things the
            // engine reads moved with them — the ground the game is played in (roof,
            // surface, noise and altitude are curated now, and the home side's stadium
            // is the one this game is played in), the schemes, which are still drawn but
            // from a league substream that no longer spends draws on identities, and
            // therefore the rosters, because a roster is built for the scheme its club
            // inherited. A game between two different clubs in a different building is a
            // different game.
            //
            // And moved again by #67, again by the world and not by the engine: nothing in
            // `FMSimulation` changed. The age a generated player is drawn at was clamped
            // into 21...38 and is now redrawn when it falls outside, and a reserve's centre
            // is floored two seasons above the entry age rather than landing on it. Age is
            // what `PlayerGenerator.currentOverall` measures a man's progress toward his
            // ceiling along, so every rating on both rosters moved — an older league is a
            // slightly better one — and a game between two rosters of different players is
            // a different game.
            //
            // And moved by the play clock, this time by the engine. Every play now records
            // the play clock it was snapped against (2025 rulebook, 4-6) as a decision
            // point, and the checksum mixes every decision point, so every checksum moves
            // for that reason alone. The football moved less: a delay of game is now the
            // play clock expiring — drawn against the slack the tempo leaves on the clock
            // in force rather than at a flat rate — so a snap on the twenty-five after a
            // change of possession is a little likelier to be one, a flag that flies costs
            // the whole play clock rather than the huddle, and a huddle after a runoff or a
            // penalty enforcement is charged against the thirty or the twenty-five it was
            // really taken against.
            //
            // And moved by the rulebook. `Rules` carried the 2024 kickoff — a touchback
            // at the receiving team's 30 — and now carries the 2025 book's 35 (6-1-5), so
            // every drive that follows a touchback starts five yards further on and
            // everything downstream of a drive's field position moves with it. The onside
            // declaration moved with it too (6-1-6): the book allows one at any time
            // while trailing rather than in the fourth quarter alone, and the baseline
            // caller now wants one from five minutes out rather than three, from two
            // minutes rather than fifty seconds when nothing can stop the clock, and in a
            // narrow third-quarter case the old rule could not reach.
            //
            // And moved by the dynamic kickoff. The kickoff is two plays now — struck
            // through the end zone, or into the landing zone to be returned (2025
            // rulebook, 6-1-4, 6-1-5) — the call chooses between them, and both read the
            // spot the kick is taken from, so a penalty on a free kick changes the kick.
            // Three quarters of kickoffs are returned where a third were, a return starts
            // inside the receiving team's 20 rather than in its end zone, a mishit kick
            // can now miss the landing zone and hand over 6-2-4's spot, and an onside kick
            // dies where the rules let it be recovered rather than ten yards past it on
            // the branch where the receiving team came up with it.
            // And moved by a foul on a play that scored. A place kick is resolved before
            // the rush at the kicker is drawn, so a flag there no longer cancels the
            // kick; a personal or unsportsmanlike foul during a field goal, a safety or a
            // try is carried to the free kick and one during a touchdown to the try
            // (2025 rulebook, 14-2-3, 11-3-3), so the spot the next play is made from
            // moves; an offensive foul on a successful try brings the try back (11-3-3
            // Item 3-a) where it used to end the sequence; and `afterThePlay` is drawn on
            // completions and sacks as well as runs, which is a flag on plays that could
            // not draw one at all.
            (UInt64(1), UInt64(5_375_534_536_715_646_457)),
            (UInt64(5), UInt64(3_124_004_378_098_102_246)),
            (UInt64(12), UInt64(15_626_393_571_278_336_379)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
