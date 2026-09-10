import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

// The rules-conformance suite: the acceptance language for the rules layer.
//
// Every scenario these tests run was written from the 2025 rulebook as the
// football-domain skill's `references/game-rules.md` gives it — the citation in each
// test's name is that file's — and never from the code. A scenario says what the sport
// does; whether the engine does it is what the run reports. Scenarios the engine cannot
// satisfy today are red on purpose and stay in the tree until the fix that turns them
// green.
//
// The scenarios themselves are `FMSimulationScenarios`, a plain library, so that a
// play-by-play printer can walk one and a reader can see the football without the
// assertions: `gamelog --scenario <name>` prints any of them. Each test names the
// scenario it runs — `RulesScenario.safetyFreeKick` — and that name is the one the tool
// takes, so the game a reader watches is the game this suite asserts on.
//
// Two conventions the clock scenarios rest on, neither of them a rule. A play's recorded
// situation is the moment the previous play ended, and the offence's tempo — the huddle —
// is charged at the snap when the clock is running, so a play snapped on a running clock
// ends at `clock - huddle - clockRunoff`; the huddle is measured from the game itself,
// never assumed. And a flag before the snap flies when the snap was due: the huddle has
// elapsed, no play time has, and only then does any runoff come off.
//
// Kinds are in the names until the tag helpers land: every test here is `football`
// except the one `pin`, which says so.

// MARK: - The tests

@Suite("Rules conformance")
struct RulesConformanceTests {

    /// The first touchdown from scrimmage in `quarter`, and who scored it.
    private func touchdown(in trace: Trace, quarter: UInt8) -> (index: Int, scorer: TeamID)? {
        guard
            let found = trace.first(where: {
                $0.situation.quarter == quarter && $0.outcome.endedIn == .touchdown
                    && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the script never scored a touchdown from scrimmage in quarter \(quarter)")
            return nil
        }
        return (found.index, found.play.situation.possession)
    }

    /// The first flag before a snap in `quarter`, with the offence's measured tempo.
    private func flag(
        in trace: Trace, quarter: UInt8
    ) -> (index: Int, play: PlayRecord, huddle: UInt16)? {
        guard
            let found = trace.first(where: {
                $0.situation.quarter == quarter && $0.outcome.kind == .penaltyOnly
            })
        else {
            Issue.record("the script never drew a flag before the snap in quarter \(quarter)")
            return nil
        }
        guard let huddle = trace.huddle else {
            Issue.record("the game never showed the offence's tempo")
            return nil
        }
        return (found.index, found.play, huddle)
    }

    /// Whether a postseason game reached `period`: the football fact a scenario about a
    /// later overtime period rests on before it can say anything about that period's
    /// clock.
    private func reachedPeriod(_ period: UInt8, in trace: Trace) -> Bool {
        let reached = trace.plays.contains { $0.situation.quarter == period }
        #expect(
            reached,
            "a postseason game level at the end of a period plays another (16-1-4-d); this one was meant to reach period \(period)"
        )
        return reached
    }

    /// The play a clock walk stretched to end at a particular second of `quarter`: the
    /// first run in it longer than a plod.
    private func stretchedPlay(
        in trace: Trace, quarter: UInt8
    ) -> (index: Int, play: PlayRecord)? {
        guard
            let found = trace.first(where: {
                $0.situation.quarter == quarter && $0.outcome.clockRunoff > 6
                    && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the walk never stretched a play in quarter \(quarter)")
            return nil
        }
        return found
    }

    /// Whether the game reached overtime: the football fact every overtime scenario
    /// needs first, asserted rather than assumed.
    private func reachedOvertime(_ trace: Trace) -> Bool {
        let reached = trace.plays.contains { $0.situation.quarter == 5 }
        #expect(reached, "a game level after four periods goes to overtime")
        return reached
    }

    // MARK: A safety, and what follows a score

    /// The side that conceded the two points puts the ball back in play with a free kick
    /// from its own twenty, and the side that scored receives.
    @Test(
        "football · Rule 11-5-2 · after a safety the team scored upon free-kicks from its 20",
        .tags(.football))
    func afterASafetyTheTeamScoredUponKicks() {
        let trace = RulesScenario.safetyFreeKick.run()
        guard let safety = trace.first(where: { $0.outcome.endedIn == .safety }) else {
            Issue.record("the script never produced a safety")
            return
        }
        let conceded = safety.play.situation.possession
        let scored = trace.opponent(of: conceded)
        trace.expectScore(
            scored, 2, "a safety is two points to the side that did not have the ball")
        trace.expectScore(conceded, 0)
        trace.expectPlay(
            safety.index + 1, kind: .kickoff, possession: conceded, ballOn: 80,
            "the side scored upon free-kicks, from its own 20")
        trace.expectPlay(
            safety.index + 2, kind: .rush, possession: scored,
            "and the side that scored takes the free kick and the ball")
    }

    /// The touchdown, its try, a kickoff by the side that scored, and the other side's
    /// first snap: the order of a score.
    @Test(
        "football · Rule 11-3-4 · after the try the team that defended it receives the kickoff",
        .tags(.football))
    func afterTheTryTheDefendingTeamReceives() {
        let trace = RulesScenario.touchdownTryKickoff.run()
        guard let scorer = trace[1]?.situation.possession else {
            Issue.record("no first snap")
            return
        }
        trace.expectSequence([.kickoff, .rush, .extraPoint, .kickoff, .rush], from: 0)
        trace.expectPlay(2, kind: .extraPoint, possession: scorer, "the side that scored tries")
        trace.expectPlay(3, kind: .kickoff, possession: scorer, "and then kicks off")
        trace.expectPlay(
            4, possession: trace.opponent(of: scorer), "the side that defended the try receives")
        trace.expectScore(scorer, 7)
    }

    @Test(
        "football · Rule 11-4-6 · after a successful field goal the team scored upon receives the kickoff",
        .tags(.football)
    )
    func afterAFieldGoalTheTeamScoredUponReceives() {
        let trace = RulesScenario.fieldGoalThenKickoff.run()
        guard let kick = trace.first(where: { $0.outcome.kind == .fieldGoal }) else {
            Issue.record("the script never kicked a field goal")
            return
        }
        let kicker = kick.play.situation.possession
        trace.expectPlay(kick.index, endedIn: .fieldGoalGood)
        trace.expectScore(kicker, 3, "a field goal is three points")
        trace.expectPlay(
            kick.index + 1, kind: .kickoff, possession: kicker, "the side that scored kicks off")
        trace.expectPlay(
            kick.index + 2, kind: .rush, possession: trace.opponent(of: kicker),
            "and the side scored upon receives")
    }

    /// Filed as A9 (#55): the return is a touchdown for the receiving side, which then
    /// tries and then kicks off, like any other score.
    @Test(
        "football · Rule 11-3-1, 11-3-4 · a kickoff returned for a touchdown gets its try, and the returning team then kicks off",
        .tags(.football)
    )
    func kickoffReturnTouchdownGetsItsTry() {
        let trace = RulesScenario.kickoffReturnTouchdown.run()
        guard let kicker = trace[0]?.situation.possession else {
            Issue.record("no opening kickoff")
            return
        }
        let returner = trace.opponent(of: kicker)
        trace.expectPlay(0, kind: .kickoff, endedIn: .touchdown)
        trace.expectPlay(
            1, kind: .extraPoint, possession: returner, "the try belongs to the side that scored")
        trace.expectPlay(2, kind: .kickoff, possession: returner, "and it then kicks off")
        trace.expectPlay(3, kind: .rush, possession: kicker, "to the side it took the ball from")
        trace.expectScore(returner, 7)
        trace.expectScore(kicker, 0)
    }

    // MARK: A touchdown on the last play of a period

    /// Down seven, the touchdown as time expires leaves the side down one: a successful
    /// try affects the outcome, so it is played, and the kick sends the game on.
    ///
    /// The try is an untimed down of the period the touchdown ended: the period is
    /// extended for it (4-8-2), so its situation reads the same quarter at 0:00.
    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 16-1-3 · a touchdown as the fourth quarter expires, down seven, gets its try in that period at 0:00, and the kick sends the game to overtime",
        .tags(.football)
    )
    func lastPlayTouchdownDownSeven() {
        let trace = RulesScenario.lastPlayTouchdownDownSeven.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectPlay(
            touchdown.index + 1, kind: .extraPoint, possession: touchdown.scorer, quarter: 4,
            clock: 0, "the try is played, as an untimed down of the fourth period")
        trace.expectPlay(
            touchdown.index + 2, kind: .kickoff, quarter: 5, clock: 600,
            "level after the try, a ten-minute overtime period follows")
    }

    /// Down six, the touchdown levels it and the kick wins it: the try is played, and
    /// nothing follows a successful one.
    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the fourth quarter expires, down six, gets its try in that period at 0:00, and the kick wins it",
        .tags(.football)
    )
    func lastPlayTouchdownDownSix() {
        let trace = RulesScenario.lastPlayTouchdownDownSix.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectPlay(
            touchdown.index + 1, kind: .extraPoint, possession: touchdown.scorer, quarter: 4,
            clock: 0, "level after the touchdown, a successful try wins, so it is played")
        trace.expectLastPlay(touchdown.index + 1, "the successful try ends the game")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 7)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 6)
    }

    /// Down eight, the touchdown leaves the side down two, and a two-point try levels
    /// it: a successful try affects the outcome, so it is played.
    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-2-b, 16-1-3 · a touchdown as the fourth quarter expires, down eight, gets a two-point try in that period at 0:00, and the conversion sends the game to overtime",
        .tags(.football)
    )
    func lastPlayTouchdownDownEight() {
        let trace = RulesScenario.lastPlayTouchdownDownEight.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectPlay(
            touchdown.index + 1, kind: .twoPointConversion, possession: touchdown.scorer,
            quarter: 4, clock: 0, "a two-point try can level it, so the try is played")
        trace.expectPlay(
            touchdown.index + 2, kind: .kickoff, quarter: 5, clock: 600,
            "level after the conversion, overtime follows")
    }

    /// Down two, the touchdown puts the side up four with no time left: no successful
    /// try could change who won, so there is none.
    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down two, gets no try because no try could affect the outcome",
        .tags(.football)
    )
    func lastPlayTouchdownDownTwo() {
        let trace = RulesScenario.lastPlayTouchdownDownTwo.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up four with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 6)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 2)
    }

    /// Down nine, the touchdown leaves the side down three: no successful try is worth
    /// three, so none is played and the game ends on the touchdown.
    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down nine, gets no try because no try could affect the outcome",
        .tags(.football)
    )
    func lastPlayTouchdownDownNine() {
        let trace = RulesScenario.lastPlayTouchdownDownNine.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "down three with time expired, the try is waived")
        trace.expectWinner(trace.opponent(of: touchdown.scorer))
        trace.expectScore(touchdown.scorer, 6)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 9)
    }

    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down one, gets no try",
        .tags(.football)
    )
    func lastPlayTouchdownDownOne() {
        let trace = RulesScenario.lastPlayTouchdownDownOne.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up five with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 12)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 7)
    }

    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, level, gets no try",
        .tags(.football))
    func lastPlayTouchdownLevel() {
        let trace = RulesScenario.lastPlayTouchdownLevel.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up six with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 6)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 0)
    }

    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, up one, gets no try",
        .tags(.football))
    func lastPlayTouchdownUpOne() {
        let trace = RulesScenario.lastPlayTouchdownUpOne.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up seven with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 13)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 6)
    }

    /// The half does not end until the try has been played — the period is extended for
    /// it (4-8-2) — and the third quarter then opens with a kickoff and a full clock.
    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the second quarter expires gets its try in that period at 0:00, and the second half then opens with a kickoff",
        .tags(.football)
    )
    func touchdownAsTheSecondQuarterExpires() {
        let trace = RulesScenario.touchdownAsSecondQuarterExpires.run()
        guard let touchdown = touchdown(in: trace, quarter: 2) else { return }
        trace.expectPlay(
            touchdown.index + 1, kind: .extraPoint, possession: touchdown.scorer, quarter: 2,
            clock: 0, "the try is played, as an untimed down of the second period")
        trace.expectPlay(
            touchdown.index + 2, kind: .kickoff, quarter: 3, clock: 900,
            "and the second half then opens with a kickoff")
        trace.expectScore(touchdown.scorer, 7)
    }

    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 11-3-4 · a touchdown as the first quarter expires gets its try in that period at 0:00, and the scoring team kicks off to open the second",
        .tags(.football)
    )
    func touchdownAsTheFirstQuarterExpires() {
        let trace = RulesScenario.touchdownAsFirstQuarterExpires.run()
        guard let touchdown = touchdown(in: trace, quarter: 1) else { return }
        trace.expectPlay(
            touchdown.index + 1, kind: .extraPoint, possession: touchdown.scorer, quarter: 1,
            clock: 0, "the try is played, as an untimed down of the first period")
        trace.expectPlay(
            touchdown.index + 2, kind: .kickoff, possession: touchdown.scorer, quarter: 2,
            clock: 900, "the side that scored kicks off to open the second quarter")
    }

    // MARK: Overtime

    @Test(
        "football · Rule 4-1-1, 16-1-3 · a regular-season game level after four periods goes to one ten-minute overtime period",
        .tags(.football)
    )
    func regulationTieGoesToOvertime() {
        let trace = RulesScenario.scoreless.run()
        guard reachedOvertime(trace),
            let overtime = trace.first(where: { $0.situation.quarter == 5 })
        else { return }
        trace.expectPlay(
            overtime.index, kind: .kickoff, clock: 600,
            "overtime opens with a kickoff and ten minutes on the clock")
    }

    @Test(
        "football · Rule 16-1-3-d · regular-season overtime is never extended: level at the end of it is a tie",
        .tags(.football)
    )
    func regularSeasonOvertimeExpiringLevelIsATie() {
        let trace = RulesScenario.scoreless.run()
        guard reachedOvertime(trace) else { return }
        #expect(
            !trace.plays.contains { $0.situation.quarter >= 6 },
            "one period, and no more")
        trace.expectWinner(nil, "level at the end of the period, the game is a tie")
    }

    @Test(
        "football · Rule 16-1-4, 16-1-4-d · a postseason game level after the fifth period plays a sixth, of fifteen minutes",
        .tags(.football)
    )
    func postseasonPlaysASixthPeriod() {
        let trace = RulesScenario.scorelessPostseasonUntilTheSixthPeriod.run()
        guard reachedOvertime(trace) else { return }
        let sixth = trace.first(where: { $0.situation.quarter == 6 })
        #expect(sixth != nil, "a postseason game level after the fifth period plays a sixth")
        guard let sixth else { return }
        trace.expectPlay(sixth.index, clock: 900, "a postseason overtime period is fifteen minutes")
        guard
            let kick = trace.first(where: {
                $0.situation.quarter == 6 && $0.outcome.kind == .fieldGoal
            })
        else {
            Issue.record("the script meant to kick a field goal in the sixth period")
            return
        }
        trace.expectLastPlay(kick.index, "both sides have possessed, so the next score ends it")
        trace.expectWinner(kick.play.situation.possession)
    }

    /// The side that receives the overtime kickoff scores a touchdown on its first
    /// possession. It still tries, it still kicks off, and the other side still gets
    /// its possession; the game ends when that possession ends without the points.
    @Test(
        "football · Rule 16-1-3-a, 16-1-3-b, 11-3-1 · a touchdown on the first overtime possession gets its try, and the other team then possesses",
        .tags(.football)
    )
    func overtimeFirstPossessionTouchdown() {
        let trace = RulesScenario.overtimeFirstPossessionTouchdown.run()
        guard reachedOvertime(trace), let touchdown = touchdown(in: trace, quarter: 5) else {
            return
        }
        let other = trace.opponent(of: touchdown.scorer)
        trace.expectPlay(
            touchdown.index + 1, kind: .extraPoint, possession: touchdown.scorer, quarter: 5,
            "the try is played: this is not sudden death")
        trace.expectPlay(
            touchdown.index + 2, kind: .kickoff, possession: touchdown.scorer, quarter: 5,
            "the side that scored kicks off")
        trace.expectPlay(
            touchdown.index + 3, kind: .rush, possession: other, quarter: 5,
            "and the other side gets its possession")
        trace.expectWinner(
            touchdown.scorer, "once both have possessed, the side with more points has won")
        #expect(
            trace.plays.last?.situation.possession == other,
            "the game ends when the second possession does")
        trace.expectScore(touchdown.scorer, 7)
        trace.expectScore(other, 0)
    }

    /// Both sides kick a field goal on their first possession, so the game is level
    /// once both have possessed, and the next points of any kind win it.
    @Test(
        "football · Rule 16-1-3-b, 16-1-3-c · once both teams have possessed in overtime, level, the next score of any kind wins",
        .tags(.football)
    )
    func overtimeAfterBothPossessedEndsOnAnyScore() {
        let trace = RulesScenario.overtimeFieldGoalsUntilOneIsUnanswered.run()
        guard reachedOvertime(trace) else { return }
        let kicks = trace.plays.enumerated().filter {
            $0.element.situation.quarter == 5 && $0.element.outcome.kind == .fieldGoal
        }
        guard kicks.count >= 2 else {
            Issue.record("the script meant each side to kick a field goal in overtime")
            return
        }
        let first = kicks[0]
        let second = kicks[1]
        #expect(
            first.element.situation.possession != second.element.situation.possession,
            "each side kicks once")
        trace.expectPlay(
            second.offset + 1, kind: .kickoff, quarter: 5,
            "level once both have possessed, the game goes on")
        guard kicks.count == 3 else {
            Issue.record(
                "the next score should have ended it: \(kicks.count) field goals were kicked")
            return
        }
        trace.expectLastPlay(
            kicks[2].offset, "the third field goal is unanswered and ends the game")
        trace.expectWinner(kicks[2].element.situation.possession)
        trace.expectScore(kicks[2].element.situation.possession, 6)
        trace.expectScore(trace.opponent(of: kicks[2].element.situation.possession), 3)
    }

    /// A kickoff is the receiving team's opportunity to possess, and a kick the kicking
    /// team legally recovers still counts as that opportunity (16-1-5-c): after a field
    /// goal on the opening possession, a muffed kickoff the kickers fall on ends the
    /// game (A.R. 16.2).
    @Test(
        "football · Rule 16-1-3-b, 16-1-5-c, A.R. 16.2 · after a field goal on the opening overtime possession, a kickoff the kicking team recovers ends the game",
        .tags(.football)
    )
    func overtimeKickoffRecoveredByTheKickersEndsIt() {
        let trace = RulesScenario.overtimeKickoffRecoveredByTheKickers.run()
        guard reachedOvertime(trace),
            let kick = trace.first(where: {
                $0.situation.quarter == 5 && $0.outcome.kind == .kickoff
                    && $0.outcome.endedIn == .fumbleRecovered
            })
        else {
            Issue.record("the script meant the kicking team to recover its overtime kickoff")
            return
        }
        let kicker = kick.play.situation.possession
        trace.expectScore(kicker, 3, "the field goal")
        trace.expectLastPlay(kick.index, "the receivers had their opportunity; the game is over")
        trace.expectWinner(kicker)
    }

    /// After the opening-possession field goal the other side's kickoff return is its
    /// opportunity; a return touchdown puts it ahead once both have possessed, so the
    /// game ends on the kick, with no try (A.R. 16.4, 4-8-2-c).
    @Test(
        "football · Rule 16-1-3-b, 16-1-3-c, 16-1-5-c, A.R. 16.4 · after a field goal on the opening overtime possession, a kickoff returned for a touchdown ends the game with no try",
        .tags(.football)
    )
    func overtimeKickoffReturnedForTouchdownEndsIt() {
        let trace = RulesScenario.overtimeKickoffReturnedForTouchdown.run()
        guard reachedOvertime(trace),
            let kick = trace.first(where: {
                $0.situation.quarter == 5 && $0.outcome.kind == .kickoff
                    && $0.outcome.endedIn == .touchdown
            })
        else {
            Issue.record("the script meant the overtime kickoff to be returned for a touchdown")
            return
        }
        let returner = trace.opponent(of: kick.play.situation.possession)
        trace.expectLastPlay(kick.index, "the touchdown decides it; no try in sudden death")
        trace.expectWinner(returner)
        trace.expectScore(returner, 6)
        trace.expectScore(kick.play.situation.possession, 3)
    }

    /// Once both have possessed, a touchdown that leaves the scorer behind is not yet
    /// decisive: its try is played, and the conversion that puts him ahead ends it.
    @Test(
        "football · Rule 16-1-3-b, 16-1-3-c, 4-8-2-c, 11-3-1 · once both have possessed in overtime, a touchdown that leaves the scorer behind gets its try, and the conversion that puts him ahead ends it",
        .tags(.football)
    )
    func overtimeTrailingScorerTryDecides() {
        let trace = RulesScenario.overtimeTrailingScorerGoesForTwo.run()
        guard reachedOvertime(trace) else { return }
        let touchdowns = trace.plays.enumerated().filter {
            $0.element.situation.quarter == 5 && $0.element.outcome.endedIn == .touchdown
                && $0.element.outcome.kind == .rush
        }
        guard touchdowns.count == 2 else {
            Issue.record("the script meant each side to score a touchdown in overtime")
            return
        }
        let answer = touchdowns[1]
        let scorer = answer.element.situation.possession
        #expect(
            answer.element.situation.scoreDifferential == -7, "the answering side trailed by seven")
        trace.expectPlay(
            answer.offset + 1, kind: .twoPointConversion, possession: scorer,
            "behind by one after the touchdown, the try is played")
        trace.expectLastPlay(answer.offset + 1, "the conversion puts the scorer ahead and ends it")
        trace.expectWinner(scorer)
        trace.expectScore(scorer, 8)
        trace.expectScore(trace.opponent(of: scorer), 7)
    }

    @Test(
        "football · Rule 16-1-3-e · each team has two timeouts in regular-season overtime",
        .tags(.football))
    func overtimeTimeoutsAreTwo() {
        let trace = RulesScenario.scoreless.run()
        guard reachedOvertime(trace),
            let opening = trace.first(where: { $0.situation.quarter == 5 })
        else { return }
        #expect(opening.play.situation.offenseTimeouts == 2)
        #expect(opening.play.situation.defenseTimeouts == 2)
    }

    /// A defence that intercepts has thereby possessed, so both sides have had their
    /// turn, and a defensive touchdown on the first possession ends it.
    @Test(
        "football · Rule 16-1-5-b, 16-1-3-b · an interception returned for a touchdown on the first overtime possession ends the game",
        .tags(.football)
    )
    func overtimeDefensiveScoreEndsIt() {
        let trace = RulesScenario.overtimeFirstPossessionInterceptionReturned.run()
        guard reachedOvertime(trace),
            let pick = trace.first(where: {
                $0.situation.quarter == 5 && $0.outcome.endedIn == .intercepted
            })
        else { return }
        let defense = trace.opponent(of: pick.play.situation.possession)
        trace.expectLastPlay(pick.index, "the return touchdown ends the game")
        trace.expectWinner(defense)
        trace.expectScore(defense, 6)
        trace.expectScore(pick.play.situation.possession, 0)
    }

    /// The one exception to each side getting a turn: the side that kicked off scores a
    /// safety against the opening drive and has won on the spot.
    @Test(
        "football · Rule 16-1-3-a · a safety against the opening overtime drive wins it for the team that kicked off",
        .tags(.football)
    )
    func overtimeOpeningDriveSafetyWinsIt() {
        let trace = RulesScenario.overtimeOpeningDriveSafety.run()
        guard reachedOvertime(trace),
            let safety = trace.first(where: {
                $0.situation.quarter == 5 && $0.outcome.endedIn == .safety
            })
        else { return }
        let kicked = trace.opponent(of: safety.play.situation.possession)
        trace.expectLastPlay(safety.index, "the safety ends the game")
        trace.expectWinner(kicked)
        trace.expectScore(kicked, 2)
    }

    // MARK: Postseason overtime halves

    /// The first play of `period`; for a period put back in play with a free kick, the
    /// kickoff.
    private func opening(of period: UInt8, in trace: Trace) -> (index: Int, play: PlayRecord)? {
        guard let found = trace.first(where: { $0.situation.quarter == period }) else {
            Issue.record("the game never reached period \(period)")
            return nil
        }
        return found
    }

    /// The last play of `period`.
    private func closing(of period: UInt8, in trace: Trace) -> PlayRecord? {
        guard let found = trace.plays.last(where: { $0.situation.quarter == period }) else {
            Issue.record("the game never reached period \(period)")
            return nil
        }
        return found
    }

    /// The timeouts each side has at a snap, read off the situation whichever side has
    /// the ball.
    private func timeouts(at situation: Situation, in trace: Trace) -> (home: UInt8, away: UInt8) {
        situation.possession == trace.home
            ? (situation.offenseTimeouts, situation.defenseTimeouts)
            : (situation.defenseTimeouts, situation.offenseTimeouts)
    }

    /// The toss before overtime is not drawn: the side that kicks off to open it stands
    /// for the captain who lost, and 16-1-4-e gives that captain the first choice of
    /// 4-2-2's privileges at the third period — receive or kick. Receiving, the other
    /// side kicks off to it from its own 35, and the touchback puts the ball at its 30.
    @Test(
        "football · Rule 16-1-4-e, 4-2-2 · a postseason game level after two overtime periods opens the third with a kickoff, the captain who lost the toss before overtime having the first choice and electing to receive",
        .tags(.football)
    )
    func thirdPostseasonOvertimePeriodOpensWithAKickoff() {
        let trace = RulesScenario.thirdPostseasonOvertimePeriod.run()
        guard reachedPeriod(7, in: trace), let overtimeKick = opening(of: 5, in: trace),
            let third = opening(of: 7, in: trace)
        else { return }
        trace.expectPlay(
            overtimeKick.index, kind: .kickoff, quarter: 5, clock: 900,
            "overtime opened with a kickoff, and the side that kicked it stands for the captain who lost the toss"
        )
        let tossLoser = overtimeKick.play.situation.possession
        trace.expectPlay(
            third.index, kind: .kickoff, possession: trace.opponent(of: tossLoser), quarter: 7,
            clock: 900, ballOn: 65,
            "the third period is put back in play with a free kick from the 35, by the side the toss loser elected to receive from"
        )
        trace.expectPlay(
            third.index + 1, possession: tossLoser, quarter: 7, clock: 900, down: .first,
            distance: 10, ballOn: 70,
            "and the toss loser has it, first and ten at its 30 after the touchback, with no time gone"
        )
    }

    /// The other boundary of the same half: a first overtime period ends as a first or
    /// third quarter does. The teams change goals and play on from where the ball lay,
    /// which in a plod is a yard on and a down later — or, on a fourth down, the other
    /// side's ball where the plod was stopped.
    @Test(
        "football · Rule 16-1-4-f, 4-2-3 · at the end of a first postseason overtime period the teams change goals and play on: possession, the down, the ball and the line to gain are unchanged, and no kick is made",
        .tags(.football)
    )
    func secondPostseasonOvertimePeriodCarriesOn() {
        let trace = RulesScenario.thirdPostseasonOvertimePeriod.run()
        guard reachedPeriod(6, in: trace), let second = opening(of: 6, in: trace),
            let last = trace[second.index - 1]
        else { return }
        let before = last.situation
        #expect(
            last.outcome.kind == .rush && last.outcome.yards == 1 && before.quarter == 5,
            "the scenario meant the first overtime period to end on a plod")
        #expect(second.play.outcome.kind != .kickoff, "no kick opens a second overtime period")
        if before.down == .fourth {
            trace.expectPlay(
                second.index, possession: trace.opponent(of: before.possession), quarter: 6,
                clock: 900, down: .first, distance: 10, ballOn: 100 - (before.ballOn - 1),
                "the plod fell short on fourth down, so the other side has it where the runner was stopped"
            )
        } else {
            trace.expectPlay(
                second.index, possession: before.possession, quarter: 6, clock: 900,
                down: before.down.next, distance: before.distance - 1, ballOn: before.ballOn - 1,
                "the same side has it, a yard on and a down later, with the line to gain where it was"
            )
        }
    }

    /// Three timeouts in each half, and 16-1-4-e, f and h make a half two overtime
    /// periods. A side that spent its three in the first two periods has three again as
    /// the third opens; a side that spent none has three, not six.
    @Test(
        "football · Rule 16-1-4-g · each team has three timeouts in each postseason overtime half: a side that spent its three across the first and second overtime periods has three again when the third opens, and a side that spent none still has three",
        .tags(.football)
    )
    func postseasonOvertimeTimeoutsAreThreePerHalf() {
        let trace = RulesScenario.thirdPostseasonOvertimePeriod.run()
        guard reachedPeriod(7, in: trace), let first = opening(of: 5, in: trace),
            let closing = closing(of: 6, in: trace), let third = opening(of: 7, in: trace)
        else { return }
        let atTheStart = timeouts(at: first.play.situation, in: trace)
        #expect(atTheStart.home == 3 && atTheStart.away == 3, "three each for the first half")
        let spent = timeouts(at: closing.situation, in: trace)
        #expect(spent.home == 0, "the scenario meant the home side to spend its three")
        #expect(spent.away == 3, "and the away side none")
        let renewed = timeouts(at: third.play.situation, in: trace)
        #expect(renewed.home == 3, "three again for the new half")
        #expect(renewed.away == 3, "three, not six: a half's timeouts do not carry over")
    }

    /// The privilege is a choice, and the other answer is a kick (4-2-2-a).
    @Test(
        "football · Rule 16-1-4-e, 4-2-2-a · the captain with the first choice at a third postseason overtime period may elect to kick off, and then kicks off",
        .tags(.football)
    )
    func tossLoserMayElectToKickOffAThirdPostseasonOvertimePeriod() {
        let trace = RulesScenario.thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff.run()
        guard reachedPeriod(7, in: trace), let overtimeKick = opening(of: 5, in: trace),
            let third = opening(of: 7, in: trace)
        else { return }
        let tossLoser = overtimeKick.play.situation.possession
        trace.expectPlay(
            third.index, kind: .kickoff, possession: tossLoser, quarter: 7, clock: 900,
            ballOn: 65, "the toss loser elected to kick off, and does")
    }

    /// The toss after a fourth period starts the pairing over: a fifth period opens as
    /// the first did, with a kick, and with a half's timeouts.
    @Test(
        "football · Rule 16-1-4-i, 16-1-2, 4-2-2, 16-1-4-g · at the end of a fourth postseason overtime period the coin is tossed again, so a fifth is put back in play with a kickoff and each side has three timeouts for the half it opens",
        .tags(.football)
    )
    func fifthPostseasonOvertimePeriodOpensWithAKickoff() {
        let trace = RulesScenario.fifthPostseasonOvertimePeriod.run()
        guard reachedPeriod(9, in: trace), let third = opening(of: 7, in: trace),
            let fourth = opening(of: 8, in: trace), let closing = closing(of: 8, in: trace),
            let fifth = opening(of: 9, in: trace)
        else { return }
        trace.expectPlay(third.index, kind: .kickoff, quarter: 7, clock: 900)
        #expect(fourth.play.outcome.kind != .kickoff, "no kick opens a fourth overtime period")
        let spent = timeouts(at: closing.situation, in: trace)
        #expect(spent.home == 0, "the scenario meant the home side to spend its three")
        trace.expectPlay(
            fifth.index, kind: .kickoff, quarter: 9, clock: 900, ballOn: 65,
            "the toss is followed by a kickoff from the 35")
        let renewed = timeouts(at: fifth.play.situation, in: trace)
        #expect(renewed.home == 3 && renewed.away == 3, "three each for the new half")
    }

    /// Which side kicks off after that toss is not the book's to say and not drawn
    /// here: the engine keeps the side with the ball at the end of the fourth period as
    /// the kicker, as it does at the first overtime period, and that side stands for
    /// the toss loser two periods on.
    @Test(
        "pin · the toss before a fifth postseason overtime period (16-1-4-i) is not drawn: as at the first, the side with the ball at the end of the period before kicks off and stands for the captain who lost it",
        .tags(.pin)
    )
    func fifthPostseasonOvertimePeriodKickerIsTheSideThatHadTheBall() {
        let trace = RulesScenario.fifthPostseasonOvertimePeriod.run()
        guard reachedPeriod(9, in: trace), let closing = closing(of: 8, in: trace),
            let fifth = opening(of: 9, in: trace)
        else { return }
        let hadTheBall =
            closing.situation.down == .fourth
            ? trace.opponent(of: closing.situation.possession) : closing.situation.possession
        trace.expectPlay(
            fifth.index, kind: .kickoff, possession: hadTheBall, quarter: 9,
            "the side with the ball at the end of the fourth overtime period kicks off the fifth")
    }

    // MARK: The clock

    /// The fourth-down stop is a change of possession: the clock stops when the play
    /// ends and does not start again until the new offence snaps, so that offence's
    /// huddle costs it nothing.
    @Test(
        "football · Rule 4-4-i, 4-3-2-a-1 · a turnover on downs stops the clock until the snap",
        .tags(.football))
    func turnoverOnDownsStopsTheClock() {
        let trace = RulesScenario.scoreless.run()
        guard
            let stop = trace.first(where: {
                $0.situation.down == .fourth && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the script never reached fourth down")
            return
        }
        let before = stop.play.situation
        trace.expectPlay(
            stop.index + 1, possession: trace.opponent(of: before.possession), down: .first,
            clockRunning: false, "the ball changes hands on downs, and the clock is dead")
        guard let next = trace[stop.index + 1] else { return }
        trace.expectPlay(
            stop.index + 2, clock: next.situation.clockRemaining - 6,
            "the new offence's first snap costs only the play's own six seconds")
    }

    @Test(
        "football · Rule 4-4-i, 4-3-2-a-1 · a punt returned and tackled in bounds stops the clock until the snap",
        .tags(.football)
    )
    func puntReturnedAndTackledStopsTheClock() {
        let trace = RulesScenario.puntReturnedAndTackled.run()
        guard let punt = trace.first(where: { $0.outcome.kind == .punt }) else {
            Issue.record("the script never punted")
            return
        }
        let before = punt.play.situation
        trace.expectPlay(
            punt.index + 1, possession: trace.opponent(of: before.possession), down: .first,
            ballOn: 70, clockRunning: false,
            "the receiving side takes over at its own 30 with the clock dead")
        guard let next = trace[punt.index + 1] else { return }
        trace.expectPlay(
            punt.index + 2, clock: next.situation.clockRemaining - 6,
            "the new offence's first snap costs only the play's own six seconds")
    }

    /// A fumble the offence falls on in the field of play is not among the stoppages:
    /// the ball is dead by a tackle, and the clock runs on through the huddle.
    @Test(
        "football · Rule 4-4 · a fumble recovered by the offence keeps the clock running",
        .tags(.football))
    func fumbleRecoveredByTheOffenseKeepsTheClockRunning() {
        let trace = RulesScenario.fumbleRecoveredByTheOffense.run()
        guard let fumble = trace[1], let next = trace[2] else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(
            2, possession: fumble.situation.possession, down: .second, distance: 7,
            clockRunning: true, "the offence keeps the ball, three yards on, with the clock running"
        )
        #expect(
            (trace[3]?.situation.clockRemaining ?? 0) < next.situation.clockRemaining - 6,
            "the huddle came off the clock as well as the play")
    }

    @Test(
        "football · Rule 4-4-i, 4-3-2-a-1 · a fumble recovered by the defence stops the clock until the snap",
        .tags(.football)
    )
    func fumbleRecoveredByTheDefenseStopsTheClock() {
        let trace = RulesScenario.fumbleRecoveredByTheDefense.run()
        guard let fumble = trace[1], let next = trace[2] else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(
            2, possession: trace.opponent(of: fumble.situation.possession), down: .first,
            clockRunning: false, "the defence has the ball, and the clock is dead")
        trace.expectPlay(
            3, clock: next.situation.clockRemaining - 6,
            "the new offence's first snap costs only the play's own six seconds")
    }

    /// Filed with A4 (#17): the clock starts when the kick is legally touched in the
    /// field of play, so a return costs the returning side the seconds it ran; the
    /// return is a change of possession, so the clock then waits for the snap.
    @Test(
        "football · Rule 4-4-a, 4-3-1, 4-4-i · a returned kickoff advances the game clock by the return, and no more",
        .tags(.football)
    )
    func returnedKickoffAdvancesTheClock() {
        let trace = RulesScenario.kickoffReturned.run()
        guard let kicker = trace[0]?.situation.possession else {
            Issue.record("no opening kickoff")
            return
        }
        trace.expectPlay(
            1, possession: trace.opponent(of: kicker), ballOn: 75, "brought out to the 25")
        trace.expectPlay(
            1, clock: 900 - 8, clockRunning: false,
            "the eight seconds of the return come off, and the clock waits for the snap")
        trace.expectPlay(2, clock: 900 - 8 - 6, "the first snap costs only its own six seconds")
    }

    @Test("football · Rule 4-3-1-c · a fair-caught kickoff starts no clock", .tags(.football))
    func fairCaughtKickoffStartsNoClock() {
        let trace = RulesScenario.kickoffFairCaught.run()
        trace.expectPlay(0, kind: .kickoff, endedIn: .fairCatch)
        trace.expectPlay(
            1, clock: 900, clockRunning: false,
            "the clock does not start on a fair catch, and waits for the snap")
    }

    /// The kicking team recovering its kick before any other legal touching is one of
    /// the cases in which the clock does not start on a free kick; it then starts on
    /// the next snap (4-3-2).
    @Test(
        "football · Rule 4-3-1-b, 4-3-2 · a kickoff the kicking team recovers starts no clock, and the clock waits for the snap",
        .tags(.football)
    )
    func kickoffRecoveredByTheKickersStartsNoClock() {
        let trace = RulesScenario.onsideKickRecovered.run()
        guard
            let onside = trace.first(where: {
                $0.outcome.kind == .kickoff && $0.outcome.endedIn == .fumbleRecovered
            })
        else {
            Issue.record("the trailing side never recovered an onside kick")
            return
        }
        trace.expectPlay(
            onside.index + 1, clock: onside.play.situation.clockRemaining, clockRunning: false,
            "no clock ran on the kick, and it waits for the snap")
    }

    @Test("football · Rule 4-3-1, 4-4-d · a kickoff touchback consumes no time", .tags(.football))
    func touchbackConsumesNoTime() {
        let trace = RulesScenario.scoreless.run()
        trace.expectPlay(0, kind: .kickoff, endedIn: .touchback)
        trace.expectPlay(
            1, clock: 900, clockRunning: false,
            "nothing was touched in the field of play, so no clock ran, and it waits for the snap")
    }

    /// A play ends at 2:01 with the clock running. The clock reaches 2:00 between
    /// downs, the warning stops it there, and the snap that follows restarts it: the
    /// offence's huddle costs one second rather than its whole tempo.
    @Test(
        "football · Rule 3-41, 4-4-h · the two-minute warning stops a running clock at exactly 2:00 and the snap restarts it",
        .tags(.football)
    )
    func twoMinuteWarningStopsAtTwoMinutes() {
        let trace = RulesScenario.playEndingJustBeforeTheTwoMinuteWarning.run()
        guard
            let stretched = trace.first(where: {
                $0.situation.quarter == 4 && $0.outcome.clockRunoff > 6 && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the walk never stretched a fourth-quarter play")
            return
        }
        trace.expectPlay(
            stretched.index + 1, quarter: 4, clock: 121, clockRunning: true,
            "the play ended at 2:01 with the clock running")
        guard let next = trace[stretched.index + 1] else { return }
        trace.expectPlay(
            stretched.index + 2, quarter: 4, clock: 120 - next.outcome.clockRunoff,
            "the huddle was cut at 2:00: the snap came at the warning, and only the play ran")
    }

    /// The clock runs past 2:00 during a play: that down finishes, and only then is the
    /// clock dead — at whatever it reads.
    @Test(
        "football · Rule 3-41 · a down under way when the clock runs past 2:00 finishes, and the clock is dead after it",
        .tags(.football)
    )
    func downUnderWayAtTwoMinutesFinishes() {
        let trace = RulesScenario.playRunningPastTheTwoMinuteWarning.run()
        guard
            let stretched = trace.first(where: {
                $0.situation.quarter == 2 && $0.outcome.clockRunoff > 6 && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the walk never stretched a second-quarter play")
            return
        }
        trace.expectPlay(
            stretched.index + 1, quarter: 2, clock: 117, clockRunning: false,
            "the down finished at 1:57, and the clock is dead from there until the snap")
        trace.expectPlay(
            stretched.index + 2, quarter: 2, clock: 117 - 6,
            "the snap at 1:57 costs only the play's own six seconds")
    }

    /// Filed as A11 (#74). Regular-season overtime is timed as the fourth quarter
    /// (16-1-3-e), and the warning is the first of the fourth quarter's timing rules
    /// (3-41): until this landed the overtime clock ran through 2:00.
    @Test(
        "football · Rule 3-41, 16-1-3-e · the two-minute warning stops a running clock at exactly 2:00 of a regular-season overtime period, and the snap restarts it",
        .tags(.football)
    )
    func twoMinuteWarningStopsAtTwoMinutesOfOvertime() {
        let trace = RulesScenario.playEndingJustBeforeTheTwoMinuteWarningOfOvertime.run()
        guard reachedOvertime(trace), let stretched = stretchedPlay(in: trace, quarter: 5) else {
            return
        }
        trace.expectPlay(
            stretched.index + 1, quarter: 5, clock: 121, clockRunning: true,
            "the play ended at 2:01 of overtime with the clock running")
        guard let next = trace[stretched.index + 1] else { return }
        trace.expectPlay(
            stretched.index + 2, quarter: 5, clock: 120 - next.outcome.clockRunoff,
            "the huddle was cut at 2:00: the snap came at the warning, and only the play ran")
    }

    @Test(
        "football · Rule 3-41, 16-1-3-e · a down under way when the clock runs past 2:00 of a regular-season overtime period finishes, and the clock is dead after it",
        .tags(.football)
    )
    func downUnderWayAtTwoMinutesOfOvertimeFinishes() {
        let trace = RulesScenario.playRunningPastTheTwoMinuteWarningOfOvertime.run()
        guard reachedOvertime(trace), let stretched = stretchedPlay(in: trace, quarter: 5) else {
            return
        }
        trace.expectPlay(
            stretched.index + 1, quarter: 5, clock: 117, clockRunning: false,
            "the down finished at 1:57 of overtime, and the clock is dead from there until the snap"
        )
        trace.expectPlay(
            stretched.index + 2, quarter: 5, clock: 117 - 6,
            "the snap at 1:57 costs only the play's own six seconds")
    }

    /// Postseason overtime pairs its periods into halves, and a half's closing rules
    /// belong to the second period of the pair (16-1-4-h): a first overtime period is a
    /// first period, and the warning (3-41) is not in it.
    @Test(
        "football · Rule 16-1-4-h, 3-41 · a first postseason overtime period is timed as a first period: the clock runs through 2:00 with nothing to stop it",
        .tags(.football)
    )
    func firstPostseasonOvertimePeriodHasNoWarning() {
        let trace = RulesScenario.playEndingAtTwoMinutesOfAFirstPostseasonOvertimePeriod.run()
        guard reachedPeriod(5, in: trace), let stretched = stretchedPlay(in: trace, quarter: 5)
        else { return }
        guard let huddle = trace.huddle else {
            Issue.record("the game never showed the offence's tempo")
            return
        }
        trace.expectPlay(
            stretched.index + 1, quarter: 5, clock: 121, clockRunning: true,
            "the play ended at 2:01 with the clock running")
        guard let next = trace[stretched.index + 1] else { return }
        trace.expectPlay(
            stretched.index + 2, quarter: 5, clock: 121 - huddle - next.outcome.clockRunoff,
            "no warning: the whole huddle came off the clock, and then the play")
    }

    @Test(
        "football · Rule 16-1-4-h, 3-41 · a second postseason overtime period ends as the first half does: the warning stops a running clock at exactly 2:00, and the snap restarts it",
        .tags(.football)
    )
    func secondPostseasonOvertimePeriodHasTheFirstHalfsWarning() {
        let trace = RulesScenario
            .playEndingJustBeforeTheTwoMinuteWarningOfASecondPostseasonOvertimePeriod.run()
        guard reachedPeriod(6, in: trace), let stretched = stretchedPlay(in: trace, quarter: 6)
        else { return }
        trace.expectPlay(
            stretched.index + 1, quarter: 6, clock: 121, clockRunning: true,
            "the play ended at 2:01 of the second overtime period with the clock running")
        guard let next = trace[stretched.index + 1] else { return }
        trace.expectPlay(
            stretched.index + 2, quarter: 6, clock: 120 - next.outcome.clockRunoff,
            "the huddle was cut at 2:00: the snap came at the warning, and only the play ran")
    }

    /// The first runner out of bounds in `quarter`, with the offence's measured tempo.
    private func outOfBounds(
        in trace: Trace, quarter: UInt8
    ) -> (index: Int, play: PlayRecord, huddle: UInt16)? {
        guard
            let found = trace.first(where: {
                $0.situation.quarter == quarter && $0.outcome.endedIn == .outOfBounds
            })
        else {
            Issue.record("the script never sent a runner out of bounds in quarter \(quarter)")
            return nil
        }
        guard let huddle = trace.huddle else {
            Issue.record("the game never showed the offence's tempo")
            return nil
        }
        return (found.index, found.play, huddle)
    }

    /// The out-of-bounds windows are asymmetric, two minutes in the first half and five
    /// in the second (4-3-2-a), and 16-1-4-h gives a second postseason overtime period
    /// the first half's: inside its last five minutes but outside two, the clock
    /// restarts on the ready-for-play signal.
    @Test(
        "football · Rule 16-1-4-h, 4-3-2-a · a second postseason overtime period carries the first half's two-minute window, so a runner out of bounds inside its last five minutes but outside two stops the clock only until the ball is ready",
        .tags(.football)
    )
    func outOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriodRestartsOnTheReady() {
        let trace = RulesScenario
            .runnerOutOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriod.run()
        guard reachedPeriod(6, in: trace), let out = outOfBounds(in: trace, quarter: 6) else {
            return
        }
        let before = out.play.situation
        #expect(
            before.clockRemaining <= 300 && before.clockRemaining - out.huddle - 6 > 120,
            "the scenario meant the runner out inside five minutes and outside two")
        trace.expectPlay(
            out.index + 1, quarter: 6, clock: before.clockRemaining - out.huddle - 6,
            clockRunning: true,
            "the huddle and the play came off, and the clock restarts on the ready: it runs into the next snap"
        )
        guard let next = trace[out.index + 1], let after = trace[out.index + 2] else {
            Issue.record("no play after the one that followed the runner out of bounds")
            return
        }
        #expect(
            after.situation.clockRemaining < next.situation.clockRemaining - 6,
            "the next huddle came off the clock as well as the play")
    }

    /// The other half of the same asymmetry: a fourth postseason overtime period ends
    /// as the fourth period does, with the five-minute window, so inside it the clock
    /// waits for the snap.
    @Test(
        "football · Rule 16-1-4-h, 4-3-2-a · a fourth postseason overtime period carries the fourth period's five-minute window, so a runner out of bounds inside its last five minutes stops the clock until the snap",
        .tags(.football)
    )
    func outOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriodWaitsForTheSnap() {
        let trace = RulesScenario
            .runnerOutOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriod.run()
        guard reachedPeriod(8, in: trace), let out = outOfBounds(in: trace, quarter: 8) else {
            return
        }
        let before = out.play.situation
        #expect(
            before.clockRemaining <= 300, "the scenario meant the runner out inside five minutes")
        trace.expectPlay(
            out.index + 1, quarter: 8, clock: before.clockRemaining - out.huddle - 6,
            clockRunning: false,
            "the huddle and the play came off, and the clock is dead until the snap")
        guard let next = trace[out.index + 1] else { return }
        trace.expectPlay(
            out.index + 2, quarter: 8, clock: next.situation.clockRemaining - 6,
            "the next snap costs only the play's own six seconds")
    }

    /// The fourth quarter's own window: inside the last five minutes of the second
    /// half a runner out of bounds stops the clock until the snap (4-3-2-a-3), here on a
    /// play that begins and ends inside them, so that nothing turns on where the window
    /// is judged.
    @Test(
        "football · Rule 4-3-2-a-3, 4-4-c · a runner out of bounds on a play snapped inside the last five minutes of the fourth quarter stops the clock until the snap",
        .tags(.football)
    )
    func outOfBoundsInsideFiveMinutesOfTheFourthQuarterWaitsForTheSnap() {
        let trace = RulesScenario.runnerOutOfBoundsInsideFiveMinutesOfTheFourthQuarter.run()
        guard let out = outOfBounds(in: trace, quarter: 4) else { return }
        let before = out.play.situation
        #expect(
            before.clockRemaining <= 300, "the scenario meant the runner out inside five minutes")
        trace.expectPlay(
            out.index + 1, quarter: 4, clock: before.clockRemaining - out.huddle - 6,
            clockRunning: false,
            "the huddle and the play came off, and the clock is dead until the snap")
        guard let next = trace[out.index + 1] else { return }
        trace.expectPlay(
            out.index + 2, quarter: 4, clock: next.situation.clockRemaining - 6,
            "the next snap costs only the play's own six seconds")
    }

    /// Where the window is judged. The article's words are "inside the last five
    /// minutes of the second half" (4-3-2-a-3), and a runner is inside them when he
    /// steps out at 4:50 on a play snapped at 5:07: the clock is read where the ball
    /// became dead. Read where the play *before* ended — up to a huddle and a play
    /// earlier — the same runner is outside the window, and the clock restarts on the
    /// ready when the book has it wait for the snap.
    @Test(
        "football · Rule 4-3-2-a-3, 4-4-c · a runner out of bounds inside the last five minutes of the fourth quarter, on a play snapped with more than five minutes left, stops the clock until the snap: the window is judged where the ball became dead",
        .tags(.football)
    )
    func outOfBoundsAcrossFiveMinutesOfTheFourthQuarterWaitsForTheSnap() {
        let trace = RulesScenario.runnerOutOfBoundsAcrossFiveMinutesOfTheFourthQuarter.run()
        guard let out = outOfBounds(in: trace, quarter: 4) else { return }
        let before = out.play.situation
        let running = trace.clockRunning(into: out.index) == true
        let snapped = Int(before.clockRemaining) - (running ? Int(out.huddle) : 0)
        let dead = snapped - Int(out.play.outcome.clockRunoff)
        #expect(
            snapped > 300, "the scenario meant the play snapped with more than five minutes left")
        #expect(dead < 300 && dead > 120, "and the runner out of bounds inside them")
        trace.expectPlay(
            out.index + 1, quarter: 4, clock: UInt16(dead), clockRunning: false,
            "the runner went out inside five minutes: the clock is dead until the snap")
        guard let next = trace[out.index + 1] else { return }
        trace.expectPlay(
            out.index + 2, quarter: 4,
            clock: next.situation.clockRemaining - next.outcome.clockRunoff,
            "the next snap costs only the play's own seconds, and no huddle")
    }

    /// The first half's window is "after the two-minute warning" (4-3-2-a-2), and the
    /// warning is taken at the conclusion of the last down snapped before 2:00 (3-41).
    /// A runner who steps out at 1:50 on a play snapped at 2:07 concludes that down: the
    /// warning stops the clock there (4-4-h), and the snap restarts it — the same answer
    /// the window gives when it is judged where the ball became dead.
    @Test(
        "football · Rule 4-3-2-a-2, 3-41, 4-4-h · a runner out of bounds after the two-minute warning of the second quarter, on a play snapped before it, stops the clock until the snap: the warning is taken as that down ends",
        .tags(.football)
    )
    func outOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarterWaitsForTheSnap() {
        let trace = RulesScenario.runnerOutOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarter
            .run()
        guard let out = outOfBounds(in: trace, quarter: 2) else { return }
        let before = out.play.situation
        let running = trace.clockRunning(into: out.index) == true
        let snapped = Int(before.clockRemaining) - (running ? Int(out.huddle) : 0)
        let dead = snapped - Int(out.play.outcome.clockRunoff)
        #expect(snapped > 120, "the scenario meant the play snapped before the warning")
        #expect(dead < 120, "and the runner out of bounds after it")
        trace.expectPlay(
            out.index + 1, quarter: 2, clock: UInt16(dead), clockRunning: false,
            "the down that crossed 2:00 is over, the warning is taken, and the clock is dead until the snap"
        )
        guard let next = trace[out.index + 1] else { return }
        trace.expectPlay(
            out.index + 2, quarter: 2,
            clock: next.situation.clockRemaining - next.outcome.clockRunoff,
            "the next snap costs only the play's own seconds, and no huddle")
    }

    // MARK: The ten-second runoff

    /// Inside two minutes with the clock running, a false start costs the offence ten
    /// seconds on top of the five yards, and the clock then starts on the ready-for-play
    /// signal rather than waiting for the snap. Filed with A5 (#32).
    @Test(
        "football · Rule 4-7-1 Item 1 · inside two minutes a false start with the clock running costs ten seconds, and the clock restarts on the ready",
        .tags(.football)
    )
    func falseStartInsideTwoMinutesCostsTenSeconds() {
        let trace = RulesScenario.falseStartInsideTwoMinutes.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(
            before.clockRemaining < 120, "the scenario meant the flag to fly inside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, down: before.down,
            distance: before.distance + 5, ballOn: before.ballOn + 5, "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle - 10, clockRunning: true,
            "the huddle, then ten seconds, and the clock restarts on the ready, not the snap")
    }

    /// Rewritten from 4-3-2-e (wave 1 review). This scenario used to run in the fourth
    /// quarter and assert that the clock restarts on the ready-for-play signal after
    /// the flag, which is wrong football there: an offensive foul during the fourth
    /// period that stops the clock before a snap has the clock start on the snap
    /// (4-3-2-e-3). The as-if-never-flown restart holds outside the late-game cases, so
    /// this case moves to the third quarter, and the fourth-quarter case follows it.
    @Test(
        "football · Rule 4-7-1, 4-4-e, 4-3-2-e · outside the late-game windows a false start with the clock running carries no runoff, and the clock restarts as if the foul had not occurred",
        .tags(.football)
    )
    func falseStartInTheThirdQuarterCostsNoTime() {
        let trace = RulesScenario.falseStartInTheThirdQuarter.run()
        guard let flag = flag(in: trace, quarter: 3) else { return }
        let before = flag.play.situation
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: true,
            "the huddle and nothing else: no play happened, and the clock restarts on the ready as though the flag had never flown"
        )
    }

    /// An offensive foul that stops the clock before a snap in the fourth period has
    /// the clock start on the snap, wherever in the period it comes.
    @Test(
        "football · Rule 4-3-2-e-3, 4-4-e · an offensive foul before the snap in the fourth quarter costs the huddle and nothing else, and the clock then starts on the snap",
        .tags(.football)
    )
    func offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap() {
        let trace = RulesScenario.falseStartInTheFourthQuarterOutsideTwoMinutes.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(
            before.clockRemaining > 120, "the scenario meant the flag to fly outside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down, no runoff outside two minutes")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: false,
            "the huddle and nothing else, and the clock waits for the snap")
    }

    /// Fourth-quarter timing rules apply in regular-season overtime (16-1-3-e), the
    /// runoff among them.
    @Test(
        "football · Rule 16-1-3-e, 4-7-1 Item 1 · inside two minutes of regular-season overtime a false start with the clock running carries the runoff, and the clock restarts on the ready",
        .tags(.football)
    )
    func falseStartInsideTwoMinutesOfOvertimeCostsTenSeconds() {
        let trace = RulesScenario.falseStartInsideTwoMinutesOfOvertime.run()
        guard reachedOvertime(trace), let flag = flag(in: trace, quarter: 5) else { return }
        let before = flag.play.situation
        #expect(
            before.clockRemaining < 120, "the scenario meant the flag to fly inside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle - 10, clockRunning: true,
            "the huddle, then ten seconds, and the clock restarts on the ready")
    }

    /// Fourth-period timing applies in regular-season overtime (16-1-3-e), so the
    /// offence's foul before the snap has the clock start on the snap there (4-3-2-e-3)
    /// as it does in the fourth quarter — outside every window, where nothing else
    /// would.
    @Test(
        "football · Rule 4-3-2-e-3, 16-1-3-e · an offensive foul before the snap in regular-season overtime, outside every window, costs the huddle and nothing else, and the clock then starts on the snap",
        .tags(.football)
    )
    func offensiveFoulInOvertimeStartsTheClockOnTheSnap() {
        let trace = RulesScenario.falseStartInOvertimeOutsideTwoMinutes.run()
        guard reachedOvertime(trace), let flag = flag(in: trace, quarter: 5) else { return }
        let before = flag.play.situation
        #expect(
            Int(before.clockRemaining) - Int(flag.huddle) > 300,
            "the scenario meant the flag to fly outside every window")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down, no runoff outside two minutes")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: false,
            "the huddle and nothing else, and the clock waits for the snap")
    }

    /// A second postseason overtime period ends as the first half does (16-1-4-h), and
    /// after the first half's warning the runoff applies (4-7-1).
    @Test(
        "football · Rule 16-1-4-h, 4-7-1 Item 1 · inside two minutes of a second postseason overtime period a false start with the clock running carries the runoff, and the clock restarts on the ready",
        .tags(.football)
    )
    func falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriodCostsTenSeconds() {
        let trace = RulesScenario.falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod
            .run()
        guard reachedPeriod(6, in: trace), let flag = flag(in: trace, quarter: 6) else { return }
        let before = flag.play.situation
        #expect(
            before.clockRemaining < 120, "the scenario meant the flag to fly inside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle - 10, clockRunning: true,
            "the huddle, then ten seconds, and the clock restarts on the ready")
    }

    /// 4-3-2-e-3 names its periods: the fourth, and regular-season overtime. What
    /// 16-1-4-h lends postseason overtime is a half's closing rules, and a first
    /// overtime period is a first period with none, so the offence's flag there
    /// restarts the clock as any foul does outside the late windows (4-3-2-e).
    @Test(
        "football · Rule 4-3-2-e-3, 16-1-4-h · an offensive foul before the snap in a first postseason overtime period, outside every window, restarts the clock on the ready as though the flag had never flown, because 4-3-2-e-3 names the fourth period and regular-season overtime only",
        .tags(.football)
    )
    func offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady() {
        let trace = RulesScenario.falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes
            .run()
        guard reachedPeriod(5, in: trace), let flag = flag(in: trace, quarter: 5) else { return }
        let before = flag.play.situation
        #expect(
            Int(before.clockRemaining) - Int(flag.huddle) > 300,
            "the scenario meant the flag to fly outside every window")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: true,
            "the huddle and nothing else, and the clock restarts on the ready as though the flag had never flown"
        )
    }

    /// The runoff needs a running clock. After an incompletion the clock is stopped, so
    /// the flag costs five yards and nothing else, and the clock waits for the snap.
    @Test(
        "football · Rule 4-7-1 Item 1 · a false start with the clock stopped carries no runoff",
        .tags(.football))
    func falseStartWithTheClockStoppedCostsNoTime() {
        let trace = RulesScenario.falseStartWithTheClockStopped.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(
            trace.clockRunning(into: flag.index) == false,
            "the scenario meant the clock to be stopped when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, clock: before.clockRemaining,
            ballOn: before.ballOn + 5, clockRunning: false,
            "five yards, no time, and the clock still waits for the snap")
    }

    /// The defence may decline the runoff and keep the yardage; a trailing defence,
    /// which wants the clock to stop, does. The yards still count.
    @Test(
        "football · Rule 4-7-1 Item 1 · the defence may decline the runoff and keep the yardage",
        .tags(.football))
    func trailingDefenseDeclinesTheRunoff() {
        let trace = RulesScenario.falseStartAgainstATrailingDefense.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(before.scoreDifferential == 7, "the scenario meant the offence to lead")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "the five yards stand")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle,
            "the huddle and nothing else: the trailing defence declined the ten seconds")
    }

    /// Instead of the runoff the offence may spend a charged timeout, and then the clock
    /// starts on the snap — which, at twelve seconds, is the whole game.
    @Test(
        "football · Rule 4-7-1 Item 1 · the offence may take a charged timeout instead of the runoff, and the clock then starts on the snap",
        .tags(.football)
    )
    func offenseTakesATimeoutInsteadOfTheRunoff() {
        let trace = RulesScenario.falseStartAtTwelveSecondsWithATimeout.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        let flew = Int(before.clockRemaining) - Int(flag.huddle)
        #expect(flew == 12, "the scenario meant the flag to fly at 0:12, not \(flew)")
        #expect(before.offenseTimeouts > 0, "the scenario meant the offence to have a timeout")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, clock: 12, ballOn: before.ballOn + 5,
            clockRunning: false,
            "the timeout is spent at the flag, no ten seconds come off, and the clock waits for the snap"
        )
        #expect(
            trace[flag.index + 1]?.situation.offenseTimeouts == before.offenseTimeouts - 1,
            "the timeout was charged")
    }

    /// A runoff can exhaust the clock: at eight seconds, the flag ends the half.
    @Test(
        "football · Rule 4-7-1 Item 1, 4-5-4 Note 4 · a ten-second runoff at eight seconds ends the half",
        .tags(.football)
    )
    func runoffAtEightSecondsEndsTheHalf() {
        let trace = RulesScenario.falseStartAtEightSecondsOfTheHalf.run()
        guard let flag = flag(in: trace, quarter: 2) else { return }
        let before = flag.play.situation
        let flew = Int(before.clockRemaining) - Int(flag.huddle)
        #expect(flew == 8, "the scenario meant the flag to fly at 0:08, not \(flew)")
        #expect(before.offenseTimeouts == 0, "the scenario meant the offence to be out of timeouts")
        trace.expectPlay(
            flag.index + 1, kind: .kickoff, quarter: 3, clock: 900,
            "the half ended on the runoff, and the third quarter opens with a kickoff")
    }

    // MARK: Fouls before the snap

    /// Filed as A10 (#56): the defence jumps before the snap with the clock running and
    /// the offence trailing inside two minutes. No play happened, so no play time is
    /// charged; there is no runoff against the defence; and the offence, which wants
    /// the snap, has the clock wait for it.
    @Test(
        "football · Rule 4-7-1 Item 2, 4-4-e, 4-3-2-e · a defensive foul before the snap charges no time and the clock waits for the snap",
        .tags(.football)
    )
    func deadBallFoulBeforeTheSnapChargesNoTime() {
        let trace = RulesScenario.neutralZoneInfractionOnATrailingOffense.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(before.scoreDifferential == -7, "the scenario meant the offence to trail")
        #expect(
            before.clockRemaining < 120, "the scenario meant the flag to fly inside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, quarter: 4, down: before.down,
            distance: before.distance - 5, ballOn: before.ballOn - 5,
            "five yards against the defence, the down replayed, and the game not over")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: false,
            "the huddle and nothing else — no snap, so no play time — and the clock waits for the snap"
        )
    }

    /// The spike the baseline caller makes inside two minutes, with the clock running
    /// into it. Filed with A10 (#56).
    private func spike(in trace: Trace) -> (index: Int, play: PlayRecord)? {
        guard
            let spike = trace.first(where: {
                $0.situation.quarter == 4 && $0.situation.clockRemaining <= 120
                    && $0.outcome.kind == .spike
            })
        else {
            Issue.record("the trailing side never spiked the ball inside two minutes")
            return nil
        }
        guard trace.clockRunning(into: spike.index) == true else {
            Issue.record("the clock was not running into the spike, so it was not a spike")
            return nil
        }
        return spike
    }

    /// An incomplete pass stops the clock until the snap: the next play's huddle costs
    /// nothing. The incompletion here is the baseline caller's spike, which the scenario
    /// scripts to fall incomplete; that it does is a precondition, not the claim.
    @Test(
        "football · Rule 4-4-f, 4-3-2 · an incomplete pass, here a spike, stops the clock until the snap",
        .tags(.football)
    )
    func spikeStopsTheClock() {
        let trace = RulesScenario.trailingByAPickSix.run()
        guard let spike = spike(in: trace) else { return }
        guard spike.play.outcome.endedIn == .incomplete else {
            Issue.record("the scenario meant the spike to fall incomplete")
            return
        }
        trace.expectPlay(
            spike.index + 1, clockRunning: false, "and the clock is dead until the snap")
        guard let next = trace[spike.index + 1], trace[spike.index + 2] != nil else { return }
        trace.expectPlay(
            spike.index + 2, clock: next.situation.clockRemaining - next.outcome.clockRunoff,
            "the snap after the spike costs only its own play time")
    }

    /// Not a rule: the reference calls the interval between snaps the offence's tempo.
    /// This pins that `BaselineCaller` calls the spike at hurry-up tempo
    /// (`PlayCaller.swift:224`) and that a hurry-up snap takes less of the clock than a
    /// huddled one, because the endgame's arithmetic depends on both and nothing else
    /// checked either.
    @Test(
        "pin · the baseline caller spikes at hurry-up tempo, and a hurry-up snap takes less clock than a huddle (PlayCaller.swift:224; the interval is a modelling convention, not a rule)",
        .tags(.pin)
    )
    func spikeIsCalledAtHurryUpTempo() {
        let trace = RulesScenario.trailingByAPickSix.run()
        guard let spike = spike(in: trace) else { return }
        #expect(spike.play.calls.offense.tempo == .hurryUp, "a spike is a hurry-up call")
        guard let after = trace[spike.index + 1], let huddle = trace.huddle else {
            Issue.record("no play after the spike, or no huddle measured")
            return
        }
        let hurried =
            Int(spike.play.situation.clockRemaining) - Int(spike.play.outcome.clockRunoff)
            - Int(after.situation.clockRemaining)
        #expect(
            hurried < Int(huddle),
            "the spike took \(hurried) seconds to snap against \(huddle) from a huddle")
    }

    // MARK: The kickoff that opens a half

    /// The play that ended the first half between downs: the one somebody was hurt on,
    /// carrying the election that ran the clock out.
    private func injuryEndingTheFirstHalf(in trace: Trace) -> (index: Int, play: PlayRecord)? {
        guard let hurt = trace.result.injuries.first,
            let play = trace[Int(hurt.occurredOn.index)]
        else {
            Issue.record("the scenario never hurt anybody")
            return nil
        }
        let index = Int(hurt.occurredOn.index)
        #expect(
            play.situation.quarter == 2 && play.situation.clockRemaining < 120,
            "the scenario meant the injury after the first half's warning")
        #expect(
            play.situation.offenseTimeouts == 0, "the scenario meant the offence out of timeouts")
        #expect(
            play.decisions.contains { $0.clockElectionValue == .injuryRunoff },
            "the record says the defence took the runoff")
        #expect(trace[index + 1]?.situation.quarter == 3, "the runoff ran the half out")
        return (index, play)
    }

    /// A half can end on the runoff (4-5-4 Note 4), between downs, and the second half's
    /// opening kickoff (6-1-1-a) follows it as it follows a half that ended on a play. A free kick ends when a team possesses the
    /// ball, and a running play begins when the receiving team does (6-1-7); a kick dead
    /// in the receivers' possession in their end zone is a touchback (11-6-2), after
    /// which they snap next at their restart spot (11-6-3). The spot is the rules'
    /// kickoff touchback spot, which still carries a 2024 value.
    @Test(
        "football · Rule 4-5-4 Note 4, 6-1-1-a, 6-1-7, 11-6-2, 11-6-3 · a first half that ends on an excess injury timeout's runoff is followed by the second-half kickoff, kicked by the side that received the opening one; a touchback is the receiving team's ball, and it snaps next at its own restart spot",
        .tags(.football)
    )
    func secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf() {
        let trace = RulesScenario.secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf.run()
        guard let hurt = injuryEndingTheFirstHalf(in: trace), let opening = trace[0] else {
            return
        }
        let openingKicker = opening.situation.possession
        trace.expectPlay(0, kind: .kickoff, "the game opened with a kickoff")
        trace.expectPlay(
            hurt.index + 1, kind: .kickoff, endedIn: .touchback,
            possession: trace.opponent(of: openingKicker), quarter: 3, clock: 900, ballOn: 65,
            "the second half opens with a kickoff from the 35, by the side that received the opening one"
        )
        trace.expectPlay(
            hurt.index + 2, possession: openingKicker, quarter: 3, clock: 900, down: .first,
            distance: 10, ballOn: Rules.standard.kickoffTouchbackSpot,
            "the touchback is the receivers' ball at their restart spot, with no time gone")
    }

    /// The same half, and the kick is returned: the receiving team established possession
    /// (6-1-7) and the ball is next put in play where that down ended (7-6-1), the
    /// return's seconds off the clock.
    @Test(
        "football · Rule 4-5-4 Note 4, 6-1-1-a, 6-1-7, 7-6-1 · a first half that ends on an excess injury timeout's runoff is followed by the second-half kickoff, kicked by the side that received the opening one; a returned kick is the receiving team's ball where the return ended, and it snaps next from there",
        .tags(.football)
    )
    func secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf() {
        let trace = RulesScenario.secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf
            .run()
        guard let hurt = injuryEndingTheFirstHalf(in: trace), let opening = trace[0] else {
            return
        }
        let openingKicker = opening.situation.possession
        trace.expectPlay(
            hurt.index + 1, kind: .kickoff, endedIn: .tackled,
            possession: trace.opponent(of: openingKicker), quarter: 3, clock: 900, ballOn: 65,
            "the second half opens with a kickoff from the 35, by the side that received the opening one"
        )
        trace.expectPlay(
            hurt.index + 2, possession: openingKicker, quarter: 3, clock: 892, down: .first,
            distance: 10, ballOn: 75,
            "the return is the receivers' ball where it ended, at their 25, and its eight seconds came off"
        )
    }

    // MARK: The play clock

    /// The play clock a flag play was taken against, as the record carries it.
    private func playClock(
        on play: PlayRecord, sourceLocation: SourceLocation = #_sourceLocation
    ) -> (seconds: UInt8, remaining: UInt8)? {
        let readings = play.decisions.compactMap(\.playClockReading)
        guard readings.count == 1, let reading = readings.first else {
            Issue.record(
                "play \(play.index) records \(readings.count) play clocks; every snap records one",
                sourceLocation: sourceLocation)
            return nil
        }
        return reading
    }

    /// The forty seconds start when the previous play ends
    /// (4-6-1), and the game clock was running through them; the ball is not put in
    /// play, so the Back Judge's whistle is the foul (4-6-4), enforced from the
    /// succeeding spot with the down unchanged (14-4-1). In the third quarter the clock
    /// then restarts as though the flag had never flown (4-3-2-e).
    @Test(
        "football · Rule 4-6-1, 4-6-4, 14-4-1 · a delay of game when the 40-second play clock expires with the ball not snapped: five yards, the down replayed, and the whole play clock gone from a running game clock",
        .tags(.football)
    )
    func delayOfGameWhenThePlayClockExpires() {
        let trace = RulesScenario.delayOfGameOnARunningClock.run()
        guard let flag = flag(in: trace, quarter: 3) else { return }
        let before = flag.play.situation
        let fullPlayClock = UInt16(Rules.standard.playClock)
        #expect(
            flag.play.outcome.penalties.first?.foul == .delayOfGame,
            "the scenario meant the flag to be a delay of game")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the play clock expired")
        if let reading = playClock(on: flag.play) {
            #expect(reading.seconds == 40, "the play clock after a play is forty seconds")
            #expect(reading.remaining == 0, "and it expired")
        }
        trace.expectPlay(
            flag.index + 1, possession: before.possession, down: before.down,
            distance: before.distance + 5, ballOn: before.ballOn + 5,
            "five yards from the succeeding spot, and the same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - fullPlayClock, clockRunning: true,
            "the whole play clock ran off the game clock before the whistle, and the clock restarts on the ready"
        )
    }

    /// A change of possession is an administrative stoppage, so the offence taking
    /// over has twenty-five seconds from the whistle (4-6-2-a); the game clock is
    /// stopped until the snap, so letting it expire costs yards and no time.
    @Test(
        "football · Rule 4-6-2-a, 4-6-4 · after a change of possession the play clock is 25 seconds, and letting it expire with the game clock stopped is a delay of game that costs no time",
        .tags(.football)
    )
    func delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock() {
        let trace = RulesScenario.delayOfGameAfterATurnoverOnDowns.run()
        guard let flag = flag(in: trace, quarter: 1) else { return }
        let before = flag.play.situation
        #expect(
            flag.play.outcome.penalties.first?.foul == .delayOfGame,
            "the scenario meant the flag to be a delay of game")
        #expect(before.down == .first, "the scenario meant the flag on the first snap of a series")
        #expect(
            trace.clockRunning(into: flag.index) == false,
            "the scenario meant the clock stopped after the change of possession")
        if let reading = playClock(on: flag.play) {
            #expect(
                reading.seconds == 25,
                "the play clock after a change of possession is twenty-five seconds")
            #expect(reading.remaining == 0, "and it expired")
        }
        trace.expectPlay(
            flag.index + 1, possession: before.possession, clock: before.clockRemaining,
            down: .first, distance: before.distance + 5, ballOn: before.ballOn + 5,
            clockRunning: false,
            "five yards, first down still, no time, and the clock still waits for the snap")
    }

    // MARK: The last forty seconds of a half

    /// The defence cannot use a dead-ball foul to run the clock
    /// out: with the clock running and the defence out of timeouts, the half ends
    /// unless the offence would rather play on, and an offence protecting a lead in the
    /// fourth quarter would not. The flag is the last play of the game.
    @Test(
        "football · Rule 4-7-3 · in the last forty seconds a defensive foul that conserves time ends the half when the defence has no timeouts left and the offence, leading, elects to end it",
        .tags(.football)
    )
    func defensiveFoulInTheLastFortySecondsEndsTheHalfAtTheOffensesElection() {
        let trace = RulesScenario.neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading
            .run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        let flew = Int(before.clockRemaining) - Int(flag.huddle)
        #expect(flew == 30, "the scenario meant the flag to fly at 0:30, not \(flew)")
        #expect(before.scoreDifferential == 7, "the scenario meant the offence to lead")
        #expect(before.defenseTimeouts == 0, "the scenario meant the defence to be out of timeouts")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        #expect(
            flag.play.decisions.contains { $0.clockElectionValue == .halfEnded },
            "the record says the offence elected to end the half")
        trace.expectLastPlay(flag.index, "the half is the game's last, so the flag ends the game")
        trace.expectWinner(before.possession)
    }

    /// The other side of the election: level, the offence with the ball wants the
    /// thirty seconds, so it plays on, and after the defence's foul inside two minutes
    /// it has the clock wait for the snap (4-7-1 Item 2).
    @Test(
        "football · Rule 4-7-3, 4-7-1 Item 2 · in the last forty seconds a defensive foul that conserves time does not end the half when the offence, level, would rather play on, and the clock then waits for the snap",
        .tags(.football)
    )
    func defensiveFoulInTheLastFortySecondsWhenTheOffenseWouldRatherPlayOn() {
        let trace = RulesScenario.neutralZoneInfractionInTheLastFortySecondsLevel.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        let flew = Int(before.clockRemaining) - Int(flag.huddle)
        #expect(flew == 30, "the scenario meant the flag to fly at 0:30, not \(flew)")
        #expect(before.scoreDifferential == 0, "the scenario meant the game level")
        #expect(before.defenseTimeouts == 0, "the scenario meant the defence to be out of timeouts")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        #expect(
            flag.play.decisions.contains { $0.clockElectionValue == .playedOn },
            "the record says the offence elected to play on")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, quarter: 4, clock: 30,
            ballOn: before.ballOn - 5, clockRunning: false,
            "five yards against the defence, the half goes on, and the clock waits for the snap")
    }

    /// The article's own exception: while the defence has a timeout left the half does
    /// not end on its foul. Nothing is elected; the leading offence lets the clock
    /// start on the ready as it would after any defensive foul inside two minutes.
    @Test(
        "football · Rule 4-7-3 · in the last forty seconds a defensive foul that conserves time does not end the half while the defence has a timeout left",
        .tags(.football)
    )
    func defensiveFoulInTheLastFortySecondsWithADefensiveTimeoutLeft() {
        let trace = RulesScenario
            .neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        let flew = Int(before.clockRemaining) - Int(flag.huddle)
        #expect(flew == 30, "the scenario meant the flag to fly at 0:30, not \(flew)")
        #expect(before.scoreDifferential == 7, "the scenario meant the offence to lead")
        #expect(before.defenseTimeouts > 0, "the scenario meant the defence to have a timeout")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        #expect(
            !flag.play.decisions.contains { $0.clockElectionValue == .halfEnded },
            "nothing to elect: the defence has a timeout, so the half cannot end on its foul")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, quarter: 4, clock: 30,
            ballOn: before.ballOn - 5, clockRunning: true,
            "five yards against the defence, the half goes on, and the clock starts on the ready")
    }

    // MARK: An injury after the two-minute warning

    /// The play somebody was hurt on, with the clock as it read when that play ended.
    private func injury(
        in trace: Trace
    ) -> (index: Int, play: PlayRecord, clockAfter: UInt16)? {
        guard let hurt = trace.result.injuries.first,
            let play = trace[Int(hurt.occurredOn.index)]
        else {
            Issue.record("the scenario never hurt anybody")
            return nil
        }
        guard let huddle = trace.huddle else {
            Issue.record("the game never showed the offence's tempo")
            return nil
        }
        let index = Int(hurt.occurredOn.index)
        let running = trace.clockRunning(into: index) == true
        let after =
            Int(play.situation.clockRemaining) - (running ? Int(huddle) : 0)
            - Int(play.outcome.clockRunoff)
        #expect(
            play.situation.quarter == 4 && play.situation.clockRemaining < 120,
            "the scenario meant the injury after the two-minute warning")
        #expect(
            after == 60 && play.outcome.endedIn == .tackled,
            "the scenario meant the play to end at 1:00 with the clock running, not \(after)")
        return (index, play, UInt16(max(0, after)))
    }

    /// After the two-minute warning the injured player's team is
    /// charged a team timeout if it has one (4-5-4-a), and a charged timeout has the
    /// clock start on the snap (4-4-j, 4-3-2). The record says which it was.
    @Test(
        "football · Rule 4-5-4-a, 4-3-2 · after the two-minute warning an injury to a player of the team in possession costs it a charged timeout, and the clock waits for the snap",
        .tags(.football)
    )
    func injuryTimeoutAfterTheWarningIsCharged() {
        let trace = RulesScenario.injuryInsideTwoMinutesWithATimeoutLeft.run()
        guard let hurt = injury(in: trace) else { return }
        let before = hurt.play.situation
        #expect(before.offenseTimeouts > 0, "the scenario meant the offence to have a timeout")
        #expect(
            hurt.play.decisions.contains { $0.clockElectionValue == .injuryTimeoutCharged },
            "the record says the injury timeout was charged")
        trace.expectPlay(
            hurt.index + 1, possession: before.possession, quarter: 4, clock: hurt.clockAfter,
            clockRunning: false,
            "no time comes off, and the clock waits for the snap")
        #expect(
            trace[hurt.index + 1]?.situation.offenseTimeouts == before.offenseTimeouts - 1,
            "the timeout was charged")
    }

    /// With no timeouts left the Referee calls an excess timeout (4-5-4-b), and since
    /// it is against the team in possession and stopped a running clock, the defence
    /// may have ten seconds run off before the ball is put in play, with the clock
    /// starting on the ready (4-5-4 Note 3). A level defence wants the clock to run.
    @Test(
        "football · Rule 4-5-4-b, 4-5-4 Note 3 · after the two-minute warning an injury to a player of the team in possession, with no timeouts left, is an excess timeout: the defence has ten seconds run off, and the clock starts on the ready",
        .tags(.football)
    )
    func excessInjuryTimeoutAfterTheWarningCarriesTheRunoff() {
        let trace = RulesScenario.injuryInsideTwoMinutesWithNoTimeoutsLeft.run()
        guard let hurt = injury(in: trace) else { return }
        let before = hurt.play.situation
        #expect(before.offenseTimeouts == 0, "the scenario meant the offence to be out of timeouts")
        #expect(before.scoreDifferential == 0, "the scenario meant the game level")
        #expect(
            hurt.play.decisions.contains { $0.clockElectionValue == .injuryRunoff },
            "the record says the defence took the runoff")
        trace.expectPlay(
            hurt.index + 1, possession: before.possession, quarter: 4,
            clock: hurt.clockAfter - 10, clockRunning: true,
            "ten seconds come off before the ball is put in play, and the clock starts on the ready"
        )
        #expect(
            trace[hurt.index + 1]?.situation.offenseTimeouts == 0,
            "there was no timeout to charge")
    }

    /// The runoff is the defence's to decline. A trailing defence wants the clock
    /// stopped, so it declines the ten seconds and, as the opponent of the team charged
    /// with the excess timeout, has the clock start on the snap (4-5-4 Note 1).
    @Test(
        "football · Rule 4-5-4 Note 3, 4-5-4 Note 1 · the defence may decline the injury runoff; a trailing defence does, and the clock then waits for the snap",
        .tags(.football)
    )
    func injuryRunoffDeclinedByATrailingDefense() {
        let trace = RulesScenario.injuryInsideTwoMinutesAgainstATrailingDefense.run()
        guard let hurt = injury(in: trace) else { return }
        let before = hurt.play.situation
        #expect(before.offenseTimeouts == 0, "the scenario meant the offence to be out of timeouts")
        #expect(before.scoreDifferential == 7, "the scenario meant the defence to trail")
        #expect(
            hurt.play.decisions.contains { $0.clockElectionValue == .injuryRunoffDeclined },
            "the record says the defence declined the runoff")
        trace.expectPlay(
            hurt.index + 1, possession: before.possession, quarter: 4, clock: hurt.clockAfter,
            clockRunning: false,
            "no ten seconds, and the clock waits for the snap")
    }

    // MARK: Tries and kicks

    /// Filed as A7 (#19): a flag before the try moves the try, and it is still a try.
    @Test(
        "football · Rule 11-3-1, 7-4-2 · a false start on a try moves the try back five yards",
        .tags(.football))
    func falseStartOnATryMovesTheTry() {
        let trace = RulesScenario.falseStartOnATry.run()
        guard let scorer = trace[1]?.situation.possession else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(
            2, kind: .penaltyOnly, possession: scorer, ballOn: 15, "the flag, on the try")
        trace.expectPlay(
            3, kind: .extraPoint, possession: scorer, ballOn: 20,
            "the try is snapped again, five yards further out")
        trace.expectPlay(4, kind: .kickoff, possession: scorer, "and then the kickoff")
        trace.expectScore(scorer, 7)
    }

    /// A miss struck from nearer than the 20 comes out to the 20.
    @Test(
        "football · Rule 11-4-2 · a missed field goal struck from inside the 20 gives the defence the ball at its 20",
        .tags(.football)
    )
    func missedFieldGoalFromInsideTheTwenty() {
        let trace = RulesScenario.missedFieldGoalFromTheTen.run()
        guard let kick = trace.first(where: { $0.outcome.kind == .fieldGoal }) else {
            Issue.record("the script never kicked")
            return
        }
        trace.expectPlay(kick.index, endedIn: .fieldGoalMissed, ballOn: 10)
        trace.expectPlay(
            kick.index + 1, possession: trace.opponent(of: kick.play.situation.possession),
            down: .first, distance: 10, ballOn: 80,
            "the defence takes over at its own 20")
    }

    /// A miss struck from beyond the 20 comes back to where it was struck: the line of
    /// scrimmage plus the depth of the snap, which is the model's constant.
    @Test(
        "football · Rule 11-4-2 · a missed field goal struck from beyond the 20 gives the defence the ball where it was struck",
        .tags(.football)
    )
    func missedFieldGoalFromBeyondTheTwenty() {
        let trace = RulesScenario.missedFieldGoalFromTheTwenty.run()
        guard let kick = trace.first(where: { $0.outcome.kind == .fieldGoal }) else {
            Issue.record("the script never kicked")
            return
        }
        let struck = 20 + Rules.standard.fieldGoalSnapDepth
        trace.expectPlay(kick.index, endedIn: .fieldGoalMissed, ballOn: 20)
        trace.expectPlay(
            kick.index + 1, possession: trace.opponent(of: kick.play.situation.possession),
            down: .first, distance: 10, ballOn: 100 - struck,
            "the defence takes over at its own \(struck)")
    }

    // MARK: Enforcement

    /// The reference names Rule 14-4 for the spots of enforcement and carries half the
    /// distance only as a term of art; this scenario is written from the closest
    /// section it has. Five yards from the 3 cannot reach the goal line: the ball ends
    /// up nearer than the 3 and still short of it, first and goal.
    @Test(
        "football · Rule 8-4-6, 12-1-6, 14-4 (closest section) · defensive holding at the 3 is half the distance and a first down",
        .tags(.football)
    )
    func defensiveHoldingAtTheThreeIsHalfTheDistance() {
        let trace = RulesScenario.defensiveHoldingAtTheThree.run()
        guard let foul = trace[2], let next = trace[3] else {
            Issue.record("the script did not reach the foul")
            return
        }
        #expect(foul.situation.ballOn == 3, "the scenario meant the foul at the 3")
        trace.expectPlay(
            3, possession: foul.situation.possession, down: .first, "an automatic first down")
        #expect(
            next.situation.ballOn < 3 && next.situation.ballOn >= 1,
            "half the distance from the 3, not the goal line: \(next.situation.ballOn)")
        #expect(next.situation.isGoalToGo, "first and goal")
    }

    /// The other direction, from the closest section the reference has: a false start
    /// from the own 3 goes back half the distance, not five, and not into the end zone.
    @Test(
        "football · Rule 7-4-2, 14-4 (closest section) · a false start at the own 3 is half the distance to the goal line",
        .tags(.football)
    )
    func falseStartAtTheOwnThreeIsHalfTheDistance() {
        let trace = RulesScenario.falseStartAtTheOwnThree.run()
        guard let foul = trace[2], let next = trace[3] else {
            Issue.record("the script did not reach the foul")
            return
        }
        #expect(foul.situation.ballOn == 97, "the scenario meant the foul at the own 3")
        trace.expectPlay(
            3, possession: foul.situation.possession, down: .first, "the down is replayed")
        #expect(
            next.situation.ballOn > 97 && next.situation.ballOn <= 99,
            "half the distance back from the own 3, and never past the goal line: \(next.situation.ballOn)"
        )
    }

    /// The reference gives the yardage and the automatic first down and names Rule 14-4
    /// for the spot; the spot itself — the end of the run — is the sentence the audit's
    /// S13 recorded. Fifteen yards from the end of a twenty-yard run is thirty-five.
    @Test(
        "football · Rule 12-2-15, 14-4 (closest section) · a facemask at the end of a 20-yard run is 15 more from the end of the run, and a first down",
        .tags(.football)
    )
    func facemaskAtTheEndOfARunIsEnforcedFromTheEndOfTheRun() {
        let trace = RulesScenario.facemaskAtTheEndOfARun.run()
        guard let run = trace[1] else {
            Issue.record("no first snap")
            return
        }
        trace.expectPlay(
            2, possession: run.situation.possession, down: .first, distance: 10,
            ballOn: run.situation.ballOn - 35,
            "twenty for the run and fifteen for the foul, first and ten")
    }

    @Test(
        "football · Rule 8-5-4 · defensive pass interference in the end zone is first and goal at the 1",
        .tags(.football)
    )
    func interferenceInTheEndZoneSpotsAtTheOne() {
        let trace = RulesScenario.interferenceInTheEndZone.run()
        guard let pass = trace[2] else {
            Issue.record("the script did not reach the pass")
            return
        }
        #expect(pass.situation.ballOn == 30, "the scenario meant the pass from the 30")
        trace.expectPlay(
            3, possession: pass.situation.possession, down: .first, distance: 1, ballOn: 1,
            "first and goal at the 1")
    }

    @Test(
        "football · Rule 8-5-4 · defensive pass interference in the end zone from inside the 2 is half the distance, and still a first down",
        .tags(.football)
    )
    func interferenceInTheEndZoneFromInsideTheTwo() {
        let trace = RulesScenario.interferenceInTheEndZoneFromTheOne.run()
        guard let pass = trace[2] else {
            Issue.record("the script did not reach the pass")
            return
        }
        #expect(pass.situation.ballOn == 1, "the scenario meant the pass from the 1")
        trace.expectPlay(
            3, possession: pass.situation.possession, down: .first, distance: 1, ballOn: 1,
            "half the distance from the 1 is inside the 1, first and goal")
    }

    // MARK: Onside kicks

    /// A trailing side declares an onside kick, and its recovery is its ball where the
    /// play died: a first down, not a change of possession.
    @Test(
        "football · Rule 6-1-6, 6-1-4-c, 6-1-4-d · an onside kick the kicking team recovers is its ball, first and ten, where it was recovered",
        .tags(.football)
    )
    func onsideRecoveryKeepsPossession() {
        let trace = RulesScenario.onsideKickRecovered.run()
        guard
            let onside = trace.first(where: {
                $0.calls.offense.concept == .onsideKick
            })
        else {
            Issue.record("the trailing side never kicked onside")
            return
        }
        let kicker = onside.play.situation.possession
        #expect(onside.play.situation.scoreDifferential < 0, "only a trailing side may kick onside")
        trace.expectPlay(onside.index, kind: .kickoff, endedIn: .fumbleRecovered)
        trace.expectPlay(
            onside.index + 1, kind: .rush, possession: kicker, down: .first, distance: 10,
            ballOn: 53, "the kicking side keeps the ball where it fell on it")
    }

    // MARK: A foul on a takeaway, and a kickoff the kickers carry in

    /// A run is a run until somebody else has the ball. The basic spot for a foul during
    /// a run followed by a change of possession is the spot where possession was lost
    /// (14-3-5-b), and a defensive foul reverts the ball to the offence before
    /// enforcement (14-4-3-a); unnecessary roughness by the defence is fifteen and an
    /// automatic first down (12-2-8). The offence snapped from its 30, ran to its 40 with
    /// a defender flagged on the way, and lost the ball there — so it gets it back
    /// fifteen past its own 40, at the opponents' 45, first and ten. Not fifteen past the
    /// 30, which is what enforcing from the previous spot gives.
    @Test(
        "football · Rule 14-3-5-b, 14-4-3-a, 12-2-8 · a defensive personal foul during a run that ends in a fumble lost gives the ball back to the offence fifteen yards past the spot of the fumble, and a first down",
        .tags(.football)
    )
    func defensiveFoulOnARunThatEndsInAFumbleIsEnforcedFromTheSpotOfTheFumble() {
        let trace = RulesScenario.roughnessByTheDefenseOnARunThatEndsInAFumbleLost.run()
        guard let strip = trace[1] else {
            Issue.record("the script never put the ball on the ground")
            return
        }
        #expect(strip.situation.ballOn == 70, "the scenario meant the snap from the own 30")
        #expect(strip.outcome.possessionLostAt == 60, "stripped at the own 40")
        trace.expectPlay(1, kind: .rush, endedIn: .fumbleLost)
        trace.expectPlay(
            2, possession: strip.situation.possession, down: .first, distance: 10, ballOn: 45,
            "the offence's ball, fifteen past where it lost possession, first and ten")
    }

    /// The same flag on a pass is a different rule. Until a forward pass from behind
    /// the line is over, a flag on either side comes off the previous
    /// spot (14-4-5, and the same sentence as 8-6-1), and the down does not turn into a
    /// running play until somebody catches the ball — so a foul that came before the catch
    /// is never measured from it. The offence snapped from its 30 and gets the ball there
    /// plus fifteen, at its own 45, first and ten (12-2-8), and the interception is wiped
    /// out. Not fifteen past the catch, which is the running rule applied to a pass.
    @Test(
        "football · Rule 14-4-5, 8-6-1, 12-2-8 · a defensive personal foul before a forward pass is intercepted is enforced from the previous spot, so the offence keeps the ball fifteen yards past where it snapped, and a first down",
        .tags(.football)
    )
    func defensiveFoulBeforeAnInterceptionIsEnforcedFromThePreviousSpot() {
        let trace = RulesScenario.roughnessByTheDefenseBeforeAnInterception.run()
        guard let pick = trace[1] else {
            Issue.record("the script never threw the interception")
            return
        }
        #expect(pick.situation.ballOn == 70, "the scenario meant the snap from the own 30")
        #expect(pick.outcome.possessionLostAt == 60, "picked off at the own 40")
        trace.expectPlay(1, kind: .pass, endedIn: .intercepted)
        trace.expectPlay(
            2, possession: pick.situation.possession, down: .first, distance: 10, ballOn: 55,
            "the offence's ball, fifteen past the previous spot, first and ten")
    }

    /// Any player of either team may recover a fumble and advance it (8-7-3 Item 1), and
    /// a runner carrying the ball into the opponents' end zone scores (11-2-1) — so a
    /// kickoff fumbled by the returner and carried in by the kicking team is the kicking
    /// team's touchdown, its try (11-3-1), and the receivers of that try receive the
    /// kickoff after it (11-3-4). The record used to read every kickoff touchdown as the
    /// receivers', so this scored for the wrong side and gave them the try.
    @Test(
        "football · Rule 8-7-3 Item 1, 11-2-1, 11-3-1, 11-3-4 · a kickoff fumbled by the returner and carried in by the kicking team is the kicking team's touchdown, its try, and its kickoff",
        .tags(.football)
    )
    func kickoffFumbledAndCarriedInIsTheKickersTouchdown() {
        let trace = RulesScenario.kickoffFumbledAndReturnedByTheKickers.run()
        guard let kicker = trace[0]?.situation.possession else {
            Issue.record("no opening kickoff")
            return
        }
        let receiver = trace.opponent(of: kicker)
        trace.expectPlay(0, kind: .kickoff, endedIn: .touchdown)
        trace.expectPlay(
            1, kind: .extraPoint, possession: kicker, "the try belongs to the side that scored")
        trace.expectPlay(2, kind: .kickoff, possession: kicker, "and it kicks off again")
        trace.expectPlay(3, kind: .rush, possession: receiver, "to the side it took the ball from")
        trace.expectScore(kicker, 7)
        trace.expectScore(receiver, 0)
        #expect(trace[0]?.outcome.pointsScored == 6, "six points on the kickoff's own record")
        #expect(trace[0]?.outcome.scoring == .touchdown, "paid to the side that had the ball")
    }
}
