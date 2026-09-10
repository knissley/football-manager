import FMCore
import Testing

@testable import FMGeneration

/// What the world checksum promises.
///
/// `GoldenWorldTests` pins its *value*; these pin its *coverage*. The number is now read
/// by `simharness` and compared across branches by `scripts/harness-reach.sh` to decide
/// that a change cannot reach the calibration run (#72), so a field the engine reads and
/// the checksum does not is a false "this change is invisible" — the one failure mode
/// that would make the tool worse than the reviewer's argument it replaces.
///
/// Each perturbation below rebuilds a generated world with exactly one thing different
/// and expects the number to move.
@Suite("World checksum")
struct WorldChecksumTests {

    private func generated(
        seed: UInt64 = 7, parts: WorldGenerator.Parts = .teamsAndRosters
    ) throws -> WorldGenerator.GeneratedWorld {
        try WorldGenerator.generate(
            seed: seed, shape: .standard, season: 2030, parts: parts, collegeCount: 80
        ).get()
    }

    /// The same world, rebuilt from its own accessors, with an optional substitution.
    ///
    /// Everything a `GeneratedWorld` holds is readable through its public surface, so a
    /// copy can be assembled and one part of it replaced. The identity copy is asserted
    /// first, below, so a perturbation that moves the number is the perturbation moving
    /// it and not the rebuild.
    private func rebuilt(
        _ world: WorldGenerator.GeneratedWorld,
        teams: [Team]? = nil,
        rosters: [TeamID: [Player]]? = nil,
        charts: [TeamID: DepthChart]? = nil,
        players: [PlayerID: Player]? = nil
    ) -> WorldGenerator.GeneratedWorld {
        var strengths: [TeamID: RosterGenerator.Strength] = [:]
        var identities: [TeamID: SchemeIdentity.Identity] = [:]
        var chosenRosters: [TeamID: [Player]] = [:]
        var chosenCharts: [TeamID: DepthChart] = [:]
        for team in world.teams {
            strengths[team.id] = world.strength(of: team.id)
            identities[team.id] = world.identity(of: team.id)
            chosenRosters[team.id] = world.roster(of: team.id)
            chosenCharts[team.id] = world.depthChart(of: team.id)
        }
        if let rosters { chosenRosters = rosters }
        if let charts { chosenCharts = charts }

        // Derived from the rosters, exactly as `WorldGenerator` derives it — unless the
        // caller hands over a map of its own, which is the case the engine cares about:
        // `GameSetup` is given this dictionary, not the rosters.
        var chosenPlayers: [PlayerID: Player] = [:]
        for id in chosenRosters.keys.sorted() {
            for player in chosenRosters[id] ?? [] { chosenPlayers[player.id] = player }
        }
        if let players { chosenPlayers = players }

        return WorldGenerator.GeneratedWorld(
            seed: world.seed,
            season: world.season,
            league: world.league,
            teams: teams ?? world.teams,
            colleges: world.colleges,
            strengths: strengths,
            identities: identities,
            rosters: chosenRosters,
            charts: chosenCharts,
            players: chosenPlayers,
            draftPipeline: world.draftPipeline,
            rivalries: world.rivalries)
    }

    /// The checksum of the same world with one man on one roster replaced.
    private func checksum(
        of world: WorldGenerator.GeneratedWorld, replacingFirstOf team: TeamID,
        with player: Player
    ) -> UInt64 {
        var all: [TeamID: [Player]] = [:]
        for one in world.teams { all[one.id] = world.roster(of: one.id) }
        all[team]?[0] = player
        return WorldChecksum.of(rebuilt(world, rosters: all))
    }

    @Test("contract: a world rebuilt from its own accessors is the same world")
    func rebuildIsIdentity() throws {
        let world = try generated()
        #expect(WorldChecksum.of(rebuilt(world)) == WorldChecksum.of(world))
    }

    @Test("contract: the same world checksums the same twice, and two seeds do not collide")
    func stableAndDistinct() throws {
        let seven = try generated()
        #expect(WorldChecksum.of(seven) == WorldChecksum.of(try generated()))
        #expect(WorldChecksum.of(seven) != WorldChecksum.of(try generated(seed: 11)))
    }

    @Test("contract: a world generated with the optional parts does not checksum as one without")
    func optionalPartsAreRead() throws {
        let bare = try generated(parts: .teamsAndRosters)
        let full = try generated(parts: .all)
        #expect(!full.draftPipeline.isEmpty)
        #expect(!full.rivalries.isEmpty)
        #expect(WorldChecksum.of(bare) != WorldChecksum.of(full))
    }

    @Test("contract: the checksum moves when the stadium a game is played in moves")
    func stadiumIsRead() throws {
        let world = try generated()
        var teams = world.teams
        // The climate is what the weather is drawn from and the noise is what the crowd
        // does to a road offence: both reach a snap without touching a rating.
        teams[0].stadium.climate = teams[0].stadium.climate == .cold ? .hot : .cold
        #expect(WorldChecksum.of(rebuilt(world, teams: teams)) != WorldChecksum.of(world))

        teams = world.teams
        teams[0].stadium.noise = teams[0].stadium.noise == 100 ? 99 : teams[0].stadium.noise + 1
        #expect(WorldChecksum.of(rebuilt(world, teams: teams)) != WorldChecksum.of(world))
    }

    @Test("contract: the checksum moves when a team changes scheme on either side")
    func schemeIsRead() throws {
        let world = try generated()
        var teams = world.teams
        let scheme = teams[0].scheme
        teams[0].scheme = TeamScheme(
            offense: scheme.offense,
            defense: DefensiveScheme(
                front: scheme.defense.front,
                coverage: scheme.defense.coverage,
                pressure: scheme.defense.pressure == .blitzHeavy ? .conservative : .blitzHeavy))
        #expect(WorldChecksum.of(rebuilt(world, teams: teams)) != WorldChecksum.of(world))
    }

    @Test("contract: the checksum moves when a player the engine reads changes")
    func playerFieldsTheEngineReadsAreRead() throws {
        let world = try generated()
        let team = world.teams[0].id
        let original = try #require(world.roster(of: team).first)

        // Secondary positions: whether a man can fill a hole in the lineup.
        let versatile = Player(
            id: original.id, name: original.name, birthSeason: original.birthSeason,
            college: original.college, draft: original.draft, firstSeason: original.firstSeason,
            position: original.position,
            secondaryPositions: original.secondaryPositions.isEmpty
                ? [.tightEnd] : [],
            physical: original.physical, ratings: original.ratings, traits: original.traits,
            hidden: original.hidden, status: original.status)
        #expect(
            checksum(of: world, replacingFirstOf: team, with: versatile) != WorldChecksum.of(world))

        // Durability: how long he is out when he goes down.
        let sturdier = Player(
            id: original.id, name: original.name, birthSeason: original.birthSeason,
            college: original.college, draft: original.draft, firstSeason: original.firstSeason,
            position: original.position, secondaryPositions: original.secondaryPositions,
            physical: original.physical, ratings: original.ratings, traits: original.traits,
            hidden: HiddenAttributes(
                ceiling: original.hidden.ceiling,
                developmentTrait: original.hidden.developmentTrait,
                workEthic: original.hidden.workEthic,
                durability: original.hidden.durability == 99 ? 98 : original.hidden.durability + 1),
            status: original.status)
        #expect(
            checksum(of: world, replacingFirstOf: team, with: sturdier) != WorldChecksum.of(world))

        // A rating, which is the obvious one and was covered before this issue.
        var ratings = original.ratings
        let key = RatingKey.allCases[0]
        ratings[key] = (ratings[key] ?? 60) == 99 ? 98 : (ratings[key] ?? 60) + 1
        let better = Player(
            id: original.id, name: original.name, birthSeason: original.birthSeason,
            college: original.college, draft: original.draft, firstSeason: original.firstSeason,
            position: original.position, secondaryPositions: original.secondaryPositions,
            physical: original.physical, ratings: ratings, traits: original.traits,
            hidden: original.hidden, status: original.status)
        #expect(
            checksum(of: world, replacingFirstOf: team, with: better) != WorldChecksum.of(world))
    }

    /// The map is what the engine is *handed*: `simharness` takes `world.players` and
    /// gives that dictionary to `GameSetup`, and `GeneratedWorld` stores it beside the
    /// rosters rather than deriving it on demand. A checksum that walked only the rosters
    /// would call a league with five points of speed added to a starter the same league
    /// — and the harness moved by hundreds of lines when that was tried.
    @Test("contract: the checksum moves when the players map the engine is handed changes")
    func playersMapIsRead() throws {
        let world = try generated()
        let team = world.teams[0].id
        let original = try #require(world.roster(of: team).first)

        var faster = original
        faster.ratings[.speed] = min(99, (original.ratings[.speed] ?? 60) + 5)
        var players = world.players
        players[original.id] = faster

        // The rosters are untouched: only the dictionary the engine reads has moved.
        #expect(world.roster(of: team).first == original)
        #expect(WorldChecksum.of(rebuilt(world, players: players)) != WorldChecksum.of(world))
    }

    /// A depth chart is a partition of the same men, and the partition is what the lineup
    /// reads. Concatenating the positions without saying how long each one is makes a
    /// man moved from the tail of one position to the head of the next invisible: the
    /// flattened sequence is identical, and the chart is a different chart.
    @Test("contract: the checksum moves when a depth chart is repartitioned over the same men")
    func depthChartPartitionIsRead() throws {
        let world = try generated()
        let team = world.teams[0].id
        let original = world.depthChart(of: team)

        let occupied = Position.allCases.filter { !original[$0].isEmpty }
        try #require(occupied.count > 1)
        let moved = try #require(original[occupied[0]].last)
        var chart = original
        chart[occupied[0]].removeLast()
        chart[occupied[1]].insert(moved, at: 0)

        // Same men, same order when the positions are laid end to end. Only the
        // boundaries moved.
        let flattened = { (one: DepthChart) in Position.allCases.flatMap { one[$0] } }
        #expect(flattened(chart) == flattened(original))

        var charts: [TeamID: DepthChart] = [:]
        for one in world.teams { charts[one.id] = world.depthChart(of: one.id) }
        charts[team] = chart
        #expect(WorldChecksum.of(rebuilt(world, charts: charts)) != WorldChecksum.of(world))
    }

    @Test("unit: hex is sixteen zero-padded digits")
    func hexIsPadded() {
        #expect(WorldChecksum.hex(0) == "0000000000000000")
        #expect(WorldChecksum.hex(255) == "00000000000000ff")
        #expect(WorldChecksum.hex(UInt64.max) == "ffffffffffffffff")
    }

    /// Two fields that meet at a boundary must not be able to slide into each other: a
    /// checksum that concatenated its strings would give the same number to a team called
    /// "Aurora King" playing at "sville Field" as to "Aurora Kings" at "ville Field".
    @Test("unit: adjacent strings cannot slide into one another")
    func stringsAreTerminated() {
        var slid = WorldChecksum()
        slid.mix("Aurora King")
        slid.mix("sville Field")

        var apart = WorldChecksum()
        apart.mix("Aurora Kings")
        apart.mix("ville Field")

        #expect(slid.value != apart.value)
    }
}
