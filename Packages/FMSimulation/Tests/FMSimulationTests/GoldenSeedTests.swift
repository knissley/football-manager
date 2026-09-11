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
            // And moved by the record rather than by the game: the twenty-two roster
            // indices of `PlayRecord.onField` are mixed in from here on, so the same
            // three games hash differently. Nothing a play produced changed — the lineup
            // is drawn by the simulator immediately before the snap is resolved, where
            // the resolver used to draw it, so every stream is spent in the same order —
            // and `Tools/gamelog` prints the same game before and after.
            //
            // And by the record again: `Outcome.passResult` and `Outcome.pointsScored`
            // are mixed in from here on. A resolver writes the first and the game the
            // second, neither reads either, and no play produced anything different;
            // `Tools/gamelog` prints the same game before and after.
            //
            // And by the record a third time: `PlayRecord.schemaVersion`, which is 1,
            // and the concept the offence called, now held by value as
            // `OffensiveCall.concept` rather than pointed at through a stand-in design
            // identifier, are mixed in from here on. The concept was always on the
            // record — the identifier was its raw value plus one — so this is the same
            // fact hashed under a different name, and nothing a play produced changed;
            // `Tools/gamelog` prints the same game before and after.
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
            //
            // And moved again by the enforcement stoppage, by the engine. A flag on a down
            // stops the game clock at the end of that down (2025 rulebook, 4-4-e) and the
            // clock starts again on the ready-for-play signal, or on the snap inside the
            // late windows (4-3-2-e). Every accepted foul on a down that ended in bounds
            // therefore costs the offence one ready-for-play interval less than before, and
            // one inside the last five minutes of a half costs it none at all, so every
            // clock reading after the first such flag in each of the three games moves and
            // the play that fills each period changes with it.
            //
            // The play clock and the record changes met in a merge, and the constants
            // below are the union: the play clock's games, hashed with the record's
            // schema version, concept, presence, pass result and points mixed in. Neither
            // side's constants could survive, because each was computed without the
            // other's mechanism; `Tools/gamelog` prints the play clock's game before and
            // after the merge.
            //
            // And by the record a fourth time: what happened while the ball was dead
            // before a snap — a charged timeout with the side that took it, the
            // two-minute warning — is a rules-layer decision point on the next snap's
            // record, and the checksum mixes every decision point. Where a kick was
            // fielded and where possession was lost went on the record with it, but
            // neither is hashed. Nothing a play produced changed: the same timeouts are
            // spent at the same moments and the clock runs as it did, and `Tools/gamelog`
            // prints the same plays before and after, with the dead ball now written
            // above them and a kick's gross and return beside it.
            //
            // And moved by the merge of those two sets of changes, which is where the
            // constants below come from. Neither side's could survive it: each was
            // computed without the other's mechanism, and the checksum on this side
            // mixes five facts the other side's did not. The football did not move —
            // `Tools/gamelog --seed 7 --home 3 --away 11` prints the same hundred and
            // seventy-nine plays with the same 35-41 either side of the merge, and every
            // line that differs is a kick or a dead ball printing detail the record only
            // just started carrying. The run-or-pass conversion moved type rather than
            // meaning: it is a case of `PlayConcept`, which the checksum mixes, where it
            // was a case of the now-deleted `PlayFamily`, which it did not.
            //
            // The enforcement stoppage and those dead-ball decision points then met in a
            // merge of their own, and the constants below are again the union: the
            // enforcement stoppage's games, hashed with the dead-ball decision points
            // mixed in. Neither side's constants could survive it, for the same reason as
            // before — each was computed without the other's mechanism — so all three are
            // regenerated here from the merged tree.
            //
            // And moved by the baseline caller, deliberately. Down and distance now
            // buckets at three and six on every down, fourth included; a passing down is
            // third or fourth and seven or more and nothing else; and the caller reads
            // all of it as a lean rather than an instruction, so it runs a small share of
            // third and longs instead of none. It also goes for it on fourth and goal
            // from inside the three, kneels out the first half when a snap can only cost
            // it, and stops spending defensive timeouts three scores down. Every one of
            // those changes what is called on some snap, and a different call is a
            // different game from there on.
            //
            // And moved again by the kneel-down, at seed 12 alone: the caller now counts
            // the play clocks it can actually spend and the ones a defensive timeout
            // takes back, so a lead that can be knelt out is knelt out to the end of the
            // game instead of two knees and then an ordinary play.
            //
            // The caller's changes and the record's met in a merge, and all three
            // constants below are the union: the caller's games, hashed with the
            // record's dead-ball decision points mixed in. Neither side's constants
            // could survive, because each was computed without the other's mechanism.
            //
            // And the caller and the clock then met in a merge of their own, and the
            // constants were regenerated from that tree, which has both: the caller
            // decides what is snapped, the clock decides how much of a period each snap
            // leaves, and each reaches the other — a knee that ends a half depends on how
            // much clock a flag or a runoff left, and what is called after the two-minute
            // warning depends on which side has the ball there. Neither parent's
            // constants could survive, because each was computed without the other's
            // mechanism.
            //
            // And moved again when every player came to carry every key — by the world,
            // and by what the engine reads of it. Nothing in the rules layer changed, but a
            // rating a position does not train is now present and low rather than absent,
            // so the resolver's fallback for an absent key — the player's overall — has
            // nothing left to fall back from. A receiver breaks tackles and holds the ball
            // on his own breakTackle and carrying instead of his overall, a corner strips
            // on his own hit power, a back in 21 personnel runs his route on his own route
            // running, a lineman covering a kick pursues on his own pursuit. Each of those
            // was a number in the sixties or seventies that is now in the twenties or
            // thirties, so a game between the same men is a different game. The men
            // themselves did not move: every trained rating is byte-identical.
            //
            // And the untrained keys then met the caller and the clock, in this merge. The
            // constants below are regenerated from the merged tree, which carries both
            // mechanisms and every one above them. On one side, every player now carries
            // every rating key, so the resolver's fallback to a man's overall for a key he
            // lacked never fires, and a receiver breaks a tackle on a number in the
            // twenties where he used to break it on one in the sixties. On the other, the
            // caller decides what is snapped and the clock decides how much of a period
            // each snap leaves. The two reach each other: a weaker cover man changes
            // whether a third and long is converted, and that changes both what is called
            // next and how much clock is left for the rest of the half. Neither parent's
            // constants could survive, because each was computed without the other's
            // mechanism, and no subset of the mechanisms above reproduces these numbers.
            //
            // And the two tracks above then met in this merge, which is where the
            // constants below come from. On one side a two-point try is a run or a pass
            // and is substituted for, a punt from plus territory is aimed, where a play
            // ends laterally is drawn from the concept and the clock, interference is
            // drawn at the throw, and a position the sport does not rotate is not drawn
            // for on every snap. On the other, a flag stops the clock at the end of its
            // down, the baseline caller decides what is snapped, every player carries
            // every rating key, and a try's every exit is recorded as the try. The two
            // reach each other on the same snaps: what the caller calls decides how often
            // a punt is struck from plus territory at all, a receiver who now breaks a
            // tackle on his own number rather than his overall reaches the boundary the
            // sideline draw is deciding about, and the clock a flag no longer spends
            // changes which snaps fall inside the late window the sideline lever reads.
            // Neither parent's constants could survive, because each was computed without
            // the other's mechanisms, and no subset of the mechanisms above reproduces
            // these numbers.
            //
            // And the rulebook track then met all of that, in this merge, which is where
            // the constants below come from. On one side `Rules` is the 2025 book — a
            // kickoff touchback at the receiving team's 35 and an onside kick declarable
            // at any time while trailing (6-1-5, 6-1-6) — the kickoff is two plays the
            // call chooses between and both read the spot the kick is taken from (6-1-4,
            // 6-1-5), a place kick is resolved before the rush at the kicker is drawn, and
            // a foul on a play that scored is carried to the try or the free kick
            // (14-2-3, 11-3-3). On the other, a two-point try is a run or a pass and is
            // substituted for, a punt from plus territory is aimed, the sideline is drawn
            // from the concept and the clock, interference is drawn at the throw, a
            // position the sport does not rotate is not drawn for, a flag stops the clock
            // at the end of its down, the baseline caller decides what is snapped, every
            // player carries every rating key, and a try's every exit is recorded as the
            // try. The two reach each other on the same snaps: a touchback five yards
            // further on changes what the caller calls from the drive's first snap, a
            // returned kickoff spends draws a touchback does not and moves every stream
            // after it, and the free kick a scoring foul moves is one the onside rule and
            // the aiming choice both read. Neither parent's constants could survive,
            // because each was computed without the other's mechanisms, and no subset of
            // the mechanisms above reproduces these numbers.
            (UInt64(1), UInt64(18_221_643_139_207_046_522)),
            (UInt64(5), UInt64(1_879_505_917_188_062_581)),
            (UInt64(12), UInt64(17_078_191_025_272_067_907)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
