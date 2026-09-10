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
        #expect(rules.isEndOfHalf(quarter: 2, isPostseason: false))
        #expect(rules.isEndOfHalf(quarter: 4, isPostseason: false))
        #expect(rules.isEndOfHalf(quarter: 1, isPostseason: false) == false)
        #expect(rules.isEndOfHalf(quarter: 3, isPostseason: false) == false)

        #expect(rules.periodTiming(quarter: 1, isPostseason: false) == .firstOrThird)
        #expect(rules.periodTiming(quarter: 2, isPostseason: false) == .second)
        #expect(rules.periodTiming(quarter: 3, isPostseason: false) == .firstOrThird)
        #expect(rules.periodTiming(quarter: 4, isPostseason: false) == .fourth)

        #expect(rules.opensHalf(quarter: 1))
        #expect(rules.opensHalf(quarter: 2) == false)
        #expect(rules.opensHalf(quarter: 3))
        #expect(rules.opensHalf(quarter: 4) == false)
        #expect(rules.opensHalf(quarter: 5), "the overtime period opens a half of its own")
    }

    /// 16-1-4-h names the second and the fourth overtime period and no later one, and
    /// 16-1-4-i tosses the coin again at the end of the fourth, as at the end of
    /// regulation. The engine reads that toss as restarting the pairing, so a fifth
    /// overtime period is timed as a first and a sixth as a second. No game has reached
    /// a third overtime period; this pins the reading so it changes on purpose.
    @Test(
        "pin · a fifth postseason overtime period is timed as a first and a sixth as a second, because the engine reads the new toss after a fourth (16-1-4-i) as restarting the pairing 16-1-4-h describes — a reading, since the book names only the second and the fourth",
        .tags(.pin)
    )
    func postseasonOvertimeBeyondTheFourthPeriodRepeatsThePairing() {
        #expect(rules.periodTiming(quarter: 9, isPostseason: true) == .firstOrThird)
        #expect(rules.periodTiming(quarter: 10, isPostseason: true) == .second)
        #expect(rules.periodTiming(quarter: 11, isPostseason: true) == .firstOrThird)
        #expect(rules.periodTiming(quarter: 12, isPostseason: true) == .fourth)
        #expect(rules.opensHalf(quarter: 9))
        #expect(rules.opensHalf(quarter: 10) == false)
        #expect(rules.opensHalf(quarter: 11))
    }

    /// The boundary set the engine and the tools share: `GameState.startNextPeriod`
    /// restarts possession and the spot by it, and `Tools/gamelog` ends a drive by it.
    /// Both read the predicate rather than restating it, so this is where it is checked.
    /// A third and a fifth overtime period are its modelling and are pinned below
    /// instead.
    @Test(
        "periodResumesWithKickoffAsModelled(quarter:) is true at the second half and the first overtime period, and false at every other period swept here",
        .tags(.unit))
    func periodResumesWithKickoffAsModelledAnswers() {
        let secondHalf = rules.quarters / 2 + 1
        let overtime = rules.quarters + 1
        #expect(rules.periodResumesWithKickoffAsModelled(quarter: secondHalf))
        #expect(rules.periodResumesWithKickoffAsModelled(quarter: overtime))
        // Every period of regulation, a second overtime period, and a fourth. A period
        // inside a half only changes ends (4-2-3), which 16-1-4-f carries into the ends
        // of a first and a third overtime period, and nothing is resumed at the start of
        // a first period at all.
        var swept: [UInt8] = Array(UInt8(1)...(rules.quarters + 2))
        swept.append(rules.quarters + 4)
        for quarter in swept where quarter != secondHalf && quarter != overtime {
            #expect(
                rules.periodResumesWithKickoffAsModelled(quarter: quarter) == false,
                "period \(quarter)")
        }
    }

    /// 16-1-4-e gives the beginning of a third overtime period the first choice of
    /// 4-2-2's two privileges to the captain who lost the toss before overtime, and
    /// 16-1-4-i tosses again after a fourth: the book puts a third postseason overtime
    /// period, and by the same reading a fifth, back in play with a kick — which is what
    /// `opensHalf` computes and the predicate does not. The engine restarts only the
    /// first overtime period and plays on at every later boundary. That is a gap rather
    /// than a reading of an unclear article, it is owned by
    /// [#86](https://github.com/knissley/football-manager/issues/86), and this is what
    /// makes it fail loudly when #86 closes it.
    @Test(
        "pin · the engine does not put a third or a fifth postseason overtime period back in play with a kick, though 16-1-4-e gives a third period's first 4-2-2 choice to the toss loser and 16-1-4-i tosses again after a fourth — the gap is #86's",
        .tags(.pin))
    func aThirdPostseasonOvertimePeriodIsNotRestartedWithAKick() {
        #expect(rules.periodResumesWithKickoffAsModelled(quarter: rules.quarters + 3) == false)
        #expect(rules.periodResumesWithKickoffAsModelled(quarter: rules.quarters + 5) == false)
        // What the book makes of the same two periods, which the timing half already has.
        #expect(rules.opensHalf(quarter: rules.quarters + 3))
        #expect(rules.opensHalf(quarter: rules.quarters + 5))
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
        _ ending: PlayEnding, quarter: UInt8 = 1, clock: UInt16 = 600, postseason: Bool = false
    ) -> ClockBehavior {
        rules.clockBehavior(
            after: ending, quarter: quarter, isPostseason: postseason, clockRemaining: clock)
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
                    after: ending, possessionChanged: true, quarter: 1, isPostseason: false,
                    clockRemaining: 600)
                    == .stopsUntilSnap,
                "\(ending)")
        }
        #expect(
            rules.clockBehavior(
                after: .tackled, possessionChanged: false, quarter: 1, isPostseason: false,
                clockRemaining: 600)
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

    /// Postseason overtime pairs its periods into halves (16-1-4-h), so the
    /// out-of-bounds windows follow the halves: two minutes at the end of a second
    /// overtime period, five at the end of a fourth, and none in a first or a third.
    @Test(
        "football · Rule 16-1-4-h, 4-3-2-a · in postseason overtime the out-of-bounds window is a second overtime period's last two minutes and a fourth's last five, and a first or third has none",
        .tags(.football)
    )
    func outOfBoundsInPostseasonOvertime() {
        #expect(
            behavior(.outOfBounds, quarter: 5, clock: 90, postseason: true)
                == .stopsUntilReadyForPlay,
            "a first overtime period is a first period")
        #expect(behavior(.outOfBounds, quarter: 6, clock: 120, postseason: true) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 6, clock: 30, postseason: true) == .stopsUntilSnap)
        #expect(
            behavior(.outOfBounds, quarter: 6, clock: 121, postseason: true)
                == .stopsUntilReadyForPlay)
        #expect(
            behavior(.outOfBounds, quarter: 6, clock: 250, postseason: true)
                == .stopsUntilReadyForPlay,
            "the first half's window is two minutes, not five")
        #expect(
            behavior(.outOfBounds, quarter: 7, clock: 90, postseason: true)
                == .stopsUntilReadyForPlay,
            "a third overtime period is a third period")
        #expect(behavior(.outOfBounds, quarter: 8, clock: 300, postseason: true) == .stopsUntilSnap)
        #expect(behavior(.outOfBounds, quarter: 8, clock: 90, postseason: true) == .stopsUntilSnap)
        #expect(
            behavior(.outOfBounds, quarter: 8, clock: 301, postseason: true)
                == .stopsUntilReadyForPlay)
    }

    private func startsOnTheSnap(quarter: UInt8, clock: UInt16, postseason: Bool = true) -> Bool {
        rules.clockStartsOnTheSnapAfterFoul(
            byOffense: true, quarter: quarter, isPostseason: postseason, clockRemaining: clock)
    }

    /// 4-3-2-e-3 names its periods — the fourth, and regular-season overtime — and a
    /// first, second or third postseason overtime period is none of them, nor is any
    /// of them timed as a fourth by 16-1-4-h. So in those the offence's foul before the
    /// snap starts the clock on the snap only inside the two-minute window a second
    /// overtime period is lent (e-1); inside five minutes of a fourth it does too
    /// (e-2). What e-3 says of a fourth overtime period outside five minutes the book
    /// does not settle, and that row is a pin, `offensiveFoulInAFourthPostseason
    /// OvertimePeriodOutsideFiveMinutes`.
    @Test(
        "football · Rule 4-3-2-e, 16-1-4-h · after an offensive foul before the snap the clock starts on the snap anywhere in the fourth period or regular-season overtime (e-3); in a first, second or third postseason overtime period, which e-3's words leave out, only inside the two-minute window a second is lent (e-1); and inside five minutes of a fourth (e-2)",
        .tags(.football)
    )
    func offensiveFoulBeforeTheSnapInPostseasonOvertime() {
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
            startsOnTheSnap(quarter: 8, clock: 250),
            "inside five minutes of a fourth overtime period (e-2)")
    }

    /// 16-1-4-h times the end of a fourth postseason overtime period as the end of the
    /// fourth period. Whether that imports 4-3-2-e-3, a rule about the whole fourth
    /// period rather than its end, the book does not say: e-3's own words name the
    /// fourth period and regular-season overtime, and 16-1-4-h speaks of a period's
    /// end. The engine reads e-3 as not reaching it, so outside five minutes — where
    /// e-2 does not decide the question either way — the clock restarts on the ready.
    /// Inside five minutes the readings agree, and that row is football above.
    @Test(
        "pin · an offensive foul before the snap in a fourth postseason overtime period outside five minutes restarts the clock on the ready, because 4-3-2-e-3 is read as not reaching it — 16-1-4-h lends a fourth overtime period the fourth period's closing rules, and whether that imports a whole-period rule the book does not settle",
        .tags(.pin)
    )
    func offensiveFoulInAFourthPostseasonOvertimePeriodOutsideFiveMinutes() {
        #expect(startsOnTheSnap(quarter: 8, clock: 400) == false)
        #expect(startsOnTheSnap(quarter: 8, clock: 301) == false)
    }

    /// The clock runs while the chains move. A first down is not a stoppage, and
    /// treating it as one would make every drive a two-minute drill.
    @Test("Gaining a first down does not stop the clock", .tags(.unit))
    func firstDownDoesNotStop() {
        #expect(behavior(.tackled, quarter: 4, clock: 100) == .keepsRunning)
    }

    @Test("The two-minute warning is detected on the play that crosses it", .tags(.unit))
    func twoMinuteWarningDetection() {
        func crosses(quarter: UInt8, before: UInt16, after: UInt16) -> Bool {
            rules.crossesTwoMinuteWarning(
                quarter: quarter, isPostseason: false, clockBefore: before, clockAfter: after)
        }
        #expect(crosses(quarter: 2, before: 125, after: 118))
        #expect(crosses(quarter: 4, before: 121, after: 120))
        #expect(crosses(quarter: 2, before: 118, after: 110) == false)
        #expect(
            crosses(quarter: 1, before: 125, after: 118) == false,
            "there is no warning at the end of the first quarter")
        #expect(crosses(quarter: 3, before: 125, after: 118) == false)
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
        _ = clock.run(30, rules: rules, isPostseason: false)
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
        let taken = clock.run(
            GameClock.Elapsed(duringPlay: 6, beforeSnap: 20), rules: rules, isPostseason: false)

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
        let taken = clock.run(
            GameClock.Elapsed(duringPlay: 20, beforeSnap: 0), rules: rules, isPostseason: false)

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
            GameClock.Elapsed(duringPlay: 6, beforeSnap: 20), rules: rules, isPostseason: false)
        #expect(inTheHuddle, "the warning is taken in the huddle")
        #expect(between.secondsRemaining == 114, "the huddle was cut at 2:00; the play ran six")

        var during = GameClock(quarter: 5, secondsRemaining: 128)
        let asTheDownEnds = during.run(
            GameClock.Elapsed(duringPlay: 20, beforeSnap: 0), rules: rules, isPostseason: false)
        #expect(asTheDownEnds, "the warning is taken as the down ends")
        #expect(during.secondsRemaining == 108, "the down finished")
    }

    /// Postseason overtime pairs its periods into halves: the warning is in a second
    /// overtime period, as at the end of the first half, and in a fourth, as at the end
    /// of the fourth period (16-1-4-h), and a first or a third has none. It is taken
    /// once a half, so it is fresh again when the pair's first period opens.
    @Test(
        "football · Rule 16-1-4-h, 3-41 · in postseason overtime the two-minute warning belongs to a second and a fourth overtime period, whose pairs are halves, and a first or third has none",
        .tags(.football)
    )
    func warningInPostseasonOvertime() {
        func warningAt(quarter: UInt8) -> (taken: Bool, clock: UInt16) {
            var clock = GameClock(quarter: quarter, secondsRemaining: 128)
            let taken = clock.run(
                GameClock.Elapsed(duringPlay: 6, beforeSnap: 20), rules: rules, isPostseason: true)
            return (taken, clock.secondsRemaining)
        }
        let first = warningAt(quarter: 5)
        #expect(first.taken == false && first.clock == 102, "a first overtime period: none")
        let second = warningAt(quarter: 6)
        #expect(second.taken && second.clock == 114, "a second: the first half's warning")
        let third = warningAt(quarter: 7)
        #expect(third.taken == false && third.clock == 102, "a third: none")
        let fourth = warningAt(quarter: 8)
        #expect(fourth.taken && fourth.clock == 114, "a fourth: the fourth period's warning")

        let regulation = GameClock(quarter: 4, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let opening = regulation.advancingPeriod(rules: rules, isPostseason: true)
        #expect(opening?.secondsRemaining == 900)
        #expect(
            opening?.twoMinuteWarningTaken == false,
            "the first overtime period opens a half, so the warning is to come")
        let pairTaken = GameClock(quarter: 6, secondsRemaining: 0, twoMinuteWarningTaken: true)
        #expect(
            pairTaken.advancingPeriod(rules: rules, isPostseason: true)?.twoMinuteWarningTaken
                == false,
            "a third overtime period opens the next half")
        let pairOpen = GameClock(quarter: 7, secondsRemaining: 0, twoMinuteWarningTaken: false)
        #expect(
            pairOpen.advancingPeriod(rules: rules, isPostseason: true)?.twoMinuteWarningTaken
                == false,
            "a fourth carries its pair's warning, still to come")
    }

    @Test("The warning is taken once per half, not once per play", .tags(.unit))
    func warningTakenOnce() {
        var clock = GameClock(quarter: 2, secondsRemaining: 130)
        let firstCrossing = clock.run(
            GameClock.Elapsed(duringPlay: 0, beforeSnap: 15), rules: rules, isPostseason: false)
        #expect(firstCrossing)
        #expect(clock.secondsRemaining == 120)

        // The next play runs through freely.
        let secondCrossing = clock.run(
            GameClock.Elapsed(duringPlay: 0, beforeSnap: 15), rules: rules, isPostseason: false)
        #expect(secondCrossing == false)
        #expect(clock.secondsRemaining == 105)
    }

    @Test("There is no warning at the end of the first or third quarter", .tags(.unit))
    func noWarningMidHalf() {
        var clock = GameClock(quarter: 1, secondsRemaining: 128)
        let firstQuarter = clock.run(20, rules: rules, isPostseason: false)
        #expect(firstQuarter == false)
        #expect(clock.secondsRemaining == 108)

        var third = GameClock(quarter: 3, secondsRemaining: 128)
        let thirdQuarter = third.run(20, rules: rules, isPostseason: false)
        #expect(thirdQuarter == false)
    }

    /// It is a once-per-half stoppage, so it resets at the half and not every quarter.
    @Test("The warning resets at halftime and not between quarters", .tags(.unit))
    func warningResets() {
        let firstHalf = GameClock(quarter: 2, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let secondHalf = firstHalf.advancingPeriod(rules: rules, isPostseason: false)
        #expect(secondHalf?.quarter == 3)
        #expect(secondHalf?.twoMinuteWarningTaken == false)

        let thirdQuarter = GameClock(quarter: 3, secondsRemaining: 0, twoMinuteWarningTaken: true)
        #expect(
            thirdQuarter.advancingPeriod(rules: rules, isPostseason: false)?.twoMinuteWarningTaken
                == true)
    }

    /// Rewritten for A11 (#74): this asserted that the overtime period had no
    /// two-minute warning, which is wrong football — fourth-period timing rules apply in
    /// regular-season overtime (16-1-3-e), the warning among them (3-41). The period
    /// opens with the warning fresh, as a half does.
    @Test("Periods advance to a full quarter, then to overtime", .tags(.unit))
    func periods() {
        let first = GameClock(quarter: 1, secondsRemaining: 0)
        #expect(first.advancingPeriod(rules: rules, isPostseason: false)?.secondsRemaining == 900)

        let fourth = GameClock(quarter: 4, secondsRemaining: 0, twoMinuteWarningTaken: true)
        let overtime = fourth.advancingPeriod(rules: rules, isPostseason: false)
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
                _ = clock.run(elapsed, rules: rules, isPostseason: false)
                snaps += 1
                previous =
                    alwaysStopping
                    ? rules.clockBehavior(
                        after: .incomplete, quarter: 4, isPostseason: false,
                        clockRemaining: clock.secondsRemaining)
                    : rules.clockBehavior(
                        after: .tackled, quarter: 4, isPostseason: false,
                        clockRemaining: clock.secondsRemaining)
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
