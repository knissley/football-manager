import FMCore
import Testing

@testable import FMSimulation

/// The play after a touchdown, as it is actually snapped.
///
/// `Rules.twoPointSnapYard` has been two since the rules were written and was read by
/// nothing: the decision to go for two was made *after* the situation was built, so every
/// conversion was attempted from the fifteen and needed fifteen yards. Across eight
/// hundred team-games not one was ever converted, and nothing failed — a rule that is
/// impossible to satisfy looks exactly like a rule that is merely hard.
@Suite("Tries")
struct TryTests {

    private static func game(seed: UInt64) -> GameResult {
        TestWorld.game(seed: seed, game: GameID(seed))
    }

    private static func plays(_ seeds: ClosedRange<UInt64>) -> [PlayRecord] {
        seeds.flatMap { game(seed: $0).plays }
    }

    @Test("Each kind of try is snapped from its own yard line")
    func triesAreSnappedFromTheRightSpot() {
        let rules = Rules.standard
        for play in Self.plays(1...30) {
            switch play.outcome.kind {
            case .extraPoint:
                #expect(play.situation.ballOn == rules.extraPointSnapYard)
            case .twoPointConversion:
                #expect(
                    play.situation.ballOn == rules.twoPointSnapYard,
                    "a conversion snapped from the \(play.situation.ballOn) needs that many yards")
            default:
                break
            }
        }
    }

    /// The point of a rule that can be satisfied: sometimes it is, and sometimes it is
    /// not. A conversion rate of zero and one of a hundred are equally wrong.
    @Test("Conversions are sometimes made and sometimes missed")
    func conversionsGoBothWays() {
        let tries = Self.plays(1...80).filter { $0.outcome.kind == .twoPointConversion }
        #expect(tries.isEmpty == false, "nobody ever went for two")
        #expect(tries.contains { $0.outcome.endedIn == .touchdown }, "no conversion ever succeeded")
        #expect(tries.contains { $0.outcome.endedIn != .touchdown }, "no conversion ever failed")
    }

    /// The scoreboard has to be reconstructible from the stream, because everything above
    /// the engine is a query over it ([ADR-0007]). If the plays say one thing and the
    /// final score says another, one of them is lying.
    @Test("The score on the board is the sum of the scoring plays")
    func scoreboardMatchesTheStream() {
        let rules = Rules.standard
        for seed in UInt64(1)...20 {
            let result = Self.game(seed: seed)
            var home: Int16 = 0
            var away: Int16 = 0

            for play in result.plays {
                let advancement =
                    play.outcome.penalties.isEmpty
                    ? rules.advance(from: play.situation, outcome: play.outcome)
                    : rules.enforce(
                        play.outcome.penalties[0], on: play.situation, outcome: play.outcome,
                        offendingTeamHadBall: play.outcome.penalties[0].offendingTeam
                            == play.situation.possession
                    ).advancement
                guard let scoring = advancement.scoring, advancement.points != 0 else { continue }

                // A safety and a return touchdown pay the side that did not have the ball.
                let defensive = scoring == .safety || scoring == .defensiveTouchdown
                let scoredByHome = (play.situation.possession == TeamID(1)) != defensive
                if scoredByHome { home += advancement.points } else { away += advancement.points }
            }

            #expect(
                home == result.homeScore && away == result.awayScore,
                "stream says \(home)-\(away), scoreboard says \(result.homeScore)-\(result.awayScore)"
            )
        }
    }
}
