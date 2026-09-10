import Testing

@testable import FMCore

/// What a try is worth, and where a touchback puts the ball.
///
/// Both were wrong for a long time, in the same way and for the same reason:
/// `Rules.advance` switched on `PlayEnding` alone and never asked what kind of play it
/// was. A made extra point paid three points as a field goal, a two-point conversion paid
/// six as a touchdown, and a kickoff into the end zone was spotted like a punt's.
///
/// None of it was caught, because none of it was ever asserted. Two hundred and
/// seventy-eight tests, and not one asked what an extra point is worth. These are the
/// rules a player can check against the scoreboard in his first game, which is exactly
/// the class of thing that gets exhaustive tests.
@Suite("Tries and touchbacks")
struct TryAndTouchbackTests {

    private let rules = Rules.standard

    private func tryFrom(_ ballOn: UInt8) -> Situation {
        Situation(
            quarter: 3, clockRemaining: 500, down: .first, distance: max(1, ballOn),
            ballOn: ballOn, possession: TeamID(1))
    }

    @Test("A made extra point is worth one point", .tags(.unit))
    func extraPointIsOnePoint() {
        let advancement = rules.advance(
            from: tryFrom(rules.extraPointSnapYard),
            outcome: Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood))

        #expect(advancement.points == 1)
        #expect(advancement.scoring == .extraPoint)
        #expect(advancement.requiresKickoff)
        #expect(advancement.requiresTry == false, "a try does not owe another try")
        #expect(advancement.possessionChanged == false, "the scoring team kicks off")
    }

    @Test("A missed extra point scores nothing and still ends in a kickoff", .tags(.unit))
    func missedExtraPoint() {
        let advancement = rules.advance(
            from: tryFrom(rules.extraPointSnapYard),
            outcome: Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalMissed))

        #expect(advancement.points == 0)
        #expect(advancement.scoring == nil)
        #expect(advancement.requiresKickoff)
    }

    @Test("A converted two-point try is worth two points", .tags(.unit))
    func twoPointIsTwoPoints() {
        let advancement = rules.advance(
            from: tryFrom(rules.twoPointSnapYard),
            outcome: Outcome(kind: .twoPointConversion, yards: 2, endedIn: .touchdown))

        #expect(advancement.points == 2)
        #expect(advancement.scoring == .twoPointConversion)
        #expect(advancement.requiresKickoff)
        #expect(advancement.requiresTry == false)
    }

    /// Every way of failing pays nothing and ends the try. A conversion is a pass, so it
    /// can be intercepted, and that must not hand the defence a first down.
    @Test(
        "A failed two-point try scores nothing, however it failed", .tags(.unit),
        arguments: [
            PlayEnding.incomplete, .tackled, .intercepted, .fumbleLost,
        ])
    func failedTwoPoint(ending: PlayEnding) {
        let advancement = rules.advance(
            from: tryFrom(rules.twoPointSnapYard),
            outcome: Outcome(kind: .twoPointConversion, yards: 0, endedIn: ending))

        #expect(advancement.points == 0)
        #expect(advancement.scoring == nil)
        #expect(advancement.requiresKickoff)
        #expect(advancement.possessionChanged == false)
    }

    /// The touchdown itself is still worth six and still owes a try — the fix to the try
    /// must not have moved the thing that was right.
    @Test("A touchdown is six points and owes a try", .tags(.unit))
    func touchdownUnchanged() {
        let situation = Situation(
            quarter: 1, clockRemaining: 800, down: .second, distance: 4, ballOn: 4,
            possession: TeamID(1))
        let advancement = rules.advance(
            from: situation, outcome: Outcome(kind: .rush, yards: 4, endedIn: .touchdown))

        #expect(advancement.points == 6)
        #expect(advancement.scoring == .touchdown)
        #expect(advancement.requiresTry)
    }

    /// A kickoff into the end zone comes out further than a punt into it. Both used the
    /// punt's spot, which quietly cost the receiving team ten yards on every possession
    /// that followed a score.
    @Test("A kickoff touchback and a punt touchback are spotted differently", .tags(.unit))
    func touchbacksDiffer() {
        let situation = Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10,
            ballOn: rules.ballOnFromOwnYard(rules.kickoffFromOwnYard), possession: TeamID(1))

        let kickoff = rules.advance(
            from: situation, outcome: Outcome(kind: .kickoff, yards: 0, endedIn: .touchback))
        let punt = rules.advance(
            from: situation, outcome: Outcome(kind: .punt, yards: 0, endedIn: .touchback))

        #expect(kickoff.ballOn == rules.kickoffTouchbackSpot)
        #expect(punt.ballOn == rules.puntTouchbackSpot)
        #expect(kickoff.ballOn < punt.ballOn, "the kickoff comes out further")
        #expect(kickoff.possessionChanged && punt.possessionChanged)
    }

    /// A kick that is fielded and run back hands the ball over where the return stopped.
    /// This used to fall through to `advanceDown`, which does not change possession at
    /// all — so a returned kick would have given the ball back to the kicking team.
    @Test("A returned kick changes hands where the return ended", .tags(.unit))
    func returnedKickChangesHands() {
        let situation = Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10,
            ballOn: rules.ballOnFromOwnYard(rules.kickoffFromOwnYard), possession: TeamID(1))

        // Brought out to his own twenty-two, which is spot 22 in the kicking team's frame.
        let advancement = rules.advance(
            from: situation,
            outcome: Outcome(kind: .kickoff, yards: 0, endedIn: .tackled, finalSpot: 22))

        #expect(advancement.possessionChanged)
        #expect(advancement.ballOn == 78, "his own twenty-two is 78 from the other goal line")
        #expect(advancement.down == .first)
        #expect(advancement.distance == rules.yardsToGain)
    }

    /// A return taken the distance scores for the team that did not have the ball, and
    /// *they* are the ones who then owe a try.
    @Test("A kick returned all the way is a touchdown for the returning team", .tags(.unit))
    func kickReturnedForScore() {
        for kind in [PlayKind.kickoff, .punt] {
            let advancement = rules.advance(
                from: Situation(
                    quarter: 3, clockRemaining: 400, down: .fourth, distance: 8, ballOn: 70,
                    possession: TeamID(1)),
                outcome: Outcome(kind: kind, yards: 0, endedIn: .touchdown, finalSpot: 100))

            #expect(advancement.scoring == .defensiveTouchdown)
            #expect(advancement.points == 6)
            #expect(advancement.possessionChanged, "the returning team has the ball for the try")
            #expect(advancement.requiresTry)
        }
    }

    /// The one kick the kicking team means to keep. Recovering it must not flip
    /// possession, which is the entire point of trying it.
    @Test("An onside kick the kicking team recovers does not change hands", .tags(.unit))
    func onsideRecovered() {
        let advancement = rules.advance(
            from: Situation(
                quarter: 4, clockRemaining: 90, down: .first, distance: 10,
                ballOn: rules.ballOnFromOwnYard(rules.kickoffFromOwnYard), possession: TeamID(1)),
            outcome: Outcome(kind: .kickoff, yards: 0, endedIn: .fumbleRecovered, finalSpot: 52))

        #expect(advancement.possessionChanged == false)
        #expect(advancement.ballOn == 52)
        #expect(advancement.down == .first)
    }

    /// A fair catch and a downed punt are the same rule from two directions, and both
    /// have to flip the frame or the receiving team's field position reads backwards.
    @Test(
        "A punt fielded or downed hands over at the flipped spot", .tags(.unit),
        arguments: [
            PlayEnding.fairCatch, .downed, .outOfBounds, .tackled,
        ])
    func puntHandsOver(ending: PlayEnding) {
        let advancement = rules.advance(
            from: Situation(
                quarter: 2, clockRemaining: 300, down: .fourth, distance: 9, ballOn: 70,
                possession: TeamID(1)),
            outcome: Outcome(kind: .punt, yards: 0, endedIn: ending, finalSpot: 18))

        #expect(advancement.possessionChanged)
        #expect(advancement.ballOn == 82, "downed on their 18 is their own 18")
    }

    /// The arithmetic a scoreboard is actually made of. A drive chart that adds up is the
    /// cheapest possible check that the scoring rules are the sport's.
    @Test("A touchdown and the kick are worth seven, and two field goals are six", .tags(.unit))
    func scoreboardArithmetic() {
        let touchdown = rules.advance(
            from: Situation(
                quarter: 1, clockRemaining: 800, down: .first, distance: 3, ballOn: 3,
                possession: TeamID(1)),
            outcome: Outcome(kind: .pass, yards: 3, endedIn: .touchdown))
        let kick = rules.advance(
            from: tryFrom(rules.extraPointSnapYard),
            outcome: Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood))
        #expect(touchdown.points + kick.points == 7)

        let fieldGoal = rules.advance(
            from: Situation(
                quarter: 2, clockRemaining: 400, down: .fourth, distance: 8, ballOn: 20,
                possession: TeamID(1)),
            outcome: Outcome(kind: .fieldGoal, yards: 0, endedIn: .fieldGoalGood))
        #expect(fieldGoal.points * 2 == 6)
    }
}
