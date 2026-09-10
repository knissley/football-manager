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

    private func penalty(
        _ foul: Foul, yards: UInt8? = nil, enforcementSpot: UInt8? = nil,
        byTeam team: TeamID = TeamID(1)
    ) -> PenaltyRecord {
        PenaltyRecord(
            foul: foul, offender: PlayerSlot(3), offendingTeam: team,
            yards: yards ?? foul.yards, wasAccepted: false, enforcementSpot: enforcementSpot)
    }

    private func outcome(
        _ yards: Int16, _ ending: PlayEnding = .tackled, kind: PlayKind = .rush,
        finalSpot: UInt8? = nil
    ) -> Outcome {
        Outcome(kind: kind, yards: yards, endedIn: ending, finalSpot: finalSpot)
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
    ///
    /// Rewritten for A6 (#18): the spot used to travel in the `yards` field as a
    /// walk-off distance; it is the record's `enforcementSpot` now, in the snapping
    /// team's frame, and `yards` is the distance walked off.
    @Test(
        "football · Rule 8-5-4, 8-6-1-b · defensive pass interference is a first down at the spot of the foul"
    )
    func spotFouls() {
        #expect(Foul.defensivePassInterference.isSpotFoul)
        #expect(Foul.defensivePassInterference.enforcement == .spotOfFoul)

        let decision = rules.enforce(
            penalty(.defensivePassInterference, yards: 38, enforcementSpot: 22),
            on: situation(down: .second, distance: 10, ballOn: 60),
            outcome: outcome(0, .incomplete), offendingTeamHadBall: false)

        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 22)
        #expect(decision.advancement.down == .first)
        #expect(decision.penalty.yards == 38, "the distance walked off")
    }

    // MARK: - Where a foul is enforced from (A6, #18)

    /// The three families, from the 2025 rulebook's Rule 14 and Rule 8 Section 6:
    /// fouls enforced from the previous spot, fouls enforced from the spot of the foul,
    /// and fouls enforced from the dead-ball spot with the play's gain counting.
    @Test(
        "football · Rule 14-3-4, 14-3-6, 8-6-1, 8-6-1-b, 8-6-1-d, 12-3-1 · every foul is enforced from the previous spot, the spot of the foul, or the succeeding spot"
    )
    func enforcementFamilies() {
        let previous: [Foul] = [
            .falseStart, .offside, .delayOfGame, .offensiveHolding, .illegalUseOfHands,
            .ineligibleReceiverDownfield, .offensivePassInterference, .defensiveHolding,
            .illegalContact,
        ]
        let spot: [Foul] = [
            .defensivePassInterference, .illegalBlockInTheBack, .illegalBlindsideBlock, .lowBlock,
        ]
        let succeeding: [Foul] = [
            .facemask, .unnecessaryRoughness, .horseCollarTackle, .illegalUseOfHelmet,
            .roughingThePasser, .unsportsmanlikeConduct, .taunting,
        ]
        for foul in previous { #expect(foul.enforcement == .previousSpot, "\(foul)") }
        for foul in spot { #expect(foul.enforcement == .spotOfFoul, "\(foul)") }
        for foul in succeeding { #expect(foul.enforcement == .succeedingSpot, "\(foul)") }
        #expect(
            Foul.allCases.filter(\.isSpotFoul)
                == Foul.allCases.filter { $0.enforcement == .spotOfFoul },
            "interference is no longer the only spot foul")
    }

    /// A run with a foul by the defence during it is enforced from the basic spot,
    /// which is the dead-ball spot when possession did not change (14-3-5-a, 14-3-6);
    /// the gain counts, then fifteen more, and a first down (12-2-15).
    @Test(
        "football · Rule 12-2-15, 14-3-5-a, 14-3-6 · a facemask at the end of a 20-yard run on first and ten is first and ten 35 yards on"
    )
    func facemaskAtTheEndOfARun() {
        let decision = rules.enforce(
            penalty(.facemask), on: situation(down: .first, distance: 10, ballOn: 60),
            outcome: outcome(20), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.penalty.awardedFirstDown)
        #expect(decision.advancement.ballOn == 25)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 10)
        #expect(decision.advancement.possessionChanged == false)
    }

    /// A pass play ends at the catch; a personal foul by the defence before the
    /// completion is enforced from the previous spot or the dead-ball spot, whichever
    /// is better for the offence (8-6-1, 8-6-1-d), with the automatic first down
    /// (12-2-11).
    @Test(
        "football · Rule 12-2-11, 8-6-1-d · roughing the passer on a 6-yard completion on third and ten is first and ten 21 yards on"
    )
    func roughingOnACompletion() {
        let decision = rules.enforce(
            penalty(.roughingThePasser), on: situation(down: .third, distance: 10, ballOn: 60),
            outcome: outcome(6, kind: .pass), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 39)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 10)
    }

    @Test(
        "football · Rule 12-2-11, 8-6-1 · roughing the passer on an incompletion is 15 from the previous spot and a first down"
    )
    func roughingOnAnIncompletion() {
        let decision = rules.enforce(
            penalty(.roughingThePasser), on: situation(down: .third, distance: 10, ballOn: 60),
            outcome: outcome(0, .incomplete, kind: .pass), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 45)
        #expect(decision.advancement.down == .first)
    }

    /// The basic spot is behind the line, so the defence's foul is enforced from the
    /// previous spot (14-3-6, the exception for the defence).
    @Test(
        "football · Rule 14-3-6 · a defensive contact foul on a play that lost yards is enforced from the previous spot"
    )
    func contactFoulOnALoss() {
        let decision = rules.enforce(
            penalty(.roughingThePasser), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(-6, kind: .sack), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 45)
        #expect(decision.advancement.down == .first)
    }

    @Test(
        "football · Rule 8-5-4, 8-6-1-b · defensive pass interference 30 yards downfield is a first down at the spot"
    )
    func interferenceDownfield() {
        let decision = rules.enforce(
            penalty(.defensivePassInterference, yards: 30, enforcementSpot: 30),
            on: situation(down: .second, distance: 10, ballOn: 60),
            outcome: outcome(0, .incomplete, kind: .pass), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 30)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 10)
    }

    @Test(
        "football · Rule 8-5-4 · offensive pass interference is ten from the previous spot, and the down is replayed"
    )
    func offensiveInterference() {
        let decision = rules.enforce(
            penalty(.offensivePassInterference),
            on: situation(down: .second, distance: 10, ballOn: 60),
            outcome: outcome(0, .incomplete, kind: .pass), offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 70)
        #expect(decision.advancement.down == .second)
        #expect(decision.advancement.distance == 20)
    }

    /// The offence fouls behind the basic spot — the run went on past the block — so
    /// enforcement is from the spot of the foul (14-3-6), and the down is replayed.
    @Test(
        "football · Rule 12-1-3-b, 14-3-6 · an illegal block in the back 8 yards into a 30-yard run puts the ball 10 yards behind the foul, and the down is replayed"
    )
    func blockInTheBackDuringARun() {
        let decision = rules.enforce(
            penalty(.illegalBlockInTheBack, enforcementSpot: 52),
            on: situation(down: .first, distance: 10, ballOn: 60),
            outcome: outcome(30), offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 62)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 12)
    }

    /// Fouls by the offence behind the line of scrimmage are enforced from the previous
    /// spot (14-3-6, exception 1).
    @Test(
        "football · Rule 14-3-6 · an offensive block in the back behind the line is enforced from the previous spot"
    )
    func blockInTheBackBehindTheLine() {
        let decision = rules.enforce(
            penalty(.illegalBlockInTheBack, enforcementSpot: 63),
            on: situation(down: .first, distance: 10, ballOn: 60),
            outcome: outcome(7), offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 70)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 20)
    }

    @Test(
        "football · Rule 12-1-3, 14-3-6 · offensive holding on a gain is ten from the previous spot, and the down is replayed"
    )
    func holdingOnAGain() {
        let decision = rules.enforce(
            penalty(.offensiveHolding), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(12), offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 70)
        #expect(decision.advancement.down == .second)
        #expect(decision.advancement.distance == 18)
    }

    /// A foul by the team scored upon during a touchdown is enforced on the try
    /// (14-2-3), which the engine does not model yet (C9): the score stands, and the
    /// flag is recorded declined until then.
    @Test("football · Rule 14-2-3 · a defensive foul on a touchdown play leaves the score standing")
    func defensiveFoulOnATouchdown() {
        let decision = rules.enforce(
            penalty(.facemask), on: situation(down: .first, distance: 10, ballOn: 20),
            outcome: outcome(20, .touchdown), offendingTeamHadBall: false)
        #expect(decision.accepted == false, "recorded declined until C9 enforces it on the try")
        #expect(decision.advancement.scoring == .touchdown)
        #expect(decision.advancement.requiresTry)
    }

    /// A foul by the offence during its own run is enforced by the three-and-one
    /// method (14-3-6): behind the basic spot, from the spot of the foul, which the
    /// record does not carry, so the previous spot stands in — and the touchdown at
    /// the end of the run does not count, because the play it came on is replayed.
    @Test(
        "football · Rule 14-3-6 · a facemask by the offence during its own touchdown run nullifies the score, enforced from the previous spot"
    )
    func offensiveContactFoulOnItsOwnScore() {
        let decision = rules.enforce(
            penalty(.facemask), on: situation(down: .first, distance: 10, ballOn: 20),
            outcome: outcome(20, .touchdown), offendingTeamHadBall: true)
        #expect(decision.accepted, "the defence takes the flag over the score")
        #expect(decision.advancement.scoring == nil)
        #expect(decision.advancement.ballOn == 35)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 25)
    }

    /// The frame rule: enforcement is computed in the frame of the team that will snap
    /// next. A personal foul by the offence during a play on which it loses the ball
    /// leaves the defence in possession, enforced from the dead-ball spot (14-4-3-b).
    @Test(
        "football · Rule 12-2-15, 14-4-3-b · a facemask by the former offence on an interception return is 15 from the dead-ball spot in the returning team's frame, first down"
    )
    func facemaskByTheFormerOffenseOnAReturn() {
        // Intercepted and returned to the 75 in the throwing team's frame: the
        // interceptors have it 25 from the goal they attack.
        let decision = rules.enforce(
            penalty(.facemask), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(0, .intercepted, kind: .pass, finalSpot: 75),
            offendingTeamHadBall: true)
        #expect(decision.accepted)
        #expect(decision.advancement.possessionChanged, "the returning team keeps the ball")
        #expect(decision.advancement.ballOn == 10, "the 25, and fifteen more")
        #expect(decision.advancement.down == .first)
    }

    @Test(
        "football · Rule 12-1-3-b, 14-3-6 · a block in the back by the returning team during a punt return is enforced from the spot of the foul in its frame"
    )
    func blockInTheBackOnAReturn() {
        // Punted from the 60; fielded and brought out to the receivers' own 30, with the
        // block at their own 20. Both spots are in the kicking team's frame, as the
        // resolver reports them, which is the same number as the receivers' own yard line.
        let decision = rules.enforce(
            penalty(.illegalBlockInTheBack, enforcementSpot: 20, byTeam: TeamID(2)),
            on: situation(down: .fourth, distance: 8, ballOn: 60),
            outcome: outcome(0, .tackled, kind: .punt, finalSpot: 30),
            offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.possessionChanged, "the receivers keep the ball")
        #expect(decision.advancement.ballOn == 90, "their own 20, and ten back: their own 10")
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 10)
    }

    @Test(
        "football · Rule 8-5-4, 8-6-1-b · interference in the end zone is first and goal at the 1")
    func interferenceInTheEndZone() {
        let decision = rules.enforce(
            penalty(.defensivePassInterference, yards: 30, enforcementSpot: 0),
            on: situation(down: .second, distance: 10, ballOn: 30),
            outcome: outcome(0, .incomplete, kind: .pass), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 1)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 1)
    }

    /// Half the distance is measured from the spot of enforcement (14-2-1), which for a
    /// contact foul at the end of a run is the end of the run.
    @Test(
        "football · Rule 14-2-1, 12-2-15 · half the distance is measured from the enforcement spot: a facemask at the 6 after a run gives the 3"
    )
    func halfTheDistanceFromTheEnforcementSpot() {
        let decision = rules.enforce(
            penalty(.facemask), on: situation(down: .first, distance: 10, ballOn: 26),
            outcome: outcome(20), offendingTeamHadBall: false)
        #expect(decision.accepted)
        #expect(decision.advancement.ballOn == 3)
        #expect(decision.advancement.down == .first)
        #expect(decision.advancement.distance == 3, "first and goal")
    }

    /// A dead-ball conduct foul by the defence after the play: fifteen from the
    /// succeeding spot and an automatic first down (12-3-1); by the offence, fifteen
    /// back and the down stands.
    @Test(
        "football · Rule 12-3-1 · unsportsmanlike conduct after the play is fifteen from the succeeding spot, an automatic first down when by the defence"
    )
    func conductFoulAfterThePlay() {
        let byDefence = rules.enforce(
            penalty(.unsportsmanlikeConduct), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(3), offendingTeamHadBall: false)
        #expect(byDefence.accepted)
        #expect(byDefence.advancement.ballOn == 42)
        #expect(byDefence.advancement.down == .first)

        let byOffence = rules.enforce(
            penalty(.unsportsmanlikeConduct), on: situation(down: .second, distance: 8, ballOn: 60),
            outcome: outcome(3), offendingTeamHadBall: true)
        #expect(byOffence.accepted)
        #expect(byOffence.advancement.ballOn == 72)
        #expect(byOffence.advancement.down == .third)
        #expect(byOffence.advancement.distance == 20)
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
