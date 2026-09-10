import Testing

@testable import FMCore

@Suite("Rules")
struct RulesTests {

    private let rules = Rules.standard

    /// One formula, in one place. It is the sort of arithmetic that gets rewritten
    /// slightly differently at three call sites, after which a kicker's range depends
    /// on which screen is asking.
    @Test(
        "A field goal is the yards to the goal line, the end zone, and the snap depth", .tags(.unit)
    )
    func fieldGoalDistance() {
        #expect(rules.fieldGoalDistance(ballOn: 30) == 47)
        #expect(rules.fieldGoalDistance(ballOn: 2) == 19)
        #expect(rules.fieldGoalDistance(ballOn: 45) == 62)
        // An extra point is snapped from the fifteen and is a thirty-two yard kick.
        #expect(rules.fieldGoalDistance(ballOn: rules.extraPointSnapYard) == 32)
    }

    /// Mixing "yards from my own goal" with "yards from theirs" is the recurring
    /// off-by-a-lot bug this codebase decided to design out. One named conversion.
    @Test("Own-yard spots convert to the stored convention", .tags(.unit))
    func ownYardConversion() {
        #expect(rules.ballOnFromOwnYard(20) == 80)
        #expect(rules.ballOnFromOwnYard(50) == 50)
        #expect(rules.puntTouchbackSpot == 80)
        #expect(rules.kickoffTouchbackSpot == 70)
    }

    @Test("Halves and periods follow the quarter count", .tags(.unit))
    func structure() {
        #expect(rules.halfLength == 1_800)
        #expect(rules.isEndOfHalf(quarter: 2))
        #expect(rules.isEndOfHalf(quarter: 4))
        #expect(rules.isEndOfHalf(quarter: 1) == false)
        #expect(rules.isEndOfHalf(quarter: 3) == false)
    }

    @Test("Overtime length and ties depend on the stage", .tags(.unit))
    func overtime() {
        #expect(rules.overtimeLength(isPostseason: false) == 600)
        #expect(rules.overtimeLength(isPostseason: true) == 900)
        #expect(rules.mayEndInATie(isPostseason: false))
        #expect(rules.mayEndInATie(isPostseason: true) == false)
    }

    /// Rules are data so variants can be tested. If a knob does not actually reach the
    /// derived value, it is decoration.
    @Test("Changing a rule changes what depends on it", .tags(.unit))
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

    @Test("Dead-ball endings stop the clock until the snap", .tags(.unit))
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
        "football · Rule 4-4, 4-4-i · a tackle in bounds and a fumble the offence falls on keep the clock running; a downed kick has changed hands and stops it",
        .tags(.football)
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
        "football · Rule 4-4-i, 4-3-2-a-1 · a change of possession stops the clock until the snap, whatever the ending",
        .tags(.football)
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
    @Test(
        "Out of bounds stops the clock only until the ball is ready, most of the game", .tags(.unit)
    )
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
    @Test("Late in a half, out of bounds stops the clock until the snap", .tags(.unit))
    func outOfBoundsLate() {
        #expect(behavior(.outOfBounds, quarter: 2, clock: 120) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 2, clock: 30) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 2, clock: 121) == .stopsUntilReadyForPlay)

        #expect(behavior(.outOfBounds, quarter: 4, clock: 300) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 4, clock: 90) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 4, clock: 301) == .stopsUntilReadyForPlay)
    }

    /// Regular-season overtime is timed as the fourth quarter (16-1-3-e), the
    /// five-minute out-of-bounds window included.
    @Test(
        "football · Rule 16-1-3-e, 4-3-2-a · regular-season overtime carries the fourth period's five-minute window: out of bounds inside it stops the clock until the snap",
        .tags(.football)
    )
    func outOfBoundsInRegularSeasonOvertime() {
        #expect(behavior(.outOfBounds, quarter: 5, clock: 300) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 5, clock: 90) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 5, clock: 301) == .stopsUntilReadyForPlay)
    }

    /// 4-3-2-e-3 names its periods — the fourth, and regular-season overtime — and what
    /// 16-1-4-h lends postseason overtime is a half's closing rules, which for a foul are
    /// the windows of e-1 and e-2. So in postseason overtime the offence's foul before
    /// the snap starts the clock on the snap inside a second period's two minutes and a
    /// fourth period's five, and nowhere else.
    @Test(
        "football · Rule 4-3-2-e, 16-1-4-h · after an offensive foul before the snap the clock starts on the snap anywhere in the fourth period or regular-season overtime (e-3), and in postseason overtime only inside the windows a second or a fourth overtime period is lent (e-1, e-2)",
        .tags(.football)
    )
    func offensiveFoulBeforeTheSnapInPostseasonOvertime() {
        func startsOnTheSnap(quarter: UInt8, clock: UInt16, postseason: Bool = true) -> Bool {
            rules.clockStartsOnTheSnapAfterFoul(
                byOffense: true, quarter: quarter, isPostseason: postseason, clockRemaining: clock)
        }
        #expect(
            startsOnTheSnap(quarter: 4, clock: 600, postseason: false),
            "the fourth period, anywhere in it")
        #expect(
            startsOnTheSnap(quarter: 5, clock: 400, postseason: false),
            "regular-season overtime, anywhere in it")
        #expect(
            startsOnTheSnap(quarter: 5, clock: 400) == false,
            "a first postseason overtime period is a first period")
        #expect(startsOnTheSnap(quarter: 5, clock: 250) == false, "and has no five-minute window")
        #expect(
            startsOnTheSnap(quarter: 6, clock: 400) == false,
            "a second overtime period, outside two minutes")
        #expect(
            startsOnTheSnap(quarter: 6, clock: 250) == false,
            "the first half's window is two minutes, not five")
        #expect(
            startsOnTheSnap(quarter: 6, clock: 100),
            "inside two minutes of a second overtime period (e-1)")
        #expect(
            startsOnTheSnap(quarter: 7, clock: 250) == false,
            "a third overtime period is a third period")
        #expect(
            startsOnTheSnap(quarter: 8, clock: 400) == false,
            "a fourth overtime period, outside five minutes")
        #expect(
            startsOnTheSnap(quarter: 8, clock: 250),
            "inside five minutes of a fourth overtime period (e-2)")
    }

    /// The clock runs while the chains move. A first down is not a stoppage, and
    /// treating it as one would make every drive a two-minute drill.
    @Test("Gaining a first down does not stop the clock", .tags(.unit))
    func firstDownDoesNotStop() {
        #expect(behavior(.tackled, quarter: 4, clock: 100) == .keepsRunning)
    }

    @Test("The two-minute warning is detected on the play that crosses it", .tags(.unit))
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

    @Test("football · Rule 4-7-1 Item 1 · the runoff is ten seconds", .tags(.football))
    func tenSeconds() {
        #expect(rules.tenSecondRunoff == 10)
    }

    /// After the two-minute warning of either half, with the clock running, an
    /// offensive dead-ball foul that stops the clock carries the runoff; the same foul
    /// outside the window, with the clock stopped, or by the defence does not.
    @Test(
        "football · Rule 4-7-1 Item 1, 4-7-1 Item 2, 4-7-2 · the runoff applies to an offensive dead-ball foul after the two-minute warning of either half with the clock running, and never to the defence",
        .tags(.football)
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

    /// Rewritten for A11 (#74) from a pin that said postseason overtime timing was not
    /// modelled. It is: 16-1-4-h pairs postseason overtime periods into halves, a second
    /// period ending as the first half does and a fourth as the fourth period does, so
    /// the warning of either half (4-7-1) is in the second and the fourth and the runoff
    /// follows it there; a first or a third period has neither.
    @Test(
        "football · Rule 16-1-4-h, 4-7-1 Item 1 · in postseason overtime the runoff applies inside two minutes of a second and of a fourth overtime period, and never in a first or a third",
        .tags(.football)
    )
    func postseasonOvertimeRunoff() {
        #expect(
            carriesRunoff(.falseStart, quarter: 5, clock: 40, postseason: true) == false,
            "a first overtime period ends as a first period does")
        #expect(
            carriesRunoff(.falseStart, quarter: 6, clock: 40, postseason: true),
            "a second overtime period ends as the first half does")
        #expect(
            carriesRunoff(.falseStart, quarter: 6, clock: 120, postseason: true) == false,
            "at the warning the clock is stopped")
        #expect(
            carriesRunoff(.falseStart, quarter: 7, clock: 40, postseason: true) == false,
            "a third overtime period ends as a third period does")
        #expect(
            carriesRunoff(.falseStart, quarter: 8, clock: 40, postseason: true),
            "a fourth overtime period ends as the fourth period does")
    }
}

@Suite("Running the clock")
struct GameClockTests {

    private let rules = Rules.standard

    /// The distinction a team down four with sixty seconds and no timeouts lives on:
    /// after an incompletion the huddle is free, after a tackle in bounds it is not.
    @Test("The pre-snap interval only costs the clock when the clock was running", .tags(.unit))
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
    @Test("Tempo spends the play clock, fastest to slowest", .tags(.unit))
    func tempoOrdering() {
        let ordered: [Tempo] = [.hurryUp, .fast, .normal, .slow, .bleedClock]
        let seconds = ordered.map(\.secondsBetweenSnaps)
        #expect(seconds == seconds.sorted())
        #expect(Tempo.bleedClock.secondsBetweenSnaps < UInt16(rules.playClock))
    }

    @Test("Running the clock down never goes below zero", .tags(.unit))
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
        "football · Rule 3-41, 4-4-h · the warning stops a running clock at 2:00 between downs, and the play then runs from there",
        .tags(.football)
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
        "football · Rule 3-41 · a down under way when the clock passes 2:00 finishes, and the clock is dead after it",
        .tags(.football)
    )
    func warningDuringADown() {
        var clock = GameClock(quarter: 4, secondsRemaining: 128)
        let taken = clock.run(GameClock.Elapsed(duringPlay: 20, beforeSnap: 0), rules: rules)

        #expect(taken, "the warning is taken as the down ends")
        #expect(clock.secondsRemaining == 108, "the down finished")
        #expect(clock.twoMinuteWarningTaken)
    }

    /// Filed as A11 (#74). Regular-season overtime is timed as the fourth quarter
    /// (16-1-3-e), so the warning (3-41) is in it: at 2:00 between downs the clock
    /// stops, and a down under way finishes.
    @Test(
        "football · Rule 3-41, 16-1-3-e · a regular-season overtime period has a two-minute warning: the clock stops at 2:00 between downs, and a down under way when it passes 2:00 finishes",
        .tags(.football)
    )
    func warningInRegularSeasonOvertime() {
        var between = GameClock(quarter: 5, secondsRemaining: 128)
        let inTheHuddle = between.run(
            GameClock.Elapsed(duringPlay: 6, beforeSnap: 20), rules: rules)
        #expect(inTheHuddle, "the warning is taken in the huddle")
        #expect(between.secondsRemaining == 114, "the huddle was cut at 2:00; the play ran six")

        var during = GameClock(quarter: 5, secondsRemaining: 128)
        let asTheDownEnds = during.run(
            GameClock.Elapsed(duringPlay: 20, beforeSnap: 0), rules: rules)
        #expect(asTheDownEnds, "the warning is taken as the down ends")
        #expect(during.secondsRemaining == 108, "the down finished")
    }

    @Test("The warning is taken once per half, not once per play", .tags(.unit))
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

    @Test("There is no warning at the end of the first or third quarter", .tags(.unit))
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
    @Test("The warning resets at halftime and not between quarters", .tags(.unit))
    func warningResets() {
        let firstHalf = GameClock(quarter: 2, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let secondHalf = firstHalf.advancingPeriod(rules: rules)
        #expect(secondHalf?.quarter == 3)
        #expect(secondHalf?.twoMinuteWarningTaken == false)

        let thirdQuarter = GameClock(quarter: 3, secondsRemaining: 0, twoMinuteWarningTaken: true)
        #expect(thirdQuarter.advancingPeriod(rules: rules)?.twoMinuteWarningTaken == true)
    }

    /// Rewritten for A11 (#74): this asserted that the overtime period had no
    /// two-minute warning, which is wrong football — fourth-period timing rules apply in
    /// regular-season overtime (16-1-3-e), the warning among them (3-41). The period
    /// opens with the warning fresh, as a half does.
    @Test("Periods advance to a full quarter, then to overtime", .tags(.unit))
    func periods() {
        let first = GameClock(quarter: 1, secondsRemaining: 0)
        #expect(first.advancingPeriod(rules: rules)?.secondsRemaining == 900)

        let fourth = GameClock(quarter: 4, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let overtime = fourth.advancingPeriod(rules: rules)
        #expect(overtime?.quarter == 5)
        #expect(overtime?.secondsRemaining == 600)
        #expect(
            overtime?.twoMinuteWarningTaken == false,
            "the overtime period opens with its warning still to come")

        let postseason = fourth.advancingPeriod(rules: rules, isPostseason: true)
        #expect(postseason?.secondsRemaining == 900)
    }

    /// The whole point of the model: a drill lives or dies on stoppages, not on yards.
    @Test("A two-minute drill gets more snaps when it stops the clock", .tags(.unit))
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
