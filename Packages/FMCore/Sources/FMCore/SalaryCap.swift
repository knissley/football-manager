/// Team-level cap accounting and the league rules that sit on top of contracts.
public enum SalaryCap {

    /// A team's cap position for one season.
    ///
    /// `space` going negative is a legitimate mid-offseason state — teams are
    /// only required to be compliant at the start of the regular season — so it
    /// is represented rather than prevented.
    public struct Position: Sendable, Hashable, Codable {

        public let season: Int
        public let leagueCap: Money
        public let carryover: Money
        public let activeCapHits: Money
        public let deadMoney: Money
        public let practiceSquadCharges: Money

        public init(
            season: Int,
            leagueCap: Money,
            carryover: Money = .zero,
            activeCapHits: Money,
            deadMoney: Money = .zero,
            practiceSquadCharges: Money = .zero
        ) {
            self.season = season
            self.leagueCap = leagueCap
            self.carryover = carryover
            self.activeCapHits = activeCapHits
            self.deadMoney = deadMoney
            self.practiceSquadCharges = practiceSquadCharges
        }

        public var adjustedCap: Money {
            leagueCap + carryover
        }

        public var committed: Money {
            activeCapHits + deadMoney + practiceSquadCharges
        }

        public var space: Money {
            adjustedCap - committed
        }

        public var isCompliant: Bool {
            space >= .zero
        }
    }

    /// A team's cap position from its contracts.
    public static func position(
        season: Int,
        leagueCap: Money,
        carryover: Money = .zero,
        contracts: [Contract],
        deadMoney: [Money] = [],
        practiceSquadCharges: Money = .zero
    ) -> Position {
        Position(
            season: season,
            leagueCap: leagueCap,
            carryover: carryover,
            activeCapHits: contracts.map { $0.capHit(in: season) }.total(),
            deadMoney: deadMoney.total(),
            practiceSquadCharges: practiceSquadCharges
        )
    }

    /// The franchise tag figure: the greater of the average of the top five cap
    /// hits at the position, and 120% of the player's own prior cap hit.
    ///
    /// The two rules disagree for a player who was already very well paid
    /// relative to his position, which is exactly when a team is deciding
    /// whether to tag him — so both are computed and the larger wins.
    ///
    /// `topSalariesAtPosition` may hold fewer than five entries in a small test
    /// league; the average is taken over what exists.
    public static func franchiseTagValue(
        topSalariesAtPosition: [Money],
        priorCapHit: Money
    ) -> Money {
        let considered = topSalariesAtPosition.sorted(by: >).prefix(5)
        let average: Money
        if considered.isEmpty {
            average = .zero
        } else {
            average = Money(
                dollars: considered.map(\.dollars).reduce(0, +) / Int64(considered.count))
        }
        return max(average, priorCapHit.scaled(by: 1.20))
    }
}

extension Contract {

    /// Trading a player accelerates his remaining proration onto the team that
    /// is *sending* him, exactly as a release would — which is why large
    /// signing bonuses make contracts hard to move.
    ///
    /// Because it accelerates exactly as a release does, it splits exactly as a
    /// release does: with `postJune1`, the current season keeps only this
    /// season's proration share and every later share lands the following
    /// season. The total is the same either way.
    ///
    /// Guaranteed salary, by contrast, travels with the player to the acquiring
    /// team, so it is excluded here.
    public func tradeAcceleration(before season: Int, postJune1: Bool = false) -> DeadMoney {
        guard postJune1 else {
            return DeadMoney(season: season, currentSeason: remainingProration(from: season))
        }

        return DeadMoney(
            season: season,
            currentSeason: prorationCharge(in: season),
            followingSeason: remainingProration(from: season + 1)
        )
    }
}
