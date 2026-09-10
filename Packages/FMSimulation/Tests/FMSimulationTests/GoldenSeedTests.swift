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
            // And moved by rotation. A position the sport does not rotate — the
            // quarterback, the five line spots, the kicker, the punter and the long
            // snapper — is no longer drawn against a snap share on every snap; the man
            // highest on the chart who is available simply takes it. That is six draws
            // fewer on every snap of every game — the quarterback and the five line
            // spots, or the specialist, the snapper and four linemen on a kick — so every
            // checksum moves for that reason alone, and with them goes the substitution
            // that had the backup quarterback taking a dropback mid-drive with the
            // starter fit.
            //
            // And moved by the sideline. Where a play ends laterally is now drawn against
            // the concept and the clock rather than at a flat 14% — an outside run
            // reaches the boundary, an inside run does not, a trailing offence inside two
            // minutes is coached to get out and a leading one to stay in (4-3-2-a) — and
            // a carrier who beat everybody chasing him draws his ending like anybody
            // else instead of being written out of bounds. One extra draw on a broken-
            // tackle sequence moves every stream after it.
            //
            // And moved by the punt. A punt from inside the opponent's 45 is now aimed —
            // a pooch between the 5 and the 10, or the corner inside the 5 for a punter
            // with the touch to be trusted with it — and the punter's accuracy is the
            // scatter around that target rather than a modifier on whether the returner
            // fields it. A touchback is a miss now (11-6-2-c, 9-5-1 Note a) rather than
            // what happened whenever a team punted from plus territory, so drives after
            // one start much nearer their own goal, and an aimed punt spends two draws
            // where a struck one spends one.
            //
            // And moved by the try and the package. A two-point conversion is now a run
            // or a pass at the caller's choice (11-3-1), substituted for like the
            // scrimmage down it is; the defence on a try is its goal-line eleven rather
            // than whatever was on the field for the touchdown; and the package a
            // defensive call names is the substitution the caller actually made rather
            // than the label its preset carried. All three change who is on the field,
            // and the personnel and package draws move the stream on every snap.
            //
            // And moved by interference. Both kinds are drawn at the throw because
            // 8-5-1 makes a forward pass from behind the line the thing interference
            // needs before it can exist at all; the coverage loop keeps the fouls whose
            // restrictions begin at the snap. Confining the draw to the target's matchup
            // is the engine's own simplification and not that article's, which protects
            // every eligible receiver. A sack, a scramble and a
            // throwaway carry no interference at all now, a deep flag is enforced from
            // the catch point rather than from a re-drawn depth, and the draw moved from
            // four reads a play to one.
            //
            // And moved once more by the correction that followed reading the harness:
            // the three constants the interference move introduced are set so the fouls
            // it did not touch keep the rates it found them at — defensive holding was
            // doubling and offensive interference tripling as a side effect — and a
            // conversion's run-or-pass call is made once with its spot rather than
            // re-asked before a replay.
            //
            // And moved at seed 1 alone by the merge with A13. The late out-of-bounds
            // window is judged from the clock where the ball became dead rather than
            // from where the play before it ended (4-3-2-a-2, 4-3-2-a-3), and the
            // sideline is now something a trailing offence reaches on purpose — so the
            // two meet on the plays that matter most to both. Seeds 5 and 12 played the
            // same game either way; seed 1 did not.
            (UInt64(1), UInt64(16_190_159_873_496_514_374)),
            (UInt64(5), UInt64(9_358_588_685_460_489_739)),
            (UInt64(12), UInt64(4_864_393_250_434_305_262)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
