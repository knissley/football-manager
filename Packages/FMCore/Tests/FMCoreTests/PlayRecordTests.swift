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

    @Test("Field zones follow distance to the opponent's goal", .tags(.unit))
    func fieldZones() {
        #expect(situation(ballOn: 3).fieldZone == .goalLine)
        #expect(situation(ballOn: 15).fieldZone == .redZone)
        #expect(situation(ballOn: 35).fieldZone == .opponentTerritory)
        #expect(situation(ballOn: 50).fieldZone == .midfield)
        #expect(situation(ballOn: 70).fieldZone == .ownTerritory)
        #expect(situation(ballOn: 95).fieldZone == .ownDeep)
    }

    @Test("The red zone is inside the twenty", .tags(.unit))
    func redZone() {
        #expect(situation(ballOn: 20).isRedZone)
        #expect(situation(ballOn: 21).isRedZone == false)
    }

    /// There is no first and ten from the opponent's six: inside the ten,
    /// distance is measured to the goal line.
    @Test("Goal-to-go is when the marker would be past the goal line", .tags(.unit))
    func goalToGo() {
        #expect(situation(distance: 10, ballOn: 6).isGoalToGo)
        #expect(situation(distance: 6, ballOn: 6).isGoalToGo)
        #expect(situation(distance: 5, ballOn: 6).isGoalToGo == false)
        #expect(situation(distance: 10, ballOn: 40).isGoalToGo == false)
    }

    @Test("The two-minute drill covers the end of either half", .tags(.unit))
    func twoMinuteDrill() {
        #expect(situation(quarter: 2, clock: 90).isTwoMinuteDrill())
        #expect(situation(quarter: 4, clock: 120).isTwoMinuteDrill())
        #expect(situation(quarter: 2, clock: 200).isTwoMinuteDrill() == false)
        #expect(situation(quarter: 1, clock: 60).isTwoMinuteDrill() == false)
        #expect(situation(quarter: 3, clock: 60).isTwoMinuteDrill() == false)
    }

    /// The half boundaries and the threshold come from the rules, so a variant moves
    /// them (A8, #20).
    @Test(
        "unit · the two-minute drill follows Rules.quarters and Rules.twoMinuteWarning",
        .tags(.unit))
    func twoMinuteDrillFollowsTheRules() {
        let variant = Rules(quarters: 2, twoMinuteWarning: 60)
        #expect(situation(quarter: 1, clock: 60).isTwoMinuteDrill(rules: variant))
        #expect(situation(quarter: 1, clock: 61).isTwoMinuteDrill(rules: variant) == false)
        #expect(situation(quarter: 2, clock: 30).isTwoMinuteDrill(rules: variant))
    }

    @Test("Obvious passing downs are late and long", .tags(.unit))
    func obviousPassing() {
        #expect(situation(down: .third, distance: 8).isObviousPassing)
        #expect(situation(down: .fourth, distance: 12).isObviousPassing)
        #expect(situation(down: .third, distance: 2).isObviousPassing == false)
        #expect(situation(down: .first, distance: 10).isObviousPassing == false)
    }

    @Test("Validity catches impossible states", .tags(.unit))
    func validity() {
        #expect(situation().isValid)
        #expect(situation(ballOn: 0).isValid == false)
        #expect(situation(distance: 0).isValid == false)
        #expect(situation(quarter: 0).isValid == false)

        var tooManyTimeouts = situation()
        tooManyTimeouts.offenseTimeouts = 4
        #expect(tooManyTimeouts.isValid == false)
    }

    /// A postseason game plays as many overtime periods as it takes, so a sixth or a
    /// seventh period is a situation the engine has to be able to describe (A8, #20).
    @Test("unit · a postseason double-overtime situation is valid", .tags(.unit))
    func doubleOvertimeIsValid() {
        #expect(situation(quarter: 6, clock: 900).isValid)
        #expect(situation(quarter: 7, clock: 400).isValid)
    }

    @Test("Downs advance and run out", .tags(.unit))
    func downs() {
        #expect(Down.first.next == .second)
        #expect(Down.third.next == .fourth)
        #expect(Down.fourth.next == nil)
    }
}

@Suite("Personnel")
struct PersonnelTests {

    @Test("Receiver count follows from backs and tight ends", .tags(.unit))
    func receiverCount() {
        #expect(PersonnelGroup.eleven.wideReceivers == 3)
        #expect(PersonnelGroup.twelve.wideReceivers == 2)
        #expect(PersonnelGroup.twentyOne.wideReceivers == 2)
        #expect(PersonnelGroup.twentyTwo.wideReceivers == 1)
        #expect(PersonnelGroup.empty.wideReceivers == 5)
    }

    @Test("Codes match the convention the sport uses", .tags(.unit))
    func codes() {
        #expect(PersonnelGroup.eleven.code == 11)
        #expect(PersonnelGroup.twelve.code == 12)
        #expect(PersonnelGroup.twentyOne.code == 21)
        #expect(PersonnelGroup.twentyTwo.code == 22)
        #expect(PersonnelGroup.ten.code == 10)
    }

    @Test("Every grouping fields exactly five skill players", .tags(.unit))
    func alwaysFiveSkillPlayers() {
        let groups: [PersonnelGroup] = [
            .eleven, .twelve, .thirteen, .twentyOne, .twentyTwo, .ten, .empty,
        ]
        for group in groups {
            #expect(group.runningBacks + group.tightEnds + group.wideReceivers == 5)
        }
    }

    @Test("Defensive packages name their back count", .tags(.unit))
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
    @Test("A decision point is eight bytes", .tags(.contract))
    func packedSize() {
        #expect(MemoryLayout<DecisionPoint>.size == 8)
        #expect(MemoryLayout<DecisionPoint>.stride == 8)
        #expect(MemoryLayout<PlayerSlot>.size == 1)
    }

    @Test("Slots are one byte and reject out-of-range indices", .tags(.unit))
    func slots() {
        #expect(PlayerSlot(0).rawValue == 0)
        #expect(PlayerSlot(21).rawValue == 21)
        #expect(PlayerSlot.none.isNone)
        #expect(PlayerSlot(5).isNone == false)
        #expect(PlayerSlot(3) < PlayerSlot(4))
    }

    @Test("Pressure records the blocker, the rusher and the timing", .tags(.unit))
    func pressure() {
        let point = DecisionPoint.pressureAllowed(
            tick: 21, blocker: PlayerSlot(4), rusher: PlayerSlot(15), afterMilliseconds: 2100)
        #expect(point.kind == .pressureAllowed)
        #expect(point.primary == PlayerSlot(4))
        #expect(point.secondary == PlayerSlot(15))
        #expect(point.value == 2100)
    }

    @Test("Typed reads decode the detail byte", .tags(.unit))
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
    @Test("Typed reads refuse to decode the wrong kind", .tags(.unit))
    func typedReadsAreKindChecked() {
        let point = DecisionPoint.catchAttempt(
            tick: 30, receiver: PlayerSlot(7), defender: PlayerSlot(18), result: .dropped)
        #expect(point.catchResult == .dropped)
        #expect(point.throwDecisionValue == nil)
        #expect(point.tackleResult == nil)
        #expect(point.blockResultValue == nil)
        #expect(point.coverageTechnique == nil)
    }

    @Test("The progression read carries both its index and the separation", .tags(.unit))
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
    @Test("Dropbacks and pass attempts are different denominators", .tags(.unit))
    func denominators() {
        #expect(PlayKind.pass.isDropback)
        #expect(PlayKind.sack.isDropback)
        #expect(PlayKind.scramble.isDropback)
        #expect(PlayKind.rush.isDropback == false)

        #expect(PlayKind.pass.isPassAttempt)
        #expect(PlayKind.sack.isPassAttempt == false)
        #expect(PlayKind.scramble.isPassAttempt == false)
    }

    @Test("Scrimmage plays exclude kicks", .tags(.unit))
    func scrimmagePlays() {
        #expect(PlayKind.rush.isScrimmagePlay)
        #expect(PlayKind.kneel.isScrimmagePlay)
        #expect(PlayKind.punt.isScrimmagePlay == false)
        #expect(PlayKind.kickoff.isScrimmagePlay == false)
    }

    @Test("Turnovers and clock stoppages are classified", .tags(.unit))
    func endings() {
        #expect(PlayEnding.intercepted.isTurnover)
        #expect(PlayEnding.fumbleLost.isTurnover)
        #expect(PlayEnding.fumbleRecovered.isTurnover == false)
        #expect(PlayEnding.tackled.isTurnover == false)

        // What the clock does is a rules question, not a property of the ending: see
        // `Rules.clockBehavior(after:quarter:clockRemaining:)`. Out of bounds is the
        // case that proves it — it stops the clock until the snap only late in a half.
        #expect(PlayEnding.incomplete.isTurnover == false)
        #expect(PlayEnding.intercepted.isTurnover)
    }

    @Test("Pre-snap fouls and automatic first downs are classified", .tags(.unit))
    func fouls() {
        #expect(Foul.falseStart.isPreSnap)
        #expect(Foul.delayOfGame.isPreSnap)
        #expect(Foul.tooManyMenOnField.isPreSnap)
        #expect(Foul.offensiveHolding.isPreSnap == false)

        #expect(Foul.defensivePassInterference.carriesAutomaticFirstDown)
        #expect(Foul.roughingThePasser.carriesAutomaticFirstDown)
        #expect(Foul.horseCollarTackle.carriesAutomaticFirstDown)
        #expect(Foul.offensiveHolding.carriesAutomaticFirstDown == false)
        #expect(Foul.falseStart.carriesAutomaticFirstDown == false)
    }

    @Test("The foul list is detailed enough to sound like a broadcast", .tags(.unit))
    func foulCoverage() {
        #expect(Foul.allCases.count >= 30)
        #expect(Set(Foul.allCases.map(\.rawValue)).count == Foul.allCases.count)
    }

    /// Deep interference is the highest-variance call in the sport precisely
    /// because it is enforced from the spot rather than as fixed yardage.
    @Test("Only pass interference is a spot foul", .tags(.unit))
    func spotFouls() {
        #expect(Foul.defensivePassInterference.isSpotFoul)
        #expect(Foul.defensivePassInterference.yards == 0)
        for foul in Foul.allCases where !foul.isSpotFoul {
            #expect(foul.yards > 0, "\(foul) has no yardage and is not a spot foul")
            #expect([5, 10, 15].contains(foul.yards), "\(foul) has odd yardage \(foul.yards)")
        }
    }

    @Test("Fouls only one side can commit are attributed to that side", .tags(.unit))
    func foulSides() {
        #expect(Foul.falseStart.committedBy == .offense)
        #expect(Foul.offensiveHolding.committedBy == .offense)
        #expect(Foul.offside.committedBy == .defense)
        #expect(Foul.roughingThePasser.committedBy == .defense)
        // Either side can taunt, or have twelve on the field.
        #expect(Foul.taunting.committedBy == nil)
        #expect(Foul.tooManyMenOnField.committedBy == nil)
    }

    @Test("Participants are addressable by slot and by role", .tags(.unit))
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
            game: GameID(1), index: 12,
            situation: Situation(
                quarter: 2, clockRemaining: 480, down: down,
                distance: distance, ballOn: ballOn, possession: TeamID(1)),
            calls: Calls(
                offense: OffensiveCall(design: PlayDesignID(100)),
                defense: .nickelTwoMan,
                offensiveCaller: .coordinator(PersonnelID(9)),
                defensiveCaller: .coordinator(PersonnelID(10))),
            outcome: Outcome(kind: kind, yards: yards, endedIn: endedIn))
    }

    @Test("A gain past the marker is a first down", .tags(.unit))
    func firstDowns() {
        #expect(record(distance: 6, yards: 8).gainedFirstDown)
        #expect(record(distance: 6, yards: 6).gainedFirstDown)
        #expect(record(distance: 6, yards: 5).gainedFirstDown == false)
    }

    @Test("A touchdown is always a first down; a turnover never is", .tags(.unit))
    func touchdownsAndTurnovers() {
        #expect(record(yards: 45, endedIn: .touchdown).gainedFirstDown)
        #expect(record(yards: 20, endedIn: .intercepted).gainedFirstDown == false)
        #expect(record(yards: 20, endedIn: .fumbleLost).gainedFirstDown == false)
    }

    /// Goal-to-go has no marker to cross — the only first down is the end zone.
    @Test("Goal-to-go gains are not first downs unless they score", .tags(.unit))
    func goalToGo() {
        #expect(record(distance: 6, ballOn: 6, yards: 5).gainedFirstDown == false)
        #expect(record(distance: 6, ballOn: 6, yards: 6, endedIn: .touchdown).gainedFirstDown)
    }

    /// A play is addressed by where it sits, not by an allocated number
    /// ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)).
    /// This is what lets a link to a play survive the game being regenerated from its
    /// seed rather than retained.
    @Test("A play's identity is derived from its game and index", .tags(.contract))
    func derivedIdentity() {
        let play = record()
        #expect(play.id == PlayRef(game: GameID(1), index: 12))

        var replayed = play
        replayed.outcome = Outcome(kind: .rush, yards: 2, endedIn: .tackled)
        #expect(
            replayed.id == play.id,
            "identity must not depend on what happened, only on where the play sits")
    }

    /// Plays are ordered within a game. A week's games are concurrent, so there is no
    /// global play order to appeal to — ordering across games comes from the schedule.
    @Test("References order by game, then by index within it", .tags(.unit))
    func referenceOrdering() {
        let first = PlayRef(game: GameID(1), index: 0)
        let later = PlayRef(game: GameID(1), index: 40)
        let otherGame = PlayRef(game: GameID(2), index: 0)

        #expect(first < later)
        #expect(later < otherGame)
        #expect(first != otherGame)
    }

    /// The calls are captured, not pointed at
    /// ([ADR-0010](../../../../docs/adr/0010-plays-designs-and-calls.md)). Editing a
    /// design in the play designer must never rewrite what was called three seasons ago.
    @Test("The record captures both calls by value", .tags(.contract))
    func callsAreCapturedByValue() {
        let play = record()
        #expect(play.calls.defense.coverage == .twoMan)
        #expect(play.calls.offense.design == PlayDesignID(100))
        #expect(play.calls.offense.tempo == .normal)
    }

    /// The call selects the package and the situation observes it, so the two must
    /// agree on a well-formed record.
    @Test("A record's defensive package matches the call that selected it", .tags(.contract))
    func packageMatchesCall() {
        var play = record()
        play.situation.defensePackage = play.calls.defense.package
        #expect(play.situation.defensePackage == .nickel)
    }

    @Test("Kicks are not first downs regardless of yardage", .tags(.unit))
    func kicks() {
        #expect(record(yards: 45, kind: .punt).gainedFirstDown == false)
    }

    @Test("Decisions are filterable by kind", .tags(.unit))
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

    @Test("A record round-trips through its value semantics", .tags(.unit))
    func valueSemantics() {
        let original = record()
        var copy = original
        copy.outcome.yards = 99
        #expect(original.outcome.yards == 8)
        #expect(copy.outcome.yards == 99)
        #expect(original != copy)
    }

    @Test("Callers are recorded so plan and execution can be compared", .tags(.unit))
    func callers() {
        let play = record()
        #expect(play.calls.offensiveCaller == .coordinator(PersonnelID(9)))
        #expect(play.calls.offensiveCaller != .player)
    }
}
