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
// Two conventions the clock scenarios rest on, neither of them a rule. The resolver is
// asked about a snap with the clock as the play before it left it, because the tempo the
// caller chose is what decides how long the interval to the snap will be; the rules layer
// then charges that interval and records the down with the clock it was really snapped
// on. So a script that needs a play to end at a particular second works from
// `clock - huddle` while an assertion over the stream reads the snap itself, and the
// huddle is measured from the game rather than assumed. And a flag before the snap flies
// when the snap was due: the interval has elapsed, no play time has, and only then does
// any runoff come off.

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
    /// Two windows, not one, and the right side's is read at the snap. Its window is a
    /// minute because snaps are never more than a play clock apart, so no walk down the
    /// clock can step over it, and the first snap inside it is therefore always one the
    /// clock can still reach. The wrong side's is wider: a snap on a running clock costs
    /// a huddle before the play, so an interception thrown inside the last thirty-odd
    /// seconds can expire the period itself. Inside two minutes the wrong side's first snap after taking the ball
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
            // The clock the ball will be snapped on, which on a running clock is the
            // offence's interval below the reading the resolver is asked with. It is the
            // second the touchdown has to run out, and a snap the clock cannot reach at
            // all is a period that ends with no down in it (4-8-1).
            let snapped =
                snap.clockIsRunning ? snap.clock - min(snap.clock, snap.huddle ?? 0) : snap.clock
            if snap.differential == differential {
                return snapped <= 60 ? snap.touchdown(seconds: max(1, snapped)) : snap.neutral
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
            caller: ScriptedCaller(offensiveConcept: { $0.ballOn == 20 ? .fieldGoal : .insideRun })
        ) { snap in
            if snap.index == 1 { return .rush(Int16(snap.ballOn) - 20) }
            return plod(snap)
        }
    }

    static var kickoffReturnTouchdown: ScriptedGame {
        ScriptedGame { snap in snap.index == 0 ? .kickoffReturnTouchdown : plod(snap) }
    }

    /// The side that has the ball first scores on its first snap, goes for two, and the
    /// defence intercepts the conversion and carries it out to midfield.
    ///
    /// Only the opening try is dictated. Nobody scores again, so no later try is called.
    static var twoPointTryIntercepted: ScriptedGame {
        ScriptedGame(caller: ScriptedCaller(twoPointDecision: { _ in true })) { snap in
            if snap.index == 1 { return snap.touchdown() }
            if snap.index == 2, snap.isTry { return .twoPointIntercepted(returnedTo: 50) }
            return plod(snap)
        }
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
            caller: ScriptedCaller(offensiveConcept: { $0.quarter == 6 ? .fieldGoal : .insideRun }),
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
            caller: ScriptedCaller(offensiveConcept: {
                $0.quarter >= 5 && $0.down == .fourth ? .fieldGoal : .insideRun
            }),
            play: plod)
    }

    /// The side that receives the overtime kickoff kicks a field goal on its first
    /// possession and then kicks off; what the kickoff produces is `kick`.
    static func overtimeFieldGoalThenKickoff(_ kick: Outcome) -> ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
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
                offensiveConcept: {
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
                offensiveConcept: {
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
                offensiveConcept: {
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
            caller: ScriptedCaller(offensiveConcept: { $0.down == .fourth ? .punt : .insideRun })
        ) { snap in
            snap.concept == .punt ? .punt(toOwn: 30, endedIn: .tackled) : plod(snap)
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

    /// The last two minutes of the fourth quarter, at hurry-up, with every second of it
    /// dictated rather than drawn.
    ///
    /// The walk down the period stretches one play to end at 2:01 — the clock running,
    /// the warning not yet taken — and that play gains ten, so the drill opens first and
    /// ten however the walk left the chains. From there the offence throws it away on one
    /// down and is tackled in bounds for a yard on the next, so the clock alternates
    /// between running into a snap and being dead into it. That alternation is the whole
    /// point: a drill lives on 4-3-2, where the interval before a snap costs the offence
    /// seconds only when nothing has stopped the clock.
    ///
    /// The eight seconds a hurry-up offence spends reaching the line is the engine's
    /// tempo table (`Tempo.hurryUp`, pinned by `test:tempoOrdering`) and not a rule. What
    /// is football is where those eight seconds land on the record.
    static var twoMinuteDrill: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(
                offensiveTempo: { $0.quarter == 4 && $0.clockRemaining <= 121 ? .hurryUp : .normal }
            )
        ) { snap in
            guard snap.isScrimmage, snap.quarter == 4 else { return snap.neutral }
            // The drill proper. Read off the play before rather than off the down, so
            // that the alternation is the same whoever has the ball.
            if snap.clock <= 121 {
                return snap.previous?.outcome.endedIn == .incomplete
                    ? .rush(1, seconds: 6) : .incompletion(seconds: 5)
            }
            // The walk down to it. A stretched play cannot skip the window, because a
            // snap on a running clock comes at most a huddle and a play after the last.
            guard snap.down != .fourth, let huddle = snap.huddle else { return snap.neutral }
            let snapped = Int(snap.clock) - (snap.clockIsRunning ? Int(huddle) : 0)
            guard snapped > 121, snapped - 121 <= 130 else { return snap.neutral }
            return .rush(10, seconds: UInt16(snapped - 121))
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
        ScriptedCaller(offensiveConcept: {
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
            if snap.down == .third, snap.concept != .spike {
                return Outcome(
                    kind: snap.concept.kind, yards: Int16(snap.distance),
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
    /// `gaining` is what the carry made. At nothing — the default — the non-offending
    /// side always prefers the yardage and the foul is accepted. At a gain worth more
    /// than the foul it is **declined**: five yards and an automatic first down are worth
    /// less than twenty and the same first down, so the offence keeps the play. Either
    /// way the down before it is an ordinary plod, so the clock is running into the snap
    /// the flag comes on.
    ///
    /// A gain has to stay short of the goal line or the down is a touchdown and a
    /// different scenario; the spot is guarded only when there is a gain to guard, so
    /// that adding the parameter cannot move a scenario that gains nothing.
    static func flagDuringADown(
        _ foul: Foul, gaining yards: Int16 = 0, quarter: UInt8 = 4, window: ClosedRange<UInt16>
    ) -> ScriptedGame {
        ScriptedGame { snap in
            guard snap.isScrimmage, snap.quarter == quarter, window.contains(snap.clock),
                snap.clockIsRunning, snap.down != .fourth,
                yards == 0 || Int(snap.ballOn) > Int(yards) + 5,
                let previous = snap.previous, previous.outcome.penalties.isEmpty,
                previous.situation.possession == snap.possession
            else { return snap.neutral }
            return snap.rush(yards, foulBy: foul)
        }
    }

    /// A pass grounded under pressure inside the last two minutes of the fourth quarter,
    /// on a down the clock was running into and that is not a fourth down, by an offence
    /// that had the ball on the play before: the act 4-7-1 lists at (b), committed with
    /// time in, so that what is left to watch is the ten seconds and the down.
    static var intentionalGroundingInsideTwoMinutes: ScriptedGame {
        ScriptedGame { snap in
            guard snap.isScrimmage, snap.quarter == 4, (40...119).contains(snap.clock),
                snap.clockIsRunning, snap.down != .fourth,
                let previous = snap.previous, previous.outcome.penalties.isEmpty,
                previous.situation.possession == snap.possession
            else { return snap.neutral }
            return snap.grounding()
        }
    }

    /// A team a long way behind scores inside the last two minutes of the fourth quarter,
    /// goes for two, and grounds the try. A try is one untimed scrimmage down (3-40), so
    /// time is not in (3-36-3), and 4-7-1 Item 1 — the runoff for an offensive act "while
    /// time is in" — has no ten seconds to run: the foul is enforced and the kickoff is
    /// put in play at the clock the touchdown left. The deficit is built in the first
    /// quarter, four touchdowns by whoever has the ball first, so that the side defending
    /// the try leads and has no reason to turn a runoff down; a leading offence's try
    /// hid the runoff before this scenario, because the trailing defence declined it.
    static var intentionalGroundingOnATwoPointTryInsideTwoMinutes: ScriptedGame {
        ScriptedGame(caller: ScriptedCaller(twoPointDecision: { _ in true })) { snap in
            if snap.isScrimmage, snap.quarter == 1, snap.down == .first,
                (0..<24).contains(snap.differential)
            {
                return snap.touchdown()
            }
            if snap.isScrimmage, snap.quarter == 4, (60...119).contains(snap.clock),
                snap.clockIsRunning, snap.differential < 0
            {
                return snap.touchdown()
            }
            if snap.isTry, snap.concept == .twoPointPass, snap.quarter == 4, snap.clock < 120,
                snap.differential < 0
            {
                return snap.groundedTry()
            }
            return snap.neutral
        }
    }

    /// The grounding comes on the down that brings the two-minute warning: snapped with a
    /// little over two minutes left, and running the clock through 2:00. The warning is an
    /// automatic timeout at the conclusion of the last down snapped before two minutes
    /// remain (3-41), so a foul during that down came before it, and 4-7-1 reaches only
    /// the acts after it: the down and the ten yards are lost as ever, no ten seconds
    /// are, and the clock — stopped by the warning — waits for the snap.
    ///
    /// The offence plays fast all game so that no two snaps are more than about twenty
    /// seconds apart and one is sure to fall in the window; the snap is where the clock
    /// stood less the measured huddle, and the play's own seconds are set from that to
    /// end it under 2:00 whichever play clock the interval was counted against.
    static var intentionalGroundingOnTheDownThatBringsTheWarning: ScriptedGame {
        ScriptedGame(caller: ScriptedCaller(offensiveTempo: { _ in .fast })) { snap in
            let huddle = snap.clockIsRunning ? Int(snap.huddle ?? 0) : 0
            let snapped = Int(snap.clock) - huddle
            guard snap.isScrimmage, snap.quarter == 4, snap.down != .fourth,
                (121...145).contains(snapped),
                let previous = snap.previous, previous.outcome.penalties.isEmpty
            else { return snap.neutral }
            return snap.grounding(seconds: UInt16(snapped - 112))
        }
    }

    /// The grounding comes on the down that runs the first half out: a pass snapped in the
    /// last forty seconds of the second quarter whose own seconds take the clock to zero.
    /// The period continues until the down ends (4-8-1) and an offensive foul extends
    /// nothing (4-8-2-b), so the half is over when the flag is enforced, time is not in,
    /// and 4-7-1 Item 1 has neither ten seconds to run off nor a timeout to offer in their
    /// place: no clock election is written, and the next snap is the second half's.
    static var intentionalGroundingAsTheHalfExpires: ScriptedGame {
        ScriptedGame { snap in
            let huddle = snap.clockIsRunning ? Int(snap.huddle ?? 0) : 0
            let snapped = Int(snap.clock) - huddle
            guard snap.isScrimmage, snap.quarter == 2, snap.down != .fourth,
                (1...40).contains(snapped),
                let previous = snap.previous, previous.outcome.penalties.isEmpty
            else { return snap.neutral }
            return snap.grounding(seconds: UInt16(snapped + 3))
        }
    }

    /// A team a long way behind grounds a pass on fourth down inside the last two minutes
    /// of the fourth quarter. The down is lost and it was the last of the series, so the
    /// defence takes over where the ten yards leave the ball (8-2-Penalty, 3-8-2); the act
    /// is the offence's, after the warning and with time in, so the ten seconds come off
    /// (4-7-1 Item 1) — the side taking the ball leads and has no reason to turn them
    /// down — and then the clock starts on the ready for the new offence, as after any
    /// runoff (4-3-2-g), the change of possession notwithstanding. The deficit is built in
    /// the first quarter, four touchdowns by whoever has the ball first.
    static var intentionalGroundingOnFourthDownInsideTwoMinutes: ScriptedGame {
        ScriptedGame { snap in
            if snap.isScrimmage, snap.quarter == 1, snap.down == .first,
                (0..<24).contains(snap.differential)
            {
                return snap.touchdown()
            }
            guard snap.isScrimmage, snap.quarter == 4, (40...119).contains(snap.clock),
                snap.clockIsRunning, snap.down == .fourth, snap.differential < 0,
                snap.ballOn > 15,
                let previous = snap.previous, previous.outcome.penalties.isEmpty,
                previous.situation.possession == snap.possession
            else { return snap.neutral }
            return snap.grounding()
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

    /// The same second snap of the game, and the same foul, on a carry of twenty: the
    /// five yards and the automatic first down are worth less than the gain, so the
    /// offence turns the penalty down. The down still ended with a flag on it, and the
    /// first period has neither a warning nor a late window, so what is left to watch is
    /// whether a declined foul stops the clock the way an accepted one does.
    static var declinedDefensiveHoldingOnAPlayEndingInBounds: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 2 ? snap.rush(20, foulBy: .defensiveHolding) : plod(snap)
        }
    }

    /// The same declined foul in the fourth quarter with between three and five minutes
    /// left, so that the play is dead inside the window 4-3-2-e-2 names and well outside
    /// the two-minute warning.
    static var declinedDefensiveHoldingInsideFiveMinutesOfTheFourthQuarter: ScriptedGame {
        flagDuringADown(.defensiveHolding, gaining: 20, window: 200...290)
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
            offensiveConcept: { situation in
                situation.quarter == 4 && situation.down == .third
                    && situation.clockRemaining <= seconds + 12 ? .spike : .insideRun
            },
            offensiveTempo: { _ in .hurryUp })
        return ScriptedGame(caller: caller) { snap in
            // Below the warning, and not at it: a stretched play that ran the clock past
            // 2:00 would be stopped there (3-41, 4-4-h) and the spike would be snapped on
            // a clock that was already dead, which is a different scenario.
            guard snap.isScrimmage, snap.quarter == 4, snap.clock < 118, snap.down == .second,
                snap.clockIsRunning, snap.concept != .spike, let huddle = snap.huddle
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

    /// A third and one in the first quarter that the offence does not get snapped: the
    /// play clock in force runs out with the ball dead.
    ///
    /// Two drives to it, both scripted — nine yards on first down, nothing on second —
    /// so that the down the clock beats is one where the five yards of 4-6-4 decide
    /// something. What the offence does about it is the caller's, and this game is run
    /// with two: one bench that spends a charged timeout on a play clock it is not going
    /// to beat, and one that has no answer at all.
    static var thePlayClockExpiresOnThirdAndOne: ScriptedGame {
        ScriptedGame(
            playClockExpires: { snap in
                snap.isScrimmage && snap.quarter == 1 && snap.down == .third
                    && snap.distance == 1
            }
        ) { snap in
            guard snap.isScrimmage, snap.quarter == 1 else { return snap.neutral }
            switch snap.down {
            case .first: return .rush(9)
            case .second: return .rush(0)
            default: return snap.neutral
            }
        }
    }

    /// The bench that answers the play clock: the offence spends a charged timeout when,
    /// and only when, the clock is about to beat it (2025 rulebook, 4-3-2, 4-6-4).
    static let spendsATimeoutOnThePlayClock = ScriptedCaller(
        timeoutOnThePlayClock: { _, context in context.playClockExpired })

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
    /// The half goes on after this flag, so the offence has to be able to reach another
    /// snap: the clock restarts on the ready (4-7-1 Item 2) and an offence at normal
    /// tempo would not get there from 0:30, which would end the period between downs
    /// (4-8-1) and hide what this scenario is for. At hurry-up it gets there.
    static var neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft: ScriptedGame {
        lateFlag(
            .neutralZoneInfraction, window: 41...119, by: 7, flagAt: 30, opening: leadBySeven,
            caller: ScriptedCaller(offensiveTempo: {
                $0.quarter == 4 && $0.clockRemaining <= 40 ? .hurryUp : .normal
            }))
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
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == yardLine ? .fieldGoal : .insideRun
            })
        ) { snap in
            if snap.index == 1 { return .rush(Int16(snap.ballOn) - Int16(yardLine)) }
            if snap.concept == .fieldGoal { return .fieldGoal(good: false) }
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

    /// The offence throws from its own 30 and is picked off at the other side's 3, which
    /// is where the false start that follows is worth half the distance. The throw is
    /// called as a throw so that the record's concept is the play it plays.
    static var falseStartAtTheOwnThree: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 70 && $0.down == .first ? .mediumPass : .insideRun
            })
        ) { snap in
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

    // MARK: The half-distance ceiling short of a goal line
    //
    // 14-2-1 caps a distance penalty at the midpoint between the spot it is enforced
    // from and the goal line the offending team defends. The cap bites whenever the
    // walk-off is longer than half that distance — which is a wider band than the
    // walk-offs that would reach the goal line outright, and the three scripts below
    // live in the part of it the older scenarios never enter: half the distance is
    // shorter than the penalty, and the penalty is still shorter than the distance.

    /// A drive to the 7, then defensive holding on a run that goes nowhere. Five yards
    /// is more than half of seven, so the ball stops at the midpoint rather than the 2.
    static var defensiveHoldingAtTheSeven: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 7)
            case 2: return snap.rush(0, foulBy: .defensiveHolding)
            default: return plod(snap)
            }
        }
    }

    /// A drive to the 20, then a facemask on a run that goes nowhere. Fifteen yards is
    /// more than half of twenty, so the ball stops at the midpoint rather than the 5.
    /// This is the common case of the ceiling: every contact foul in the red zone.
    static var facemaskAtTheTwenty: ScriptedGame {
        ScriptedGame { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 20)
            case 2: return snap.rush(0, foulBy: .facemask)
            default: return plod(snap)
            }
        }
    }

    /// The offence throws from its own 30 and is picked off at the other side's 7, where
    /// the false start that follows is worth half the distance rather than five yards.
    /// The throw is called as a throw so that the record's concept is the play it plays.
    static var falseStartAtTheOwnSeven: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 70 && $0.down == .first ? .mediumPass : .insideRun
            })
        ) { snap in
            switch snap.index {
            case 1: return .interception(to: 7)
            case 2: return snap.preSnapFoul(.falseStart)
            default: return plod(snap)
            }
        }
    }

    /// A touchdown, then a two-point try walked out to the 7 by a false start and walked
    /// back in by defensive offside.
    ///
    /// Two flags rather than one because a try starts on the 2, where five yards would
    /// reach the goal line and every reading of the ceiling agrees. Walked out to the 7
    /// first, the same five yards land in the band where they do not: 11-3-3 exempts no
    /// try from 14-2-1, and 14-3-4-f puts the try's own spot among the spots 14-2-1
    /// measures from.
    static var twoPointTryWalkedOutAndBackIn: ScriptedGame {
        ScriptedGame(caller: ScriptedCaller(twoPointDecision: { _ in true })) { snap in
            switch snap.index {
            case 1: return snap.touchdown()
            case 2: return snap.preSnapFoul(.falseStart)
            case 3: return snap.preSnapFoul(.offside)
            case 4: return .twoPoint(converted: true)
            default: return plod(snap)
            }
        }
    }

    /// A run to the opponents' 30, then a throw at the end zone a defender interferes on.
    /// The throw is called as a deep throw so that the record's concept is the play it
    /// plays.
    static var interferenceInTheEndZone: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 30 && $0.down == .first ? .deepPass : .insideRun
            })
        ) { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 30)
            case 2: return snap.incompletion(interferenceAt: 35)
            default: return plod(snap)
            }
        }
    }

    /// The same interference from the 1, where half the distance rather than the spot is
    /// the answer. The throw is called as a throw so that the record's concept is the play
    /// it plays.
    static var interferenceInTheEndZoneFromTheOne: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 1 && $0.down == .first ? .quickPass : .insideRun
            })
        ) { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 1)
            case 2: return snap.incompletion(interferenceAt: 3)
            default: return plod(snap)
            }
        }
    }

    /// A drive to the twenty, then a field goal with a flag on the rush at the kicker.
    ///
    /// Whether the kick is good and which of the two kicker fouls it was are the two axes
    /// 14-2-3 turns on: a made kick carries a personal foul to the free kick, and a missed
    /// one is enforced on the down like any other.
    static func kickerFoul(_ foul: Foul, good: Bool) -> ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: { $0.ballOn == 20 ? .fieldGoal : .insideRun })
        ) { snap in
            if snap.index == 1 { return .rush(Int16(snap.ballOn) - 20) }
            if snap.concept == .fieldGoal {
                return snap.kick(.fieldGoal, good: good, foulBy: foul)
            }
            return plod(snap)
        }
    }

    /// A touchdown, then a successful extra point with an offensive hold on it.
    static var holdingOnASuccessfulTry: ScriptedGame {
        ScriptedGame { snap in
            if snap.index == 1 { return snap.touchdown() }
            if snap.concept == .extraPoint {
                return snap.kick(.extraPoint, good: true, foulBy: .offensiveHolding)
            }
            return plod(snap)
        }
    }

    /// The first snap from scrimmage, at the offence's own 35 — where a kickoff
    /// touchback leaves it under the 2025 book (6-1-5) — is a run of ten yards on which a
    /// defender is flagged for unnecessary roughness; the back is stripped at the end of
    /// it, at his own 45, and the defence takes it back to the offence's 25.
    ///
    /// A run followed by a change of possession takes the spot where possession went as
    /// its basic spot (14-3-5-b), and a defensive foul gives the ball back to the offence
    /// before the walk-off (14-4-3-a): fifteen from its own 45, not fifteen from its 35.
    /// The gain is what makes the fumble the spot — a fumble behind the line would send
    /// the flag back to the previous spot (14-3-6, the exception for the defence), which
    /// is the strip-sack scenario below.
    static var roughnessByTheDefenseOnARunThatEndsInAFumbleLost: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 1
                ? snap.rush(10, fumbledAndReturnedTo: 75, foulBy: .unnecessaryRoughness)
                : plod(snap)
        }
    }

    /// The same field position and the same flag, thrown instead of run: the first snap
    /// from scrimmage, at the offence's own 35, is a pass a defender is flagged for
    /// unnecessary roughness on before it is picked off ten yards downfield — at the
    /// offence's 45 — and run back to its 25.
    ///
    /// Until a forward pass from behind the line is over, a flag on
    /// either side comes off the previous spot (14-4-5, and the same sentence as 8-6-1),
    /// and the down does not turn into a running play until somebody catches the ball. A
    /// defensive personal foul before the catch takes the better of two spots for the
    /// offence — where it snapped, or where the ball was dead (14-4-5-d): the interceptor was
    /// dropped at the offence's own 25, behind where it snapped, so the previous spot is
    /// the better of the two — fifteen from its own 35, and the interception is wiped out.
    /// The offence throws on first down from its own 35 so that the record's concept is
    /// the play the script gives it.
    static var roughnessByTheDefenseBeforeAnInterception: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 65 && $0.down == .first ? .mediumPass : .insideRun
            })
        ) { snap in
            snap.index == 1
                ? snap.interception(caught: 10, returnedTo: 75, foulBy: .unnecessaryRoughness)
                : plod(snap)
        }
    }

    /// A run to the offence's own 40, then a dropback on which a defender is flagged for
    /// unnecessary roughness and the quarterback is stripped six yards behind the line, at
    /// his own 34; the defence falls on it and takes it back to the offence's 20.
    ///
    /// The ball came loose behind the line, so the basic spot is behind the line, and a
    /// defensive foul — behind the line or beyond it — is walked off from the previous
    /// spot instead (14-3-6, the exception for the defence; 14-4-6-b for a foul during the
    /// fumble itself): fifteen from the own 40, not fifteen from the own 34, which would
    /// charge the offence for the sack a second time. The dropback is called as a throw so
    /// that the record's concept is the play it plays.
    static var roughnessByTheDefenseOnAStripSack: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 60 && $0.down == .first ? .mediumPass : .insideRun
            })
        ) { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 60)
            case 2: return snap.sack(-6, fumbledAndReturnedTo: 80, foulBy: .unnecessaryRoughness)
            default: return plod(snap)
            }
        }
    }

    /// A run to the opponents' 45, then a throw a defender is flagged for unnecessary
    /// roughness on; it is picked off at the opponents' 20 and the interceptor is dropped
    /// at the opponents' 30 — fifteen yards nearer the goal line than the snap was.
    ///
    /// The other arm of the same exception. A defensive personal foul before a forward
    /// pass thrown from behind the line is completed is walked off from the better of two
    /// spots for the offence — where it snapped, or where the ball was dead (14-4-5-d, and
    /// the same sentence as 8-6-1-d); an interception is not a completion (8-1-3), which
    /// puts a foul that preceded it inside the exception and not outside it. Here the
    /// dead-ball spot is the better of the two, so it is fifteen from the opponents' 30
    /// and not fifteen from the opponents' 45. The throw is called as a throw so that the
    /// record's concept is the play it plays.
    static var roughnessByTheDefenseBeforeADeepInterception: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(offensiveConcept: {
                $0.ballOn == 45 && $0.down == .first ? .mediumPass : .insideRun
            })
        ) { snap in
            switch snap.index {
            case 1: return .rush(Int16(snap.ballOn) - 45)
            case 2:
                return snap.interception(
                    caught: 25, returnedTo: 30, foulBy: .unnecessaryRoughness)
            default: return plod(snap)
            }
        }
    }

    /// The opening kickoff is fielded two yards deep, fumbled, and carried into the end
    /// zone by the kicking team.
    static var kickoffFumbledAndReturnedByTheKickers: ScriptedGame {
        ScriptedGame { snap in
            snap.index == 0 ? .kickoffFumbledAndReturnedByTheKickers : plod(snap)
        }
    }

    /// A pick-six puts one side up seven; the other kicks a field goal, is down four,
    /// and kicks onside. The kicking team falls on it at its own 47.
    static var onsideKickRecovered: ScriptedGame {
        ScriptedGame(
            caller: ScriptedCaller(
                offensiveConcept: { $0.ballOn == 20 ? .fieldGoal : .insideRun },
                onsideDecision: { $0.scoreDifferential < 0 })
        ) { snap in
            if snap.concept == .onsideKick { return .onsideKick(recoveredAt: 53) }
            guard snap.isScrimmage else { return snap.neutral }
            if snap.differential == 0 { return .pickSix }
            if snap.differential == -7, snap.ballOn > 20 { return .rush(Int16(snap.ballOn) - 20) }
            return snap.neutral
        }
    }
}
