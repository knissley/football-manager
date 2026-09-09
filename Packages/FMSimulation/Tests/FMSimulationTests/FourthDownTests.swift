import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The most-discussed decision in the modern game.
///
/// The baseline used to take any kick inside its maximum before asking whether to go,
/// which meant a fifty-five yarder on fourth and one from the opponent's thirty-eight,
/// and going for it at all required fourth and three or less in a six-yard strip of the
/// field. It went for it on 13% of its fourth-and-ones, in a sport where the figure is
/// nearer two-thirds.
@Suite("Fourth down")
struct FourthDownTests {

    private let caller = BaselineCaller()

    /// `ballOn` is yards from the opponent's goal, so a high number is being backed up.
    private func decision(
        distance: UInt8, ballOn: UInt8, quarter: UInt8 = 2, clock: UInt16 = 600,
        differential: Int16 = 0
    ) -> PlayFamily? {
        let situation = Situation(
            quarter: quarter, clockRemaining: clock, down: .fourth, distance: distance,
            ballOn: ballOn, possession: TeamID(1), scoreDifferential: differential)
        var random = SplittableRandom(seed: 4)
        let call = caller.offensiveCall(
            for: situation, classified: SituationClass(situation),
            context: PlayContext(
                offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
                players: [:],
                offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
                rules: .standard),
            random: &random)
        return CrudePlaybook.family(of: call.design)
    }

    private func goesForIt(_ family: PlayFamily?) -> Bool {
        guard let family else { return false }
        return family != .punt && family != .fieldGoal
    }

    @Test("Fourth and one is a play, not a formality")
    func fourthAndOne() {
        #expect(goesForIt(decision(distance: 1, ballOn: 50)), "fourth and one at midfield")
        #expect(goesForIt(decision(distance: 1, ballOn: 45)), "fourth and one in their half")
        #expect(
            !goesForIt(decision(distance: 1, ballOn: 85)),
            "fourth and one from your own fifteen is a punt")
    }

    /// Chasing the game moves the line back; protecting a lead moves it forward.
    @Test("Field position and the scoreboard both move the decision")
    func contextMoves() {
        #expect(
            !goesForIt(decision(distance: 1, ballOn: 62)),
            "fourth and one from your own thirty-eight, level, is a punt")
        #expect(
            goesForIt(decision(distance: 1, ballOn: 62, differential: -7)),
            "the same down, seven behind, is not")
    }

    /// No-man's land: too far for a kick worth taking, too close for a punt to buy much.
    @Test("Short yardage in no-man's land is a fourth-down attempt")
    func noMansLand() {
        #expect(goesForIt(decision(distance: 3, ballOn: 45)), "fourth and three from their 45")
        #expect(
            decision(distance: 3, ballOn: 25) == .fieldGoal,
            "fourth and three from their 25 is a kick")
        #expect(decision(distance: 12, ballOn: 30) == .fieldGoal)
        #expect(decision(distance: 12, ballOn: 60) == .punt)
    }

    /// A long kick is worth attempting when the alternative is nothing, and a bad trade
    /// against forty yards of field position when there is a game left to play.
    @Test("A fifty-five yarder is an endgame kick, not a first-half one")
    func longKicksAreSituational() {
        // Their 38 is a 55-yard attempt.
        #expect(
            decision(distance: 12, ballOn: 38, quarter: 1, clock: 800) == .punt,
            "a fifty-five yarder in the first quarter is a punt")
        #expect(
            decision(distance: 12, ballOn: 38, quarter: 4, clock: 100, differential: -2)
                == .fieldGoal,
            "the same kick to win it is worth taking")
    }

    /// Behind late, a punt is a surrender — and a field goal is only worth taking if it
    /// ties the game or wins it.
    @Test("Down late, you kick only when the kick is enough")
    func desperation() {
        #expect(
            decision(distance: 8, ballOn: 25, quarter: 4, clock: 40, differential: -3)
                == .fieldGoal,
            "down three, in range, with no time: take the tie")
        #expect(
            goesForIt(decision(distance: 8, ballOn: 25, quarter: 4, clock: 40, differential: -7)),
            "down seven, a field goal does not help")
    }

    /// Two minutes before halftime is not two minutes before the end.
    ///
    /// `SituationClass.isDesperation` is true inside two minutes of *either* half, which
    /// is right as a description — you are behind and time is short. Acting on it the same
    /// way in both halves is not: before the break there is a whole half left, and
    /// punting from your own twenty is still the right call. Reading the description as an
    /// instruction had teams going for it on fourth and long from their own end before
    /// halftime, which was half of every deep fourth-down attempt in the league.
    @Test("Being behind before halftime does not mean going for it from your own end")
    func firstHalfIsNotDesperation() {
        // Own 20, fourth and eight, down four, ninety seconds before the break.
        #expect(
            decision(distance: 8, ballOn: 80, quarter: 2, clock: 90, differential: -4) == .punt)
        // The same down and distance with ninety seconds left in the game is a different
        // question, and there the punt really is a surrender.
        #expect(
            goesForIt(decision(distance: 8, ballOn: 80, quarter: 4, clock: 90, differential: -4)),
            "down four with ninety seconds left in the game")

        // A first-half two-minute drill still behaves normally in good field position.
        #expect(
            decision(distance: 6, ballOn: 30, quarter: 2, clock: 90, differential: -4)
                == .fieldGoal,
            "in range before the half, take the points")
    }

    /// The conversion chart, on both sides of the scoreboard. The differential is read
    /// *before* the try, so trailing by two means the conversion ties it.
    @Test("Two-point decisions follow the chart")
    func twoPointChart() {
        func goesForTwo(_ differential: Int16, quarter: UInt8) -> Bool {
            let situation = Situation(
                quarter: quarter, clockRemaining: 500, down: .first, distance: 1, ballOn: 2,
                possession: TeamID(1), scoreDifferential: differential)
            return caller.goesForTwo(situation: situation, classified: SituationClass(situation))
        }

        #expect(goesForTwo(-2, quarter: 3), "down two: the conversion ties it")
        #expect(goesForTwo(-5, quarter: 3), "down five: it makes it a field goal game")
        #expect(goesForTwo(-10, quarter: 3))
        #expect(goesForTwo(4, quarter: 4), "up four: the second point makes it a touchdown game")

        #expect(!goesForTwo(-2, quarter: 1), "not in the first quarter")
        #expect(!goesForTwo(-7, quarter: 3), "down seven: kick it and you are level")
        #expect(!goesForTwo(0, quarter: 3))
    }
}
