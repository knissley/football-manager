import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

/// The coin toss, and what the two captains did with it, read back out of the stream.
///
/// The record used to carry the kickoff and nothing else, so from a finished game a
/// reader could say who kicked off each half and not one thing about why. Which captain
/// won the toss, whether he took the ball, the goal, or deferred, and what the other
/// captain was left with are four facts the sport settles before a ball is snapped, and a
/// season narrative that cannot say them is reading something the stream does not have.
///
/// So what is asserted here is the round trip and not the values: play a game, walk its
/// plays, and rebuild the toss and both elections from the decision points alone. Nothing
/// in here reads `GameSimulator.State`.
@Suite("The coin toss in the record")
struct CoinTossTests {

    // MARK: - Reading a game's tosses back out of its stream

    /// One half, as its opening free kick records it.
    private struct Opener {
        let index: Int
        let quarter: UInt8
        /// The side kicking this free kick off, which is the side in possession at it.
        let kicksOff: TeamID
        let receives: TeamID
        /// The captain who won the toss, where this kick is the one a toss decided;
        /// `nil` on a half that follows a first choice instead (4-2-2, 16-1-4-e).
        let tossWinner: TeamID?
        let winnerElected: TossElection?
        let loserElected: TossElection?
    }

    /// Every half's opening play, and the toss points on it — from the stream and the
    /// rules' own answer to which periods open a half, and from nothing else.
    private static func openers(of plays: [PlayRecord], rules: Rules) -> [Opener] {
        var found: [Opener] = []
        for (index, play) in plays.enumerated() {
            let quarter = play.situation.quarter
            let opensAHalf =
                index == 0
                || (quarter != plays[index - 1].situation.quarter
                    && rules.periodResumesWithKickoff(quarter: quarter))
            guard opensAHalf else { continue }
            let kicksOff = play.situation.possession
            let receives = opponent(of: kicksOff, in: plays)
            let wonByTheKicker = play.decisions.compactMap(\.coinTossWonByTheSideKickingOff).first
            found.append(
                Opener(
                    index: index,
                    quarter: quarter,
                    kicksOff: kicksOff,
                    receives: receives,
                    tossWinner: wonByTheKicker.map { $0 ? kicksOff : receives },
                    winnerElected: play.decisions.compactMap(\.tossElectionByTheWinner).first,
                    loserElected: play.decisions.compactMap(\.tossElectionByTheLoser).first))
        }
        return found
    }

    /// The other club in the game, from the stream: two sides play it, and every play
    /// names one of them.
    private static func opponent(of team: TeamID, in plays: [PlayRecord]) -> TeamID {
        plays.map(\.situation.possession).first { $0 != team } ?? team
    }

    /// Which captain took privilege (a) at this half and how he took it — exactly one of
    /// the two does, the other being given the goal or having deferred (4-2-2).
    private static func tookTheBall(
        _ opener: Opener, winner: TeamID, loser: TeamID
    ) -> (side: TeamID, receives: Bool)? {
        if let election = opener.winnerElected, election == .receive || election == .kickOff {
            return (winner, election == .receive)
        }
        if let election = opener.loserElected, election == .receive || election == .kickOff {
            return (loser, election == .receive)
        }
        return nil
    }

    // MARK: - The contract

    /// The round trip, over the golden seeds and over a postseason game that reaches a
    /// fifth overtime period, so a third and a fifth are both in it.
    ///
    /// Four claims, each a sentence of 4-2-2 or of the articles that send a reader back
    /// to it:
    ///
    /// 1. **A half that follows a toss carries the toss**, and a half that follows a
    ///    first choice does not: the coin is tossed before the game (4-2-2), at the end
    ///    of regulation (16-1-2) and at the end of a fourth overtime period (16-1-4-i),
    ///    while the second half and a third overtime period open on the first choice of
    ///    the captain who lost the toss before them (4-2-2, 16-1-4-e).
    /// 2. **Both captains are on the record at every one of those halves**, one election
    ///    each: 4-2-2 has the winner take a privilege and the loser given the other, and
    ///    for the second half it has the captains of both teams inform the Referee of
    ///    their respective choices.
    /// 3. **Exactly one captain takes privilege (a)**, and what he elected is what
    ///    happened — electing to receive, the other side kicks off to him (4-2-2-a).
    /// 4. **The loser never defers.** The article gives the deferral to the winner alone.
    @Test(
        "contract: from the stream alone, the toss winner, both captains' elections and who kicked off are readable at every half (2025 rulebook, 4-2-2, 16-1-2, 16-1-4-e, 16-1-4-i)",
        .tags(.contract),
        arguments: [UInt64(1), 5, 12])
    func theTossIsReadableFromTheStream(seed: UInt64) {
        check(plays: TestWorld.game(seed: seed).plays, what: "the game at seed \(seed)")
    }

    @Test(
        "contract: the same round trip on a postseason game that reaches a fifth overtime period, so a third (16-1-4-e) and a fifth (16-1-4-i) are both read",
        .tags(.contract))
    func theTossIsReadableThroughFivePostseasonOvertimePeriods() {
        let trace = RulesScenario.fifthPostseasonOvertimePeriod.run()
        let quarters = Set(trace.plays.map(\.situation.quarter))
        #expect(
            quarters.contains(7) && quarters.contains(9),
            "the scenario was meant to reach a third and a fifth overtime period")
        check(plays: trace.plays, what: "the fifth-overtime-period scenario")
    }

    private func check(plays: [PlayRecord], what: String, rules: Rules = .standard) {
        let openers = Self.openers(of: plays, rules: rules)
        #expect(openers.count >= 2, "\(what): only \(openers.count) half opened")
        // The captain who won the last toss seen, which is the one every half until the
        // next toss answers to (4-2-2, 16-1-4-e).
        var carried: TeamID?
        for opener in openers {
            let at = "\(what), the half opening at play \(opener.index) of period \(opener.quarter)"
            let followsAToss = rules.periodFollowsACoinToss(quarter: opener.quarter)
            // 1. The toss is on the kick it decided, and on no other.
            #expect(
                (opener.tossWinner != nil) == followsAToss,
                "\(at): the coin toss point is \(followsAToss ? "missing" : "on a half that follows no toss")"
            )
            if let winner = opener.tossWinner { carried = winner }
            guard let winner = carried else {
                Issue.record("\(at): no toss has been recorded in this game at all")
                continue
            }
            let loser = winner == opener.kicksOff ? opener.receives : opener.kicksOff

            // 2. One election each, both captains, at every half.
            #expect(opener.winnerElected != nil, "\(at): the toss winner made no election")
            #expect(opener.loserElected != nil, "\(at): the toss loser made no election")

            // 3. Exactly one captain took privilege (a), and the kick followed it.
            guard let taken = Self.tookTheBall(opener, winner: winner, loser: loser) else {
                Issue.record("\(at): neither captain took the opportunity to receive or kick off")
                continue
            }
            let expectedKicker =
                taken.receives ? (taken.side == winner ? loser : winner) : taken.side
            #expect(
                opener.kicksOff == expectedKicker,
                "\(at): the captain who took (a) elected to \(taken.receives ? "receive" : "kick off") and the kick disagrees"
            )

            // 4. The deferral is the winner's alone (4-2-2).
            #expect(
                opener.loserElected != .deferred,
                "\(at): the captain who lost the toss deferred")
        }
    }

    // MARK: - The draw

    /// A toss is a draw, and a draw that comes out the same every time is not one. Over
    /// the corpus both clubs win the pregame toss, which is what says the coin is being
    /// tossed rather than handed to the same captain every week.
    @Test(
        "contract: the pregame toss is drawn rather than awarded — both clubs win it across the corpus",
        .tags(.contract))
    func theTossIsDrawn() {
        var winners: Set<TeamID> = []
        for result in TestWorld.corpus {
            guard let opening = result.plays.first,
                let wonByTheKicker = opening.decisions.compactMap(\.coinTossWonByTheSideKickingOff)
                    .first
            else {
                Issue.record("game \(result.game) opened with no coin toss on the record")
                continue
            }
            let kicker = opening.situation.possession
            winners.insert(wonByTheKicker ? kicker : Self.opponent(of: kicker, in: result.plays))
        }
        #expect(winners.count == 2, "one club won every toss in the corpus")
    }

    // MARK: - The football of 4-2-2

    /// A game of one-yard plods, long enough to reach the second half, with the toss
    /// election the scenario names.
    private func halves(electing: @escaping @Sendable (Bool) -> TossElection) -> Trace {
        ScriptedGame(
            caller: ScriptedCaller(tossElection: { _, mayDefer in electing(mayDefer) }),
            play: { $0.neutral }
        ).run()
    }

    /// The two halves of a scripted game, as their opening kicks record them.
    private func bothHalves(of trace: Trace) -> (first: Opener, second: Opener)? {
        let openers = Self.openers(of: trace.plays, rules: .standard)
        guard openers.count >= 2, openers[1].quarter == 3 else {
            Issue.record("the scenario did not reach the second half")
            return nil
        }
        return (openers[0], openers[1])
    }

    /// The deferral, and the whole of what it is for: the captain who wins the toss and
    /// defers makes no choice at the first half, so the other captain has the first
    /// choice there — and at the second half the choice is the deferrer's.
    @Test(
        "football · Rule 4-2-2 · a captain who defers his choice to the second half leaves the first half's first choice to the other captain, and has the second half's himself: the other takes the ball to open, and the deferrer takes it after halftime",
        .tags(.football))
    func deferringMovesTheFirstChoiceToTheOtherCaptain() {
        guard let (first, second) = bothHalves(of: halves(electing: { $0 ? .deferred : .receive }))
        else { return }
        guard let winner = first.tossWinner else {
            Issue.record("the opening kick carries no coin toss")
            return
        }
        let loser = winner == first.kicksOff ? first.receives : first.kicksOff
        #expect(first.winnerElected == .deferred, "the winner was meant to defer")
        #expect(
            first.loserElected == .receive,
            "the first choice at the first half is the other captain's, and he takes the ball")
        #expect(
            first.receives == loser,
            "so the captain who did not win the toss receives the opening kickoff")
        #expect(
            second.winnerElected == .receive,
            "the second half's first choice is the deferrer's (4-2-2)")
        #expect(
            second.loserElected == .goal,
            "and the other captain is given the privilege left")
        #expect(second.receives == winner, "so the deferrer receives the second-half kickoff")
    }

    /// The other answer to the same question. A winner who takes the ball has spent his
    /// choice: the loser is given the goal, and the second half's first choice is the
    /// loser's, which he spends on the ball in his turn.
    @Test(
        "football · Rule 4-2-2, 4-2-2-a · a captain who takes the opportunity to receive rather than defer receives the opening kickoff, the other captain is given the choice of goal, and the second half's first choice is the loser's",
        .tags(.football))
    func takingTheBallLeavesTheGoalAndTheSecondHalfToTheLoser() {
        guard let (first, second) = bothHalves(of: halves(electing: { _ in .receive })) else {
            return
        }
        guard let winner = first.tossWinner else {
            Issue.record("the opening kick carries no coin toss")
            return
        }
        let loser = winner == first.kicksOff ? first.receives : first.kicksOff
        #expect(first.winnerElected == .receive, "the winner was meant to take the ball")
        #expect(first.loserElected == .goal, "the loser is given the other privilege (4-2-2)")
        #expect(first.receives == winner, "the winner receives the opening kickoff")
        #expect(
            second.loserElected == .receive,
            "the second half's first choice is the captain who lost the pregame toss (4-2-2)")
        #expect(second.winnerElected == .goal, "and the winner is given what is left")
        #expect(second.receives == loser, "so the loser receives the second-half kickoff")
    }

    /// Privilege (b) is a real answer to the toss, and taking it hands (a) to the other
    /// captain rather than settling the kick.
    @Test(
        "football · Rule 4-2-2, 4-2-2-b · a captain who takes the choice of goal leaves the opportunity to receive or kick off to the other captain, who takes the ball",
        .tags(.football))
    func takingTheGoalLeavesTheBallToTheOtherCaptain() {
        guard let (first, _) = bothHalves(of: halves(electing: { _ in .goal })) else { return }
        guard let winner = first.tossWinner else {
            Issue.record("the opening kick carries no coin toss")
            return
        }
        let loser = winner == first.kicksOff ? first.receives : first.kicksOff
        #expect(first.winnerElected == .goal, "the winner was meant to take the goal")
        #expect(first.loserElected == .receive, "which leaves (a) to the other captain")
        #expect(first.receives == loser, "and he takes the ball, so the toss winner kicks off")
    }

    /// The replay contract covers the toss, because the toss comes out of `FMRandom` at
    /// the game's own seed: the same setup replays to the same coin and the same
    /// elections.
    @Test(
        "contract: the same seed produces the same toss and the same elections", .tags(.contract))
    func theTossReplays() {
        for seed in UInt64(1)...4 {
            let first = TestWorld.game(seed: seed).plays.first?.decisions ?? []
            let again = TestWorld.game(seed: seed).plays.first?.decisions ?? []
            #expect(!first.isEmpty, "the opening kickoff of seed \(seed) recorded nothing")
            #expect(first == again, "the opening kickoff of seed \(seed) did not replay")
        }
    }
}
