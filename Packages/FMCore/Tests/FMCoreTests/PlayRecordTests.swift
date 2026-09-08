import Testing

@testable import FMCore

@Suite("Situation")
struct SituationTests {

    private func situation(
        down: Down = .first, distance: UInt8 = 10, ballOn: UInt8 = 75,
        quarter: UInt8 = 1, clock: UInt16 = 900
    ) -> Situation {
        Situation(
            quarter: quarter, clockRemaining: clock, down: down,
            distance: distance, ballOn: ballOn, possession: TeamID(1))
    }

    @Test("Field zones follow distance to the opponent's goal")
    func fieldZones() {
        #expect(situation(ballOn: 3).fieldZone == .goalLine)
        #expect(situation(ballOn: 15).fieldZone == .redZone)
        #expect(situation(ballOn: 35).fieldZone == .opponentTerritory)
        #expect(situation(ballOn: 50).fieldZone == .midfield)
        #expect(situation(ballOn: 70).fieldZone == .ownTerritory)
        #expect(situation(ballOn: 95).fieldZone == .ownDeep)
    }

    @Test("The red zone is inside the twenty")
    func redZone() {
        #expect(situation(ballOn: 20).isRedZone)
        #expect(situation(ballOn: 21).isRedZone == false)
    }

    /// There is no first and ten from the opponent's six: inside the ten,
    /// distance is measured to the goal line.
    @Test("Goal-to-go is when the marker would be past the goal line")
    func goalToGo() {
        #expect(situation(distance: 10, ballOn: 6).isGoalToGo)
        #expect(situation(distance: 6, ballOn: 6).isGoalToGo)
        #expect(situation(distance: 5, ballOn: 6).isGoalToGo == false)
        #expect(situation(distance: 10, ballOn: 40).isGoalToGo == false)
    }

    @Test("The two-minute drill covers the end of either half")
    func twoMinuteDrill() {
        #expect(situation(quarter: 2, clock: 90).isTwoMinuteDrill)
        #expect(situation(quarter: 4, clock: 120).isTwoMinuteDrill)
        #expect(situation(quarter: 2, clock: 200).isTwoMinuteDrill == false)
        #expect(situation(quarter: 1, clock: 60).isTwoMinuteDrill == false)
        #expect(situation(quarter: 3, clock: 60).isTwoMinuteDrill == false)
    }

    @Test("Obvious passing downs are late and long")
    func obviousPassing() {
        #expect(situation(down: .third, distance: 8).isObviousPassing)
        #expect(situation(down: .fourth, distance: 12).isObviousPassing)
        #expect(situation(down: .third, distance: 2).isObviousPassing == false)
        #expect(situation(down: .first, distance: 10).isObviousPassing == false)
    }

    @Test("Validity catches impossible states")
    func validity() {
        #expect(situation().isValid)
        #expect(situation(ballOn: 0).isValid == false)
        #expect(situation(distance: 0).isValid == false)
        #expect(situation(quarter: 0).isValid == false)

        var tooManyTimeouts = situation()
        tooManyTimeouts.offenseTimeouts = 4
        #expect(tooManyTimeouts.isValid == false)
    }

    @Test("Downs advance and run out")
    func downs() {
        #expect(Down.first.next == .second)
        #expect(Down.third.next == .fourth)
        #expect(Down.fourth.next == nil)
    }
}

@Suite("Personnel")
struct PersonnelTests {

    @Test("Receiver count follows from backs and tight ends")
    func receiverCount() {
        #expect(PersonnelGroup.eleven.wideReceivers == 3)
        #expect(PersonnelGroup.twelve.wideReceivers == 2)
        #expect(PersonnelGroup.twentyOne.wideReceivers == 2)
        #expect(PersonnelGroup.twentyTwo.wideReceivers == 1)
        #expect(PersonnelGroup.empty.wideReceivers == 5)
    }

    @Test("Codes match the convention the sport uses")
    func codes() {
        #expect(PersonnelGroup.eleven.code == 11)
        #expect(PersonnelGroup.twelve.code == 12)
        #expect(PersonnelGroup.twentyOne.code == 21)
        #expect(PersonnelGroup.twentyTwo.code == 22)
        #expect(PersonnelGroup.ten.code == 10)
    }

    @Test("Every grouping fields exactly five skill players")
    func alwaysFiveSkillPlayers() {
        let groups: [PersonnelGroup] = [
            .eleven, .twelve, .thirteen, .twentyOne, .twentyTwo, .ten, .empty,
        ]
        for group in groups {
            #expect(group.runningBacks + group.tightEnds + group.wideReceivers == 5)
        }
    }

    @Test("Defensive packages name their back count")
    func defensiveBacks() {
        #expect(DefensivePackage.base.defensiveBacks == 4)
        #expect(DefensivePackage.nickel.defensiveBacks == 5)
        #expect(DefensivePackage.dime.defensiveBacks == 6)
    }
}

@Suite("Decision points")
struct DecisionPointTests {

    /// The storage estimate in docs/play-record.md assumes eight bytes per
    /// decision point — roughly 130 bytes a play, 54MB for a decade of
    /// league-wide history. If this grows, that arithmetic and the retention
    /// policy built on it both need revisiting, so the size is asserted rather
    /// than hoped for.
    @Test("A decision point is eight bytes")
    func packedSize() {
        #expect(MemoryLayout<DecisionPoint>.size == 8)
        #expect(MemoryLayout<DecisionPoint>.stride == 8)
        #expect(MemoryLayout<PlayerSlot>.size == 1)
    }

    @Test("Slots are one byte and reject out-of-range indices")
    func slots() {
        #expect(PlayerSlot(0).rawValue == 0)
        #expect(PlayerSlot(21).rawValue == 21)
        #expect(PlayerSlot.none.isNone)
        #expect(PlayerSlot(5).isNone == false)
        #expect(PlayerSlot(3) < PlayerSlot(4))
    }

    @Test("Pressure records the blocker, the rusher and the timing")
    func pressure() {
        let point = DecisionPoint.pressureAllowed(
            tick: 21, blocker: PlayerSlot(4), rusher: PlayerSlot(15), afterMilliseconds: 2100)
        #expect(point.kind == .pressureAllowed)
        #expect(point.primary == PlayerSlot(4))
        #expect(point.secondary == PlayerSlot(15))
        #expect(point.value == 2100)
    }

    @Test("Typed reads decode the detail byte")
    func typedReads() {
        let throwPoint = DecisionPoint.throwDecision(
            tick: 25, passer: PlayerSlot(0), target: PlayerSlot(7), decision: .checkdown)
        #expect(throwPoint.throwDecisionValue == .checkdown)

        let catchPoint = DecisionPoint.catchAttempt(
            tick: 30, receiver: PlayerSlot(7), defender: PlayerSlot(18), result: .contestedCatch)
        #expect(catchPoint.catchResult == .contestedCatch)

        let tacklePoint = DecisionPoint.tackleAttempt(
            tick: 34, defender: PlayerSlot(18), carrier: PlayerSlot(7), result: .broken)
        #expect(tacklePoint.tackleResult == .broken)

        let blockPoint = DecisionPoint.blockResult(
            tick: 8, blocker: PlayerSlot(3), defender: PlayerSlot(14), result: .pancake)
        #expect(blockPoint.blockResultValue == .pancake)
    }

    /// A mis-typed query must not silently reinterpret a byte belonging to
    /// another kind.
    @Test("Typed reads refuse to decode the wrong kind")
    func typedReadsAreKindChecked() {
        let point = DecisionPoint.catchAttempt(
            tick: 30, receiver: PlayerSlot(7), defender: PlayerSlot(18), result: .dropped)
        #expect(point.catchResult == .dropped)
        #expect(point.throwDecisionValue == nil)
        #expect(point.tackleResult == nil)
        #expect(point.blockResultValue == nil)
        #expect(point.coverageTechnique == nil)
    }

    @Test("The progression read carries both its index and the separation")
    func progression() {
        let point = DecisionPoint.readProgression(
            tick: 18, receiver: PlayerSlot(8), index: 2, separationCentimetres: 45)
        #expect(point.detail == 2)
        #expect(point.value == 45)
        #expect(point.primary == PlayerSlot(8))
    }
}

@Suite("Play outcomes")
struct PlayOutcomeTests {

    /// Denominators are specific. A sack is not a pass attempt but it is a
    /// dropback, and getting that wrong makes the sack-rate calibration target
    /// meaningless.
    @Test("Dropbacks and pass attempts are different denominators")
    func denominators() {
        #expect(PlayKind.pass.isDropback)
        #expect(PlayKind.sack.isDropback)
        #expect(PlayKind.scramble.isDropback)
        #expect(PlayKind.rush.isDropback == false)

        #expect(PlayKind.pass.isPassAttempt)
        #expect(PlayKind.sack.isPassAttempt == false)
        #expect(PlayKind.scramble.isPassAttempt == false)
    }

    @Test("Scrimmage plays exclude kicks")
    func scrimmagePlays() {
        #expect(PlayKind.rush.isScrimmagePlay)
        #expect(PlayKind.kneel.isScrimmagePlay)
        #expect(PlayKind.punt.isScrimmagePlay == false)
        #expect(PlayKind.kickoff.isScrimmagePlay == false)
    }

    @Test("Turnovers and clock stoppages are classified")
    func endings() {
        #expect(PlayEnding.intercepted.isTurnover)
        #expect(PlayEnding.fumbleLost.isTurnover)
        #expect(PlayEnding.fumbleRecovered.isTurnover == false)
        #expect(PlayEnding.tackled.isTurnover == false)

        #expect(PlayEnding.incomplete.stopsClock)
        #expect(PlayEnding.outOfBounds.stopsClock)
        #expect(PlayEnding.tackled.stopsClock == false)
    }

    @Test("Pre-snap fouls and automatic first downs are classified")
    func fouls() {
        #expect(Foul.falseStart.isPreSnap)
        #expect(Foul.delayOfGame.isPreSnap)
        #expect(Foul.offensiveHolding.isPreSnap == false)

        #expect(Foul.defensivePassInterference.carriesAutomaticFirstDown)
        #expect(Foul.roughingThePasser.carriesAutomaticFirstDown)
        #expect(Foul.offensiveHolding.carriesAutomaticFirstDown == false)
        #expect(Foul.falseStart.carriesAutomaticFirstDown == false)
    }

    @Test("Participants are addressable by slot and by role")
    func participants() {
        let outcome = Outcome(
            kind: .pass, yards: 12, endedIn: .tackled,
            participants: [
                Participation(
                    slot: PlayerSlot(0), player: PlayerID(1),
                    position: .quarterback, role: .passer),
                Participation(
                    slot: PlayerSlot(7), player: PlayerID(2),
                    position: .wideReceiver, role: .receiver),
                Participation(
                    slot: PlayerSlot(18), player: PlayerID(3),
                    position: .cornerback, role: .tackler),
            ])

        #expect(outcome.participant(at: PlayerSlot(7))?.player == PlayerID(2))
        #expect(PlayerSlot(7).isOffense)
        #expect(PlayerSlot(18).isOffense == false)
        #expect(
            outcome.participant(at: PlayerSlot(18))?
                .team(possessionTeam: TeamID(1), defendingTeam: TeamID(2)) == TeamID(2))
        #expect(outcome.participant(at: PlayerSlot(21)) == nil)
        #expect(outcome.participants(inRole: .passer).count == 1)
        #expect(outcome.participants(inRole: .blocker).isEmpty)
    }
}

@Suite("Play records")
struct PlayRecordTests {

    private func record(
        down: Down = .third, distance: UInt8 = 6, ballOn: UInt8 = 45,
        yards: Int16 = 8, endedIn: PlayEnding = .tackled, kind: PlayKind = .pass
    ) -> PlayRecord {
        PlayRecord(
            id: PlayID(1), game: GameID(1), index: 12,
            situation: Situation(
                quarter: 2, clockRemaining: 480, down: down,
                distance: distance, ballOn: ballOn, possession: TeamID(1)),
            calls: Calls(
                offensivePlay: PlayID(100), defensiveCall: DefensiveCallID(200),
                offensiveCaller: .coordinator(StaffID(9)),
                defensiveCaller: .coordinator(StaffID(10))),
            outcome: Outcome(kind: kind, yards: yards, endedIn: endedIn))
    }

    @Test("A gain past the marker is a first down")
    func firstDowns() {
        #expect(record(distance: 6, yards: 8).gainedFirstDown)
        #expect(record(distance: 6, yards: 6).gainedFirstDown)
        #expect(record(distance: 6, yards: 5).gainedFirstDown == false)
    }

    @Test("A touchdown is always a first down; a turnover never is")
    func touchdownsAndTurnovers() {
        #expect(record(yards: 45, endedIn: .touchdown).gainedFirstDown)
        #expect(record(yards: 20, endedIn: .intercepted).gainedFirstDown == false)
        #expect(record(yards: 20, endedIn: .fumbleLost).gainedFirstDown == false)
    }

    /// Goal-to-go has no marker to cross — the only first down is the end zone.
    @Test("Goal-to-go gains are not first downs unless they score")
    func goalToGo() {
        #expect(record(distance: 6, ballOn: 6, yards: 5).gainedFirstDown == false)
        #expect(record(distance: 6, ballOn: 6, yards: 6, endedIn: .touchdown).gainedFirstDown)
    }

    @Test("Kicks are not first downs regardless of yardage")
    func kicks() {
        #expect(record(yards: 45, kind: .punt).gainedFirstDown == false)
    }

    @Test("Decisions are filterable by kind")
    func decisionFiltering() {
        var play = record()
        play.decisions = [
            .pressureAllowed(
                tick: 20, blocker: PlayerSlot(4), rusher: PlayerSlot(15), afterMilliseconds: 2100),
            .pressureHeld(
                tick: 20, blocker: PlayerSlot(3), rusher: PlayerSlot(14), forMilliseconds: 3200),
            .throwDecision(
                tick: 24, passer: PlayerSlot(0), target: PlayerSlot(7), decision: .checkdown),
        ]
        #expect(play.decisions(ofKind: .pressureAllowed).count == 1)
        #expect(play.decisions(ofKind: .throwDecision).count == 1)
        #expect(play.decisions(ofKind: .tackleAttempt).isEmpty)
    }

    @Test("A record round-trips through its value semantics")
    func valueSemantics() {
        let original = record()
        var copy = original
        copy.outcome.yards = 99
        #expect(original.outcome.yards == 8)
        #expect(copy.outcome.yards == 99)
        #expect(original != copy)
    }

    @Test("Callers are recorded so plan and execution can be compared")
    func callers() {
        let play = record()
        #expect(play.calls.offensiveCaller == .coordinator(StaffID(9)))
        #expect(play.calls.offensiveCaller != .player)
    }
}
