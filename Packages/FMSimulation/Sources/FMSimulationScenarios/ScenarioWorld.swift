import FMCore
import FMGeneration
import FMRandom
import FMSimulation
import Synchronization

/// The world a scripted scenario plays in.
///
/// Every suite in the engine used to assemble its own: twenty colleges, two rosters at the
/// league average from a bare stream, `TeamID(1)` against `TeamID(2)` at a neutral field.
/// Seven copies of it, each subtly different, and none of them the world the game ships —
/// two teams of exactly equal strength never meet in a real league.
///
/// This is `WorldGenerator.generate(seed:shape:season:)`, the same call `worldgen` and the
/// harness make, so a scenario plays a game between two clubs of drawn strength, with
/// drawn schemes, from a real league.
///
/// `.minimal` — eight teams — because a suite builds a fresh world per seed and a
/// thirty-two team league is four times the generation for two rosters' worth of use. No
/// draft pipeline and no rivalries for the same reason: nothing in a game reads either.
///
/// It lives in the library rather than in the test target so that the tests and
/// `gamelog --scenario` play the *same* game: a printer that built its own world would be
/// showing a reader something other than what the suite asserts on.
public enum ScenarioWorld {

    public static let shape = LeagueShape.minimal
    public static let season = 2030

    /// A world is a pure function of its seed, so the callers that walk the same seeds over
    /// and over generate each one once. Behind a mutex because Swift Testing runs tests in
    /// parallel; without it, building the world would be the suite's slowest thing.
    private static let cache = Mutex<[UInt64: WorldGenerator.GeneratedWorld]>([:])

    /// The world at a seed. Fails loudly rather than substituting a fallback: a caller that
    /// silently played in a different world from the one it names would be worse than a
    /// crash.
    public static func world(seed: UInt64) -> WorldGenerator.GeneratedWorld {
        if let cached = cache.withLock({ $0[seed] }) { return cached }
        let generated = WorldGenerator.generate(
            seed: seed, shape: shape, season: season, parts: .teamsAndRosters, collegeCount: 20)
        let built: WorldGenerator.GeneratedWorld
        switch generated {
        case .success(let world):
            built = world
        case .failure(let failure):
            // `.minimal` is a validated preset, so the only way here is a generator bug.
            // Stopping is right: a substituted world would make every scenario lie.
            fatalError(
                "the scenario world at seed \(seed) is not a league: \(failure.explanations)")
        }
        cache.withLock { $0[seed] = built }
        return built
    }

    /// A game between two teams of the world at `seed`, by position in the league's
    /// stable order.
    public static func setup(
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
}
