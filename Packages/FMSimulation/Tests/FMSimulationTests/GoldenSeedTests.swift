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
            //
            // And moved again by the world, not by the engine: nothing in `FMSimulation`
            // changed. A receiver and a tight end train ball security now — carrying and
            // break tackle are drawn around their own quality instead of being filled in
            // from the untrained table's ball-carrying row — so the two draws moved from
            // the identifier-split untrained substream to the trained stream. Both
            // positions' numbers moved with them, carrying from about 25 to about 69, and
            // so did everything the trained stream reaches after a man's ratings: his
            // build, his combine, his name, his college and every man drawn after him.
            // `TestWorld` is `WorldGenerator.generate`, so both rosters are different
            // men, and the engine reads the two moved keys directly — a receiver holds on
            // to the ball and breaks a tackle on a number in the sixties where he did it
            // on one in the twenties. A game between different men who run after the catch
            // differently is a different game.
            //
            // And moved by the clock, by the engine. The interval between downs is
            // charged before the situation is built rather than after it is recorded, so
            // every play's recorded clock moves from the end of the play before to the
            // moment the ball was snapped. Three things follow that the checksum can see.
            // A period the interval alone exhausts now ends with **no down recorded**
            // (2025 rulebook, 4-8-1), and a play removed from the end of a period removes
            // every later play's seed split with it, so each of these games diverges
            // wholly from its first such period. The two-minute warning taken between
            // downs now belongs to the snap that follows it rather than to the one after
            // that, and no longer buys the offence a free interval on the down after the
            // warning. And a caller reading the clock at the previous whistle, which is
            // where it still reads it, is asked about a game that no longer carries those
            // downs. `Tools/gamelog --seed 7 --home 3 --away 11` prints a hundred and
            // seventy-eight plays where it printed a hundred and sixty-six, with the
            // clock column reading at the snap throughout.
            //
            // And moved again because the pocket has a clock in it. A rusher who beats
            // his blocker is recorded as having beaten him and nothing more; the pocket
            // gets one verdict a snap, and it is pressure only if the man got there
            // before the ball was out. That alone moves every dropback's stream — a
            // `.blockResult` a rep where a `.pressureAllowed` or a `.pressureHeld` used
            // to be, and one verdict after the read instead of one point per rep — and
            // the checksum mixes every decision point. With it, the rep win rate is the
            // pressure rate's lever now that it is no longer the pressure rate itself,
            // and it is set from that row, so fewer rushers win, fewer get home, fewer
            // sacks and scrambles are taken and every drive after one of them is a
            // different drive.
            //
            // And the two clocks then met in this merge, which is where the constants below
            // come from. On one side the interval between downs is charged before the
            // situation is built, so a period that interval alone exhausts records no down
            // at all. On the other the pocket has a clock in it: one verdict a snap taken
            // against the moment the ball came out, with the rep win rate as that row's
            // lever now that it is no longer the row itself, so fewer rushers get home and
            // fewer sacks and scrambles are taken. The two reach each other on the same
            // snaps. A sack that is no longer taken is a different outcome with a different
            // runoff and a different next spot, so the period reaches its end at a
            // different whistle and a different set of intervals is the one that exhausts
            // it; and a down the clock no longer records is a dropback whose reps are never
            // drawn, so the pocket verdict that snap would have carried never enters the
            // stream. Neither parent's constants could survive, because each was computed
            // without the other's mechanism, and no subset of the mechanisms above
            // reproduces these numbers.
            //
            // And moved by the catch, in three ways the checksum mixes through the catch
            // decision and through the draws each one spends. A defensive interference
            // foul now settles the catch instead of sitting beside it (2025 rulebook,
            // 8-5-1): the flag is drawn at the throw and the catch is resolved with it in
            // hand, so the pass is incomplete and the result is the defender's, where two
            // thirds of those flags used to fly on passes that were then completed. No
            // interference of either kind is drawn on a throw the record calls
            // uncatchable, which 8-5-3-c makes legal contact. And placement now decides
            // whose incompletion an uncaught ball was: a poor one is the throw's, and
            // `CatchResult` has a case for it, where every failed catch with the receiver
            // open used to be charged to him as a drop. Each interference draw that ends
            // a catch early leaves the catch and interception draws unspent, and each
            // uncatchable throw leaves the interference draw unspent, so every stream
            // after the first of them in a game diverges. `Tools/gamelog --seed 7
            // --home 3 --away 11` prints a hundred and sixty-five plays where it printed
            // a hundred and seventy-eight, with nine drops where it printed eighteen and
            // five interference calls that are now five incompletions accepted at the
            // spot, where all four of the defence's were completions and every one was
            // declined.
            //
            // And the pocket and the catch then met in this merge, which is where the
            // constants below come from. On one side the pocket gets one verdict a snap,
            // taken against the moment the ball came out, so far fewer dropbacks are
            // pressured. On the other a defensive interference flag settles the catch,
            // no flag is drawn on a throw nobody could reach, and placement decides whose
            // incompletion an uncaught ball was. The two reach each other on the same
            // snaps, and in both directions. Pressure is what makes a throw inaccurate,
            // so a pocket that holds puts more balls on target and fewer where they could
            // not be caught — which moves the mix of drops, break-ups and off-target
            // throws the other side is labelling, and the uncatchable throws it declines
            // to flag. A sack that is no longer taken is a throw instead, so there is a
            // catch to resolve and a matchup to draw interference on where there was
            // neither. And a flag that now ends the catch is accepted at the spot, which
            // keeps a drive alive and hands the pocket more dropbacks to judge. Neither
            // parent's constants could survive, because each was computed without the
            // other's mechanism, and no subset of the mechanisms above reproduces these
            // numbers.
            //
            // And moved again by the benches spending their timeouts. Nothing in the
            // rules layer changed; what changed is when a coach asks for one. A defence a
            // single score down now stops the clock through the whole five-minute
            // clock-burn window rather than only inside the last three and a third, an
            // offence with the ball in the last minute of either half stops it rather
            // than keep a timeout it cannot carry past the whistle, and an offence on
            // third or fourth and short facing a play clock it is not going to beat
            // spends one instead of the five yards. A charged timeout is an
            // administrative stoppage, so each one resets the play clock to the short one
            // and leaves the game clock waiting for the snap — which changes how much of
            // the period the next snap costs, which changes what is called on the snap
            // after that, and the stream diverges from there.
            //
            // And moved by the kicker, deliberately, by the engine. A place kick now
            // reads both of his ratings rather than one: the touch sets the level as it
            // always did, and the leg sets how fast the chance falls once the kick is
            // long enough for a leg to be what is being asked for — so a man who cannot
            // get the ball there misses from fifty-five where he used to miss from
            // fifty-five as often as a kicker having a bad day. The caller reads the same
            // curve instead of two flat numbers, so how far a club will kick from is its
            // kicker's and no longer the league's: a median leg's range is exactly where
            // the flat numbers put it, a strong leg's is further and a weak leg's nearer,
            // and the fourth downs that fall outside it are gone for or punted by the
            // chart that was already there. On the tree this mechanism was written on,
            // the first snap that differed in each of the three games was a fourth down
            // that was a kick and is now a play. Measured again on the three callers
            // assembled, before the catch below joined them, it reached none of the
            // three: no fourth-down decision and no attempt in those three games came
            // out differently, which is what a median leg's range being exactly where
            // the two flat numbers were looks like from inside three games. So this
            // mechanism is measured in the harness's kicking rows, where it moves
            // attempts from fifty and beyond by three points of share; a golden of three
            // games is not where it shows.
            //
            // And moved by the caller, which is the engine. Who each side sends out
            // changed on three counts: the offence's ordinary-down grouping is eleven
            // personnel or a second tight end where a fourth receiver used to be mixed
            // in, a passing down outside two minutes is played from eleven personnel
            // rather than sometimes from four receivers, and the defence answers three
            // receivers on an ordinary down with its nickel back every time instead of
            // staying in a four-back front about a quarter of the time. An empty set is
            // answered with six defensive backs rather than seven. Both sides' draws
            // move with all four — two of them are gone, so every stream downstream of a
            // snap is spent in a different order — and the eleven men on each side of
            // the ball are different men on a large share of snaps, which changes what
            // the play produced and not merely what it was called.
            //
            // And the bench, the kicker and the huddle then met in this merge, which is
            // where the constants below come from. On one side a bench spends timeouts
            // where the sport spends them, and each charged one resets the play clock to
            // the short interval and leaves the game clock waiting for the snap. On
            // another, how far a club will kick from is its kicker's rather than the
            // league's, and the fourth downs outside that range are gone for or punted
            // instead. On the third, the grouping and the front are the sport's: eleven
            // personnel answered by a nickel back every time, a second tight end where a
            // fourth receiver used to be. The three reach each other on the same snaps.
            // Different men on the field produce a different play, so the down and
            // distance after it differ, so the fourth down the kicker's range is asked
            // about is a different fourth down at a different spot — and the score and
            // clock a bench reads before spending a timeout are the ones those drives
            // left. Run the other way, a timeout that costs the next snap less of the
            // period changes which downs a period has room for at all, and a down that
            // is never played is a grouping never sent out and a kick never attempted.
            // Neither parent's constants could survive, and none of the three branches'
            // could either: each was computed on a tree without the other two, and all
            // three were computed before the interval was charged at the snap and the
            // pocket got one verdict.
            //
            // And the three callers then met the catch, in this merge, which is where
            // the constants below come from. On one side a bench spends its timeouts,
            // range is the kicker's and the grouping and the front are the sport's. On
            // the other an interference foul settles the catch rather than sitting
            // beside it, no flag is drawn on a throw nobody could reach, and a poor
            // throw is the throw's incompletion rather than the receiver's drop. They
            // reach each other on the same snaps and in both directions: a flag that now
            // ends a catch and is accepted at the spot keeps a drive alive, so the
            // fourth down the kicker's range would have been asked about never arrives
            // and the clock a bench reads at the two-minute warning is a different one;
            // run the other way, a defence that answers three receivers from its nickel
            // back covers those throws with a fifth defensive back, so which balls are
            // catchable at all — and therefore which flags are drawn and which
            // incompletions are whose — is decided by a secondary that was not on the
            // field before. Neither parent's constants could survive, because each was
            // computed without the other's mechanisms, and no subset of the mechanisms
            // above reproduces these numbers. Checked before they were written down: all
            // three seeds differ from both parents of this merge, from each of the three
            // caller branches, and from both intermediate merges on this branch.
            // And moved again by the run game. A carry no longer reads its yards off one
            // line through the hole quality with a flat lottery on the end of it: the
            // hole decides which of three things happened — the point of attack lost,
            // the ordinary carry through it, or the play side washed — and the ordinary
            // one gains three to nine, decided by the carrier's vision and contact
            // balance against the second level's tackling. The long run is a tackle
            // missed in space rather than a draw on a hole that opened. Every carry
            // spends a different number of draws in a different order, so every game
            // diverges from its first handoff.
            //
            // And the run game then met the pocket, in this merge, which is where the
            // constants below come from. On one side a carry is three outcomes and a
            // long run is a man beaten. On the other the pocket gets one verdict a snap
            // and it is pressure only if the rusher got there before the ball was out,
            // so fewer rushers get home and fewer sacks and scrambles are taken. The two
            // reach each other on the same drives: a carry that gains five where it
            // gained one is a second and five rather than a second and nine, which is a
            // different call, and the dropback that call produces is the one the pocket
            // is now deciding differently; a sack no longer taken leaves a down the run
            // game then plays. Neither parent's constants could survive, because each
            // was computed without the other's mechanism, and no subset of the
            // mechanisms above reproduces these numbers.
            //
            // And the run game then met all of that, in this merge, which is where the
            // constants below come from. On one side a carry is three outcomes — the
            // point of attack lost, the ordinary carry through it, the play side washed
            // — and a long run is a tackle missed in space rather than a draw on a hole
            // that opened. On the other a bench spends its timeouts, range is the
            // kicker's, the grouping and the front are the sport's, an interference foul
            // settles the catch, and a poor throw is the throw's incompletion. They
            // reach each other on the same drives and in both directions. A carry that
            // gains five where it gained one is a second and five rather than a second
            // and nine, which is a different call, so the throw the catch rules are now
            // deciding is a throw that would not have been made; and a defence that
            // answers three receivers from its nickel back meets the run with six in the
            // box where seven used to stand, which moves the point of attack the carry
            // is now three outcomes of. Neither parent's constants could survive,
            // because each was computed without the other's mechanisms, and no subset of
            // the mechanisms above reproduces these numbers. Checked before they were
            // written down: all three seeds differ from both parents of this merge.
            //
            // And moved again by the defence, on one grouping. A two-tight-end grouping
            // is no longer answered from the four-back front every time: three snaps in
            // ten of it draw the fifth defensive back instead, because a second tight
            // end is one fewer back to account for and one more man the defence would
            // rather cover with a defensive back. Two backs still draw the front every
            // time. This moves the stream two ways at once. It spends a draw on every
            // two-tight-end snap outside a down the offence has to throw on, where the
            // rule before it asked nothing, so every draw after that one on those snaps
            // is a different draw; and on the snaps it answers with the fifth back it
            // puts a different eleven men on the field, which changes what the play
            // produced and not only what it was called. All three golden games diverge,
            // which is what a rule that reaches about a fifth of snaps looks like from
            // inside three games.
            //
            // And the run game then met the defence's answer to one grouping, in this
            // merge, which is where the constants below come from. On one side a carry
            // is three outcomes and a long run is a man beaten. On the other a
            // two-tight-end grouping draws the fifth defensive back three snaps in ten
            // where it drew the four-back front every time. They reach each other on
            // exactly the snaps that matter to both: a carry from a two-tight-end
            // grouping now meets a six-man box on some of the downs it used to meet a
            // seven-man box on, and the point of attack the carry is three outcomes of
            // is decided against whoever is standing there — so the same handoff is a
            // different carry, and the down and distance it leaves is a different down.
            // Run the other way, a carry that gains five where it gained one is a second
            // and five rather than a second and nine, which is a grouping the offence
            // would not have sent out and therefore an answer the defence was never
            // asked for. Neither parent's constants could survive, because each was
            // computed without the other's mechanism. Checked before they were written
            // down: all three seeds differ from both parents of this merge.
            //
            // And then the play clock stopped being a rate and became an interval with a
            // decision in it. Whether the offence gets a snap away inside the clock in
            // force is asked once per snap, before either bench is asked for a timeout
            // and before the eleven men are drawn — where the flag used to be drawn
            // beside the down, after the false start and inside the resolver. That draw
            // has moved in every snap's stream, so every game diverges from its first
            // possession whether or not a play clock is ever lost. Three things then
            // differ in the football as well: the offence spends a timeout on a play
            // clock only when it has actually lost one rather than whenever the clock
            // looked tight, which is about 0.7 fewer timeouts a game; the snap that
            // follows a charged timeout is a prepared one, so it takes about half as many
            // delays of game as an ordinary snap instead of rather more; and a down where
            // nobody stopped the clock is a delay of game whatever else might have been
            // drawn on it, since no play was run.
            //
            // And the play clock then met the run game and the defence's answer to one
            // grouping, in this merge, which is where the constants below come from. On
            // one side a play clock that is about to expire is a decision a bench makes
            // rather than a flag drawn beside the down. On the other a carry is three
            // outcomes of a point of attack, and a two-tight-end grouping draws the fifth
            // defensive back three snaps in ten where it drew the four-back front every
            // time. They reach each other on exactly the downs both are about. The
            // timeout is spent on third and fourth and short, and how often an offence is
            // *in* third and short is the run game's to decide — a carry that gains five
            // where it gained one is a second and five, so the down the bench is asked
            // about is a different down at a different distance. Run the other way, a
            // timeout that stops the clock leaves a down played where five yards would
            // have been walked off, so the distance the next carry is run at is one the
            // run game would never have seen. And the defence's answer decides who is
            // standing at that point of attack on the down the timeout bought. Neither
            // parent's constants could survive, because each was computed without the
            // other's mechanisms. Checked before they were written down: all three seeds
            // differ from both parents of this merge.
            //
            // And then the two-minute warning started leaving what the book says it
            // leaves. A warning taken between downs is an administrative stoppage, so the
            // snap it precedes is against twenty-five seconds from the Referee's whistle
            // rather than the forty that had been counting down (4-6-2, 4-6-3-a), and the
            // clock is settled before the snap is prepared so that the record, the
            // context and the draw against the interval all read it. Measured over the
            // shared corpus: forty games carry sixty warnings between downs and
            // twenty-one during a down, so this is about a snap and a half a game.
            //
            // Two of the three seeds move and one does not, which was checked rather than
            // assumed. Seed 1's only warning between downs falls after a down that was
            // itself a stoppage, so that snap was already on the short clock and the
            // reading it records is the one it recorded before — its checksum below is
            // unchanged, and the same number it carried through the merge above. Seeds 5
            // and 12 each have a snap that moves from forty to twenty-five, which moves
            // both the reading on the record and the odds the offence is beaten by the
            // interval, and from there the game diverges.
            //
            // And then the pass rush was given a window that spans the holds it is read
            // against. A beaten blocker's man used to arrive on a uniform 1,500-2,899 ms
            // while the routes asked for 1,400 through 3,400, so three of the five pass
            // concepts sat outside the window and their pressure verdict was a constant.
            // He now arrives from 1,000 ms on a core of the same width with a tail that
            // halves every half second. All three seeds move, and every one of them has
            // to: the draw is a different draw on the first lost rep of the game, the
            // number of values it consumes is itself random now, and both the verdict and
            // the stream diverge from there. There is no snap in any of the three that
            // could have come out the same by luck, so — unlike the warning above — a
            // seed that did *not* move would be the thing worth investigating.
            (UInt64(1), UInt64(6_815_553_386_457_547_323)),
            (UInt64(5), UInt64(6_467_780_222_937_450_596)),
            (UInt64(12), UInt64(2_014_329_887_637_027_649)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
