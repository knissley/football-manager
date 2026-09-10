import FMCore
import FMSimulation

// The rules-conformance scenarios: the acceptance language for the rules layer, as
// scripted games.
//
// Every scenario in here was written from the 2025 rulebook as the football-domain
// skill's `references/game-rules.md` gives it — the citation each one carries is that
// file's — and never from the code. A scenario says what the sport does; whether the
// engine does it is what the run reports. Scenarios the engine cannot satisfy today are
// red on purpose and stay in the tree until the fix that turns them green.
//
// The scenarios are separate from the tests that run them, and they are a library rather
// than test support, so that a play-by-play printer can walk one and a reader can see the
// football without the assertions: `gamelog --scenario <name>`. The assertions are
// `RulesConformanceTests` in the engine's test target.
//
// The scripts themselves are internal to this module and the scenarios are reached by
// name, through `RulesScenario` — which is the list the tool prints. A conformance
// scenario a tool cannot name is one nobody can watch, and that is the thing this
// arrangement is here to prevent.
//
// Two conventions the clock scenarios rest on, neither of them a rule. A play's recorded
// situation is the moment the previous play ended, and the offence's tempo — the huddle —
// is charged at the snap when the clock is running, so a play snapped on a running clock
// ends at `clock - huddle - clockRunoff`; the huddle is measured from the game itself,
// never assumed. And a flag before the snap flies when the snap was due: the huddle has
// elapsed, no play time has, and only then does any runoff come off.

/// The rules-conformance scenarios, as scripted games.
///
/// The two openings other suites script their own endgames from are public; everything
/// else in here — the scripts and the named scenarios — is internal, and a scenario is
/// reached by name, through `RulesScenario`.
public enum RulesScenarios {

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
    public static func leadBySeven(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return snap.touchdown() }
        if snap.index == 2, snap.isTry { return .extraPoint(good: true) }
        return nil
    }

    /// The side that has the ball first scores on its first snap and misses the kick.
    public static func leadBySix(_ snap: Snap) -> Outcome? {
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

    /// Seven for the side that has the ball first, and then two more when the other
    /// side is tackled in its own end zone on its first snap: a lead of nine.
    static func leadByNine(_ snap: Snap) -> Outcome? {
        if snap.index == 1 { return snap.touchdown() }
        if snap.index == 2, snap.isTry { return .extraPoint(good: true) }
        if snap.index == 4 { return snap.safety() }
        return nil
    }

    static var lastPlayTouchdownDownNine: ScriptedGame {
        lastPlayTouchdown(trailingBy: 9, opening: leadByNine)
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

    /// The side that receives the overtime kickoff kicks a field goal on its first
    /// possession and then kicks off; what the kickoff produces is `kick`.
    static func overtimeFieldGoalThenKickoff(_ kick: Outcome) -> ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveFamily: {
                $0.quarter >= 5 && $0.down == .fourth ? .fieldGoal : .insideRun
            })
        ) { snap in
            if snap.quarter == 5, snap.isKickoff, snap.differential == 3 { return kick }
            return plod(snap)
        }
    }

    static var overtimeKickoffRecoveredByTheKickersAfterFieldGoal: ScriptedGame {
        overtimeFieldGoalThenKickoff(.kickoffRecoveredByTheKickers(at: 53))
    }

    static var overtimeKickoffReturnedForTouchdownAfterFieldGoal: ScriptedGame {
        overtimeFieldGoalThenKickoff(.kickoffReturnTouchdown)
    }

    /// The first side to possess in overtime scores a touchdown and kicks the point; the
    /// second side answers with a touchdown, trails by one, and goes for two.
    static var overtimeTrailingScorerGoesForTwo: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(twoPointDecision: {
                $0.quarter == 5 && $0.scoreDifferential == -1
            })
        ) { snap in
            guard snap.quarter == 5 else { return plod(snap) }
            if snap.isScrimmage, snap.differential == 0 || snap.differential == -7 {
                return snap.touchdown()
            }
            if snap.isTry, snap.differential == -1 { return .twoPoint(converted: true) }
            return plod(snap)
        }
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

    // MARK: Postseason overtime halves

    /// The home side of the scenario world at its default seed, for a script in which one
    /// side does something the other does not.
    static var home: TeamID { ScenarioWorld.world(seed: 1).teams[0].id }

    /// A scoreless postseason walk to a third overtime period, decided there by a field
    /// goal on the first fourth down. The home side spends two timeouts in the first
    /// overtime period and its last in the second; the away side spends none.
    static var thirdPostseasonOvertimePeriod: ScriptedGame {
        let home = home
        return ScriptedGame(
            isPostseason: true,
            caller: ScriptedCaller(
                offensiveFamily: {
                    $0.quarter == 7 && $0.down == .fourth ? .fieldGoal : .insideRun
                },
                timeoutDecision: { situation, isOffense in
                    guard isOffense, situation.possession == home else { return false }
                    switch situation.quarter {
                    case 5: return situation.offenseTimeouts > 1
                    case 6: return situation.offenseTimeouts > 0
                    default: return false
                    }
                }),
            play: plod)
    }

    /// The same walk, and the captain with the first choice at the third period elects
    /// to kick off rather than receive.
    static var thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff: ScriptedGame {
        ScriptedGame(
            isPostseason: true,
            caller: ScriptedCaller(
                offensiveFamily: {
                    $0.quarter == 7 && $0.down == .fourth ? .fieldGoal : .insideRun
                },
                receiveDecision: { $0.quarter != 7 }),
            play: plod)
    }

    /// A scoreless postseason walk to a fifth overtime period, decided there. The home
    /// side spends every timeout it has in every overtime period, so that what it opens
    /// each half with is the half's own and not a carry-over.
    static var fifthPostseasonOvertimePeriod: ScriptedGame {
        let home = home
        return ScriptedGame(
            isPostseason: true,
            caller: ScriptedCaller(
                offensiveFamily: {
                    $0.quarter == 9 && $0.down == .fourth ? .fieldGoal : .insideRun
                },
                timeoutDecision: { situation, isOffense in
                    isOffense && situation.possession == home && situation.quarter > 4
                        && situation.offenseTimeouts > 0
                }),
            play: plod)
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

    static var kickoffFairCaught: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 0 ? .kickoffFairCaught(atOwn: 25, seconds: 4) : plod(snap)
        }
    }

    /// A walk down `quarter` in which the first play that can be is stretched to end at
    /// `second` — tackled in bounds with the clock running, unless `endedIn` says the
    /// runner stepped out — and everything else is a yard at a time.
    ///
    /// With `snappedAfter` set, the play stretched is the first one snapped with more
    /// than that on the clock, so that it can be made to straddle a boundary: snapped
    /// outside a window and dead inside it, which is the one shape a play kept inside a
    /// window (`runnerOutOfBounds`) can never take.
    ///
    /// A postseason walk needs an end: a postseason game level at the end of a period
    /// plays another (16-1-4-d), so a scoreless one never finishes. With `decidedIn` set
    /// the game is the postseason's, and the side with the ball in that period kicks a
    /// field goal on its first fourth down, which in sudden death wins it.
    static func playStretchedToEnd(
        quarter: UInt8, at second: UInt16, endedIn: PlayEnding = .tackled,
        snappedAfter floor: UInt16 = 0, postseasonDecidedIn decidedIn: UInt8? = nil
    ) -> ScriptedGame {
        ScriptedGame(isPostseason: decidedIn != nil, caller: decider(decidedIn)) { snap in
            guard snap.isScrimmage, snap.quarter == quarter, snap.down != .fourth,
                let huddle = snap.huddle
            else { return snap.neutral }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            guard snapped > Int(second), snapped > Int(floor), snapped - Int(second) <= 130
            else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - Int(second)), endedIn: endedIn)
        }
    }

    /// A walk down `quarter` in which a runner goes out of bounds: on each snap taken
    /// with the clock running and `window` on it, except one straight after another such
    /// play, so that what follows the first is a plod and the restart can be read off
    /// it. Everything else is a yard at a time. `decidedIn` is as for
    /// `playStretchedToEnd`.
    ///
    /// The window is on the clock as the play's situation records it — the end of the
    /// play before — and this scenario keeps the whole play inside it: the huddle and
    /// the six seconds of the play come off that reading, so the runner is out of bounds
    /// inside the window however the window is judged. The play that straddles a
    /// window's edge, snapped outside it and dead inside it, is `playStretchedToEnd`
    /// with `snappedAfter`.
    static func runnerOutOfBounds(
        quarter: UInt8, window: ClosedRange<UInt16>, postseasonDecidedIn decidedIn: UInt8? = nil
    ) -> ScriptedGame {
        ScriptedGame(isPostseason: decidedIn != nil, caller: decider(decidedIn)) { snap in
            guard snap.isScrimmage, snap.quarter == quarter, snap.down != .fourth,
                snap.clockIsRunning, window.contains(snap.clock),
                snap.previous?.outcome.endedIn != .outOfBounds
            else { return snap.neutral }
            return .rush(1, endedIn: .outOfBounds)
        }
    }

    /// A caller that plods until `period`, when it kicks a field goal on fourth down:
    /// the way a scoreless postseason walk is brought to an end. With no period it never
    /// kicks.
    static func decider(_ period: UInt8?) -> ScriptedCaller {
        ScriptedCaller(offensiveFamily: {
            $0.quarter == period && $0.down == .fourth ? .fieldGoal : .insideRun
        })
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
        isPostseason: Bool = false,
        opening: @escaping @Sendable (Snap) -> Outcome? = { _ in nil },
        caller: ScriptedCaller = ScriptedCaller()
    ) -> ScriptedGame {
        ScriptedGame(isPostseason: isPostseason, caller: caller) { snap in
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

    static var falseStartInTheFourthQuarterOutsideTwoMinutes: ScriptedGame {
        lateFlag(window: 160...400)
    }

    static var falseStartInTheThirdQuarter: ScriptedGame {
        lateFlag(quarter: 3, window: 160...400)
    }

    /// The scoreless walk reaches overtime, and the flag flies inside its last two
    /// minutes.
    static var falseStartInsideTwoMinutesOfOvertime: ScriptedGame {
        lateFlag(quarter: 5, window: 40...119)
    }

    /// The scoreless walk reaches overtime, and the flag flies with more than five
    /// minutes left in it — outside every window, so that what decides the restart is
    /// the period's own timing and not a window's.
    static var falseStartInOvertimeOutsideTwoMinutes: ScriptedGame {
        lateFlag(quarter: 5, window: 340...500)
    }

    /// A postseason walk to a second overtime period, and the flag flies inside its last
    /// two minutes; a field goal in the third period ends the game.
    static var falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod: ScriptedGame {
        lateFlag(quarter: 6, window: 40...119, isPostseason: true, caller: decider(7))
    }

    /// A postseason walk, and the flag flies in the first overtime period with more than
    /// five minutes left in it; a field goal in the second period ends the game.
    static var falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes: ScriptedGame {
        lateFlag(quarter: 5, window: 340...500, isPostseason: true, caller: decider(6))
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

    // MARK: Fouls during a down

    /// A foul during a down, on a play that is run and ends in bounds, in a window of
    /// `quarter` where the clock is running into the snap. The flag flies on the play
    /// rather than before it, which is the difference 4-4-e turns on.
    ///
    /// The offence gains nothing on the flagged snap, so the non-offending side always
    /// prefers the yardage and the foul is accepted; the down before it is an ordinary
    /// plod, so the clock is running into the snap the flag comes on.
    static func flagDuringADown(
        _ foul: Foul, quarter: UInt8 = 4, window: ClosedRange<UInt16>
    ) -> ScriptedGame {
        ScriptedGame { snap in
            guard snap.isScrimmage, snap.quarter == quarter, window.contains(snap.clock),
                snap.clockIsRunning, snap.down != .fourth,
                let previous = snap.previous, previous.outcome.penalties.isEmpty,
                previous.situation.possession == snap.possession
            else { return snap.neutral }
            return snap.rush(0, foulBy: foul)
        }
    }

    /// The second snap of the game — the first with the clock running into it, since the
    /// opening kickoff leaves it dead until the snap — draws a defensive holding on a run
    /// stopped for no gain. The first period has neither a two-minute warning nor a late
    /// window, so nothing but 4-3-2-e decides how the clock restarts.
    static var defensiveHoldingOnAPlayEndingInBounds: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 2 ? snap.rush(0, foulBy: .defensiveHolding) : plod(snap)
        }
    }

    /// The same foul in the fourth quarter with between three and five minutes left, so
    /// that the play is dead inside the window 4-3-2-e-2 names and well outside the
    /// two-minute warning.
    static var defensiveHoldingInsideFiveMinutesOfTheFourthQuarter: ScriptedGame {
        flagDuringADown(.defensiveHolding, window: 200...290)
    }

    /// An offensive foul during a fourth-quarter down with between six and ten minutes
    /// left: outside every window, and outside 4-3-2-e-3, which reaches only a foul that
    /// stops the clock before a snap.
    static var offensiveHoldingInTheFourthQuarterOutsideFiveMinutes: ScriptedGame {
        flagDuringADown(.offensiveHolding, window: 400...600)
    }

    // MARK: The spike

    /// A fourth quarter played at hurry-up throughout, in which one second-down play is
    /// stretched so that the third-down snap after it — the spike — is taken with exactly
    /// `seconds` on the clock, with the clock running into it.
    ///
    /// Every snap is a hurry-up snap so that the offence's interval between downs is one
    /// number the trace can measure, and the spike's snap can be placed on the clock: a
    /// play recorded at `clock` on a running clock is snapped at `clock` less that
    /// interval. Nothing here says the offence is out of timeouts, which is *why* a real
    /// offence spikes rather than anything the clock rules turn on; the scripted caller
    /// never asks for one.
    static func spikeSnapped(at seconds: UInt16) -> ScriptedGame {
        let caller = ScriptedCaller(
            offensiveFamily: { situation in
                situation.quarter == 4 && situation.down == .third
                    && situation.clockRemaining <= seconds + 12 ? .spike : .insideRun
            },
            offensiveTempo: { _ in .hurryUp })
        return ScriptedGame(caller: caller) { snap in
            // Below the warning, and not at it: a stretched play that ran the clock past
            // 2:00 would be stopped there (3-41, 4-4-h) and the spike would be snapped on
            // a clock that was already dead, which is a different scenario.
            guard snap.isScrimmage, snap.quarter == 4, snap.clock < 118, snap.down == .second,
                snap.clockIsRunning, snap.family != .spike, let huddle = snap.huddle
            else { return snap.neutral }
            // Stretch this play so that it ends `huddle` seconds above the spike's snap:
            // the next snap then comes with exactly `seconds` left.
            let snapped = Int(snap.clock) - Int(huddle)
            let ends = Int(seconds) + Int(huddle)
            guard snapped > ends, snapped - ends <= 130 else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - ends))
        }
    }

    // MARK: The play clock

    /// The offence lets the play clock run out on a third-quarter snap with the game
    /// clock running. The flag flies when the play clock expires — forty seconds after
    /// the previous play ended (4-6-1) — and not when the huddle would have ended.
    static var delayOfGameOnARunningClock: ScriptedGame {
        lateFlag(.delayOfGame, quarter: 3, window: 160...400)
    }

    /// The first snap after the ball changes hands on downs in the first quarter, with
    /// the game clock stopped, is a delay of game: the play clock in force is the short
    /// one that follows an administrative stoppage (4-6-2-a), and no game clock ran.
    static var delayOfGameAfterATurnoverOnDowns: ScriptedGame {
        ScriptedGame { snap in
            guard snap.isScrimmage, snap.quarter == 1, snap.down == .first,
                (700...800).contains(snap.clock),
                let previous = snap.previous, previous.outcome.kind == .rush,
                previous.situation.down == .fourth,
                previous.situation.possession != snap.possession
            else { return snap.neutral }
            return snap.preSnapFoul(.delayOfGame)
        }
    }

    // MARK: The last forty seconds of a half

    /// Every side burns its second-half timeouts while on defence in the fourth quarter,
    /// well before the closing minutes, so that whoever is on defence at the end has
    /// none left to save the half with.
    static let defenseBurnsItsTimeouts = ScriptedCaller(timeoutDecision: { situation, isOffense in
        !isOffense && situation.quarter == 4 && situation.clockRemaining <= 800
            && situation.clockRemaining > 160 && situation.defenseTimeouts > 0
    })

    /// The defence jumps at 0:30 of the fourth quarter with the clock running, against
    /// an offence leading by seven from a first-snap touchdown, and with no timeouts
    /// left to save the half with.
    static var neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading: ScriptedGame {
        lateFlag(
            .neutralZoneInfraction, window: 41...119, by: 7, flagAt: 30, opening: leadBySeven,
            caller: defenseBurnsItsTimeouts)
    }

    /// The same flag at 0:30 with the game level and the defence out of timeouts.
    static var neutralZoneInfractionInTheLastFortySecondsLevel: ScriptedGame {
        lateFlag(
            .neutralZoneInfraction, window: 41...119, flagAt: 30, caller: defenseBurnsItsTimeouts)
    }

    /// The same flag at 0:30 against a leading offence, with the defence's timeouts
    /// intact.
    static var neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft: ScriptedGame {
        lateFlag(.neutralZoneInfraction, window: 41...119, by: 7, flagAt: 30, opening: leadBySeven)
    }

    // MARK: An injury after the two-minute warning

    /// A walk to the fourth quarter's closing two minutes in which the side whose score
    /// reads `differential` has the ball — the other side throws an interception when
    /// it has it there — and its first snap after the warning is stretched so that the
    /// play ends at 1:00 with the clock running. One of its players is hurt on that
    /// play. With `outOfTimeouts`, that side spent its second-half timeouts on offence
    /// earlier in the quarter, so the injury timeout has nothing to be charged to.
    static func injuryInsideTwoMinutes(
        by differential: Int16 = 0, outOfTimeouts: Bool,
        opening: @escaping @Sendable (Snap) -> Outcome? = { _ in nil }
    ) -> ScriptedGame {
        let caller =
            outOfTimeouts
            ? ScriptedCaller(timeoutDecision: { situation, isOffense in
                isOffense && situation.quarter == 4 && situation.scoreDifferential == differential
                    && situation.clockRemaining > 160 && situation.offenseTimeouts > 0
            })
            : ScriptedCaller()
        return ScriptedGame(
            caller: caller,
            injury: { snap, outcome in
                // The stretched play is the one longer than a plod.
                snap.quarter == 4 && snap.isScrimmage && outcome.kind == .rush
                    && outcome.endedIn == .tackled && outcome.clockRunoff > 6 ? .offense : nil
            }
        ) { snap in
            if let staged = opening(snap) { return staged }
            guard snap.isScrimmage, snap.quarter == 4, snap.clock <= 150 else {
                return snap.neutral
            }
            guard snap.differential == differential else { return .interception(to: 50) }
            guard snap.clock < 120, snap.down != .fourth, let huddle = snap.huddle else {
                return snap.neutral
            }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            let target = 60
            guard snapped > target, snapped - target <= 130 else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - target))
        }
    }

    static var injuryInsideTwoMinutesWithATimeoutLeft: ScriptedGame {
        injuryInsideTwoMinutes(outOfTimeouts: false)
    }

    static var injuryInsideTwoMinutesWithNoTimeoutsLeft: ScriptedGame {
        injuryInsideTwoMinutes(outOfTimeouts: true)
    }

    /// The injured side leads by seven and has no timeouts, so the defence that is
    /// offered the runoff is the trailing one.
    static var injuryInsideTwoMinutesAgainstATrailingDefense: ScriptedGame {
        injuryInsideTwoMinutes(by: 7, outOfTimeouts: true, opening: leadBySeven)
    }

    /// The fourth quarter's last forty seconds, with the offence leading by seven and a
    /// defender hurt on a play stretched to end at 0:30 with the clock running. The
    /// defence has spent its second-half timeouts earlier in the quarter, so the injury
    /// timeout is an excess one charged against it (4-5-4-b) and the offence, leading,
    /// has nothing to gain from the thirty seconds that remain.
    static var injuryToADefenderInTheLastFortySeconds: ScriptedGame {
        ScriptedGame(
            caller: defenseBurnsItsTimeouts,
            injury: { snap, outcome in
                // The stretched play is the one longer than a plod.
                snap.quarter == 4 && snap.isScrimmage && outcome.kind == .rush
                    && outcome.endedIn == .tackled && outcome.clockRunoff > 6 ? .defense : nil
            }
        ) { snap in
            if let staged = leadBySeven(snap) { return staged }
            guard snap.isScrimmage, snap.quarter == 4, snap.clock <= 150 else {
                return snap.neutral
            }
            guard snap.differential == 7 else { return .interception(to: 50) }
            guard snap.clock < 120, snap.down != .fourth, let huddle = snap.huddle else {
                return snap.neutral
            }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            let target = 30
            guard snapped > target, snapped - target <= 130 else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - target))
        }
    }

    // MARK: The kickoff that opens a half

    /// A first half that ends between downs, on an excess injury timeout's runoff, and
    /// the kickoff that opens the second. Both sides spend their first-half timeouts on
    /// offence early in the second quarter, so whichever side has the ball after the
    /// warning has none; its first snap after the warning is stretched to end at 0:08
    /// with the clock running, and one of its players is hurt on that play. Level, the
    /// defence takes the ten seconds (4-5-4 Note 3), which is more than remain, so the
    /// half ends on the runoff (4-5-4 Note 4). What the second-half kickoff produces is
    /// `kick`.
    static func injuryRunoffEndsTheFirstHalf(kick: Outcome) -> ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(timeoutDecision: { situation, isOffense in
                isOffense && situation.quarter == 2 && situation.clockRemaining > 160
                    && situation.offenseTimeouts > 0
            }),
            injury: { snap, outcome in
                // The stretched play is the one longer than a plod.
                snap.quarter == 2 && snap.isScrimmage && outcome.kind == .rush
                    && outcome.endedIn == .tackled && outcome.clockRunoff > 6 ? .offense : nil
            }
        ) { snap in
            if snap.quarter == 3, snap.isKickoff { return kick }
            guard snap.isScrimmage, snap.quarter == 2, snap.clock < 120, snap.down != .fourth,
                let huddle = snap.huddle
            else { return snap.neutral }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            let target = 8
            guard snapped > target, snapped - target <= 130 else { return snap.neutral }
            return .rush(1, seconds: UInt16(snapped - target))
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
