import Testing

@testable import FMCore

/// Cap arithmetic is rule-based, unambiguous, and directly visible to the player
/// on a contract screen. It is also the easiest thing in the project to get
/// subtly wrong, so it is tested exhaustively rather than representatively.
private let seasonZero = 2030

private func makeContract(
    firstSeason: Int = seasonZero,
    signingBonus: Money = .zero,
    baseSalaries: [Money],
    guarantees: [Money] = [],
    rosterBonuses: [Money] = [],
    likelyIncentives: [Money] = []
) -> Contract {
    let years = baseSalaries.indices.map { index in
        ContractYear(
            baseSalary: baseSalaries[index],
            rosterBonus: index < rosterBonuses.count ? rosterBonuses[index] : .zero,
            guaranteedSalary: index < guarantees.count ? guarantees[index] : .zero,
            likelyToBeEarnedIncentives: index < likelyIncentives.count
                ? likelyIncentives[index] : .zero
        )
    }
    return Contract(
        id: ContractID(1),
        player: PlayerID(1),
        team: TeamID(1),
        firstSeason: firstSeason,
        signingBonus: signingBonus,
        years: years
    )
}

@Suite("Proration")
struct ProrationTests {

    @Test("A bonus spreads evenly across a short contract")
    func evenSpread() {
        let bonus = ProratedBonus(
            amount: .millions(12), firstSeason: seasonZero, overContractYears: 3)
        for season in seasonZero..<(seasonZero + 3) {
            #expect(bonus.share(in: season) == .millions(4))
        }
        #expect(bonus.share(in: seasonZero + 3) == .zero)
        #expect(bonus.share(in: seasonZero - 1) == .zero)
    }

    /// The classic trap. A seven-year deal still prorates over five, so the
    /// annual charge is larger than a naive `bonus / years` suggests and the
    /// final two seasons carry none of it.
    @Test("Proration never exceeds five years")
    func fiveYearCap() {
        let bonus = ProratedBonus(
            amount: .millions(35), firstSeason: seasonZero, overContractYears: 7)
        #expect(bonus.years == 5)
        for season in seasonZero..<(seasonZero + 5) {
            #expect(bonus.share(in: season) == .millions(7))
        }
        #expect(bonus.share(in: seasonZero + 5) == .zero)
        #expect(bonus.share(in: seasonZero + 6) == .zero)
    }

    @Test("A one-year deal charges the whole bonus at once")
    func singleYear() {
        let bonus = ProratedBonus(
            amount: .millions(5), firstSeason: seasonZero, overContractYears: 1)
        #expect(bonus.share(in: seasonZero) == .millions(5))
    }

    /// The invariant that keeps a contract screen adding up. Integer division
    /// leaves a remainder; losing it would mean a schedule that does not sum to
    /// the bonus a player was told he received.
    @Test(
        "Shares always sum to exactly the bonus",
        arguments: [
            (1_000_001, 3), (10_000_000, 3), (7_777_777, 7), (1, 5), (2, 5),
            (999_999_999, 5), (12_345_678, 4), (5, 4), (0, 5), (100, 3),
        ])
    func sharesSumExactly(amount: Int64, years: Int) {
        let bonus = ProratedBonus(
            amount: Money(dollars: amount), firstSeason: seasonZero, overContractYears: years)
        let summed = bonus.seasons.map(bonus.share(in:)).total()
        #expect(summed.dollars == amount, "\(amount) over \(years) years summed to \(summed)")
    }

    @Test("Shares differ by at most a dollar")
    func sharesAreBalanced() {
        let bonus = ProratedBonus(
            amount: Money(dollars: 10_000_002), firstSeason: seasonZero, overContractYears: 4)
        let shares = bonus.seasons.map { bonus.share(in: $0).dollars }
        guard let low = shares.min(), let high = shares.max() else {
            Issue.record("no shares produced")
            return
        }
        #expect(high - low <= 1)
    }

    @Test("Remaining proration counts this season and later")
    func remaining() {
        let bonus = ProratedBonus(
            amount: .millions(20), firstSeason: seasonZero, overContractYears: 4)
        #expect(bonus.remaining(from: seasonZero) == .millions(20))
        #expect(bonus.remaining(from: seasonZero + 1) == .millions(15))
        #expect(bonus.remaining(from: seasonZero + 3) == .millions(5))
        #expect(bonus.remaining(from: seasonZero + 4) == .zero)
    }
}

@Suite("Cap hits")
struct CapHitTests {

    @Test("A cap hit is base plus roster bonus plus proration plus likely incentives")
    func components() {
        let contract = makeContract(
            signingBonus: .millions(10),
            baseSalaries: [.millions(1), .millions(5)],
            rosterBonuses: [.millions(2), .zero],
            likelyIncentives: [.millions(0.5), .zero]
        )
        // 1 + 2 + 5 (10 over 2 years) + 0.5
        #expect(contract.capHit(in: seasonZero) == .millions(8.5))
        // 5 + 5
        #expect(contract.capHit(in: seasonZero + 1) == .millions(10))
    }

    @Test("Unlikely incentives are excluded")
    func unlikelyIncentivesExcluded() {
        var contract = makeContract(baseSalaries: [.millions(4)])
        contract.years[0].notLikelyToBeEarnedIncentives = .millions(3)
        #expect(contract.capHit(in: seasonZero) == .millions(4))
    }

    @Test("Seasons outside the contract cost nothing")
    func outsideTheTerm() {
        let contract = makeContract(baseSalaries: [.millions(4), .millions(5)])
        #expect(contract.capHit(in: seasonZero - 1) == .zero)
        #expect(contract.capHit(in: seasonZero + 2) == .zero)
    }

    @Test("Cap hits over the term sum to base plus bonus")
    func totalOverTerm() {
        let contract = makeContract(
            signingBonus: .millions(9),
            baseSalaries: [.millions(2), .millions(3), .millions(4)]
        )
        let total = contract.seasons.map(contract.capHit(in:)).total()
        #expect(total == .millions(18))
    }
}

@Suite("Dead money")
struct DeadMoneyTests {

    /// Releasing before a single snap is played accelerates the entire bonus.
    @Test("Release in year one accelerates the whole bonus")
    func releaseInYearOne() {
        let contract = makeContract(
            signingBonus: .millions(20),
            baseSalaries: [.millions(1), .millions(5), .millions(8), .millions(10)]
        )
        let dead = contract.deadMoney(releasedBefore: seasonZero)
        #expect(dead.currentSeason == .millions(20))
        #expect(dead.followingSeason == .zero)
    }

    @Test("Release mid-contract accelerates only what is unamortised")
    func releaseMidContract() {
        let contract = makeContract(
            signingBonus: .millions(20),
            baseSalaries: [.millions(1), .millions(5), .millions(8), .millions(10)]
        )
        // Two of four years already charged; 10 remains.
        #expect(contract.deadMoney(releasedBefore: seasonZero + 2).currentSeason == .millions(10))
    }

    @Test("Release in the final year leaves only that year's share")
    func releaseInFinalYear() {
        let contract = makeContract(
            signingBonus: .millions(20),
            baseSalaries: [.millions(1), .millions(5), .millions(8), .millions(10)]
        )
        #expect(contract.deadMoney(releasedBefore: seasonZero + 3).currentSeason == .millions(5))
    }

    @Test("Release after the contract ends costs nothing")
    func releaseAfterExpiry() {
        let contract = makeContract(
            signingBonus: .millions(20), baseSalaries: [.millions(1), .millions(5)])
        #expect(contract.deadMoney(releasedBefore: seasonZero + 2).total == .zero)
    }

    @Test("Guaranteed salary still owed adds to dead money")
    func guaranteesCount() {
        let contract = makeContract(
            signingBonus: .millions(12),
            baseSalaries: [.millions(2), .millions(6), .millions(9)],
            guarantees: [.millions(2), .millions(6), .zero]
        )
        // Proration 12 remaining + guarantees of 6 still owed from year two.
        let dead = contract.deadMoney(releasedBefore: seasonZero + 1)
        #expect(dead.currentSeason == .millions(8) + .millions(6))
    }

    /// The designation splits the charge: this year keeps one share, everything
    /// later lands next year. The relief is real but delayed, which is the
    /// tradeoff the rule exists to create.
    @Test("A post-June-1 release splits across two seasons")
    func postJune1Split() {
        let contract = makeContract(
            signingBonus: .millions(20),
            baseSalaries: [.millions(1), .millions(5), .millions(8), .millions(10)]
        )
        let dead = contract.deadMoney(releasedBefore: seasonZero + 1, postJune1: true)
        #expect(dead.currentSeason == .millions(5))
        #expect(dead.followingSeason == .millions(10))
        #expect(dead.total == .millions(15))
    }

    @Test("A post-June-1 release costs the same in total as a standard one")
    func postJune1PreservesTotal() {
        let contract = makeContract(
            signingBonus: .millions(30),
            baseSalaries: [.millions(2), .millions(6), .millions(9), .millions(12), .millions(15)]
        )
        for season in contract.seasons {
            let standard = contract.deadMoney(releasedBefore: season)
            let split = contract.deadMoney(releasedBefore: season, postJune1: true)
            #expect(standard.total == split.total, "totals diverged in \(season)")
            #expect(split.currentSeason <= standard.currentSeason)
        }
    }

    @Test("Cap savings can be negative when dead money exceeds the hit")
    func negativeSavings() {
        let contract = makeContract(
            signingBonus: .millions(40),
            baseSalaries: [.millions(1), .millions(1), .millions(1), .millions(1)]
        )
        // Hit is 1 + 10 = 11; releasing costs the full 40 still on the books.
        #expect(contract.capHit(in: seasonZero) == .millions(11))
        #expect(contract.capSavings(releasedBefore: seasonZero) == .millions(11) - .millions(40))
        #expect(contract.capSavings(releasedBefore: seasonZero).isNegative)
    }

    @Test("A post-June-1 designation improves current-season savings")
    func postJune1Savings() {
        let contract = makeContract(
            signingBonus: .millions(40),
            baseSalaries: [.millions(1), .millions(8), .millions(9), .millions(10)]
        )
        let standard = contract.capSavings(releasedBefore: seasonZero + 1)
        let split = contract.capSavings(releasedBefore: seasonZero + 1, postJune1: true)
        #expect(split > standard)
    }
}

@Suite("Restructures")
struct RestructureTests {

    @Test("A restructure lowers this year's hit and raises later ones")
    func basicRestructure() throws {
        let contract = makeContract(
            signingBonus: .zero,
            baseSalaries: [.millions(12), .millions(12), .millions(12), .millions(12)]
        )
        #expect(contract.capHit(in: seasonZero) == .millions(12))

        let restructured = try #require(
            contract.restructured(in: seasonZero, converting: .millions(8)))

        // 8 converted over four remaining years: 2 per year.
        #expect(restructured.capHit(in: seasonZero) == .millions(6))
        #expect(restructured.capHit(in: seasonZero + 1) == .millions(14))
        #expect(restructured.capHit(in: seasonZero + 3) == .millions(14))
    }

    @Test("A restructure moves money without creating or destroying it")
    func restructurePreservesTotal() throws {
        let contract = makeContract(
            signingBonus: .millions(10),
            baseSalaries: [.millions(9), .millions(11), .millions(13)]
        )
        let before = contract.seasons.map(contract.capHit(in:)).total()

        let restructured = try #require(
            contract.restructured(in: seasonZero, converting: .millions(6)))
        let after = restructured.seasons.map(restructured.capHit(in:)).total()

        #expect(before == after)
    }

    @Test("A restructure increases dead money on a later release")
    func restructureRaisesDeadMoney() throws {
        let contract = makeContract(
            baseSalaries: [.millions(10), .millions(10), .millions(10)])
        let restructured = try #require(
            contract.restructured(in: seasonZero, converting: .millions(9)))

        #expect(contract.deadMoney(releasedBefore: seasonZero + 1).total == .zero)
        #expect(restructured.deadMoney(releasedBefore: seasonZero + 1).total == .millions(6))
    }

    /// Restructuring a restructured deal is how a team walks into cap hell, and
    /// each conversion must keep its own schedule rather than merging.
    @Test("Restructuring twice stacks independent proration streams")
    func repeatedRestructure() throws {
        let contract = makeContract(
            baseSalaries: [.millions(20), .millions(20), .millions(20), .millions(20)])

        let once = try #require(contract.restructured(in: seasonZero, converting: .millions(16)))
        let twice = try #require(once.restructured(in: seasonZero + 1, converting: .millions(9)))

        #expect(twice.proratedBonuses.count == 2)

        // The first restructure took 16 out of year *one*'s base and spread it
        // over four years at 4; the second took 9 out of year two's base and
        // spread it over the three remaining years at 3.
        //   year one:   base 4,  proration 4                    =  8
        //   year two:   base 11, proration 4 + 3                = 18
        //   years 3-4:  base 20, proration 4 + 3                = 27 each
        #expect(twice.capHit(in: seasonZero) == .millions(8))
        #expect(twice.capHit(in: seasonZero + 1) == .millions(18))
        #expect(twice.capHit(in: seasonZero + 2) == .millions(27))
        #expect(twice.capHit(in: seasonZero + 3) == .millions(27))

        // Converting money never changes what the deal costs in total.
        #expect(twice.seasons.map(twice.capHit(in:)).total() == .millions(80))

        // And the back end is now heavier than before either conversion.
        #expect(twice.capHit(in: seasonZero + 3) > contract.capHit(in: seasonZero + 3))
    }

    @Test("A restructure in the final year has nowhere to spread")
    func restructureInFinalYear() throws {
        let contract = makeContract(baseSalaries: [.millions(10), .millions(10)])
        let restructured = try #require(
            contract.restructured(in: seasonZero + 1, converting: .millions(6)))
        #expect(restructured.capHit(in: seasonZero + 1) == .millions(10))
    }

    @Test("Invalid restructures are refused rather than silently clamped")
    func invalidRestructures() {
        let contract = makeContract(baseSalaries: [.millions(10), .millions(10)])
        #expect(contract.restructured(in: seasonZero, converting: .millions(11)) == nil)
        #expect(contract.restructured(in: seasonZero + 5, converting: .millions(1)) == nil)
        #expect(contract.restructured(in: seasonZero, converting: .zero) == nil)
        #expect(contract.restructured(in: seasonZero, converting: .millions(-1)) == nil)
    }

    /// Rewritten from `Converted money becomes guaranteed`, which asserted the
    /// bug: it required the conversion to land in `guaranteedSalary` as well as
    /// in a proration stream, so dead money charged the same dollars twice.
    ///
    /// A restructure converts base salary into a signing-bonus-like payment. The
    /// cash is paid at the conversion and prorates over the remaining seasons,
    /// capped at five; that proration is its only cap treatment. Dead money is
    /// remaining proration plus guaranteed salary *still owed*, and converted
    /// money is no longer owed — it has been paid.
    ///
    /// Source: `football-domain` skill, `references/salary-cap.md`, sections
    /// "Contract anatomy" (signing bonus is cash up front, prorated), "Dead
    /// money" (`remainingProration + guaranteedSalaryStillOwed`) and
    /// "Restructures".
    @Test("football · Converted money is counted once in dead money")
    func convertedMoneyIsCountedOnce() throws {
        // Three years at 10 apiece, a 9 signing bonus prorating 3 a season, and
        // 4 of year two's base guaranteed before anything is converted.
        let contract = makeContract(
            signingBonus: .millions(9),
            baseSalaries: [.millions(10), .millions(10), .millions(10)],
            guarantees: [.zero, .millions(4), .zero]
        )
        let restructured = try #require(
            contract.restructured(in: seasonZero, converting: .millions(6)))

        // The 6 leaves year one's base and opens a second stream at 2 a season.
        // It does not join the guarantee schedule: it is cash paid, not owed.
        #expect(restructured.year(seasonZero)?.baseSalary == .millions(4))
        #expect(restructured.year(seasonZero)?.guaranteedSalary == .zero)
        #expect(restructured.prorationCharge(in: seasonZero) == .millions(5))

        // Released in the same league year as the conversion: 9 of signing bonus
        // and 6 of conversion accelerate, plus the 4 guaranteed in year two.
        let immediately = restructured.deadMoney(releasedBefore: seasonZero)
        #expect(immediately.currentSeason == .millions(19))
        #expect(immediately.total == .millions(19))

        // Released before year two: two seasons of each stream remain, 6 and 4,
        // plus the same 4 of guaranteed salary — and nothing else.
        let dead = restructured.deadMoney(releasedBefore: seasonZero + 1)
        #expect(dead.currentSeason == .millions(6) + .millions(4) + .millions(4))
        #expect(dead.followingSeason == .zero)

        // "Nothing else" stated against the un-restructured deal: converting
        // adds exactly the conversion's unamortised proration, 4, not 10.
        let before = contract.deadMoney(releasedBefore: seasonZero + 1)
        #expect(dead.total - before.total == .millions(4))
    }

    /// Converting base salary that was already guaranteed does not create new
    /// money. The guarantee is satisfied in cash at the conversion and rides
    /// into the proration stream; what stays guaranteed is the base salary that
    /// is left, because that is all that can still be owed.
    ///
    /// Source: `football-domain` skill, `references/salary-cap.md`, "Dead money"
    /// — dead money counts guaranteed salary *still owed* — and "Restructures".
    @Test("football · Converting guaranteed base salary discharges that guarantee in cash")
    func convertingGuaranteedBaseDischargesTheGuarantee() throws {
        // Year one's 10 is fully guaranteed, as a first year usually is. No
        // signing bonus, so the conversion is the only proration stream.
        let contract = makeContract(
            baseSalaries: [.millions(10), .millions(8), .millions(6)],
            guarantees: [.millions(10), .zero, .zero]
        )
        let restructured = try #require(
            contract.restructured(in: seasonZero, converting: .millions(6)))

        #expect(restructured.year(seasonZero)?.baseSalary == .millions(4))
        #expect(restructured.year(seasonZero)?.guaranteedSalary == .millions(4))

        // Releasing before a snap is played costs the 6 already paid, now
        // accelerating as proration, plus the 4 still owed: exactly the 10 the
        // team had guaranteed, which is what it was on the hook for all along.
        let dead = restructured.deadMoney(releasedBefore: seasonZero)
        #expect(dead.currentSeason == .millions(10))
        #expect(dead.total == contract.deadMoney(releasedBefore: seasonZero).total)
    }
}

@Suite("Trades")
struct TradeTests {

    /// Proration accelerates onto the team sending the player, which is why a
    /// big signing bonus makes a contract hard to move.
    @Test("Trading accelerates proration onto the trading team")
    func acceleration() {
        let contract = makeContract(
            signingBonus: .millions(25),
            baseSalaries: [.millions(2), .millions(6), .millions(9), .millions(12), .millions(15)]
        )
        let accelerated = contract.tradeAcceleration(before: seasonZero + 2)
        #expect(accelerated.currentSeason == .millions(15))
        #expect(accelerated.followingSeason == .zero)
    }

    @Test("Guaranteed salary travels with the player rather than accelerating")
    func guaranteesTravel() {
        let contract = makeContract(
            signingBonus: .millions(10),
            baseSalaries: [.millions(5), .millions(5)],
            guarantees: [.millions(5), .millions(5)]
        )
        #expect(contract.tradeAcceleration(before: seasonZero + 1).total == .millions(5))
        // A release, by contrast, keeps the guarantee on the original team.
        #expect(contract.deadMoney(releasedBefore: seasonZero + 1).total == .millions(10))
    }

    /// A trade accelerates proration exactly as a release does, so it splits
    /// exactly as a release does: after June 1 the current season keeps only
    /// this season's share and everything later lands the following season.
    /// The relief is real but delayed, and the total never changes.
    ///
    /// Source: `football-domain` skill, `references/salary-cap.md`, "Dead money"
    /// (the post-June-1 split) and "Player movement" (a trade accelerates
    /// proration onto the trading team).
    @Test("football · A post-June-1 trade splits acceleration across two seasons")
    func postJune1Trade() {
        // 25 of signing bonus over five years is 5 a season; two are charged by
        // the time of the trade, so 15 is unamortised.
        let contract = makeContract(
            signingBonus: .millions(25),
            baseSalaries: [.millions(2), .millions(6), .millions(9), .millions(12), .millions(15)],
            guarantees: [.millions(2), .millions(6), .millions(9), .zero, .zero]
        )
        let split = contract.tradeAcceleration(before: seasonZero + 2, postJune1: true)

        #expect(split.currentSeason == .millions(5))
        #expect(split.followingSeason == .millions(10))
        // Guaranteed salary travels with the player either way, so none of the
        // 9 guaranteed in this season shows up on the trading team.
        #expect(split.total == .millions(15))
        #expect(split.total == contract.tradeAcceleration(before: seasonZero + 2).total)
    }
}

@Suite("Team cap position")
struct CapPositionTests {

    @Test("Space is the adjusted cap less everything committed")
    func space() {
        let position = SalaryCap.Position(
            season: seasonZero,
            leagueCap: .millions(255),
            carryover: .millions(5),
            activeCapHits: .millions(230),
            deadMoney: .millions(12),
            practiceSquadCharges: .millions(3)
        )
        #expect(position.adjustedCap == .millions(260))
        #expect(position.committed == .millions(245))
        #expect(position.space == .millions(15))
        #expect(position.isCompliant)
    }

    @Test("Overcommitment is representable and flagged")
    func overCap() {
        let position = SalaryCap.Position(
            season: seasonZero,
            leagueCap: .millions(255),
            activeCapHits: .millions(270)
        )
        #expect(position.space == .millions(-15))
        #expect(position.space.isNegative)
        #expect(!position.isCompliant)
    }

    @Test("A position built from contracts sums their hits")
    func fromContracts() {
        let contracts = [
            makeContract(signingBonus: .millions(10), baseSalaries: [.millions(5), .millions(5)]),
            makeContract(baseSalaries: [.millions(3), .millions(3)]),
        ]
        let position = SalaryCap.position(
            season: seasonZero,
            leagueCap: .millions(100),
            contracts: contracts,
            deadMoney: [.millions(4)]
        )
        #expect(position.activeCapHits == .millions(13))
        #expect(position.space == .millions(83))
    }
}

@Suite("Franchise tag")
struct FranchiseTagTests {

    @Test("The top-five average wins for a modestly paid player")
    func averageWins() {
        let value = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [
                .millions(30), .millions(28), .millions(26), .millions(24), .millions(22),
            ],
            priorCapHit: .millions(5)
        )
        #expect(value == .millions(26))
    }

    /// The rules disagree exactly when a team is deciding whether to tag someone
    /// already paid above his position's market.
    @Test("The 120% floor wins for an already well-paid player")
    func oneTwentyWins() {
        let value = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [
                .millions(30), .millions(28), .millions(26), .millions(24), .millions(22),
            ],
            priorCapHit: .millions(40)
        )
        #expect(value == .millions(48))
    }

    @Test("Only the top five salaries count")
    func onlyTopFive() {
        let value = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [
                .millions(30), .millions(28), .millions(26), .millions(24), .millions(22),
                .millions(1), .millions(1), .millions(1),
            ],
            priorCapHit: .zero
        )
        #expect(value == .millions(26))
    }

    @Test("Order of the salary list does not matter")
    func orderIndependent() {
        let ascending = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [.millions(10), .millions(20), .millions(30)],
            priorCapHit: .zero
        )
        let descending = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [.millions(30), .millions(20), .millions(10)],
            priorCapHit: .zero
        )
        #expect(ascending == descending)
    }

    @Test("A small league with fewer than five salaries still produces a figure")
    func shortList() {
        let value = SalaryCap.franchiseTagValue(
            topSalariesAtPosition: [.millions(20), .millions(10)],
            priorCapHit: .zero
        )
        #expect(value == .millions(15))
        #expect(
            SalaryCap.franchiseTagValue(topSalariesAtPosition: [], priorCapHit: .millions(10))
                == .millions(12))
    }
}

@Suite("Money")
struct MoneyTests {

    @Test("Arithmetic and comparison behave")
    func arithmetic() {
        #expect(Money.millions(1) + Money.millions(2) == Money.millions(3))
        #expect(Money.millions(5) - Money.millions(8) == Money.millions(-3))
        #expect(Money(dollars: 100) * 3 == Money(dollars: 300))
        #expect(-Money.millions(2) == Money.millions(-2))
        #expect(Money.millions(1) < Money.millions(2))
        #expect([Money.millions(1), Money.millions(2)].total() == Money.millions(3))
    }

    @Test("Scaling rounds to the nearest dollar")
    func scaling() {
        #expect(Money(dollars: 100).scaled(by: 1.2) == Money(dollars: 120))
        #expect(Money(dollars: 10).scaled(by: 1.25) == Money(dollars: 13))
        #expect(Money(dollars: 3).scaled(by: 0.5) == Money(dollars: 2))
    }

    @Test("Formatting reads as money without importing Foundation")
    func formatting() {
        #expect(Money.millions(12.5).description == "$12.500M")
        #expect(Money(dollars: 1_000_000).description == "$1.000M")
        #expect(Money(dollars: 1_020_000).description == "$1.020M")
        #expect(Money(dollars: 999).description == "$999")
        #expect(Money.millions(-3).description == "-$3.000M")
    }
}
