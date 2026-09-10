import FMCore
import Testing

@testable import FMSimulation

// The rules-conformance suite: the acceptance language for the rules layer.
//
// Every scenario in here was written from the 2025 rulebook as the football-domain
// skill's `references/game-rules.md` gives it — the citation in each test's name is that
// file's — and never from the code. A scenario says what the sport does; whether the
// engine does it is what the run reports. Scenarios the engine cannot satisfy today are
// red on purpose and stay in the tree until the fix that turns them green.
//
// The scenarios are separate from the tests that run them (`RulesScenarios`), so that a
// play-by-play printer can walk one and a reader can see the football without the
// assertions.
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

// MARK: - The scenarios

/// The rules-conformance scenarios, as scripted games.
enum RulesScenarios {

    // MARK: Building blocks

    /// Whatever was called, for one yard, tackled in bounds. The ball changes hands on
    /// downs every four plays and nobody ever scores: the plainest way to run a clock.
    static func plod(_ snap: Snap) -> Outcome {
        snap.neutral
    }

    /// The last snap of `quarter` is a touchdown by the side whose score reads
    /// `differential`. When the other side has the ball inside the closing two minutes
    /// it throws an interception, so the right side always gets the last snap, which it
    /// takes at its first snap inside the closing minute.
    ///
    /// Two windows, not one. The right side's is a minute because snaps are never more
    /// than a play clock apart, so no walk down the clock can step over it. The wrong
    /// side's is wider: a snap on a running clock costs a huddle before the play, so an
    /// interception thrown inside the last thirty-odd seconds can expire the period
    /// itself. Inside two minutes the wrong side's first snap after taking the ball
    /// over is huddle-free — the clock stops on a change of possession — and any later
    /// snap of its own comes with more than a huddle left, so it always gives the ball
    /// back with time on the clock.
    static func touchdownAsTimeExpires(
        quarter: UInt8, by differential: Int16
    )
        -> @Sendable (Snap) -> Outcome
    {
        { snap in
            guard snap.isScrimmage, snap.quarter == quarter else { return snap.neutral }
            if snap.differential == differential {
                return snap.clock <= 60 ? snap.touchdownAsTimeExpires() : snap.neutral
            }
            return snap.clock <= 120 ? .interception(to: 50) : snap.neutral
        }
    }

    /// The side that has the ball first scores on its first snap and kicks the point.
    ///
    /// Only the opening try (play 2) is dictated. Every later try is left to the
    /// neutral outcome, which honours whatever was called: an opening that answered
    /// every try with a made kick answered a two-point call with an extra point, and
    /// one that answered every try with a miss could never let a walk-off kick win.
    static func leadBySeven(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return snap.touchdown() }
        if snap.index == 2, snap.isTry { return .extraPoint(good: true) }
        return nil
    }

    /// The side that has the ball first scores on its first snap and misses the kick.
    static func leadBySix(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return snap.touchdown() }
        if snap.index == 2, snap.isTry { return .extraPoint(good: false) }
        return nil
    }

    /// The side that has the ball first throws an interception to its own two, and the
    /// interceptors are then tackled in their own end zone: two points, and the side
    /// that had the ball first leads by them.
    static func leadByTwo(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return .interception(to: 2) }
        if snap.index == 2 { return snap.safety() }
        return nil
    }

    /// Seven for the side that has the ball first; a touchdown and a missed kick for the
    /// other, on its first snap. The first side then leads by one.
    static func sevenToSix(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return snap.touchdown() }
        if snap.isTry { return .extraPoint(good: snap.differential == 6) }
        if snap.quarter == 1, snap.isScrimmage, snap.differential == -7 { return snap.touchdown() }
        return nil
    }

    // MARK: A safety, and what follows a score

    static var safetyFreeKick: ScriptedGame {
        ScriptedGame { snap in leadByTwo(snap) ?? plod(snap) }
    }

    static var touchdownTryKickoff: ScriptedGame {
        ScriptedGame { snap in leadBySeven(snap) ?? plod(snap) }
    }

    static var fieldGoalThenKickoff: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveFamily: { $0.ballOn == 20 ? .fieldGoal : .insideRun })
        ) { snap in
            if snap.index == 1 { return .rush(Int16(snap.ballOn) - 20) }
            return plod(snap)
        }
    }

    static var kickoffReturnTouchdown: ScriptedGame {
        ScriptedGame { snap in snap.index == 0 ? .kickoffReturnTouchdown : plod(snap) }
    }

    // MARK: A touchdown on the last play of a period

    static func lastPlayTouchdown(
        trailingBy deficit: Int16, opening: @escaping @Sendable (Snap) -> Outcome?,
        goesForTwo: Bool = false
    ) -> ScriptedGame {
        let ending = touchdownAsTimeExpires(quarter: 4, by: -deficit)
        return ScriptedGame(caller: ScriptedCaller(twoPointDecision: { _ in goesForTwo })) {
            snap in
            opening(snap) ?? ending(snap)
        }
    }

    static var lastPlayTouchdownDownSeven: ScriptedGame {
        lastPlayTouchdown(trailingBy: 7, opening: leadBySeven)
    }

    static var lastPlayTouchdownDownSix: ScriptedGame {
        lastPlayTouchdown(trailingBy: 6, opening: leadBySix)
    }

    static var lastPlayTouchdownDownEight: ScriptedGame {
        lastPlayTouchdown(
            trailingBy: 8,
            opening: { snap in
                if snap.index == 1 { return snap.touchdown() }
                if snap.isTry { return .twoPoint(converted: true) }
                return nil
            },
            goesForTwo: true)
    }

    static var lastPlayTouchdownDownTwo: ScriptedGame {
        lastPlayTouchdown(trailingBy: 2, opening: leadByTwo)
    }

    static var lastPlayTouchdownDownOne: ScriptedGame {
        lastPlayTouchdown(trailingBy: 1, opening: sevenToSix)
    }

    static var lastPlayTouchdownLevel: ScriptedGame {
        lastPlayTouchdown(trailingBy: 0, opening: { _ in nil })
    }

    static var lastPlayTouchdownUpOne: ScriptedGame {
        lastPlayTouchdown(trailingBy: -1, opening: sevenToSix)
    }

    static var touchdownAsSecondQuarterExpires: ScriptedGame {
        ScriptedGame(play: touchdownAsTimeExpires(quarter: 2, by: 0))
    }

    static var touchdownAsFirstQuarterExpires: ScriptedGame {
        ScriptedGame(play: touchdownAsTimeExpires(quarter: 1, by: 0))
    }

    // MARK: Overtime

    /// Nobody scores, ever.
    static var scoreless: ScriptedGame {
        ScriptedGame(play: plod)
    }

    static var scorelessPostseasonUntilTheSixthPeriod: ScriptedGame {
        ScriptedGame(
            isPostseason: true,
            caller: ScriptedCaller(offensiveFamily: { $0.quarter == 6 ? .fieldGoal : .insideRun }),
            play: plod)
    }

    static var overtimeFirstPossessionTouchdown: ScriptedGame {
        ScriptedGame { snap in
            if snap.quarter == 5, snap.isScrimmage, snap.differential == 0 {
                return snap.touchdown()
            }
            return plod(snap)
        }
    }

    /// Each side kicks a field goal on its first overtime possession, and then the side
    /// that had it first kicks another.
    static var overtimeFieldGoalsUntilOneIsUnanswered: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveFamily: {
                $0.quarter >= 5 && $0.down == .fourth ? .fieldGoal : .insideRun
            }),
            play: plod)
    }

    static var overtimeFirstPossessionInterceptionReturned: ScriptedGame {
        ScriptedGame { snap in
            if snap.quarter == 5, snap.isScrimmage, snap.differential == 0 { return .pickSix }
            return plod(snap)
        }
    }

    static var overtimeOpeningDriveSafety: ScriptedGame {
        ScriptedGame { snap in
            if snap.quarter == 5, snap.isScrimmage, snap.differential == 0 { return snap.safety() }
            return plod(snap)
        }
    }

    // MARK: The clock

    static var puntReturnedAndTackled: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveFamily: { $0.down == .fourth ? .punt : .insideRun })
        ) { snap in
            snap.family == .punt ? .punt(toOwn: 30, endedIn: .tackled) : plod(snap)
        }
    }

    static var fumbleRecoveredByTheOffense: ScriptedGame {
        ScriptedGame { snap in snap.index == 1 ? .fumble(recoveredAfter: 3) : plod(snap) }
    }

    static var fumbleRecoveredByTheDefense: ScriptedGame {
        ScriptedGame { snap in snap.index == 1 ? .fumble(lostAt: 60) : plod(snap) }
    }

    static var kickoffReturned: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 0 ? .kickoffReturn(toOwn: 25, seconds: 8) : plod(snap)
        }
    }

    /// A walk down `quarter` in which the first play that can be is stretched to end at
    /// `second` with the clock running, and everything else is a yard at a time.
    static func playStretchedToEnd(quarter: UInt8, at second: UInt16) -> ScriptedGame {
        ScriptedGame { snap in
            guard snap.isScrimmage, snap.quarter == quarter, snap.down != .fourth,
                let huddle = snap.huddle
            else { return snap.neutral }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            guard snapped > Int(second), snapped - Int(second) <= 130 else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - Int(second)))
        }
    }

    // MARK: Fouls before the snap late in a half

    /// A flag before the snap by the side whose score reads `differential`, inside
    /// `window` of `quarter`, with the clock running unless `stopped`.
    ///
    /// The other side throws an interception when it has the ball in the window, so the
    /// right side is on offence; the flag then flies on the first snap that follows one
    /// of the side's own plays. With `target` set, that last play is stretched so that
    /// the clock reads `target` when the flag flies, using the offence's measured tempo.
    static func lateFlag(
        _ foul: Foul = .falseStart,
        quarter: UInt8 = 4,
        window: ClosedRange<UInt16>,
        by differential: Int16? = nil,
        flagAt target: UInt16? = nil,
        stopped: Bool = false,
        opening: @escaping @Sendable (Snap) -> Outcome? = { _ in nil },
        caller: ScriptedCaller = ScriptedCaller()
    ) -> ScriptedGame {
        ScriptedGame(caller: caller) { snap in
            if let staged = opening(snap) { return staged }
            guard snap.isScrimmage, snap.quarter == quarter else { return snap.neutral }
            let rightSide = differential.map { $0 == snap.differential } ?? true
            let previous = snap.previous
            let ownPlayBefore =
                previous?.situation.possession == snap.possession
                && previous?.outcome.kind != .penaltyOnly && snap.distance <= 10

            if let target {
                // The flag, once the stretched play has brought the clock to where the
                // huddle ends at `target`: the flag flies when the snap was due.
                if let huddle = snap.huddle, snap.clock <= target + huddle, snap.clockIsRunning,
                    rightSide, ownPlayBefore
                {
                    return snap.preSnapFoul(foul)
                }
                guard window.contains(snap.clock) else { return snap.neutral }
                guard rightSide else { return .interception(to: 50) }
                // Stretch this play so that the next snap is due at `target`: it ends
                // at `target` plus the huddle the offence will then take.
                guard let huddle = snap.huddle, snap.down != .fourth else { return snap.neutral }
                let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
                let ends = Int(target) + Int(huddle)
                guard snapped > ends else { return snap.neutral }
                return .rush(1, seconds: UInt16(snapped - ends))
            }

            guard window.contains(snap.clock) else { return snap.neutral }
            guard rightSide else { return .interception(to: 50) }
            if stopped {
                let afterAnIncompletion = previous?.outcome.endedIn == .incomplete
                if afterAnIncompletion, !snap.clockIsRunning, ownPlayBefore {
                    return snap.preSnapFoul(foul)
                }
                return snap.down == .fourth ? snap.neutral : .incompletion()
            }
            if snap.clockIsRunning, ownPlayBefore { return snap.preSnapFoul(foul) }
            return snap.neutral
        }
    }

    static var falseStartInsideTwoMinutes: ScriptedGame {
        lateFlag(window: 40...119)
    }

    static var falseStartOutsideTwoMinutes: ScriptedGame {
        lateFlag(window: 160...400)
    }

    static var falseStartWithTheClockStopped: ScriptedGame {
        lateFlag(window: 40...119, stopped: true)
    }

    static var falseStartAgainstATrailingDefense: ScriptedGame {
        lateFlag(window: 40...119, by: 7, opening: leadBySeven)
    }

    static var falseStartAtTwelveSecondsWithATimeout: ScriptedGame {
        lateFlag(window: 60...119, flagAt: 12)
    }

    /// Both sides burn their first-half timeouts early in the second quarter, so nobody
    /// can buy the runoff back.
    static var falseStartAtEightSecondsOfTheHalf: ScriptedGame {
        lateFlag(
            quarter: 2, window: 60...119, flagAt: 8,
            caller: ScriptedCaller(timeoutDecision: { situation, isOffense in
                isOffense && situation.quarter == 2 && situation.clockRemaining <= 400
                    && situation.clockRemaining > 160 && situation.offenseTimeouts > 0
            }))
    }

    static var neutralZoneInfractionOnATrailingOffense: ScriptedGame {
        lateFlag(.neutralZoneInfraction, window: 40...119, by: -7, opening: leadBySeven)
    }

    /// One side leads by seven from a pick-six on the first snap; everything else is a
    /// yard at a time, tackled in bounds. Inside two minutes the leader gives the ball
    /// back, and the trailing side's third downs move the chains so that it keeps the
    /// ball while the clock runs down. What the baseline caller does with that endgame
    /// is the question.
    static var trailingByAPickSix: ScriptedGame {
        ScriptedGame { snap in
            if snap.index == 1 { return .pickSix }
            guard snap.quarter == 4, snap.clock <= 120, snap.isScrimmage else { return plod(snap) }
            if snap.differential > 0 { return .interception(to: 50) }
            if snap.down == .third, snap.family != .spike {
                return Outcome(
                    kind: snap.family?.kind ?? .pass, yards: Int16(snap.distance),
                    endedIn: .tackled, clockRunoff: 6)
            }
            return plod(snap)
        }
    }

    // MARK: Tries, kicks and enforcement

    static var falseStartOnATry: ScriptedGame {
        ScriptedGame { snap in
            if snap.index == 1 { return snap.touchdown() }
            if snap.isTry {
                let flaggedAlready = snap.previous?.outcome.kind == .penaltyOnly
                return snap.ballOn == 15 && !flaggedAlready
                    ? snap.preSnapFoul(.falseStart) : .extraPoint(good: true)
            }
            return plod(snap)
        }
    }

    /// A drive to `yardLine`, then a missed field goal from there.
    static func missedFieldGoal(from yardLine: UInt8) -> ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveFamily: {
                $0.ballOn == yardLine ? .fieldGoal : .insideRun
            })
        ) { snap in
            if snap.index == 1 { return .rush(Int16(snap.ballOn) - Int16(yardLine)) }
            if snap.family == .fieldGoal { return .fieldGoal(good: false) }
            return plod(snap)
        }
    }

    static var defensiveHoldingAtTheThree: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 3)
            case 2: return snap.rush(0, foulBy: .defensiveHolding)
            default: return plod(snap)
            }
        }
    }

    static var falseStartAtTheOwnThree: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .interception(to: 3)
            case 2: return snap.preSnapFoul(.falseStart)
            default: return plod(snap)
            }
        }
    }

    static var facemaskAtTheEndOfARun: ScriptedGame {
        ScriptedGame { snap in snap.index == 1 ? snap.rush(20, foulBy: .facemask) : plod(snap) }
    }

    static var interferenceInTheEndZone: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 30)
            case 2: return snap.incompletion(interferenceAt: 35)
            default: return plod(snap)
            }
        }
    }

    static var interferenceInTheEndZoneFromTheOne: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 1)
            case 2: return snap.incompletion(interferenceAt: 3)
            default: return plod(snap)
            }
        }
    }

    /// A pick-six puts one side up seven; the other kicks a field goal, is down four,
    /// and kicks onside. The kicking team falls on it at its own 47.
    static var onsideKickRecovered: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(
                offensiveFamily: { $0.ballOn == 20 ? .fieldGoal : .insideRun },
                onsideDecision: { $0.scoreDifferential < 0 })
        ) { snap in
            if snap.family == .onsideKick { return .onsideKick(recoveredAt: 53) }
            guard snap.isScrimmage else { return snap.neutral }
            if snap.differential == 0 { return .pickSix }
            if snap.differential == -7, snap.ballOn > 20 { return .rush(Int16(snap.ballOn) - 20) }
            return snap.neutral
        }
    }
}

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
    @Test("football · Rule 11-5-2 · after a safety the team scored upon free-kicks from its 20")
    func afterASafetyTheTeamScoredUponKicks() {
        let trace = RulesScenarios.safetyFreeKick.run()
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
    @Test("football · Rule 11-3-4 · after the try the team that defended it receives the kickoff")
    func afterTheTryTheDefendingTeamReceives() {
        let trace = RulesScenarios.touchdownTryKickoff.run()
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
        "football · Rule 11-4-6 · after a successful field goal the team scored upon receives the kickoff"
    )
    func afterAFieldGoalTheTeamScoredUponReceives() {
        let trace = RulesScenarios.fieldGoalThenKickoff.run()
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
        "football · Rule 11-3-1, 11-3-4 · a kickoff returned for a touchdown gets its try, and the returning team then kicks off"
    )
    func kickoffReturnTouchdownGetsItsTry() {
        let trace = RulesScenarios.kickoffReturnTouchdown.run()
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
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 16-1-3 · a touchdown as the fourth quarter expires, down seven, gets its try in that period at 0:00, and the kick sends the game to overtime"
    )
    func lastPlayTouchdownDownSeven() {
        let trace = RulesScenarios.lastPlayTouchdownDownSeven.run()
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
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the fourth quarter expires, down six, gets its try in that period at 0:00, and the kick wins it"
    )
    func lastPlayTouchdownDownSix() {
        let trace = RulesScenarios.lastPlayTouchdownDownSix.run()
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
        "football · Rule 4-8-2, 4-8-2-c, 11-3-2-b, 16-1-3 · a touchdown as the fourth quarter expires, down eight, gets a two-point try in that period at 0:00, and the conversion sends the game to overtime"
    )
    func lastPlayTouchdownDownEight() {
        let trace = RulesScenarios.lastPlayTouchdownDownEight.run()
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
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down two, gets no try because no try could affect the outcome"
    )
    func lastPlayTouchdownDownTwo() {
        let trace = RulesScenarios.lastPlayTouchdownDownTwo.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up four with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 6)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 2)
    }

    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down one, gets no try"
    )
    func lastPlayTouchdownDownOne() {
        let trace = RulesScenarios.lastPlayTouchdownDownOne.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up five with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 12)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 7)
    }

    @Test("football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, level, gets no try")
    func lastPlayTouchdownLevel() {
        let trace = RulesScenarios.lastPlayTouchdownLevel.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up six with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 6)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 0)
    }

    @Test(
        "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, up one, gets no try")
    func lastPlayTouchdownUpOne() {
        let trace = RulesScenarios.lastPlayTouchdownUpOne.run()
        guard let touchdown = touchdown(in: trace, quarter: 4) else { return }
        trace.expectLastPlay(touchdown.index, "up seven with time expired, the try is waived")
        trace.expectWinner(touchdown.scorer)
        trace.expectScore(touchdown.scorer, 13)
        trace.expectScore(trace.opponent(of: touchdown.scorer), 6)
    }

    /// The half does not end until the try has been played — the period is extended for
    /// it (4-8-2) — and the third quarter then opens with a kickoff and a full clock.
    @Test(
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the second quarter expires gets its try in that period at 0:00, and the second half then opens with a kickoff"
    )
    func touchdownAsTheSecondQuarterExpires() {
        let trace = RulesScenarios.touchdownAsSecondQuarterExpires.run()
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
        "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 11-3-4 · a touchdown as the first quarter expires gets its try in that period at 0:00, and the scoring team kicks off to open the second"
    )
    func touchdownAsTheFirstQuarterExpires() {
        let trace = RulesScenarios.touchdownAsFirstQuarterExpires.run()
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
        "football · Rule 4-1-1, 16-1-3 · a regular-season game level after four periods goes to one ten-minute overtime period"
    )
    func regulationTieGoesToOvertime() {
        let trace = RulesScenarios.scoreless.run()
        guard reachedOvertime(trace),
            let overtime = trace.first(where: { $0.situation.quarter == 5 })
        else { return }
        trace.expectPlay(
            overtime.index, kind: .kickoff, clock: 600,
            "overtime opens with a kickoff and ten minutes on the clock")
    }

    @Test(
        "football · Rule 16-1-3-d · regular-season overtime is never extended: level at the end of it is a tie"
    )
    func regularSeasonOvertimeExpiringLevelIsATie() {
        let trace = RulesScenarios.scoreless.run()
        guard reachedOvertime(trace) else { return }
        #expect(
            !trace.plays.contains { $0.situation.quarter >= 6 },
            "one period, and no more")
        trace.expectWinner(nil, "level at the end of the period, the game is a tie")
    }

    @Test(
        "football · Rule 16-1-4, 16-1-4-d · a postseason game level after the fifth period plays a sixth, of fifteen minutes"
    )
    func postseasonPlaysASixthPeriod() {
        let trace = RulesScenarios.scorelessPostseasonUntilTheSixthPeriod.run()
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
        "football · Rule 16-1-3-a, 16-1-3-b, 11-3-1 · a touchdown on the first overtime possession gets its try, and the other team then possesses"
    )
    func overtimeFirstPossessionTouchdown() {
        let trace = RulesScenarios.overtimeFirstPossessionTouchdown.run()
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
        "football · Rule 16-1-3-b, 16-1-3-c · once both teams have possessed in overtime, level, the next score of any kind wins"
    )
    func overtimeAfterBothPossessedEndsOnAnyScore() {
        let trace = RulesScenarios.overtimeFieldGoalsUntilOneIsUnanswered.run()
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

    /// A defence that intercepts has thereby possessed, so both sides have had their
    /// turn, and a defensive touchdown on the first possession ends it.
    @Test(
        "football · Rule 16-1-5-b, 16-1-3-b · an interception returned for a touchdown on the first overtime possession ends the game"
    )
    func overtimeDefensiveScoreEndsIt() {
        let trace = RulesScenarios.overtimeFirstPossessionInterceptionReturned.run()
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
        "football · Rule 16-1-3-a · a safety against the opening overtime drive wins it for the team that kicked off"
    )
    func overtimeOpeningDriveSafetyWinsIt() {
        let trace = RulesScenarios.overtimeOpeningDriveSafety.run()
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

    // MARK: The clock

    /// The fourth-down stop is a change of possession: the clock stops when the play
    /// ends and does not start again until the new offence snaps, so that offence's
    /// huddle costs it nothing.
    @Test("football · Rule 4-4-i, 4-3-2-a-1 · a turnover on downs stops the clock until the snap")
    func turnoverOnDownsStopsTheClock() {
        let trace = RulesScenarios.scoreless.run()
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
        "football · Rule 4-4-i, 4-3-2-a-1 · a punt returned and tackled in bounds stops the clock until the snap"
    )
    func puntReturnedAndTackledStopsTheClock() {
        let trace = RulesScenarios.puntReturnedAndTackled.run()
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
    @Test("football · Rule 4-4 · a fumble recovered by the offence keeps the clock running")
    func fumbleRecoveredByTheOffenseKeepsTheClockRunning() {
        let trace = RulesScenarios.fumbleRecoveredByTheOffense.run()
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
        "football · Rule 4-4-i, 4-3-2-a-1 · a fumble recovered by the defence stops the clock until the snap"
    )
    func fumbleRecoveredByTheDefenseStopsTheClock() {
        let trace = RulesScenarios.fumbleRecoveredByTheDefense.run()
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
        "football · Rule 4-4-a, 4-3-1, 4-4-i · a returned kickoff advances the game clock by the return, and no more"
    )
    func returnedKickoffAdvancesTheClock() {
        let trace = RulesScenarios.kickoffReturned.run()
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

    @Test("football · Rule 4-3-1, 4-4-d · a kickoff touchback consumes no time")
    func touchbackConsumesNoTime() {
        let trace = RulesScenarios.scoreless.run()
        trace.expectPlay(0, kind: .kickoff, endedIn: .touchback)
        trace.expectPlay(
            1, clock: 900, clockRunning: false,
            "nothing was touched in the field of play, so no clock ran, and it waits for the snap")
    }

    /// A play ends at 2:01 with the clock running. The clock reaches 2:00 between
    /// downs, the warning stops it there, and the snap that follows restarts it: the
    /// offence's huddle costs one second rather than its whole tempo.
    @Test(
        "football · Rule 3-41, 4-4-h · the two-minute warning stops a running clock at exactly 2:00 and the snap restarts it"
    )
    func twoMinuteWarningStopsAtTwoMinutes() {
        let trace = RulesScenarios.playStretchedToEnd(quarter: 4, at: 121).run()
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
        "football · Rule 3-41 · a down under way when the clock runs past 2:00 finishes, and the clock is dead after it"
    )
    func downUnderWayAtTwoMinutesFinishes() {
        let trace = RulesScenarios.playStretchedToEnd(quarter: 2, at: 117).run()
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

    // MARK: The ten-second runoff

    /// Inside two minutes with the clock running, a false start costs the offence ten
    /// seconds on top of the five yards, and the clock then starts on the ready-for-play
    /// signal rather than waiting for the snap. Filed with A5 (#32).
    @Test(
        "football · Rule 4-7-1 Item 1 · inside two minutes a false start with the clock running costs ten seconds, and the clock restarts on the ready"
    )
    func falseStartInsideTwoMinutesCostsTenSeconds() {
        let trace = RulesScenarios.falseStartInsideTwoMinutes.run()
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

    @Test("football · Rule 4-7-1 · outside two minutes the same false start carries no runoff")
    func falseStartOutsideTwoMinutesCostsNoTime() {
        let trace = RulesScenarios.falseStartOutsideTwoMinutes.run()
        guard let flag = flag(in: trace, quarter: 4) else { return }
        let before = flag.play.situation
        #expect(
            before.clockRemaining > 120, "the scenario meant the flag to fly outside two minutes")
        #expect(
            trace.clockRunning(into: flag.index) == true,
            "the scenario meant the clock to be running when the flag flew")
        trace.expectPlay(
            flag.index + 1, possession: before.possession, ballOn: before.ballOn + 5,
            "five yards, same down")
        trace.expectPlay(
            flag.index + 1, clock: before.clockRemaining - flag.huddle, clockRunning: true,
            "the huddle and nothing else: no play happened, and the clock restarts as though the flag had never flown"
        )
    }

    /// The runoff needs a running clock. After an incompletion the clock is stopped, so
    /// the flag costs five yards and nothing else, and the clock waits for the snap.
    @Test("football · Rule 4-7-1 Item 1 · a false start with the clock stopped carries no runoff")
    func falseStartWithTheClockStoppedCostsNoTime() {
        let trace = RulesScenarios.falseStartWithTheClockStopped.run()
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
    @Test("football · Rule 4-7-1 Item 1 · the defence may decline the runoff and keep the yardage")
    func trailingDefenseDeclinesTheRunoff() {
        let trace = RulesScenarios.falseStartAgainstATrailingDefense.run()
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
        "football · Rule 4-7-1 Item 1 · the offence may take a charged timeout instead of the runoff, and the clock then starts on the snap"
    )
    func offenseTakesATimeoutInsteadOfTheRunoff() {
        let trace = RulesScenarios.falseStartAtTwelveSecondsWithATimeout.run()
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
        "football · Rule 4-7-1 Item 1, 4-5-4 Note 4 · a ten-second runoff at eight seconds ends the half"
    )
    func runoffAtEightSecondsEndsTheHalf() {
        let trace = RulesScenarios.falseStartAtEightSecondsOfTheHalf.run()
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
        "football · Rule 4-7-1 Item 2, 4-4-e, 4-3-2-e · a defensive foul before the snap charges no time and the clock waits for the snap"
    )
    func deadBallFoulBeforeTheSnapChargesNoTime() {
        let trace = RulesScenarios.neutralZoneInfractionOnATrailingOffense.run()
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
        "football · Rule 4-4-f, 4-3-2 · an incomplete pass, here a spike, stops the clock until the snap"
    )
    func spikeStopsTheClock() {
        let trace = RulesScenarios.trailingByAPickSix.run(with: BaselineCaller())
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
        "pin · the baseline caller spikes at hurry-up tempo, and a hurry-up snap takes less clock than a huddle (PlayCaller.swift:224; the interval is a modelling convention, not a rule)"
    )
    func spikeIsCalledAtHurryUpTempo() {
        let trace = RulesScenarios.trailingByAPickSix.run(with: BaselineCaller())
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

    // MARK: Tries and kicks

    /// Filed as A7 (#19): a flag before the try moves the try, and it is still a try.
    @Test("football · Rule 11-3-1, 7-4-2 · a false start on a try moves the try back five yards")
    func falseStartOnATryMovesTheTry() {
        let trace = RulesScenarios.falseStartOnATry.run()
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
        "football · Rule 11-4-2 · a missed field goal struck from inside the 20 gives the defence the ball at its 20"
    )
    func missedFieldGoalFromInsideTheTwenty() {
        let trace = RulesScenarios.missedFieldGoal(from: 10).run()
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
        "football · Rule 11-4-2 · a missed field goal struck from beyond the 20 gives the defence the ball where it was struck"
    )
    func missedFieldGoalFromBeyondTheTwenty() {
        let trace = RulesScenarios.missedFieldGoal(from: 20).run()
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
        "football · Rule 8-4-6, 12-1-6, 14-4 (closest section) · defensive holding at the 3 is half the distance and a first down"
    )
    func defensiveHoldingAtTheThreeIsHalfTheDistance() {
        let trace = RulesScenarios.defensiveHoldingAtTheThree.run()
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
        "football · Rule 7-4-2, 14-4 (closest section) · a false start at the own 3 is half the distance to the goal line"
    )
    func falseStartAtTheOwnThreeIsHalfTheDistance() {
        let trace = RulesScenarios.falseStartAtTheOwnThree.run()
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
        "football · Rule 12-2-15, 14-4 (closest section) · a facemask at the end of a 20-yard run is 15 more from the end of the run, and a first down"
    )
    func facemaskAtTheEndOfARunIsEnforcedFromTheEndOfTheRun() {
        let trace = RulesScenarios.facemaskAtTheEndOfARun.run()
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
        "football · Rule 8-5-4 · defensive pass interference in the end zone is first and goal at the 1"
    )
    func interferenceInTheEndZoneSpotsAtTheOne() {
        let trace = RulesScenarios.interferenceInTheEndZone.run()
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
        "football · Rule 8-5-4 · defensive pass interference in the end zone from inside the 2 is half the distance, and still a first down"
    )
    func interferenceInTheEndZoneFromInsideTheTwo() {
        let trace = RulesScenarios.interferenceInTheEndZoneFromTheOne.run()
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
        "football · Rule 6-1-6, 6-1-4-c, 6-1-4-d · an onside kick the kicking team recovers is its ball, first and ten, where it was recovered"
    )
    func onsideRecoveryKeepsPossession() {
        let trace = RulesScenarios.onsideKickRecovered.run()
        guard
            let onside = trace.first(where: {
                CrudePlaybook.family(of: $0.calls.offense.design) == .onsideKick
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
}
