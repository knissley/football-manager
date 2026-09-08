import Testing

@testable import FMCore

/// Invariants that must hold for *every* contract shape, checked across a grid
/// rather than at hand-picked points.
///
/// Example-based tests confirm the cases someone thought of. These confirm the
/// cases nobody thought of, which for cap arithmetic is where the damage is:
/// a rule that works for a clean four-year deal and quietly loses money on a
/// seven-year deal with an odd bonus is exactly the bug that reaches a contract
/// screen.
///
/// The grid is enumerated, not random, so failures are reproducible and there
/// is nothing to flake.
@Suite("Cap invariants across contract shapes")
struct SalaryCapPropertyTests {

    private static let baseSeason = 2030

    /// Deliberately awkward: prime-ish bonuses, terms either side of the
    /// five-year proration cap, and amounts that do not divide evenly.
    private static let bonuses: [Int64] = [
        0, 1, 7, 999_999, 1_000_000, 12_345_678, 35_000_000, 999_999_999,
    ]
    private static let terms = [1, 2, 3, 4, 5, 6, 7]

    private static func contract(term: Int, bonus: Int64) -> Contract {
        // Written out rather than inlined: a single initialiser call with three
        // ternaries defeats the type checker.
        var years: [ContractYear] = []
        for index in 0..<term {
            let base = Money(dollars: 1_000_000 + Int64(index) * 2_500_000)
            let roster: Money = index % 2 == 0 ? Money(dollars: 250_000) : Money.zero
            let guaranteed: Money = index < 2 ? Money(dollars: 750_000) : Money.zero
            let incentives: Money = index % 3 == 0 ? Money(dollars: 125_000) : Money.zero
            years.append(
                ContractYear(
                    baseSalary: base,
                    rosterBonus: roster,
                    guaranteedSalary: guaranteed,
                    likelyToBeEarnedIncentives: incentives
                )
            )
        }
        return Contract(
            id: ContractID(1),
            player: PlayerID(1),
            team: TeamID(1),
            firstSeason: baseSeason,
            signingBonus: Money(dollars: bonus),
            years: years
        )
    }

    private static var allShapes: [(term: Int, bonus: Int64)] {
        terms.flatMap { term in bonuses.map { (term, $0) } }
    }

    /// Cap hits across the term must account for every dollar promised and no
    /// more. Rounding that loses a few dollars per year compounds into a
    /// contract that does not reconcile.
    @Test("Cap hits over the term account for exactly the money committed")
    func moneyIsConserved() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)

            let charged = contract.seasons.map(contract.capHit(in:)).total()
            let promised =
                contract.years.map(\.baseSalary).total()
                + contract.years.map(\.rosterBonus).total()
                + contract.years.map(\.likelyToBeEarnedIncentives).total()
                + Money(dollars: shape.bonus)

            #expect(charged == promised, "term \(shape.term), bonus \(shape.bonus)")
        }
    }

    /// The designation changes *when* dead money lands, never how much.
    @Test("A post-June-1 designation only moves dead money, never reduces it")
    func designationPreservesTotal() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            for season in contract.seasons {
                let standard = contract.deadMoney(releasedBefore: season)
                let split = contract.deadMoney(releasedBefore: season, postJune1: true)

                #expect(standard.total == split.total, "term \(shape.term) season \(season)")
                #expect(split.currentSeason <= standard.currentSeason)
                #expect(split.followingSeason >= .zero)
            }
        }
    }

    @Test("Unamortised proration only ever shrinks as seasons pass")
    func prorationIsMonotonic() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            var previous = contract.remainingProration(from: contract.firstSeason)
            #expect(previous == Money(dollars: shape.bonus))

            for season in contract.seasons.dropFirst() {
                let current = contract.remainingProration(from: season)
                #expect(current <= previous, "term \(shape.term) season \(season)")
                previous = current
            }
            #expect(contract.remainingProration(from: contract.lastSeason + 1) == .zero)
        }
    }

    @Test("Cap savings is always the hit less what the release charges this year")
    func savingsMatchesDefinition() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            for season in contract.seasons {
                for postJune1 in [false, true] {
                    let dead = contract.deadMoney(releasedBefore: season, postJune1: postJune1)
                    let expected = contract.capHit(in: season) - dead.currentSeason
                    #expect(
                        contract.capSavings(releasedBefore: season, postJune1: postJune1)
                            == expected)
                }
            }
        }
    }

    /// Proration never spreads past five years however long the deal runs, and
    /// never past the deal itself.
    @Test("Proration respects both the five-year cap and the contract term")
    func prorationBounds() {
        for shape in Self.allShapes where shape.bonus > 0 {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            for bonus in contract.proratedBonuses {
                #expect(bonus.years <= ProratedBonus.maximumYears)
                #expect(bonus.years <= shape.term)
                #expect(bonus.seasons.upperBound <= contract.lastSeason + 1)
            }
        }
    }

    /// Converting base salary shifts money later without changing the total, and
    /// always buys relief in the season it happens.
    @Test("Restructuring shifts money forward without changing the total")
    func restructurePreservesTotal() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            guard shape.term > 1 else { continue }

            for season in contract.seasons.dropLast() {
                guard let year = contract.year(season), year.baseSalary > .zero else { continue }
                let amount = Money(dollars: year.baseSalary.dollars / 2)
                guard amount > .zero,
                    let restructured = contract.restructured(in: season, converting: amount)
                else { continue }

                let before = contract.seasons.map(contract.capHit(in:)).total()
                let after = restructured.seasons.map(restructured.capHit(in:)).total()
                #expect(before == after, "term \(shape.term) season \(season)")

                #expect(restructured.capHit(in: season) < contract.capHit(in: season))
                #expect(
                    restructured.deadMoney(releasedBefore: season + 1).total
                        >= contract.deadMoney(releasedBefore: season + 1).total)
            }
        }
    }

    @Test("A cap hit is never less than the proration it carries")
    func hitCoversProration() {
        for shape in Self.allShapes {
            let contract = Self.contract(term: shape.term, bonus: shape.bonus)
            for season in contract.seasons {
                #expect(contract.capHit(in: season) >= contract.prorationCharge(in: season))
            }
        }
    }
}
