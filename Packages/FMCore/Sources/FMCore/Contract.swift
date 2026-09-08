/// A signing bonus, or a restructure conversion, spread across seasons.
///
/// Modelled as its own stream rather than a single field on the contract,
/// because a restructure creates a *new* proration schedule alongside the
/// original one. A contract that has been restructured twice carries three
/// overlapping streams, and flattening them into one number is how cap
/// arithmetic silently drifts.
public struct ProratedBonus: Sendable, Hashable, Codable {

    /// Proration is capped at five years no matter how long the contract runs.
    /// This is the single most common source of wrong cap maths.
    public static let maximumYears = 5

    public let amount: Money
    public let firstSeason: Int
    public let years: Int

    public init(amount: Money, firstSeason: Int, overContractYears contractYears: Int) {
        precondition(amount >= .zero, "a bonus cannot be negative")
        precondition(contractYears >= 1, "a bonus must prorate over at least one year")
        self.amount = amount
        self.firstSeason = firstSeason
        self.years = min(contractYears, Self.maximumYears)
    }

    public var seasons: Range<Int> {
        firstSeason..<(firstSeason + years)
    }

    /// This bonus's charge against a given season.
    ///
    /// Integer division leaves a remainder, which is distributed one dollar at a
    /// time across the earliest seasons so that the shares sum to the bonus
    /// *exactly*. A schedule that loses a few dollars to rounding is a schedule
    /// that will not reconcile on a contract screen.
    public func share(in season: Int) -> Money {
        guard seasons.contains(season) else { return .zero }
        let perYear = amount.dollars / Int64(years)
        let remainder = amount.dollars % Int64(years)
        let offset = Int64(season - firstSeason)
        return Money(dollars: perYear + (offset < remainder ? 1 : 0))
    }

    /// The unamortised remainder: everything charged in `season` and later.
    public func remaining(from season: Int) -> Money {
        seasons.filter { $0 >= season }.map(share(in:)).total()
    }
}

/// One year of a contract.
public struct ContractYear: Sendable, Hashable, Codable {

    public var baseSalary: Money
    public var rosterBonus: Money

    /// How much of this year's base and roster bonus is owed even if the player
    /// is released. Drives dead money.
    public var guaranteedSalary: Money

    /// Incentives judged likely to be earned, which count against the cap now.
    public var likelyToBeEarnedIncentives: Money

    /// Incentives judged unlikely, which do not count now and reconcile the
    /// following season.
    public var notLikelyToBeEarnedIncentives: Money

    public init(
        baseSalary: Money,
        rosterBonus: Money = .zero,
        guaranteedSalary: Money = .zero,
        likelyToBeEarnedIncentives: Money = .zero,
        notLikelyToBeEarnedIncentives: Money = .zero
    ) {
        self.baseSalary = baseSalary
        self.rosterBonus = rosterBonus
        self.guaranteedSalary = guaranteedSalary
        self.likelyToBeEarnedIncentives = likelyToBeEarnedIncentives
        self.notLikelyToBeEarnedIncentives = notLikelyToBeEarnedIncentives
    }
}

/// A player contract, and the cap arithmetic that follows from it.
///
/// The rules here are unambiguous, entirely rule-based, and directly visible to
/// the player on a contract screen — which is why this is the most heavily
/// tested code in the project.
public struct Contract: Sendable, Hashable, Codable, Identifiable {

    public let id: ContractID
    public let player: PlayerID
    public let team: TeamID

    /// The first season this contract covers. `years[0]` is this season.
    public let firstSeason: Int

    public var years: [ContractYear]

    /// The signing bonus, plus one entry for each restructure conversion.
    public var proratedBonuses: [ProratedBonus]

    public init(
        id: ContractID,
        player: PlayerID,
        team: TeamID,
        firstSeason: Int,
        years: [ContractYear],
        proratedBonuses: [ProratedBonus] = []
    ) {
        precondition(!years.isEmpty, "a contract must cover at least one season")
        self.id = id
        self.player = player
        self.team = team
        self.firstSeason = firstSeason
        self.years = years
        self.proratedBonuses = proratedBonuses
    }

    /// Build a contract from a signing bonus, which prorates over its term
    /// (capped at five years).
    public init(
        id: ContractID,
        player: PlayerID,
        team: TeamID,
        firstSeason: Int,
        signingBonus: Money,
        years: [ContractYear]
    ) {
        let bonus = ProratedBonus(
            amount: signingBonus,
            firstSeason: firstSeason,
            overContractYears: years.count
        )
        self.init(
            id: id,
            player: player,
            team: team,
            firstSeason: firstSeason,
            years: years,
            proratedBonuses: signingBonus > .zero ? [bonus] : []
        )
    }

    public var seasons: Range<Int> {
        firstSeason..<(firstSeason + years.count)
    }

    public var lastSeason: Int {
        firstSeason + years.count - 1
    }

    public func year(_ season: Int) -> ContractYear? {
        guard seasons.contains(season) else { return nil }
        return years[season - firstSeason]
    }

    /// The total proration charged in a season, across every bonus stream.
    public func prorationCharge(in season: Int) -> Money {
        proratedBonuses.map { $0.share(in: season) }.total()
    }

    /// What this contract costs against the cap in a season.
    ///
    /// `base + rosterBonus + proration + likely-to-be-earned incentives`.
    /// Unlikely incentives are excluded by definition.
    public func capHit(in season: Int) -> Money {
        guard let year = year(season) else { return .zero }
        return year.baseSalary
            + year.rosterBonus
            + prorationCharge(in: season)
            + year.likelyToBeEarnedIncentives
    }

    /// Proration not yet charged as of `season`, which is what accelerates on a
    /// release or trade.
    public func remainingProration(from season: Int) -> Money {
        proratedBonuses.map { $0.remaining(from: season) }.total()
    }

    /// Guaranteed money still owed from `season` onwards.
    public func guaranteedSalaryOwed(from season: Int) -> Money {
        seasons
            .filter { $0 >= season }
            .compactMap { year($0)?.guaranteedSalary }
            .total()
    }
}

/// What releasing or trading a player costs, split by season.
///
/// A split is the point: a post-June-1 designation moves most of the charge into
/// the following year, and collapsing that to a single total loses the entire
/// strategic tradeoff.
public struct DeadMoney: Sendable, Hashable, Codable {

    public let season: Int
    public let currentSeason: Money
    public let followingSeason: Money

    public var total: Money { currentSeason + followingSeason }

    public init(season: Int, currentSeason: Money, followingSeason: Money = .zero) {
        self.season = season
        self.currentSeason = currentSeason
        self.followingSeason = followingSeason
    }
}

extension Contract {

    /// The cost of releasing the player before `season`.
    ///
    /// All unamortised proration accelerates into the current season, along with
    /// any guaranteed salary still owed.
    ///
    /// With `postJune1`, the current season keeps only *this* year's proration
    /// share and every later share lands the following season. The guaranteed
    /// salary owed for the current season stays in the current season either
    /// way — it is money already promised for this year.
    public func deadMoney(releasedBefore season: Int, postJune1: Bool = false) -> DeadMoney {
        let guaranteedOwed = guaranteedSalaryOwed(from: season)

        guard postJune1 else {
            return DeadMoney(
                season: season,
                currentSeason: remainingProration(from: season) + guaranteedOwed
            )
        }

        return DeadMoney(
            season: season,
            currentSeason: prorationCharge(in: season) + guaranteedOwed,
            followingSeason: remainingProration(from: season + 1)
        )
    }

    /// What releasing the player actually saves against this season's cap.
    ///
    /// Negative when dead money exceeds the cap hit, which is the situation
    /// people mean when they say a contract is untradeable.
    public func capSavings(releasedBefore season: Int, postJune1: Bool = false) -> Money {
        capHit(in: season) - deadMoney(releasedBefore: season, postJune1: postJune1).currentSeason
    }

    /// Converting base salary into a signing bonus: cap relief now, more dead
    /// money later.
    ///
    /// The converted amount leaves this season's base salary and prorates over
    /// the remaining seasons (capped at five). It becomes fully guaranteed,
    /// because it is paid immediately.
    ///
    /// Returns `nil` if the season is not under contract or the amount exceeds
    /// the base salary available to convert.
    public func restructured(in season: Int, converting amount: Money) -> Contract? {
        guard amount > .zero, let existing = year(season) else { return nil }
        guard amount <= existing.baseSalary else { return nil }

        var updated = self
        let index = season - firstSeason
        updated.years[index].baseSalary -= amount
        updated.years[index].guaranteedSalary += amount

        let remainingYears = lastSeason - season + 1
        updated.proratedBonuses.append(
            ProratedBonus(
                amount: amount,
                firstSeason: season,
                overContractYears: remainingYears
            )
        )
        return updated
    }
}
