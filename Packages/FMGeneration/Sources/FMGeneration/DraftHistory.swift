import FMCore
import FMRandom

/// How the league you inherit got here.
///
/// **This is history, not a draft.** Nothing below picks anybody: it writes down where a
/// player who already exists plausibly went, years ago, in a draft that was never
/// simulated. The draft you actually run is a decision in `FMSimulation`, and the two
/// share nothing but `DraftInfo` — for the same reason `RosterGenerator` shares nothing
/// with the AI roster manager.
///
/// Before this existed no generated player carried a `DraftInfo` at all, so the initial
/// league had no past: nobody had been picked by anybody, and accrued seasons were
/// guessed from a birthday.
public enum DraftHistory {

    /// The board a history is written against: how deep the draft went and how many picks
    /// each round held.
    public struct Board: Sendable, Hashable {

        public let rounds: Int
        public let picksPerRound: Int

        /// Both are clamped to what `DraftInfo` can carry — a round and a pick are each a
        /// `UInt8` — so no board can be described that a pick could not then be recorded
        /// on.
        public init(rounds: Int, picksPerRound: Int) {
            self.rounds = min(255, max(1, rounds))
            self.picksPerRound = min(255, max(1, picksPerRound))
        }

        /// Seven rounds of thirty-two: the draft a standard league runs.
        public static let standard = Board(rounds: 7, picksPerRound: 32)

        public var picks: Int { rounds * picksPerRound }
    }

    // MARK: - The shape of a league's history

    /// How much of a league was drafted at all.
    ///
    /// The remaining quarter arrived undrafted, which is a way of getting to a league and
    /// not a missing record. A generation target for the world we ship rather than a
    /// measured fact about any real league — no source is claimed for it.
    public static let draftedShare = 0.75

    /// How far where a player went sits from what he turned out to be capable of, in
    /// ceiling points.
    ///
    /// The whole reason a round is worth showing. With no spread the draft order would be
    /// the ceiling order written twice, and the undrafted starter and the first-round
    /// backup — the two most interesting players on any roster — could not exist.
    static let boardSpread = 5.0

    /// The league's ceiling distribution, as the score at each seventh of the drafted
    /// share, highest first.
    ///
    /// Read: a player needed a score of 84.9 to be in the top seventh of the drafted
    /// three quarters of the league, which is what a first-round pick is here. Measured
    /// over standard thirty-two-team worlds at seeds 1, 5, 7 and 11 — 6,784 players — and
    /// guarded by the round-share tests rather than trusted.
    ///
    /// Absolute, rather than a player's place in his own team's order. That is what lets a
    /// contender hold more early picks than a rebuilding club instead of every roster in
    /// the league carrying the same four first-rounders.
    static let scoreQuantiles: [Double] = [84.9, 79.9, 76.2, 73.1, 70.3, 67.8, 64.9]

    /// The score a player needed to sit inside the top `fraction` of the league.
    ///
    /// Piecewise linear between the measured points, and linear off either end from the
    /// outermost pair, so a board with more or fewer rounds than seven divides the same
    /// distribution instead of needing its own table.
    static func score(atFractionFromTop fraction: Double) -> Double {
        let count = scoreQuantiles.count
        guard count >= 2 else { return scoreQuantiles.first ?? 0 }

        let step = draftedShare / Double(count)
        // Zero at the first measured point, one at the second, and so on.
        let position = fraction / step - 1.0
        var lower = position < 0 ? 0 : Int(position)
        if lower > count - 2 { lower = count - 2 }

        let fromLower = position - Double(lower)
        return scoreQuantiles[lower]
            + (scoreQuantiles[lower + 1] - scoreQuantiles[lower]) * fromLower
    }

    /// Which round a score went in, or `nil` for a player nobody drafted.
    static func round(forScore score: Double, board: Board) -> Int? {
        for round in 1...board.rounds {
            let fraction = draftedShare * Double(round) / Double(board.rounds)
            if score >= self.score(atFractionFromTop: fraction) { return round }
        }
        return nil
    }

    /// The youngest anybody arrives at.
    ///
    /// A true junior comes out at twenty-one and nobody comes out younger, which is what
    /// makes this the floor of the age draw in `RosterGenerator` as well: a league cannot
    /// hold a man younger than the youngest age anybody enters it at. The two are the same
    /// number on purpose, and a contract test says so.
    static let youngestEntryAge = 21

    /// The age a player arrived in the league at.
    ///
    /// Centred on the twenty-two `PlayerGenerator` treats as entry and three years wide:
    /// a true junior comes out at twenty-one, most players at twenty-two or twenty-three,
    /// and a fifth-year senior at twenty-four. A generation shape, not a sourced one, and
    /// it is a year young against the nearest real comparison: first-season players on week
    /// 1 rosters were about a seventh twenty-one, a quarter to a third twenty-two, about a
    /// third twenty-three and a seventh to a quarter twenty-four over 2023-2025 (nflverse
    /// weekly roster data), where this draw puts nearly half of them at twenty-two. Nothing
    /// here reads that comparison — it is written down so the next person does not have to
    /// go and measure it again.
    static func entryAge(using random: inout SplittableRandom) -> Int {
        switch random.next(upperBound: 100) {
        case ..<20: return youngestEntryAge
        case ..<65: return 22
        case ..<90: return 23
        default: return 24
        }
    }

    /// The label the per-player substream is split on. Paired with the player's
    /// identifier, so a history depends on the player rather than on how many players
    /// happened to be built before him.
    static let stream: UInt64 = 0x0d_7a_f7

    // MARK: - One player's arrival

    /// Where and when a player arrived.
    ///
    /// The round comes off his ceiling, blurred by `boardSpread`. The season comes off his
    /// age at entry — a twenty-eight-year-old who came out at twenty-two has been here six
    /// years. The pick within the round comes off the seed and nothing else: a generated
    /// league has no standings behind it that could have produced an order, and inventing
    /// one would be inventing seasons that never happened.
    ///
    /// Drawn from a substream keyed on the identifier rather than from the caller's
    /// stream, so giving a world a past moves nothing that was generated without one
    /// ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md)).
    public static func record(
        for id: PlayerID,
        ceiling: UInt8,
        age: Int,
        season: Int,
        board: Board,
        from random: SplittableRandom
    ) -> (draft: DraftInfo?, firstSeason: Int) {
        var stream = random.split(Self.stream, id.rawValue)

        // Nobody's history starts before he did: a player younger than the age drawn came
        // out as early as he could have.
        let entry = min(entryAge(using: &stream), age)
        let firstSeason = season - (age - entry)

        let score = Double(ceiling) + stream.nextGaussian() * boardSpread
        guard let round = round(forScore: score, board: board) else {
            return (nil, firstSeason)
        }

        let pick = 1 + Int(stream.next(upperBound: UInt64(board.picksPerRound)))
        return (
            DraftInfo(
                season: firstSeason,
                round: UInt8(round),
                pick: UInt8(pick),
                overallPick: UInt16((round - 1) * board.picksPerRound + pick)),
            firstSeason
        )
    }
}
