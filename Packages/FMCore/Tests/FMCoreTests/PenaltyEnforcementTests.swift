import Testing

@testable import FMCore

@Suite("Penalty enforcement")
struct PenaltyEnforcementTests {

    private let rules = Rules.standard

    private func situation(
        down: Down = .second, distance: UInt8 = 8, ballOn: UInt8 = 60
    ) -> Situation {
        Situation(
            quarter: 2, clockRemaining: 600, down: down, distance: distance, ballOn: ballOn,
            possession: TeamID(1))
    }

    private func penalty(_ foul: Foul, yards: UInt8? = nil) -> PenaltyRecord {
        PenaltyRecord(
            foul: foul, offender: PlayerSlot(3), offendingTeam: TeamID(1),
            yards: yards ?? foul.yards, wasAccepted: false)
    }

    private func outcome(_ yards: Int16, _ ending: PlayEnding = .tackled) -> Outcome {
        Outcome(kind: .rush, yards: yards, endedIn: ending)
    }

    /// The classic bug this exists to prevent: a declined penalty that still moves the
    /// ball. Declining must return the play's own advancement, untouched.
    ///
    /// Five yards on the defence against a twenty-five yard gain is the unambiguous
    /// case — no offence takes the flag.
    @Test("A declined penalty changes nothing about the play")
    func declinedChangesNothing() {
        let before = situation(down: .second, distance: 8, ballOn: 60)
        let play = outcome(25)
        let expected = rules.advance(from: before, outcome: play)

        let decision = rules.enforce(
            penalty(.defensiveHolding), on: before, outcome: play, offendingTeamHadBall: false)

        #expect(decision.accepted == false)
        #expect(decision.penalty.wasAccepted == false)
        #expect(decision.penalty.awardedFirstDown == false, "a declined flag awards nothing")
        #expect(decision.advancement == expected)
    }

    /// A holding call on a long touchdown is declined. No yardage is worth giving back
    /// points.
    @Test("A team never declines its own score to take yards")
    func scoresAreNeverGivenBack() {
        let decision = rules.enforce(
            penalty(.defensiveHolding), on: situation(ballOn: 40),
            outcome: outcome(40, .touchdown), offendingTeamHadBall: false)

        #expect(decision.accepted == false)
        #expect(decision.advancement.scoring == .touchdown)
    }

    /// And the mirror: the defence does not accept a flag that leaves the offence's
    /// score standing. Accepting a five-yard holding call after conceding a touchdown
    /// would be a scoreboard bug wearing a rules hat.
    @Test("The defence never accepts a flag that leaves a score standing")
    func defenceDeclinesWhenItWouldConcede() {
        let decision = rules.enforce(
            penalty(.offensiveHolding), on: situation(down: .second, distance: 8, ballOn: 40),
            outcome: outcome(40, .touchdown), offendingTeamHadBall: true)
        #expect(decision.accepted, "a flag on the offence wipes out their own touchdown")
        #expect(decision.advancement.scoring == nil)
    }

    /// The defence taking away a big gain is the other unambiguous direction.
    @Test("The defence accepts a flag that erases a long gain")
    func defenceTakesAwayABigGain() {
        let decision = rules.enforce(
            penalty(.offensiveHolding), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(30), offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 70)
    }

    /// Third and eight, an incompletion, and a five-yard flag on the defence: take it.
    @Test("The offence takes yards when the play gained nothing")
    func offenceTakesYardsOnAFailedPlay() {
        let decision = rules.enforce(
            penalty(.illegalContact), on: situation(down: .third, distance: 8, ballOn: 60),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: false)

        #expect(decision.accepted)
        #expect(decision.penalty.wasAccepted)
        #expect(decision.penalty.awardedFirstDown, "illegal contact is an automatic first down")
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.ballOn == 55)
    }

    /// Moving back five yards makes it second and thirteen, not second and eight. The
    /// marker does not move with the ball.
    ///
    /// Tested through a pre-snap foul, which always stands, so the assertion is about
    /// enforcement arithmetic and not about a close accept/decline judgement.
    @Test("An accepted foul against the offence replays the down from further back")
    func offensiveFoulAddsToTheDistance() {
        let decision = rules.enforce(
            penalty(.falseStart), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: true)

        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 65)
        #expect(decision.advancement.down == .second, "the down is replayed")
        #expect(decision.advancement.distance == 13)
    }

    @Test("Automatic first downs are awarded only against the defence")
    func automaticFirstDowns() {
        for foul in Foul.allCases where foul.carriesAutomaticFirstDown {
            let againstDefence = rules.enforce(
                penalty(foul), on: situation(down: .third, distance: 15, ballOn: 60),
                outcome: outcome(0, .incomplete), offendingTeamHadBall: false)
            #expect(againstDefence.penalty.awardedFirstDown, "\(foul)")
            #expect(againstDefence.advancement.down == .first)
        }

        // The same foul charged to the offence never awards them anything.
        let againstOffence = rules.enforce(
            penalty(.offensivePassInterference), on: situation(),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: true)
        #expect(againstOffence.penalty.awardedFirstDown == false)
    }

    /// A pre-snap foul is a dead ball. There is no play to decline in favour of, so the
    /// flag stands whatever the play "would" have produced.
    @Test("Pre-snap fouls always stand")
    func preSnapFoulsStand() {
        for foul in Foul.allCases where foul.isPreSnap {
            let decision = rules.enforce(
                penalty(foul), on: situation(), outcome: outcome(45, .touchdown),
                offendingTeamHadBall: true)
            #expect(decision.accepted, "\(foul) should not be declinable")
        }
    }

    /// A penalty can never place the ball in an end zone, in either direction. Half the
    /// distance to the goal is the rule, and it applies on both ends of the field.
    /// Tested through pre-snap fouls, which always stand, so the arithmetic is measured
    /// rather than the accept/decline judgement.
    @Test("Half the distance keeps the ball out of both end zones")
    func halfTheDistance() {
        let nearTheirGoal = rules.enforce(
            penalty(.offside), on: situation(ballOn: 4),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: false)
        #expect(nearTheirGoal.accepted)
        #expect(nearTheirGoal.advancement.ballOn >= 1)
        #expect(nearTheirGoal.advancement.ballOn < 4, "five yards would have reached the end zone")

        let nearOwnGoal = rules.enforce(
            penalty(.falseStart), on: situation(ballOn: 97),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: true)
        #expect(nearOwnGoal.accepted)
        #expect(nearOwnGoal.advancement.ballOn <= 99)
        #expect(nearOwnGoal.advancement.ballOn > 97, "five yards would have been a safety")
    }

    /// Deep interference is the highest-variance call in the sport because it is
    /// enforced from the spot rather than at a fixed yardage.
    @Test("A spot foul is enforced at its measured distance")
    func spotFouls() {
        #expect(Foul.defensivePassInterference.isSpotFoul)

        let decision = rules.enforce(
            penalty(.defensivePassInterference, yards: 38),
            on: situation(down: .second, distance: 10, ballOn: 60),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: false)

        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 22)
        #expect(decision.advancement.down == .first)
    }

    /// Whichever branch is taken, the result has to be a legal down at a legal spot.
    @Test("Every enforcement leaves a legal situation")
    func enforcementIsAlwaysLegal() {
        let spots: [UInt8] = [2, 5, 20, 50, 80, 96, 99]
        for foul in Foul.allCases {
            for ballOn in spots {
                for offense in [true, false] {
                    for ending in [PlayEnding.tackled, .incomplete, .touchdown, .intercepted] {
                        let decision = rules.enforce(
                            penalty(foul), on: situation(ballOn: ballOn),
                            outcome: Outcome(
                                kind: .rush, yards: 6, endedIn: ending, finalSpot: ballOn),
                            offendingTeamHadBall: offense)
                        let result = decision.advancement
                        #expect(
                            result.ballOn >= 1 && result.ballOn <= 99,
                            "\(foul) at \(ballOn) landed on \(result.ballOn)")
                        #expect(result.distance >= 1, "\(foul) produced a distance of zero")
                    }
                }
            }
        }
    }
}
