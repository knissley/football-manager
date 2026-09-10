import Testing

@testable import FMCore

@Suite("Situation classification")
struct SituationClassTests {

    private func classify(
        down: Down = .first, distance: UInt8 = 10, ballOn: UInt8 = 75,
        quarter: UInt8 = 1, clock: UInt16 = 900, differential: Int16 = 0
    ) -> SituationClass {
        SituationClass(
            Situation(
                quarter: quarter, clockRemaining: clock, down: down,
                distance: distance, ballOn: ballOn, possession: TeamID(1),
                scoreDifferential: differential))
    }

    // MARK: - Down and distance

    /// One to three, four to six, seven or more — on every down that has the buckets,
    /// fourth included. Seven is where the ground stops being a realistic answer, and a
    /// bucket that ran to seven put third and seven in with third and four, which is a
    /// different down entirely.
    @Test("Distance buckets split at three and six yards, on fourth down too", .tags(.unit))
    func distanceBuckets() {
        #expect(classify(down: .second, distance: 3).downAndDistance == .secondShort)
        #expect(classify(down: .second, distance: 4).downAndDistance == .secondMedium)
        #expect(classify(down: .second, distance: 6).downAndDistance == .secondMedium)
        #expect(classify(down: .second, distance: 7).downAndDistance == .secondLong)

        #expect(classify(down: .third, distance: 3).downAndDistance == .thirdShort)
        #expect(classify(down: .third, distance: 4).downAndDistance == .thirdMedium)
        #expect(classify(down: .third, distance: 6).downAndDistance == .thirdMedium)
        #expect(classify(down: .third, distance: 7).downAndDistance == .thirdLong)

        #expect(classify(down: .fourth, distance: 3).downAndDistance == .fourthShort)
        #expect(classify(down: .fourth, distance: 7).downAndDistance == .fourthLong)
        // Fourth and five is neither: it is the bucket in between, and it exists so that
        // "fourth and seven or more" can be said at all.
        #expect(classify(down: .fourth, distance: 4).downAndDistance != .fourthShort)
        #expect(classify(down: .fourth, distance: 6).downAndDistance != .fourthLong)
        #expect(
            classify(down: .fourth, distance: 5).downAndDistance
                == classify(down: .fourth, distance: 4).downAndDistance)
    }

    /// First down is one bucket at any distance: first and twenty after a hold
    /// is still a down where the whole playbook is open.
    @Test("First down is a single bucket regardless of distance", .tags(.unit))
    func firstDownIsOneBucket() {
        #expect(classify(down: .first, distance: 10).downAndDistance == .firstDown)
        #expect(classify(down: .first, distance: 20).downAndDistance == .firstDown)
        #expect(classify(down: .first, distance: 1, ballOn: 40).downAndDistance == .firstDown)
    }

    /// Goal-to-go is its own kind of down: the field is short in a way that
    /// changes the play menu, so it outranks the distance bucket.
    @Test("Goal-to-go outranks the distance bucket on every down", .tags(.unit))
    func goalToGoWins() {
        for down in Down.allCases {
            #expect(classify(down: down, distance: 8, ballOn: 8).downAndDistance == .goalToGo)
        }
        #expect(classify(down: .third, distance: 2, ballOn: 2).downAndDistance == .goalToGo)
    }

    @Test("Last down, passing down and short yardage read as the sport does", .tags(.unit))
    func downPredicates() {
        #expect(DownAndDistanceClass.fourthShort.isLastDown)
        #expect(DownAndDistanceClass.fourthLong.isLastDown)
        #expect(DownAndDistanceClass.thirdLong.isLastDown == false)
        #expect(DownAndDistanceClass.goalToGo.isLastDown == false)

        // A passing down is third or fourth and seven or more, and nothing else. Second
        // and eight is a down with a whole extra play behind it, and third and four is a
        // down the sport runs on all the time.
        #expect(DownAndDistanceClass.thirdLong.isPassingDown)
        #expect(DownAndDistanceClass.fourthLong.isPassingDown)
        #expect(DownAndDistanceClass.thirdMedium.isPassingDown == false)
        #expect(DownAndDistanceClass.secondLong.isPassingDown == false)
        #expect(DownAndDistanceClass.thirdShort.isPassingDown == false)
        #expect(DownAndDistanceClass.firstDown.isPassingDown == false)

        #expect(DownAndDistanceClass.thirdShort.isShortYardage)
        #expect(DownAndDistanceClass.fourthShort.isShortYardage)
        #expect(DownAndDistanceClass.goalToGo.isShortYardage)
        #expect(DownAndDistanceClass.thirdMedium.isShortYardage == false)
    }

    // MARK: - Score

    /// Down four and down seven are the same problem; down nine is a different
    /// one. The boundaries are where the number of possessions changes.
    @Test("Score buckets split where the possession count changes", .tags(.unit))
    func scoreBuckets() {
        #expect(ScoreState(differential: -17) == .trailingThreeScores)
        #expect(ScoreState(differential: -16) == .trailingTwoScores)
        #expect(ScoreState(differential: -9) == .trailingTwoScores)
        #expect(ScoreState(differential: -8) == .trailingOneScore)
        #expect(ScoreState(differential: -1) == .trailingOneScore)
        #expect(ScoreState(differential: 0) == .tied)
        #expect(ScoreState(differential: 1) == .leadingOneScore)
        #expect(ScoreState(differential: 8) == .leadingOneScore)
        #expect(ScoreState(differential: 9) == .leadingTwoScores)
        #expect(ScoreState(differential: 16) == .leadingTwoScores)
        #expect(ScoreState(differential: 17) == .leadingThreeScores)
    }

    @Test("Trailing, leading and one-score are consistent with the buckets", .tags(.unit))
    func scorePredicates() {
        #expect(ScoreState.trailingOneScore.isTrailing)
        #expect(ScoreState.trailingThreeScores.isTrailing)
        #expect(ScoreState.tied.isTrailing == false)
        #expect(ScoreState.tied.isLeading == false)
        #expect(ScoreState.leadingOneScore.isLeading)

        #expect(ScoreState.trailingOneScore.isOneScoreGame)
        #expect(ScoreState.tied.isOneScoreGame)
        #expect(ScoreState.leadingOneScore.isOneScoreGame)
        #expect(ScoreState.trailingTwoScores.isOneScoreGame == false)
    }

    /// The differential is from the possessing team's point of view, so the same
    /// scoreboard classifies as mirror-image states depending on who has the ball.
    @Test("The same scoreboard mirrors when possession changes", .tags(.unit))
    func scoreIsPossessionRelative() {
        #expect(ScoreState(differential: -6) == .trailingOneScore)
        #expect(ScoreState(differential: 6) == .leadingOneScore)
    }

    // MARK: - Time

    @Test("Time buckets follow the quarter and the stoppages that matter", .tags(.unit))
    func timeBuckets() {
        #expect(classify(quarter: 1, clock: 900).time == .opening)
        #expect(classify(quarter: 1, clock: 10).time == .opening)
        #expect(classify(quarter: 2, clock: 121).time == .middle)
        #expect(classify(quarter: 2, clock: 120).time == .twoMinuteFirstHalf)
        #expect(classify(quarter: 3, clock: 30).time == .thirdQuarter)
        #expect(classify(quarter: 4, clock: 301).time == .fourthQuarter)
        #expect(classify(quarter: 4, clock: 300).time == .clockBurn)
        #expect(classify(quarter: 4, clock: 121).time == .clockBurn)
        #expect(classify(quarter: 4, clock: 120).time == .twoMinuteGame)
        #expect(classify(quarter: 5, clock: 600).time == .overtime)
    }

    /// The first-half two-minute warning is a real situational break, but it is
    /// not the endgame — you can punt at the end of a half without apology.
    @Test("Two-minute and endgame are different things", .tags(.unit))
    func timePredicates() {
        #expect(TimeState.twoMinuteFirstHalf.isTwoMinute)
        #expect(TimeState.twoMinuteGame.isTwoMinute)
        #expect(TimeState.clockBurn.isTwoMinute == false)

        #expect(TimeState.twoMinuteFirstHalf.isEndgame == false)
        #expect(TimeState.clockBurn.isEndgame)
        #expect(TimeState.twoMinuteGame.isEndgame)
        #expect(TimeState.overtime.isEndgame)
        #expect(TimeState.fourthQuarter.isEndgame == false)
    }

    // MARK: - Reads shared by both sides of the ball

    /// Only the distances that really do take the run off the menu. Third and four and
    /// second and eight are downs a defence still has to play honest against, and a
    /// caller that reads them as a throw is one the defence can bet against for nothing.
    @Test("Distance alone makes a passing down obvious", .tags(.unit))
    func mustPassOnDistance() {
        #expect(classify(down: .third, distance: 9, quarter: 2, clock: 600).isMustPass)
        #expect(classify(down: .fourth, distance: 9, quarter: 2, clock: 600).isMustPass)
        #expect(classify(down: .third, distance: 4, quarter: 2, clock: 600).isMustPass == false)
        #expect(classify(down: .second, distance: 8, quarter: 2, clock: 600).isMustPass == false)
        #expect(classify(down: .third, distance: 2, quarter: 2, clock: 600).isMustPass == false)
        #expect(classify(down: .first, distance: 10, quarter: 2, clock: 600).isMustPass == false)
    }

    /// A passing down is a passing down whenever it happens. The endgame qualifier used
    /// to switch the read off in the last five minutes, so third and fifteen with four
    /// minutes left classified as an ordinary down.
    @Test("A passing down reads the same in the endgame as anywhere else", .tags(.unit))
    func passingDownIsNotSwitchedOffLate() {
        #expect(
            classify(down: .third, distance: 12, quarter: 4, clock: 240, differential: 7)
                .isMustPass)
    }

    /// Trailing inside two minutes, the clock forces the throw even on first and
    /// ten — which is exactly why a defence can sit back and play the sideline.
    @Test("The clock forces the throw when trailing late", .tags(.unit))
    func mustPassOnClock() {
        #expect(
            classify(down: .first, distance: 10, quarter: 4, clock: 90, differential: -4).isMustPass
        )
        #expect(
            classify(down: .first, distance: 10, quarter: 2, clock: 90, differential: -4).isMustPass
        )
        #expect(
            classify(down: .first, distance: 10, quarter: 4, clock: 90, differential: 4).isMustPass
                == false)
    }

    /// Tied in the last two minutes you are playing for a field goal, unless you
    /// are backed up — from your own eight you are content to see overtime.
    @Test("Tied and late is a must-pass only outside your own end", .tags(.unit))
    func mustPassWhenTiedLate() {
        #expect(classify(down: .first, distance: 10, ballOn: 60, quarter: 4, clock: 80).isMustPass)
        #expect(
            classify(down: .first, distance: 10, ballOn: 92, quarter: 4, clock: 80).isMustPass
                == false)
    }

    /// The mirror image of the two-minute drill, and the reason it belongs in
    /// shared vocabulary: one team wants the clock to run, the other wants it stopped.
    @Test("Clock burn is the leading team's version of the same moment", .tags(.unit))
    func clockBurn() {
        #expect(classify(quarter: 4, clock: 240, differential: 7).isClockBurn)
        #expect(classify(quarter: 4, clock: 240, differential: -7).isClockBurn == false)
        #expect(classify(quarter: 4, clock: 240, differential: 0).isClockBurn == false)
        #expect(classify(quarter: 4, clock: 400, differential: 7).isClockBurn == false)
    }

    @Test("Desperation is trailing with a half running out", .tags(.unit))
    func desperation() {
        #expect(classify(quarter: 4, clock: 60, differential: -3).isDesperation)
        #expect(classify(quarter: 2, clock: 60, differential: -3).isDesperation)
        #expect(classify(quarter: 4, clock: 60, differential: 3).isDesperation == false)
        #expect(classify(quarter: 4, clock: 240, differential: -3).isDesperation == false)
        #expect(classify(quarter: 5, clock: 60, differential: -3).isDesperation == false)
    }

    /// A description of where going for it is live, not a recommendation — a
    /// conservative coach punts from here and is not wrong to.
    @Test("Fourth-down territory is short yardage, or late and behind", .tags(.unit))
    func fourthDownTerritory() {
        #expect(classify(down: .fourth, distance: 2, ballOn: 45).isFourthDownTerritory)
        #expect(classify(down: .fourth, distance: 2, ballOn: 92).isFourthDownTerritory == false)
        #expect(
            classify(
                down: .fourth, distance: 9, ballOn: 45, quarter: 4, clock: 100, differential: -6
            )
            .isFourthDownTerritory)
        #expect(
            classify(down: .fourth, distance: 9, ballOn: 45, quarter: 1).isFourthDownTerritory
                == false)
        #expect(classify(down: .third, distance: 2, ballOn: 45).isFourthDownTerritory == false)
    }

    @Test("Field goal range starts at the opponent's forty-nine", .tags(.unit))
    func fieldGoalRange() {
        #expect(classify(ballOn: 49).isFieldGoalRange)
        #expect(classify(ballOn: 50).isFieldGoalRange == false)
        #expect(classify(ballOn: 3).isFieldGoalRange)
    }

    /// Defence gets its own read on leverage, because the moments a coordinator
    /// scripts for are not the same list the offence worries about.
    @Test(
        "Defensive leverage covers get-off downs, the red zone and late close games", .tags(.unit))
    func defensiveLeverage() {
        #expect(classify(down: .third, distance: 6).isHighLeverageForDefense)
        #expect(classify(down: .fourth, distance: 1).isHighLeverageForDefense)
        #expect(classify(down: .first, distance: 10, ballOn: 12).isHighLeverageForDefense)
        #expect(
            classify(down: .first, distance: 10, quarter: 4, clock: 100, differential: 3)
                .isHighLeverageForDefense)
        #expect(classify(down: .first, distance: 10, ballOn: 75).isHighLeverageForDefense == false)
        #expect(classify(down: .second, distance: 8, ballOn: 60).isHighLeverageForDefense == false)
    }

    // MARK: - The point of the type

    /// The whole reason this exists: a two-minute drill is one moment, and both
    /// sidelines have to be describing the same one. There is a single
    /// classification per snap, read from the offence's point of view, and the
    /// two benches draw opposite conclusions from the *same* value rather than
    /// each building their own.
    @Test("One classification per snap serves both sidelines", .tags(.unit))
    func oneSharedDescription() {
        // Second and eight from midfield, down four, seventy-five seconds left.
        let snap = classify(
            down: .second, distance: 8, ballOn: 55, quarter: 4, clock: 75, differential: -4)

        // The offence reads: we have to throw, and we are out of time.
        #expect(snap.isMustPass)
        #expect(snap.isDesperation)

        // The defence reads the same value: they have to throw, so play the
        // sticks and the sideline. Nothing is mirrored, nothing is recomputed.
        #expect(snap.score.isTrailing)
        #expect(snap.isClockBurn == false)
        #expect(snap.isHighLeverageForDefense)
    }

    /// The complement: the same clock, the other scoreboard. The leading team
    /// wants the clock to run, and now `isClockBurn` is the read both benches
    /// share instead.
    @Test("Flipping only the scoreboard flips which read fires", .tags(.unit))
    func clockBurnIsTheComplement() {
        let trailing = classify(
            down: .second, distance: 8, ballOn: 55, quarter: 4, clock: 75, differential: -4)
        let leading = classify(
            down: .second, distance: 8, ballOn: 55, quarter: 4, clock: 75, differential: 4)

        #expect(trailing.downAndDistance == leading.downAndDistance)
        #expect(trailing.field == leading.field)
        #expect(trailing.time == leading.time)

        #expect(trailing.isDesperation && trailing.isClockBurn == false)
        #expect(leading.isClockBurn && leading.isDesperation == false)
    }

    /// The classification is a pure function of the situation, which is what
    /// lets a tendency table built from replayed history line up with live play.
    @Test("Classification depends only on the fields it reads", .tags(.contract))
    func classificationIsStable() {
        var situation = Situation(
            quarter: 3, clockRemaining: 400, down: .third, distance: 5, ballOn: 30,
            possession: TeamID(1), scoreDifferential: -3)
        let before = SituationClass(situation)

        situation.possession = TeamID(9)
        situation.offenseTimeouts = 0
        situation.defensePackage = .dime

        #expect(SituationClass(situation) == before)
    }

    /// Every bucket has to be reachable, or a gameplan rule keyed to it would
    /// silently never fire.
    @Test("Every down-and-distance bucket is reachable", .tags(.contract))
    func everyBucketIsReachable() {
        var seen: Set<DownAndDistanceClass> = []
        for down in Down.allCases {
            for distance in UInt8(1)...UInt8(15) {
                for ballOn in [3, 18, 45, 50, 70, 95] as [UInt8] {
                    seen.insert(
                        classify(down: down, distance: distance, ballOn: ballOn).downAndDistance)
                }
            }
        }
        #expect(seen.count == DownAndDistanceClass.allCases.count)
    }

    // MARK: - Period numbers come from the rules (A8, #20)

    /// `Rules.quarters` is data, and the classification has to follow it rather than
    /// hard-code 2, 4 and 5. Under a two-period variant the first period is the end of the
    /// first half and the second is the end of the game.
    @Test(
        "unit · under a two-period variant the first period ends the first half and the second ends the game",
        .tags(.unit)
    )
    func twoPeriodVariantClassifiesByStructure() {
        let twoPeriods = Rules(quarters: 2)
        func classify(quarter: UInt8, clock: UInt16) -> TimeState {
            SituationClass(
                Situation(
                    quarter: quarter, clockRemaining: clock, down: .first, distance: 10,
                    ballOn: 75, possession: TeamID(1)),
                rules: twoPeriods
            ).time
        }
        #expect(classify(quarter: 1, clock: 500) == .middle)
        #expect(classify(quarter: 1, clock: 120) == .twoMinuteFirstHalf)
        #expect(classify(quarter: 2, clock: 500) == .fourthQuarter)
        #expect(classify(quarter: 2, clock: 300) == .clockBurn)
        #expect(classify(quarter: 2, clock: 120) == .twoMinuteGame)
        #expect(classify(quarter: 3, clock: 600) == .overtime)
    }

    /// A postseason game can reach a sixth period and beyond; every one of them is
    /// overtime.
    @Test("unit · a sixth period is overtime", .tags(.unit))
    func sixthPeriodIsOvertime() {
        #expect(classify(quarter: 6, clock: 900).time == .overtime)
        #expect(classify(quarter: 7, clock: 900).time == .overtime)
    }

    /// The two-minute threshold is `Rules.twoMinuteWarning`, not a literal 120.
    @Test("unit · the two-minute threshold is read from Rules.twoMinuteWarning", .tags(.unit))
    func twoMinuteThresholdComesFromRules() {
        let variant = Rules(twoMinuteWarning: 60)
        func time(quarter: UInt8, clock: UInt16) -> TimeState {
            SituationClass(
                Situation(
                    quarter: quarter, clockRemaining: clock, down: .first, distance: 10,
                    ballOn: 75, possession: TeamID(1)),
                rules: variant
            ).time
        }
        #expect(time(quarter: 2, clock: 61) == .middle)
        #expect(time(quarter: 2, clock: 60) == .twoMinuteFirstHalf)
        #expect(time(quarter: 4, clock: 61) == .clockBurn)
        #expect(time(quarter: 4, clock: 60) == .twoMinuteGame)
    }
}
