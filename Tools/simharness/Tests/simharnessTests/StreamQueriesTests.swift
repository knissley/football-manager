import FMCore
import Testing

@testable import simharness

/// The harness derives its rows from the record rather than from a second opinion about
/// what the record must have meant.
///
/// Each of these is a case where recomputing a fact the record already carries gives a
/// different answer from reading it. That is the whole of the claim: not that reading is
/// tidier, but that the two disagree, and the recomputation is the one that is wrong.
@Suite("Stream queries")
struct StreamQueriesTests {

    private func play(
        index: UInt16 = 0,
        down: Down = .first,
        distance: UInt8 = 10,
        ballOn: UInt8 = 50,
        quarter: UInt8 = 1,
        clockRemaining: UInt16 = 900,
        scoreDifferential: Int16 = 0,
        concept: PlayConcept = .insideRun,
        kind: PlayKind = .rush,
        yards: Int16 = 0,
        endedIn: PlayEnding = .tackled,
        passResult: PassResult? = nil,
        participants: [Participation] = [],
        decisions: [DecisionPoint] = [],
        onField: [UInt8]? = nil
    ) -> PlayRecord {
        PlayRecord(
            game: GameID(1), index: index,
            situation: Situation(
                quarter: quarter, clockRemaining: clockRemaining, down: down, distance: distance,
                ballOn: ballOn, possession: TeamID(1), scoreDifferential: scoreDifferential),
            calls: Calls(
                offense: OffensiveCall(concept: concept), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic),
            decisions: decisions,
            outcome: Outcome(
                kind: kind, yards: yards, endedIn: endedIn, passResult: passResult,
                participants: participants),
            onField: onField ?? Array(repeating: PlayRecord.vacant, count: PlayerSlot.count))
    }

    // MARK: - First downs

    /// Second and goal from the five, carried five yards to the one. The yardage equals
    /// the distance, so a recomputation of `yards >= distance` calls it a first down; the
    /// record does not, because goal-to-go is measured to the goal line and nothing short
    /// of the end zone is a new set of downs.
    @Test(
        "contract: a goal-to-go gain that matches the distance is not a first down, and the record says so",
        .tags(.contract))
    func goalToGoIsNotAFirstDown() {
        let carried = play(down: .second, distance: 5, ballOn: 5, yards: 5)
        #expect(carried.situation.isGoalToGo)
        #expect(carried.outcome.yards >= Int16(carried.situation.distance))
        #expect(carried.gainedFirstDown == false)
        #expect(StreamQueries.firstDownsEarned(in: [carried]) == 0)
    }

    /// A pass intercepted beyond the sticks. The recomputation reads the yardage and the
    /// ending separately and can credit the offence with a first down on a play it does
    /// not have the ball at the end of.
    @Test(
        "contract: a turnover is not a first down however far the ball travelled",
        .tags(.contract))
    func aTurnoverIsNotAFirstDown() {
        let picked = play(
            down: .third, distance: 4, concept: .mediumPass, kind: .pass, yards: 12,
            endedIn: .intercepted, passResult: .intercepted)
        #expect(picked.outcome.yards >= Int16(picked.situation.distance))
        #expect(StreamQueries.firstDownsEarned(in: [picked]) == 0)
    }

    @Test("unit: an ordinary conversion and a touchdown are both first downs", .tags(.unit))
    func theOrdinaryCases() {
        let converted = play(down: .third, distance: 4, yards: 4)
        let scored = play(
            down: .third, distance: 20, ballOn: 30, concept: .deepPass, kind: .pass, yards: 30,
            endedIn: .touchdown, passResult: .complete)
        let short = play(down: .third, distance: 4, yards: 3)
        #expect(StreamQueries.firstDownsEarned(in: [converted, scored, short]) == 2)
    }

    // MARK: - Catches

    /// The man who caught the ball is the man in the `.target` role: a receiver who ran a
    /// route and was thrown to is upgraded from `.receiver`, so crediting `.receiver`
    /// credits every man on the play except the one who made the catch. And a catch for
    /// no gain is a catch: the record says the pass was complete.
    @Test(
        "contract: a catch for no gain is credited to the man in the target role, not to the others",
        .tags(.contract))
    func catchesGoToTheTarget() {
        let catcher = PlayerID(11)
        let decoy = PlayerID(12)
        let caught = play(
            concept: .quickPass, kind: .pass, yards: 0, endedIn: .tackled, passResult: .complete,
            participants: [
                Participation(
                    slot: PlayerSlot(6), player: catcher, position: .wideReceiver, role: .target),
                Participation(
                    slot: PlayerSlot(7), player: decoy, position: .wideReceiver, role: .receiver),
            ])
        let credited = StreamQueries.catches(in: [caught])
        #expect(credited[catcher] == 1)
        #expect(credited[decoy] == nil)
    }

    @Test("unit: an incompletion credits nobody with a catch", .tags(.unit))
    func anIncompletionIsNotACatch() {
        let dropped = play(
            concept: .quickPass, kind: .pass, yards: 0, endedIn: .incomplete,
            passResult: .incomplete,
            participants: [
                Participation(
                    slot: PlayerSlot(6), player: PlayerID(11), position: .wideReceiver,
                    role: .target)
            ])
        #expect(StreamQueries.catches(in: [dropped]).isEmpty)
    }

    // MARK: - Run share by down and distance

    @Test(
        "unit: the run share splits second, third and fourth down three ways and puts goal-to-go in none of them",
        .tags(.unit))
    func runShareBuckets() {
        let plays = [
            play(down: .second, distance: 2, concept: .insideRun, kind: .rush),
            play(down: .second, distance: 2, concept: .mediumPass, kind: .pass),
            play(down: .third, distance: 5, concept: .outsideRun, kind: .rush),
            play(down: .third, distance: 12, concept: .deepPass, kind: .sack, yards: -7),
            play(down: .fourth, distance: 1, concept: .insideRun, kind: .rush),
            // Goal-to-go is its own class and belongs to no by-down bucket.
            play(down: .second, distance: 3, ballOn: 3, concept: .insideRun, kind: .rush),
            // A kneel is a clock play, not a choice between the run and the pass.
            play(down: .first, distance: 10, concept: .kneel, kind: .kneel, yards: -1),
        ]
        let split = StreamQueries.runShare(in: plays)
        #expect(split[.secondShort]?.calls == 2)
        #expect(split[.secondShort]?.runs == 1)
        #expect(split[.thirdMedium]?.calls == 1)
        #expect(split[.thirdMedium]?.runs == 1)
        #expect(split[.thirdLong]?.calls == 1)
        #expect(split[.thirdLong]?.runs == 0, "a sack is the pass it was called as")
        #expect(split[.fourthShort]?.runs == 1)
        #expect(split[.goalToGo] == nil, "goal-to-go is in no by-down bucket")
        #expect(split[.firstDown] == nil, "first down is one class, and no row splits it")
    }

    // MARK: - Where a play ended

    @Test(
        "unit: the sideline share counts only the plays that ended with the ball dead in the field or out of bounds",
        .tags(.unit))
    func sidelineEndings() {
        let plays = [
            play(endedIn: .outOfBounds),
            play(endedIn: .tackled),
            play(endedIn: .tackled),
            play(kind: .pass, endedIn: .incomplete, passResult: .incomplete),
            play(kind: .pass, endedIn: .touchdown, passResult: .complete),
        ]
        let ends = StreamQueries.endedOnTheSideline(in: plays)
        #expect(ends.ballDead == 3)
        #expect(ends.outOfBounds == 1)
    }

    // MARK: - Punts

    @Test("unit: the touchback share counts the punts that reached the end zone", .tags(.unit))
    func touchbackShare() {
        let punts = [
            play(down: .fourth, distance: 8, ballOn: 40, concept: .punt, kind: .punt,
                endedIn: .touchback),
            play(down: .fourth, distance: 8, ballOn: 40, concept: .punt, kind: .punt,
                endedIn: .downed),
            play(down: .fourth, distance: 8, ballOn: 40, concept: .punt, kind: .punt,
                endedIn: .fairCatch),
        ]
        let share = StreamQueries.touchbacks(in: punts)
        #expect(share.kicks == 3)
        #expect(share.touchbacks == 1)
    }

    // MARK: - Pressure

    @Test(
        "unit: sacks under pressure are counted off the same dropbacks the pressures are",
        .tags(.unit))
    func pressureAndSacks() {
        let pressure = DecisionPoint.pressureAllowed(
            tick: 10, blocker: PlayerSlot(4), rusher: PlayerSlot(11), afterMilliseconds: 2200)
        let plays = [
            play(concept: .mediumPass, kind: .sack, yards: -7, decisions: [pressure]),
            play(
                concept: .mediumPass, kind: .pass, yards: 9, passResult: .complete,
                decisions: [pressure]),
            play(concept: .mediumPass, kind: .pass, yards: 9, passResult: .complete),
        ]
        let under = StreamQueries.pressure(in: plays)
        #expect(under.pressured == 2)
        #expect(under.sacks == 1)
    }

    // MARK: - The try

    @Test("unit: the two-point split reads the concept that was called", .tags(.unit))
    func twoPointSplit() {
        let tries = [
            play(concept: .twoPointRun, kind: .twoPointConversion, endedIn: .touchdown),
            play(concept: .twoPointPass, kind: .twoPointConversion, endedIn: .incomplete,
                passResult: .incomplete),
            play(concept: .twoPointPass, kind: .twoPointConversion, endedIn: .touchdown,
                passResult: .complete),
        ]
        let split = StreamQueries.twoPointTries(in: tries)
        #expect(split.run == 1)
        #expect(split.pass == 2)
    }

    // MARK: - Snaps

    /// The snap count is presence, not credit: every man `onField` names took the snap,
    /// whether or not the play thought him worth a participation row.
    @Test(
        "contract: a snap count reads the record's onField and credits men who earned no participation row",
        .tags(.contract))
    func snapsComeFromOnField() {
        var indices = Array(repeating: PlayRecord.vacant, count: PlayerSlot.count)
        indices[0] = 0  // the quarterback
        indices[1] = 1  // a back
        let snapped = play(onField: indices)
        #expect(snapped.outcome.participants.isEmpty)
        let counts = StreamQueries.snapsByPositionGroup(
            in: [(plays: [snapped], rosters: [TeamID(1): [PlayerID(1), PlayerID(2)]])],
            group: { $0 == PlayerID(1) ? .quarterback : .backfield })
        #expect(counts[.quarterback] == 1)
        #expect(counts[.backfield] == 1)
    }

    // MARK: - The targets these rows are graded against

    /// Every `runShare.` row names a bucket the engine's own class enumerates, so a row
    /// cannot outlive the split it grades.
    @Test(
        "contract: every runShare row names a DownAndDistanceClass case on second, third or fourth down",
        .tags(.contract))
    func runShareRowsNameARealBucket() {
        let named = CalibrationTarget.all.filter { $0.id.hasPrefix("runShare.") }
        #expect(named.count == 9)
        for target in named {
            let bucket = String(target.id.dropFirst("runShare.".count))
            let matched = DownAndDistanceClass.allCases.first { "\($0)" == bucket }
            #expect(matched != nil, "\(target.id) names no DownAndDistanceClass case")
            if let matched {
                #expect(
                    matched != .firstDown && matched != .goalToGo,
                    "\(target.id) grades a class no row splits")
            }
        }
    }
}

/// A row the harness could not grade is a row that cannot be `OFF`, so a run has to name
/// it. Printing an em dash and counting it in a tally is how `row:ypcOutnumberedByOne`
/// lost its whole sample without a single check going red.
@Suite("Ungraded rows")
struct UngradedRowTests {

    @Test("contract: an ungraded row is named with the reason it could not be graded", .tags(.contract))
    func namedWithItsReason() {
        var rows = UngradedRows()
        rows.record("winTotalSigma", reason: "needs a season with a schedule")
        #expect(rows.rows.count == 1)
        #expect(rows.rows[0].id == "winTotalSigma")
        #expect(rows.lines.contains { $0.contains("winTotalSigma") })
        #expect(rows.lines.contains { $0.contains("needs a season with a schedule") })
    }

    /// The failure this is really for: a row that goes ungraded and says nothing about
    /// why. It must read as a defect in the run rather than as an empty column.
    @Test("contract: a row recorded with no reason says that it has none", .tags(.contract))
    func silenceIsLoud() {
        var rows = UngradedRows()
        rows.record("ypcOutnumberedByOne", reason: "")
        #expect(rows.lines.contains { $0.contains(UngradedRows.noReasonGiven) })
    }

    @Test("unit: rows are listed in the order the run reported them", .tags(.unit))
    func inReportedOrder() {
        var rows = UngradedRows()
        rows.record("b", reason: "second")
        rows.record("a", reason: "first")
        #expect(rows.rows.map(\.id) == ["b", "a"])
    }
}
