import FMCore
import FMRandom
import Testing

@testable import FMGeneration

/// One entry point builds a world, and the strength of a team owes nothing to where it
/// sits in the league.
///
/// The generator this replaces gave team *n* an offset interpolated from *n*: at seed 7
/// the league's mean overall climbed from 58.9 at team 0 to 69.4 at team 31, every
/// division was stronger than the one before it, and a conference race was decided by
/// generation order. Nothing failed, because nothing looked.
@Suite("World generation")
struct WorldGeneratorTests {

    private func generated(
        seed: UInt64, shape: LeagueShape = .compact, parts: WorldGenerator.Parts = .all
    ) -> WorldGenerator.GeneratedWorld? {
        try? WorldGenerator.generate(
            seed: seed, shape: shape, season: 2030, parts: parts, collegeCount: 20
        ).get()
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func teamMeanOveralls(_ world: WorldGenerator.GeneratedWorld) -> [Double] {
        world.teams.map { team in
            mean(world.roster(of: team.id).map { Double($0.overall) })
        }
    }

    // MARK: - One entry point

    @Test("contract: one call builds a whole world")
    func aWorldIsWholeAtOnce() throws {
        let world = try #require(generated(seed: 3))

        #expect(world.seed == 3)
        #expect(world.season == 2030)
        #expect(world.teams.count == LeagueShape.compact.totalTeams)
        #expect(world.league.structureFailures.isEmpty)
        #expect(world.colleges.isEmpty == false)
        #expect(world.draftPipeline.isEmpty == false)
        #expect(world.rivalries.isEmpty == false)

        for team in world.teams {
            #expect(world.roster(of: team.id).count == RosterShape.standard.rosterSize)
            #expect(world.depthChart(of: team.id).starter(at: .quarterback) != nil)
            #expect(world.identity(of: team.id)?.played == team.scheme)
        }
        // Every player on every roster is reachable by identifier, which is the shape a
        // game setup wants.
        let onRosters = world.teams.flatMap { world.roster(of: $0.id) }
        #expect(onRosters.allSatisfy { world.players[$0.id] != nil })
        #expect(Set(onRosters.map(\.id)).count == onRosters.count, "a player on two rosters")
    }

    @Test("contract: teams come back in identifier order")
    func teamsAreOrdered() throws {
        let world = try #require(generated(seed: 11))
        #expect(world.teams.map(\.id.rawValue) == world.teams.map(\.id.rawValue).sorted())
    }

    // MARK: - Strength is drawn, not assigned

    /// The issue's own example, kept as the test: the league at seed 7 must not be a
    /// ladder. Both halves are asserted — the offsets the generator drew, and the mean
    /// overalls they actually produced — because a strength that never reached a roster
    /// would pass the first check alone.
    @Test("contract: at seed 7 the league is not a ladder in team index")
    func seedSevenIsNotMonotone() throws {
        let world = try #require(generated(seed: 7, shape: .standard))

        let offsets = world.teams.map { world.strength(of: $0.id).offset }
        #expect(offsets != offsets.sorted(), "strength rises with team index")
        #expect(offsets != Array(offsets.sorted().reversed()), "strength falls with index")

        let means = teamMeanOveralls(world)
        #expect(means != means.sorted(), "team quality rises with team index")
        #expect(
            means != Array(means.sorted().reversed()), "team quality falls with team index")

        // The teams that would have been the weakest and the strongest under the old
        // interpolation. Neither is anywhere near the edge of the league any more.
        let ranked = means.sorted()
        let bottom = ranked[0]
        let top = ranked[ranked.count - 1]
        #expect(means[0] > bottom, "team 0 is still the worst club in the league")
        #expect(means[means.count - 1] < top, "the last team is still the best club")
    }

    /// The strong form, and the one that would have caught the bug on any seed. Over
    /// enough worlds every position in the league averages out to the middle; under an
    /// index-linear assignment position 0 averages -8 and the last position +8, forever.
    @Test("contract: no position in the league is systematically stronger")
    func positionInTheLeagueCarriesNoStrength() {
        let teams = 32
        let seeds: [UInt64] = (1...60).map { UInt64($0) }
        var totals = [Double](repeating: 0, count: teams)

        for seed in seeds {
            var random = SplittableRandom(seed: seed)
            let drawn = WorldGenerator.strengths(count: teams, using: &random)
            for (index, strength) in drawn.enumerated() { totals[index] += strength.offset }
        }

        for (index, total) in totals.enumerated() {
            let average = total / Double(seeds.count)
            // Uniform on ±8 has a standard deviation near 4.6, so the mean of sixty draws
            // has one near 0.6. Three points is five of those, and the old generator sat
            // eight away at both ends.
            #expect(
                average > -3 && average < 3,
                "team \(index) averages \(average) across \(seeds.count) leagues")
        }
    }

    @Test("contract: a league's strength is centred on zero")
    func strengthIsCentred() throws {
        for seed in UInt64(1)...8 {
            let world = try #require(generated(seed: seed))
            let offsets = world.teams.map { world.strength(of: $0.id).offset }
            let average = mean(offsets)
            #expect(
                average > -0.000_001 && average < 0.000_001,
                "seed \(seed) drew a league with mean offset \(average)")
        }
    }

    @Test("unit: strengths are drawn inside the spread")
    func strengthsRespectTheSpread() {
        for seed in UInt64(1)...20 {
            var random = SplittableRandom(seed: seed)
            let drawn = WorldGenerator.strengths(count: 32, using: &random)
            #expect(drawn.count == 32)
            // Centring moves every offset by at most the spread, so twice it is the bound
            // that always holds.
            for strength in drawn {
                #expect(
                    strength.offset > -2 * WorldGenerator.strengthSpread
                        && strength.offset < 2 * WorldGenerator.strengthSpread)
            }
            // And a league that came out flat would be a broken draw, not a quiet season.
            let span = (drawn.map(\.offset).max() ?? 0) - (drawn.map(\.offset).min() ?? 0)
            #expect(span > 6, "seed \(seed) drew a league with a span of \(span)")
        }
    }

    @Test("unit: an empty league draws no strengths")
    func noTeamsNoStrengths() {
        var random = SplittableRandom(seed: 1)
        #expect(WorldGenerator.strengths(count: 0, using: &random).isEmpty)
    }

    // MARK: - Reproducible, and separable

    @Test("contract: the same seed builds the same world")
    func sameSeedSameWorld() throws {
        let first = try #require(generated(seed: 21))
        let second = try #require(generated(seed: 21))

        #expect(first.teams == second.teams)
        #expect(first.league == second.league)
        #expect(first.rivalries == second.rivalries)
        for team in first.teams {
            #expect(first.roster(of: team.id) == second.roster(of: team.id))
            #expect(first.depthChart(of: team.id) == second.depthChart(of: team.id))
            #expect(first.strength(of: team.id) == second.strength(of: team.id))
        }
    }

    @Test("contract: different seeds build different worlds")
    func differentSeedsDifferentWorlds() throws {
        let first = try #require(generated(seed: 21))
        let second = try #require(generated(seed: 22))
        #expect(first.teams != second.teams)
        #expect(teamMeanOveralls(first) != teamMeanOveralls(second))
    }

    /// Each stage draws from its own labelled substream, so asking for fewer parts must
    /// not move the parts you did ask for. If this fails, a caller that skips the draft
    /// pipeline is playing in a different league from one that does not.
    @Test("contract: asking for fewer parts gives the same world, with less of it")
    func partsDoNotMoveTheRest() throws {
        let whole = try #require(generated(seed: 33, parts: .all))
        let bare = try #require(generated(seed: 33, parts: .teamsAndRosters))

        #expect(bare.draftPipeline.isEmpty)
        #expect(bare.rivalries.isEmpty)
        #expect(whole.teams == bare.teams)
        #expect(whole.colleges == bare.colleges)
        for team in whole.teams {
            #expect(whole.roster(of: team.id) == bare.roster(of: team.id))
            #expect(whole.strength(of: team.id) == bare.strength(of: team.id))
        }
    }

    // MARK: - The league it produces

    /// Generation's job is a league with contenders and rebuilds in it. The bands here are
    /// the same ones `LeagueDistributionTests` asserts about a hand-built league; this is
    /// the check that the real entry point still lands inside them.
    @Test("contract: a generated league has a spread of team quality")
    func theLeagueHasContendersAndRebuilds() throws {
        let world = try #require(generated(seed: 7, shape: .standard))
        let means = teamMeanOveralls(world)
        let best = means.max() ?? 0
        let worst = means.min() ?? 0

        #expect(best - worst > 4, "every club is the same club: \(worst) to \(best)")
        #expect(best - worst < 20, "the league is two different sports: \(worst) to \(best)")

        let players = world.teams.flatMap { world.roster(of: $0.id) }
        let overall = mean(players.map { Double($0.overall) })
        #expect(overall > 62 && overall < 72, "league mean overall \(overall)")
    }
}
