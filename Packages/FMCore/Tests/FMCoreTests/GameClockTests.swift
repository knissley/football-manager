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
    @Test("A live ball keeps the clock running")
    func liveBallRuns() {
        #expect(behavior(.tackled) == .keepsRunning)
        #expect(behavior(.fumbleRecovered) == .keepsRunning)
        #expect(behavior(.downed) == .keepsRunning)
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
        #expect(afterTackle.total == 6 + 26)

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

    /// The clock stops *at* two minutes, not past it. Letting a play run through the
    /// warning is how a half quietly loses a snap.
    @Test("A play crossing two minutes stops exactly on the warning")
    func stopsOnTheWarning() {
        var clock = GameClock(quarter: 4, secondsRemaining: 128)
        let taken = clock.run(20, rules: rules)

        #expect(taken)
        #expect(clock.secondsRemaining == 120)
        #expect(clock.twoMinuteWarningTaken)
    }

    @Test("The warning is taken once per half, not once per play")
    func warningTakenOnce() {
        var clock = GameClock(quarter: 2, secondsRemaining: 130)
        let firstCrossing = clock.run(15, rules: rules)
        #expect(firstCrossing)
        #expect(clock.secondsRemaining == 120)

        // The next play runs through freely.
        let secondCrossing = clock.run(15, rules: rules)
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
                _ = clock.run(elapsed.total, rules: rules)
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
