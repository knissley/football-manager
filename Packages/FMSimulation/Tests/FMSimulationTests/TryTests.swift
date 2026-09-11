import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

/// The play after a touchdown, as it is actually snapped.
///
/// `Rules.twoPointSnapYard` has been two since the rules were written and was read by
/// nothing: the decision to go for two was made *after* the situation was built, so every
/// conversion was attempted from the fifteen and needed fifteen yards. Across eight
/// hundred team-games not one was ever converted, and nothing failed — a rule that is
/// impossible to satisfy looks exactly like a rule that is merely hard.
@Suite("Tries")
struct TryTests {

    /// The standard corpus, whose size is derived where it is defined.
    ///
    /// Three tests in here walked games, at thirty, eighty and twenty seeds, and each
    /// re-simulated the games the others had already played: two hundred and ten games
    /// to read what forty distinct ones say, because a game is a pure function of its
    /// setup and playing it twice cannot tell anybody anything. They read one corpus now.
    ///
    /// Forty carries everything they ask. The thinnest is a two-point try being *called*:
    /// the engine attempts one about half a game — 41 across the corpus's first eighty —
    /// so forty expect twenty, and both of the branches the football test below needs are
    /// half of that again. There is no case in here rarer than that; the one that was, a
    /// flag on a try, is checked by scenario in the two tests that follow it.
    private static let sample: [GameResult] = TestWorld.corpus

    private static var plays: [PlayRecord] { sample.flatMap(\.plays) }

    /// Rewritten for A7 (#19). This used to assert that *every* try is snapped from
    /// the standard spot, which is wrong football: a flag on the try moves it (2025
    /// rulebook, 11-3-3), and asserting the standard spot regardless is exactly how a
    /// flag that was recorded and never applied stayed invisible. A try that no flag
    /// preceded is snapped from its own yard line; one a flag preceded is not.
    ///
    /// Rewritten again, and its own note says why. A foul during the touchdown is
    /// enforced on the try (14-2-3) and moves it by **yards**, which flags before the
    /// replay can walk straight back off — and this counted those yards as a boolean
    /// while counting every later flag's yardage properly. So a sequence that nets to
    /// nothing honestly, and lands on the standard spot for that reason, read as a try
    /// a flag had moved: holding on a converted two-point try puts the replay ten out,
    /// and two defensive fouls on the replay bring it ten back. That is precisely the
    /// cancelling case the note below says to count and skip, and the arithmetic simply
    /// did not do what the note described.
    @Test(
        "football · Rule 11-3-1, 11-3-3 · a try is snapped from its own yard line unless a flag on the try moved it",
        .tags(.football)
    )
    func triesAreSnappedFromTheRightSpot() {
        let rules = Rules.standard
        var checked = 0
        var moved = 0
        for plays in Self.sample.map(\.plays) {
            for index in plays.indices {
                let play = plays[index]
                let standard: UInt8
                switch play.outcome.kind {
                case .extraPoint: standard = rules.extraPointSnapYard
                case .twoPointConversion: standard = rules.twoPointSnapYard
                default: continue
                }

                // Every flag that preceded this try, walking back, with what each did to
                // the spot: a foul by the offence pushes the try out, one by the defence
                // brings it in. More than one can fly before the same try, and two that
                // cancel — a neutral zone infraction and then a false start — put the ball
                // back on the standard yard line honestly. "Not the standard spot" is the
                // wrong question to ask of that one, so it is counted and skipped rather
                // than asserted on either way.
                var net = 0
                var flags = 0
                var back = index - 1
                while back >= 0, plays[back].outcome.kind == .penaltyOnly,
                    plays[back].situation.possession == play.situation.possession,
                    plays[back].calls.offense == play.calls.offense
                {
                    flags += 1
                    for penalty in plays[back].outcome.penalties where penalty.wasAccepted {
                        net +=
                            penalty.foul.committedBy == .offense
                            ? Int(penalty.yards) : -Int(penalty.yards)
                    }
                    back -= 1
                }

                // The other way a try is not at its standard spot, and it is 11-3-3's
                // too: a foul during the touchdown is enforced *on* the try (14-2-3), so
                // it moves the spot with no `penaltyOnly` play of its own. The play the
                // walk-back ends on is that touchdown, and an accepted penalty on a
                // scoring play is the only thing it can mean.
                //
                // Its yardage goes into the same running total as every other flag's,
                // because it is walked off the same way and a later flag can walk it
                // back. Counted as a boolean it was the one flag whose cancellation this
                // could not see.
                var duringTheTouchdown = false
                if back >= 0, plays[back].outcome.endedIn == .touchdown {
                    for penalty in plays[back].outcome.penalties where penalty.wasAccepted {
                        duringTheTouchdown = true
                        net +=
                            penalty.foul.committedBy == .offense
                            ? Int(penalty.yards) : -Int(penalty.yards)
                    }
                }

                if net != 0 {
                    moved += 1
                    #expect(
                        play.situation.ballOn != standard,
                        "a flag on the try left it at the standard spot (play \(play.index))")
                } else if flags == 0 && !duringTheTouchdown {
                    checked += 1
                    #expect(
                        play.situation.ballOn == standard,
                        "a try snapped from the \(play.situation.ballOn) (play \(play.index))")
                }
            }
        }
        #expect(checked > 0, "no tries to check")
        #expect(moved > 0, "forty games and no flag on a try; the second half of this is unarmed")
    }

    // MARK: - A flag on the try (A7, #19)

    /// A false start on the kick: the try is replayed from five yards further out, and
    /// the kick is that much longer. Fifteen plus five is the 20, and a kick from the 20
    /// is 37 yards by the engine's one field-goal formula.
    @Test(
        "football · Rule 11-3-3 Item 2, 7-4-2 · a false start on an extra point re-kicks from the 20, a 37-yard try",
        .tags(.football)
    )
    func falseStartOnTheKickMovesItBack() {
        let trace = RulesScenario.falseStartOnATry.run()
        guard let scorer = trace[1]?.situation.possession else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(2, kind: .penaltyOnly, possession: scorer, ballOn: 15, "the flag")
        trace.expectPlay(
            3, kind: .extraPoint, possession: scorer, ballOn: 20, "re-kicked from the 20")
        guard let kick = trace[3] else { return }
        #expect(
            Rules.standard.fieldGoalDistance(ballOn: kick.situation.ballOn) == 37,
            "a 37-yard try")
        trace.expectScore(scorer, 7)
    }

    /// Defensive offside on a two-point try: half the distance from the 2 is the 1, and
    /// the try is snapped there. The scoring side is asked again whether to go for two
    /// from the 1, and this one still does.
    @Test(
        "football · Rule 11-3-3 Item 2, 7-4-5, 14-2-1 · defensive offside on a two-point try snaps the replay from the 1",
        .tags(.football)
    )
    func offsideOnTheConversionMovesItIn() {
        let trace = ScriptedGame(caller: ScriptedCaller(twoPointDecision: { _ in true })) { snap in
            if snap.index == 1 { return snap.touchdown() }
            if snap.isTry {
                let flaggedAlready = snap.previous?.outcome.kind == .penaltyOnly
                return snap.ballOn == 2 && !flaggedAlready
                    ? snap.preSnapFoul(.offside) : .twoPoint(converted: true)
            }
            return snap.neutral
        }
        .run()
        guard let scorer = trace[1]?.situation.possession else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(2, kind: .penaltyOnly, possession: scorer, ballOn: 2, "the flag")
        trace.expectPlay(
            3, kind: .twoPointConversion, possession: scorer, distance: 1, ballOn: 1,
            "the conversion is snapped from the 1")
        trace.expectScore(scorer, 8)
    }

    /// A try is not exempt from the half-distance ceiling. 11-3-3 lifts nothing — it
    /// applies the same half-distance twice inside its own interference exception — and
    /// 14-3-4-f puts the try's spot among the spots 14-2-1 measures from.
    ///
    /// A try starts on the 2, where five yards would reach the goal line and the ceiling
    /// is not in dispute. Walked out to the 7 by a false start first, the same five yards
    /// land where it is: half of seven is three and a half, so the replay comes from the
    /// 4 — the walk-off rounded down to the whole yard the engine can spot, which is a
    /// modelling choice — and not from the 2.
    @Test(
        "football · Rule 14-2-1, 11-3-3, 11-3-3 Item 2 · a five-yard defensive foul on a try snapped from the 7 is half the distance, and a try is not exempt from the ceiling",
        .tags(.football)
    )
    func offsideOnATryFromTheSevenIsHalfTheDistance() {
        let trace = RulesScenario.twoPointTryWalkedOutAndBackIn.run()
        guard let scorer = trace[1]?.situation.possession else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(2, kind: .penaltyOnly, possession: scorer, ballOn: 2, "the false start")
        trace.expectPlay(3, kind: .penaltyOnly, possession: scorer, ballOn: 7, "then the offside")
        guard let replay = trace[4] else {
            Issue.record("the script did not reach the replayed try")
            return
        }
        #expect(replay.situation.ballOn < 7, "the flag moved the try in")
        #expect(
            2 * Int(replay.situation.ballOn) >= 7,
            "never past the midpoint of the 7: \(replay.situation.ballOn)")
        trace.expectPlay(
            4, kind: .twoPointConversion, possession: scorer, ballOn: 4,
            "the try is snapped from the midpoint, the walk-off rounded down")
        trace.expectScore(scorer, 8)
    }

    /// A two-point try is a scrimmage down like any other, and the sport lets it be a run.
    ///
    /// 2025 rulebook, 11-3-1: the team that scored puts the ball in play 15 yards from the
    /// defence's goal line for a try-kick, or **two yards from it for a try by pass or
    /// run**. Every conversion this engine attempted was a pass, so half the play the rule
    /// describes did not exist — and with it went the heavy grouping a team sends out for
    /// it and the goal-line defence that answers.
    ///
    /// **Both halves of the article, and each one asked where it can be answered.** That
    /// the engine can *snap* a try as a run is a fact about the resolver, and it is forced:
    /// two hundred two-point runs are snapped and every one of them has to come back a
    /// two-point conversion with a carrier. That a caller ever *chooses* to run one is a
    /// fact about a game, and only a game can say it — the corpus's forty hold sixteen
    /// conversions, nine carried and seven thrown, so the thinner of the two branches is
    /// missed about one time in a thousand.
    ///
    /// The count is a guard on the instrument rather than the claim: it says the sample
    /// still reached enough conversions for the two assertions after it to mean anything.
    /// Six is two and a half standard deviations under sixteen, which fires when the
    /// caller has stopped going for two and not when it went for two a little less often.
    @Test(
        "football · Rule 11-3-1 · a two-point try may be a run, and some of them are",
        .tags(.football))
    func twoPointTriesCanBeRuns() {
        let snapped = TestWorld.resolved(.twoPointRun, count: 200)
        for run in snapped where run.outcome.kind != .penaltyOnly {
            // A flag before the snap wipes the down out and there is no play to be a run,
            // which is why the exit is excluded rather than asserted against.
            #expect(
                run.outcome.kind == .twoPointConversion,
                "a two-point run was recorded as \(run.outcome.kind)")
        }
        #expect(
            snapped.contains { $0.outcome.participants.contains { $0.role == .rusher } },
            "nobody carried the ball on two hundred two-point runs")

        let tries = Self.plays.filter { $0.outcome.kind == .twoPointConversion }
        #expect(tries.count > 6, "only \(tries.count) conversions were attempted")
        let carried = tries.filter { play in
            play.outcome.participants.contains { $0.role == .rusher }
        }
        let thrown = tries.filter { play in
            play.outcome.participants.contains { $0.role == .passer }
        }
        #expect(!carried.isEmpty, "every conversion was a pass: \(tries.count) of them")
        #expect(!thrown.isEmpty, "every conversion was a run: \(tries.count) of them")
    }

    // MARK: - A two-point try the defence takes away

    /// A two-point try the defence intercepts is still the try, and the whole of the
    /// try: it is one scrimmage down (11-3-1), the whistle closes it out whether or not
    /// anybody scored on it (11-3-2-e), and the side that was on defence for it receives
    /// the free kick that follows (11-3-4). So nothing is scored, nothing is replayed, and the ball does
    /// not change hands for the kickoff however far the interceptor carried it — the
    /// side that scored the touchdown kicks off, exactly as it would have after a
    /// conversion or an incompletion.
    ///
    /// Driven through the crude resolver rather than scripted, because the defect this
    /// was written for is the resolver's: it labelled the pick an ordinary pass, and the
    /// rules layer, which reads the kind, then walked the ordinary scrimmage path and
    /// handed the ball to the interceptors for the kickoff.
    @Test(
        "football · Rule 11-3-1, 11-3-2-e, 11-3-4 · a two-point try that is intercepted is still the try, and the side that defended it receives the kickoff",
        .tags(.football)
    )
    func aTwoPointTryThatIsInterceptedIsStillTheTry() {
        let rules = Rules.standard
        let resolutions = TestWorld.resolved(.twoPointPass, count: 2_000)
        let picks = resolutions.filter { $0.outcome.endedIn == .intercepted }
        #expect(
            picks.count >= 20,
            "\(picks.count) intercepted two-point tries in \(resolutions.count): too few to assert on"
        )

        for pick in picks {
            let advancement = rules.advance(from: pick.situation, outcome: pick.outcome)
            #expect(advancement.points == 0, "an intercepted try scored something")
            #expect(advancement.scoring == nil, "an intercepted try was a scoring play")
            #expect(
                advancement.possessionChanged == false,
                "the interceptors were given the ball for the kickoff")
            #expect(advancement.requiresKickoff, "no kickoff was owed after the try")
            #expect(advancement.requiresTry == false, "the try was replayed")
        }
    }

    /// The point of a rule that can be satisfied: sometimes it is, and sometimes it is
    /// not. A conversion rate of zero and one of a hundred are equally wrong.
    @Test("Conversions are sometimes made and sometimes missed", .tags(.unit))
    func conversionsGoBothWays() {
        let tries = Self.plays.filter { $0.outcome.kind == .twoPointConversion }
        #expect(tries.isEmpty == false, "nobody ever went for two")
        #expect(tries.contains { $0.outcome.endedIn == .touchdown }, "no conversion ever succeeded")
        #expect(tries.contains { $0.outcome.endedIn != .touchdown }, "no conversion ever failed")
    }

    /// The scoreboard has to be reconstructible from the stream, because everything above
    /// the engine is a query over it ([ADR-0007]). If the plays say one thing and the
    /// final score says another, one of them is lying.
    ///
    /// Summed from what the record says — the points on the play and who scored them —
    /// and never by running the rules again. This test used to call `Rules.advance` and
    /// `Rules.enforce` on every play to find out what it scored, which proved the rules
    /// agree with themselves and nothing about the stream; `pointsScored` sat on every
    /// record at zero while it passed.
    @Test("The score on the board is the sum of the scoring plays", .tags(.contract))
    func scoreboardMatchesTheStream() {
        for result in Self.sample {
            var home: Int16 = 0
            var away: Int16 = 0
            var scoringPlays = 0

            for play in result.plays {
                guard let scoring = play.outcome.scoring else {
                    #expect(play.outcome.pointsScored == 0, "points on a play that did not score")
                    continue
                }
                scoringPlays += 1
                let points = Int16(play.outcome.pointsScored)
                #expect(points > 0, "a \(scoring) worth nothing")

                // A safety and a return touchdown pay the side that did not have the ball.
                let defensive = scoring == .safety || scoring == .defensiveTouchdown
                let scoredByHome = (play.situation.possession == TeamID(1)) != defensive
                if scoredByHome { home += points } else { away += points }
            }

            #expect(scoringPlays > 0, "game \(result.game): nobody scored")
            #expect(
                home == result.homeScore && away == result.awayScore,
                "stream says \(home)-\(away), scoreboard says \(result.homeScore)-\(result.awayScore)"
            )
        }
    }
}
