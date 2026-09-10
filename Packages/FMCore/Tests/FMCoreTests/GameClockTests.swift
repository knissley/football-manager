import Testing

@testable import FMCore

@Suite("Rules")
struct RulesTests {

    private let rules = Rules.standard

    /// One formula, in one place. It is the sort of arithmetic that gets rewritten
    /// slightly differently at three call sites, after which a kicker's range depends
    /// on which screen is asking.
    @Test("A field goal is the yards to the goal line, the end zone, and the snap depth")
    func fieldGoalDistance() {
        #expect(rules.fieldGoalDistance(ballOn: 30) == 47)
        #expect(rules.fieldGoalDistance(ballOn: 2) == 19)
        #expect(rules.fieldGoalDistance(ballOn: 45) == 62)
        // An extra point is snapped from the fifteen and is a thirty-two yard kick.
        #expect(rules.fieldGoalDistance(ballOn: rules.extraPointSnapYard) == 32)
    }

    /// Mixing "yards from my own goal" with "yards from theirs" is the recurring
    /// off-by-a-lot bug this codebase decided to design out. One named conversion.
    @Test("Own-yard spots convert to the stored convention")
    func ownYardConversion() {
        #expect(rules.ballOnFromOwnYard(20) == 80)
        #expect(rules.ballOnFromOwnYard(50) == 50)
        #expect(rules.puntTouchbackSpot == 80)
        #expect(rules.kickoffTouchbackSpot == 70)
    }

    @Test("Halves and periods follow the quarter count")
    func structure() {
        #expect(rules.halfLength == 1_800)
        #expect(rules.isEndOfHalf(quarter: 2))
        #expect(rules.isEndOfHalf(quarter: 4))
        #expect(rules.isEndOfHalf(quarter: 1) == false)
        #expect(rules.isEndOfHalf(quarter: 3) == false)
    }

    @Test("Overtime length and ties depend on the stage")
    func overtime() {
        #expect(rules.overtimeLength(isPostseason: false) == 600)
        #expect(rules.overtimeLength(isPostseason: true) == 900)
        #expect(rules.mayEndInATie(isPostseason: false))
        #expect(rules.mayEndInATie(isPostseason: true) == false)
    }

    /// Rules are data so variants can be tested. If a knob does not actually reach the
    /// derived value, it is decoration.
    @Test("Changing a rule changes what depends on it")
    func rulesAreData() {
        var variant = Rules.standard
        variant.fieldGoalSnapDepth = 8
        variant.puntTouchbackOwnYard = 25
        #expect(variant.fieldGoalDistance(ballOn: 30) == 48)
        #expect(variant.puntTouchbackSpot == 75)
    }
}

@Suite("Clock stoppage")
struct ClockStoppageTests {

    private let rules = Rules.standard

    private func behavior(
        _ ending: PlayEnding, quarter: UInt8 = 1, clock: UInt16 = 600
    ) -> ClockBehavior {
        rules.clockBehavior(after: ending, quarter: quarter, clockRemaining: clock)
    }

    @Test("Dead-ball endings stop the clock until the snap")
    func deadBallStops() {
        #expect(behavior(.incomplete) == .stopsUntilSnap)
        #expect(behavior(.touchdown) == .stopsUntilSnap)
        #expect(behavior(.intercepted) == .stopsUntilSnap)
        #expect(behavior(.fumbleLost) == .stopsUntilSnap)
        #expect(behavior(.safety) == .stopsUntilSnap)
        #expect(behavior(.touchback) == .stopsUntilSnap)
        #expect(behavior(.fieldGoalGood) == .stopsUntilSnap)
        #expect(behavior(.fieldGoalMissed) == .stopsUntilSnap)
        #expect(behavior(.fairCatch) == .stopsUntilSnap)
    }

    /// The ball stayed live, so the clock did too.
    ///
    /// Rewritten for A4 (#17): the `.downed` row asserted that a downed punt keeps the
    /// clock running. A downed kick has changed hands, and a change of possession stops
    /// the clock until the snap.
    @Test(
        "football · Rule 4-4, 4-4-i · a tackle in bounds and a fumble the offence falls on keep the clock running; a downed kick has changed hands and stops it"
    )
    func liveBallRuns() {
        #expect(behavior(.tackled) == .keepsRunning)
        #expect(behavior(.fumbleRecovered) == .keepsRunning)
        #expect(behavior(.downed) == .stopsUntilSnap, "a downed kick is a change of possession")
    }

    /// The ending alone cannot tell a fourth-down stop from a first-down tackle, or a
    /// returned punt from a run: both end `.tackled`. The change of possession is what
    /// stops the clock, whatever the ending.
    @Test(
        "football · Rule 4-4-i, 4-3-2-a-1 · a change of possession stops the clock until the snap, whatever the ending"
    )
    func changeOfPossessionStops() {
        for ending in PlayEnding.allCases {
            #expect(
                rules.clockBehavior(
                    after: ending, possessionChanged: true, quarter: 1, clockRemaining: 600)
                    == .stopsUntilSnap,
                "\(ending)")
        }
        #expect(
            rules.clockBehavior(
                after: .tackled, possessionChanged: false, quarter: 1, clockRemaining: 600)
                == .keepsRunning,
            "without a change of possession the ending decides")
    }

    /// **The rule most often modelled wrong**, and the one that decides whether a
    /// two-minute drill works at all. Early in a half, going out of bounds costs the
    /// offence the play clock and nothing more.
    @Test("Out of bounds stops the clock only until the ball is ready, most of the game")
    func outOfBoundsEarly() {
        #expect(behavior(.outOfBounds, quarter: 1, clock: 600) == .stopsUntilReadyForPlay)
        #expect(behavior(.outOfBounds, quarter: 2, clock: 400) == .stopsUntilReadyForPlay)
        #expect(behavior(.outOfBounds, quarter: 3, clock: 60) == .stopsUntilReadyForPlay)
        #expect(
            behavior(.outOfBounds, quarter: 4, clock: 400) == .stopsUntilReadyForPlay,
            "the fourth-quarter window is five minutes, not the whole quarter")
    }

    /// Late in a half it stops until the snap, and the windows are asymmetric: two
    /// minutes in the first half, five in the second. That asymmetry is real.
    @Test("Late in a half, out of bounds stops the clock until the snap")
    func outOfBoundsLate() {
        #expect(behavior(.outOfBounds, quarter: 2, clock: 120) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 2, clock: 30) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 2, clock: 121) == .stopsUntilReadyForPlay)

        #expect(behavior(.outOfBounds, quarter: 4, clock: 300) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 4, clock: 90) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 4, clock: 301) == .stopsUntilReadyForPlay)
    }

    /// The clock runs while the chains move. A first down is not a stoppage, and
    /// treating it as one would make every drive a two-minute drill.
    @Test("Gaining a first down does not stop the clock")
    func firstDownDoesNotStop() {
        #expect(behavior(.tackled, quarter: 4, clock: 100) == .keepsRunning)
    }

    @Test("The two-minute warning is detected on the play that crosses it")
    func twoMinuteWarningDetection() {
        #expect(rules.crossesTwoMinuteWarning(quarter: 2, clockBefore: 125, clockAfter: 118))
        #expect(rules.crossesTwoMinuteWarning(quarter: 4, clockBefore: 121, clockAfter: 120))
        #expect(
            rules.crossesTwoMinuteWarning(quarter: 2, clockBefore: 118, clockAfter: 110) == false)
        #expect(
            rules.crossesTwoMinuteWarning(quarter: 1, clockBefore: 125, clockAfter: 118) == false,
            "there is no warning at the end of the first quarter")
        #expect(
            rules.crossesTwoMinuteWarning(quarter: 3, clockBefore: 125, clockAfter: 118) == false)
    }
}

@Suite("The ten-second runoff")
struct TenSecondRunoffTests {

    private let rules = Rules.standard

    private func carriesRunoff(
        _ foul: Foul, byOffense: Bool = true, quarter: UInt8 = 4, clock: UInt16 = 40,
        running: Bool = true, postseason: Bool = false
    ) -> Bool {
        rules.carriesRunoff(
            foul: foul, byOffense: byOffense, quarter: quarter, isPostseason: postseason,
            clockRemaining: clock, clockWasRunning: running)
    }

    @Test("football · Rule 4-7-1 Item 1 · the runoff is ten seconds")
    func tenSeconds() {
        #expect(rules.tenSecondRunoff == 10)
    }

    /// After the two-minute warning of either half, with the clock running, an
    /// offensive dead-ball foul that stops the clock carries the runoff; the same foul
    /// outside the window, with the clock stopped, or by the defence does not.
    @Test(
        "football · Rule 4-7-1 Item 1, 4-7-1 Item 2, 4-7-2 · the runoff applies to an offensive dead-ball foul after the two-minute warning of either half with the clock running, and never to the defence"
    )
    func window() {
        for foul in [
            Foul.falseStart, .delayOfGame, .illegalFormation, .illegalMotion,
            .illegalShift, .illegalSubstitution,
        ] {
            #expect(carriesRunoff(foul), "\(foul) inside two minutes of the fourth quarter")
            #expect(
                carriesRunoff(foul, quarter: 2, clock: 90), "\(foul) inside two minutes of the half"
            )
        }
        #expect(carriesRunoff(.falseStart, quarter: 4, clock: 130) == false, "outside two minutes")
        #expect(
            carriesRunoff(.falseStart, quarter: 4, clock: 120) == false,
            "at the warning the clock is stopped")
        #expect(
            carriesRunoff(.falseStart, quarter: 1, clock: 40) == false,
            "no warning in the first period")
        #expect(carriesRunoff(.falseStart, quarter: 3, clock: 40) == false, "nor the third")
        #expect(
            carriesRunoff(.falseStart, quarter: 5, clock: 40),
            "fourth-quarter timing rules apply in regular-season overtime (16-1-3-e)")
        #expect(carriesRunoff(.falseStart, running: false) == false, "with the clock stopped")
        #expect(carriesRunoff(.offside, byOffense: false) == false, "never against the defence")
        #expect(carriesRunoff(.neutralZoneInfraction, byOffense: false) == false)
        #expect(carriesRunoff(.encroachment, byOffense: false) == false)
    }

    /// Postseason overtime reads its periods as halves for timing (16-1-4-h), which the
    /// engine does not model: `Rules.hasFourthPeriodTiming` answers no for every
    /// postseason overtime period, so no runoff applies there. Pinned so that the
    /// answer changes on purpose, with A11 (#74), rather than by accident.
    @Test(
        "pin · no runoff in postseason overtime, because postseason overtime timing (16-1-4-h) is not modelled pending #74"
    )
    func postseasonOvertimeRunoffIsNotModelled() {
        #expect(carriesRunoff(.falseStart, quarter: 5, clock: 40, postseason: true) == false)
    }
}

@Suite("Running the clock")
struct GameClockTests {

    private let rules = Rules.standard

    /// The distinction a team down four with sixty seconds and no timeouts lives on:
    /// after an incompletion the huddle is free, after a tackle in bounds it is not.
    @Test("The pre-snap interval only costs the clock when the clock was running")
    func elapsedDependsOnThePreviousStoppage() {
        let afterIncompletion = GameClock.elapsed(
            playDuration: 6, tempo: .hurryUp, previousBehavior: .stopsUntilSnap)
        #expect(afterIncompletion.beforeSnap == 0)
        #expect(afterIncompletion.total == 6)

        let afterTackle = GameClock.elapsed(
            playDuration: 6, tempo: .normal, previousBehavior: .keepsRunning)
        #expect(afterTackle.beforeSnap == Tempo.normal.secondsBetweenSnaps)
        #expect(afterTackle.total == 6 + Tempo.normal.secondsBetweenSnaps)

        let afterOutOfBounds = GameClock.elapsed(
            playDuration: 6, tempo: .normal, previousBehavior: .stopsUntilReadyForPlay)
        #expect(afterOutOfBounds.beforeSnap < afterTackle.beforeSnap)
        #expect(afterOutOfBounds.beforeSnap > 0)
    }

    /// Tempo is the mechanism behind both a two-minute drill and a four-minute one.
    @Test("Tempo spends the play clock, fastest to slowest")
    func tempoOrdering() {
        let ordered: [Tempo] = [.hurryUp, .fast, .normal, .slow, .bleedClock]
        let seconds = ordered.map(\.secondsBetweenSnaps)
        #expect(seconds == seconds.sorted())
        #expect(Tempo.bleedClock.secondsBetweenSnaps < UInt16(rules.playClock))
    }

    @Test("Running the clock down never goes below zero")
    func clockFloor() {
        var clock = GameClock(quarter: 1, secondsRemaining: 5)
        _ = clock.run(30, rules: rules)
        #expect(clock.secondsRemaining == 0)
        #expect(clock.isExpired)
    }

    /// Rewritten for A4 (#17). The old test pinned `run` clamping the whole interval —
    /// huddle and play together — at 2:00, which swallowed a play snapped just before
    /// the warning and truncated a down under way at 2:00. The warning is a stoppage
    /// between downs: when the clock reaches 2:00 in the huddle it stops there, the snap
    /// restarts it, and the play then runs from 2:00.
    @Test(
        "football · Rule 3-41, 4-4-h · the warning stops a running clock at 2:00 between downs, and the play then runs from there"
    )
    func warningBetweenDowns() {
        var clock = GameClock(quarter: 4, secondsRemaining: 128)
        let taken = clock.run(GameClock.Elapsed(duringPlay: 6, beforeSnap: 20), rules: rules)

        #expect(taken)
        #expect(clock.secondsRemaining == 114, "the huddle was cut at 2:00; the play ran six")
        #expect(clock.twoMinuteWarningTaken)
    }

    /// A down under way when the clock passes 2:00 finishes; only then is the clock
    /// dead, at whatever it reads.
    @Test(
        "football · Rule 3-41 · a down under way when the clock passes 2:00 finishes, and the clock is dead after it"
    )
    func warningDuringADown() {
        var clock = GameClock(quarter: 4, secondsRemaining: 128)
        let taken = clock.run(GameClock.Elapsed(duringPlay: 20, beforeSnap: 0), rules: rules)

        #expect(taken, "the warning is taken as the down ends")
        #expect(clock.secondsRemaining == 108, "the down finished")
        #expect(clock.twoMinuteWarningTaken)
    }

    @Test("The warning is taken once per half, not once per play")
    func warningTakenOnce() {
        var clock = GameClock(quarter: 2, secondsRemaining: 130)
        let firstCrossing = clock.run(
            GameClock.Elapsed(duringPlay: 0, beforeSnap: 15), rules: rules)
        #expect(firstCrossing)
        #expect(clock.secondsRemaining == 120)

        // The next play runs through freely.
        let secondCrossing = clock.run(
            GameClock.Elapsed(duringPlay: 0, beforeSnap: 15), rules: rules)
        #expect(secondCrossing == false)
        #expect(clock.secondsRemaining == 105)
    }

    @Test("There is no warning at the end of the first or third quarter")
    func noWarningMidHalf() {
        var clock = GameClock(quarter: 1, secondsRemaining: 128)
        let firstQuarter = clock.run(20, rules: rules)
        #expect(firstQuarter == false)
        #expect(clock.secondsRemaining == 108)

        var third = GameClock(quarter: 3, secondsRemaining: 128)
        let thirdQuarter = third.run(20, rules: rules)
        #expect(thirdQuarter == false)
    }

    /// It is a once-per-half stoppage, so it resets at the half and not every quarter.
    @Test("The warning resets at halftime and not between quarters")
    func warningResets() {
        let firstHalf = GameClock(quarter: 2, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let secondHalf = firstHalf.advancingPeriod(rules: rules)
        #expect(secondHalf?.quarter == 3)
        #expect(secondHalf?.twoMinuteWarningTaken == false)

        let thirdQuarter = GameClock(quarter: 3, secondsRemaining: 0, twoMinuteWarningTaken: true)
        #expect(thirdQuarter.advancingPeriod(rules: rules)?.twoMinuteWarningTaken == true)
    }

    @Test("Periods advance to a full quarter, then to overtime")
    func periods() {
        let first = GameClock(quarter: 1, secondsRemaining: 0)
        #expect(first.advancingPeriod(rules: rules)?.secondsRemaining == 900)

        let fourth = GameClock(quarter: 4, secondsRemaining: 0)
        let overtime = fourth.advancingPeriod(rules: rules)
        #expect(overtime?.quarter == 5)
        #expect(overtime?.secondsRemaining == 600)
        #expect(overtime?.twoMinuteWarningTaken == true, "overtime has no two-minute warning")

        let postseason = fourth.advancingPeriod(rules: rules, isPostseason: true)
        #expect(postseason?.secondsRemaining == 900)
    }

    /// The whole point of the model: a drill lives or dies on stoppages, not on yards.
    @Test("A two-minute drill gets more snaps when it stops the clock")
    func twoMinuteDrillArithmetic() {
        func snapsAvailable(alwaysStopping: Bool) -> Int {
            var clock = GameClock(quarter: 4, secondsRemaining: 118, twoMinuteWarningTaken: true)
            var snaps = 0
            var previous: ClockBehavior = .stopsUntilSnap

            while !clock.isExpired && snaps < 40 {
                let elapsed = GameClock.elapsed(
                    playDuration: 6, tempo: .hurryUp, previousBehavior: previous)
                _ = clock.run(elapsed, rules: rules)
                snaps += 1
                previous =
                    alwaysStopping
                    ? rules.clockBehavior(
                        after: .incomplete, quarter: 4, clockRemaining: clock.secondsRemaining)
                    : rules.clockBehavior(
                        after: .tackled, quarter: 4, clockRemaining: clock.secondsRemaining)
            }
            return snaps
        }

        let stopping = snapsAvailable(alwaysStopping: true)
        let running = snapsAvailable(alwaysStopping: false)
        #expect(
            stopping > running * 2, "stopping the clock: \(stopping), letting it run: \(running)")
        #expect(running >= 4, "even a running clock should allow a few hurry-up snaps")
    }
}
