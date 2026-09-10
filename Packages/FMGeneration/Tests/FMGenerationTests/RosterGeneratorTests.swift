import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030

private func makeRoster(
    shape: RosterShape = .standard,
    strength: RosterGenerator.Strength = .leagueAverage,
    seed: UInt64 = 1
) -> [Player] {
    var random = SplittableRandom(seed: seed)
    var ids = IdentifierSequence<PlayerSubject>()
    let colleges = NameGenerator.collegePool(count: 60, using: &random)
    return RosterGenerator.roster(
        shape: shape, strength: strength, season: season,
        colleges: colleges, ids: &ids, using: &random)
}

private func mean(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

@Suite("Roster shape")
struct RosterShapeTests {

    @Test("The standard roster is 53 with eleven starters a side", .tags(.unit))
    func standardShape() {
        #expect(RosterShape.standard.rosterSize == 53)
        // Eleven on offence, eleven on defence, plus the three kicking specialists.
        #expect(RosterShape.standard.starterCount == 25)

        let offense = RosterShape.standard.requirements
            .filter { $0.position.side == .offense }
            .reduce(0) { $0 + $1.starters }
        let defense = RosterShape.standard.requirements
            .filter { $0.position.side == .defense }
            .reduce(0) { $0 + $1.starters }
        #expect(offense == 11)
        #expect(defense == 11)
    }

    @Test("Every shape fields exactly five offensive linemen", .tags(.unit))
    func coversTheField() {
        for shape in [RosterShape.standard, RosterShape.minimal] {
            let linemen = shape.requirements
                .filter { $0.position.isOffensiveLine }
                .reduce(0) { $0 + $1.starters }
            #expect(linemen == 5)
        }
    }

    /// Twenty-five players: eleven a side plus the three kicking specialists,
    /// with no depth at all. Small enough that a four-team league sims a season
    /// in a blink.
    @Test("A minimal roster is every starter and nobody else", .tags(.unit))
    func minimalShape() {
        #expect(RosterShape.minimal.rosterSize == 25)
        #expect(RosterShape.minimal.starterCount == 25)
        #expect(
            RosterShape.minimal.requirements.allSatisfy { $0.starters == $0.total },
            "a minimal roster should carry no reserves")
    }
}

@Suite("Roster generation")
struct RosterGeneratorTests {

    @Test("A roster is exactly the size its shape asks for", .tags(.unit))
    func size() {
        #expect(makeRoster().count == 53)
        #expect(makeRoster(shape: .minimal).count == 25)
    }

    @Test("Every position requirement is filled exactly", .tags(.unit))
    func positionCounts() {
        let roster = makeRoster()
        for requirement in RosterShape.standard.requirements {
            let count = roster.filter { $0.position == requirement.position }.count
            #expect(count == requirement.total, "\(requirement.position) had \(count)")
        }
    }

    @Test("The same seed produces the same roster", .tags(.contract))
    func deterministic() {
        #expect(makeRoster(seed: 4242) == makeRoster(seed: 4242))
    }

    @Test("Identifiers are unique and allocated in order", .tags(.contract))
    func identifiers() {
        let roster = makeRoster()
        #expect(Set(roster.map(\.id)).count == roster.count)
        #expect(roster.map(\.id) == roster.map(\.id).sorted())
    }

    /// If a starter is not clearly better than his backup, an injury costs
    /// nothing and depth stops being a decision.
    @Test("Starters are clearly better than the players behind them", .tags(.unit))
    func startersOutrankBackups() {
        let roster = makeRoster()
        let starters = RosterGenerator.projectedStarters(from: roster)
        let starterIDs = Set(starters.map(\.id))
        let reserves = roster.filter { !starterIDs.contains($0.id) }

        let starterMean = mean(starters.map { Int($0.overall) })
        let reserveMean = mean(reserves.map { Int($0.overall) })
        #expect(starterMean > reserveMean + 6, "starters \(starterMean), reserves \(reserveMean)")
    }

    @Test("Projected starters fill each position the right number of times", .tags(.unit))
    func starterCounts() {
        let starters = RosterGenerator.projectedStarters(from: makeRoster())
        for requirement in RosterShape.standard.requirements where requirement.starters > 0 {
            let count = starters.filter { $0.position == requirement.position }.count
            #expect(count == requirement.starters, "\(requirement.position) started \(count)")
        }
    }

    /// A league where every team is the same is a league where roster building
    /// does not matter.
    @Test("Stronger teams produce stronger rosters", .tags(.unit))
    func strengthSeparates() {
        let contender = mean(makeRoster(strength: .contender, seed: 7).map { Int($0.overall) })
        let average = mean(makeRoster(strength: .leagueAverage, seed: 7).map { Int($0.overall) })
        let rebuilding = mean(makeRoster(strength: .rebuilding, seed: 7).map { Int($0.overall) })

        #expect(contender > average)
        #expect(average > rebuilding)
        #expect(contender - rebuilding > 5, "only \(contender - rebuilding) between the extremes")
    }

    /// Team quality should show up most in the starting lineup. Everybody's
    /// fifth receiver is roughly the same player.
    @Test("Team quality lifts starters more than depth", .tags(.unit))
    func strengthConcentratesInStarters() {
        func split(_ strength: RosterGenerator.Strength) -> (starters: Double, reserves: Double) {
            let roster = makeRoster(strength: strength, seed: 11)
            let starters = RosterGenerator.projectedStarters(from: roster)
            let ids = Set(starters.map(\.id))
            return (
                mean(starters.map { Int($0.overall) }),
                mean(roster.filter { !ids.contains($0.id) }.map { Int($0.overall) })
            )
        }
        let strong = split(.contender)
        let weak = split(.rebuilding)

        let starterGap = strong.starters - weak.starters
        let reserveGap = strong.reserves - weak.reserves
        #expect(starterGap > reserveGap, "starters \(starterGap), reserves \(reserveGap)")
    }

    @Test("Ages span a believable range and centre on the prime", .tags(.unit))
    func ageDistribution() {
        let roster = makeRoster()
        let ages = roster.map { $0.age(in: season) }
        #expect(ages.allSatisfy { $0 >= 21 && $0 <= 38 })
        let average = mean(ages)
        #expect(average > 24 && average < 29, "mean age \(average)")
        #expect(ages.contains { $0 <= 23 }, "no young players")
        #expect(ages.contains { $0 >= 31 }, "no veterans")
    }

    @Test("Starters are older than the players developing behind them", .tags(.unit))
    func startersAreOlder() {
        var starterAges: [Int] = []
        var reserveAges: [Int] = []
        for seed in UInt64(1)...12 {
            let roster = makeRoster(seed: seed)
            let starters = RosterGenerator.projectedStarters(from: roster)
            let ids = Set(starters.map(\.id))
            starterAges += starters.map { $0.age(in: season) }
            reserveAges += roster.filter { !ids.contains($0.id) }.map { $0.age(in: season) }
        }
        #expect(mean(starterAges) > mean(reserveAges))
    }

    @Test("Nobody on a generated roster is above his ceiling", .tags(.contract))
    func ceilingHolds() {
        for seed in UInt64(1)...20 {
            for player in makeRoster(seed: seed) {
                #expect(player.overall <= player.hidden.ceiling, "\(player.name) exceeded ceiling")
            }
        }
    }
}

/// The beginning of the conservation testing the development design depends on:
/// before growth and decline exist, the league it starts from has to be the
/// right shape.
@Suite("League talent distribution")
struct LeagueDistributionTests {

    private func league(teams: Int = 32, seed: UInt64 = 99) -> [[Player]] {
        var random = SplittableRandom(seed: seed)
        var ids = IdentifierSequence<PlayerSubject>()
        let colleges = NameGenerator.collegePool(count: 120, using: &random)
        return (0..<teams).map { index in
            // A spread of team quality, from rebuilding to contending.
            let offset = -8.0 + 16.0 * Double(index) / Double(max(1, teams - 1))
            return RosterGenerator.roster(
                strength: .init(offset: offset), season: season,
                colleges: colleges, ids: &ids, using: &random)
        }
    }

    @Test("A generated league has a believable overall distribution", .tags(.unit))
    func distribution() {
        let players = league().flatMap { $0 }
        #expect(players.count == 32 * 53)

        let overalls = players.map { Int($0.overall) }
        let average = mean(overalls)
        let variance = mean(overalls.map { ($0 - Int(average)) * ($0 - Int(average)) })

        #expect(average > 64 && average < 74, "league mean \(average)")
        #expect(variance > 40 && variance < 160, "league variance \(variance)")
    }

    @Test("Elite players are rare and terrible players exist", .tags(.unit))
    func tails() {
        let players = league().flatMap { $0 }
        let elite = players.filter { $0.overall >= 90 }
        let stars = players.filter { $0.overall >= 85 }
        let fringe = players.filter { $0.overall < 60 }

        #expect(elite.count > 0, "a league with no elite players")
        #expect(Double(elite.count) / Double(players.count) < 0.02, "\(elite.count) elite players")
        #expect(stars.count > elite.count)
        #expect(fringe.count > players.count / 20, "no fringe players at all")
    }

    @Test("Quarterbacks are the most valuable and the most concentrated", .tags(.unit))
    func quarterbacks() {
        let players = league().flatMap { $0 }
        let starters = players.filter { $0.position == .quarterback }
            .sorted { $0.overall > $1.overall }
        // 32 teams carry three each.
        #expect(starters.count == 96)
        // A handful are genuinely good and most are not.
        #expect(starters.prefix(10).allSatisfy { $0.overall >= 75 })
    }

    @Test("Every team fields a legal roster", .tags(.contract))
    func everyTeamIsLegal() {
        for roster in league() {
            #expect(roster.count == 53)
            for requirement in RosterShape.standard.requirements {
                #expect(
                    roster.filter { $0.position == requirement.position }.count == requirement.total
                )
            }
        }
    }
}
