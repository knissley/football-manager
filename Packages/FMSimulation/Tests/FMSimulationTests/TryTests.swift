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

    private static func game(seed: UInt64) -> GameResult {
        TestWorld.game(seed: seed, game: GameID(seed))
    }

    private static func plays(_ seeds: ClosedRange<UInt64>) -> [PlayRecord] {
        seeds.flatMap { game(seed: $0).plays }
    }

    /// Rewritten for A7 (#19). This used to assert that *every* try is snapped from
    /// the standard spot, which is wrong football: a flag on the try moves it (2025
    /// rulebook, 11-3-3), and asserting the standard spot regardless is exactly how a
    /// flag that was recorded and never applied stayed invisible. A try that no flag
    /// preceded is snapped from its own yard line; one a flag preceded is not.
    @Test(
        "football · Rule 11-3-1, 11-3-3 · a try is snapped from its own yard line unless a flag on the try moved it",
        .tags(.football)
    )
    func triesAreSnappedFromTheRightSpot() {
        let rules = Rules.standard
        var checked = 0
        var moved = 0
        for plays in (UInt64(1)...30).map({ Self.game(seed: $0).plays }) {
            for (previous, play) in zip(plays, plays.dropFirst()) {
                let standard: UInt8
                switch play.outcome.kind {
                case .extraPoint: standard = rules.extraPointSnapYard
                case .twoPointConversion: standard = rules.twoPointSnapYard
                default: continue
                }
                let flagOnTheTry =
                    previous.outcome.kind == .penaltyOnly
                    && previous.situation.possession == play.situation.possession
                    && previous.calls.offense == play.calls.offense
                if flagOnTheTry {
                    moved += 1
                    #expect(
                        play.situation.ballOn != standard,
                        "a flag on the try left it at the standard spot (play \(play.index))")
                } else {
                    checked += 1
                    #expect(
                        play.situation.ballOn == standard,
                        "a try snapped from the \(play.situation.ballOn) (play \(play.index))")
                }
            }
        }
        #expect(checked > 0, "no tries to check")
        #expect(moved > 0, "thirty games and no flag on a try; the second half of this is unarmed")
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

    /// A two-point try is a scrimmage down like any other, and the sport lets it be a run.
    ///
    /// 2025 rulebook, 11-3-1: the team that scored puts the ball in play 15 yards from the
    /// defence's goal line for a try-kick, or **two yards from it for a try by pass or
    /// run**. Every conversion this engine attempted was a pass, so half the play the rule
    /// describes did not exist — and with it went the heavy grouping a team sends out for
    /// it and the goal-line defence that answers.
    @Test(
        "football · Rule 11-3-1 · a two-point try may be a run, and some of them are",
        .tags(.football))
    func twoPointTriesCanBeRuns() {
        let tries = Self.plays(1...80).filter { $0.outcome.kind == .twoPointConversion }
        #expect(tries.count > 10, "only \(tries.count) conversions were attempted")
        let carried = tries.filter { play in
            play.outcome.participants.contains { $0.role == .rusher }
        }
        let thrown = tries.filter { play in
            play.outcome.participants.contains { $0.role == .passer }
        }
        #expect(!carried.isEmpty, "every conversion was a pass: \(tries.count) of them")
        #expect(!thrown.isEmpty, "every conversion was a run: \(tries.count) of them")

    }

    /// The point of a rule that can be satisfied: sometimes it is, and sometimes it is
    /// not. A conversion rate of zero and one of a hundred are equally wrong.
    @Test("Conversions are sometimes made and sometimes missed", .tags(.unit))
    func conversionsGoBothWays() {
        let tries = Self.plays(1...80).filter { $0.outcome.kind == .twoPointConversion }
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
        for seed in UInt64(1)...20 {
            let result = Self.game(seed: seed)
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

            #expect(scoringPlays > 0, "seed \(seed): nobody scored")
            #expect(
                home == result.homeScore && away == result.awayScore,
                "stream says \(home)-\(away), scoreboard says \(result.homeScore)-\(result.awayScore)"
            )
        }
    }
}
