import FMCore
import FMGeneration
import FMRandom
import Synchronization

@testable import FMSimulation

/// The world the engine's tests play in.
///
/// Every suite in here used to assemble its own: twenty colleges, two rosters at the
/// league average from a bare stream, `TeamID(1)` against `TeamID(2)` at a neutral field.
/// Seven copies of it, each subtly different, and none of them the world the game ships —
/// two teams of exactly equal strength never meet in a real league.
///
/// This is `WorldGenerator.generate(seed:shape:season:)`, the same call `worldgen` and the
/// harness make, so a test plays a game between two clubs of drawn strength, with drawn
/// schemes, from a real league.
///
/// `.minimal` — eight teams — because a suite builds a fresh world per seed and a
/// thirty-two team league is four times the generation for two rosters' worth of use. No
/// draft pipeline and no rivalries for the same reason: nothing in a game reads either.
enum TestWorld {

    static let shape = LeagueShape.minimal
    static let season = 2030

    /// A world is a pure function of its seed, so the suites that walk the same seeds over
    /// and over generate each one once. Behind a mutex because Swift Testing runs tests in
    /// parallel; without it, building the world would be the suite's slowest thing.
    private static let cache = Mutex<[UInt64: WorldGenerator.GeneratedWorld]>([:])

    /// The world at a seed. Fails loudly rather than substituting a fallback: a test that
    /// silently played in a different world from the one it names would be worse than a
    /// crash.
    static func world(seed: UInt64) -> WorldGenerator.GeneratedWorld {
        if let cached = cache.withLock({ $0[seed] }) { return cached }
        let generated = WorldGenerator.generate(
            seed: seed, shape: shape, season: season, parts: .teamsAndRosters, collegeCount: 20)
        let built: WorldGenerator.GeneratedWorld
        switch generated {
        case .success(let world):
            built = world
        case .failure(let failure):
            // `.minimal` is a validated preset, so the only way here is a generator bug.
            // Stopping is right: a substituted world would make every suite in here lie.
            fatalError("the test world at seed \(seed) is not a league: \(failure.explanations)")
        }
        cache.withLock { $0[seed] = built }
        return built
    }

    /// A game between two teams of the world at `seed`, by position in the league's
    /// stable order.
    static func setup(
        seed: UInt64,
        game: GameID = GameID(1),
        home homeIndex: Int = 0,
        away awayIndex: Int = 1,
        stadium: Stadium? = nil,
        weather: WeatherState = .clear,
        rules: Rules = .standard,
        isPostseason: Bool = false
    ) -> GameSetup {
        let world = Self.world(seed: seed)
        let home = world.teams[homeIndex]
        let away = world.teams[awayIndex]
        return GameSetup(
            game: game,
            home: GameTeam(
                id: home.id, depthChart: world.depthChart(of: home.id), scheme: home.scheme),
            away: GameTeam(
                id: away.id, depthChart: world.depthChart(of: away.id), scheme: away.scheme),
            players: world.players,
            stadium: stadium ?? home.stadium,
            weather: weather,
            rules: rules,
            seed: seed,
            isPostseason: isPostseason)
    }

    /// A game played by the crude resolver and the baseline caller — what almost every
    /// suite in here wants.
    static func game(
        seed: UInt64,
        game gameID: GameID = GameID(1),
        home: Int = 0,
        away: Int = 1,
        stadium: Stadium? = nil,
        weather: WeatherState = .clear,
        isPostseason: Bool = false
    ) -> GameResult {
        GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(
                setup(
                    seed: seed, game: gameID, home: home, away: away, stadium: stadium,
                    weather: weather, isPostseason: isPostseason))
    }

    /// One team's roster and depth chart, for the tests that need a rotation rather than
    /// a game.
    static func team(
        seed: UInt64, at index: Int = 0
    )
        -> (team: Team, chart: DepthChart, players: [PlayerID: Player])
    {
        let world = Self.world(seed: seed)
        let team = world.teams[index]
        return (team, world.depthChart(of: team.id), world.players)
    }
}
