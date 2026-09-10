import FMCore
import FMGeneration
import FMRandom
import FMSimulationScenarios

@testable import FMSimulation

/// The world the engine's tests play in.
///
/// The world itself is `ScenarioWorld`, in `FMSimulationScenarios`, because
/// `gamelog --scenario` plays the same games these suites do and a printer that built its
/// own world would be showing a reader something other than what the suite asserts on.
/// What stays here is what only a test wants: a finished game at a seed, and one team's
/// roster.
enum TestWorld {

    static let shape = ScenarioWorld.shape
    static let season = ScenarioWorld.season

    /// The world at a seed, generated once and cached; see `ScenarioWorld`.
    static func world(seed: UInt64) -> WorldGenerator.GeneratedWorld {
        ScenarioWorld.world(seed: seed)
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
        ScenarioWorld.setup(
            seed: seed, game: game, home: homeIndex, away: awayIndex, stadium: stadium,
            weather: weather, rules: rules, isPostseason: isPostseason)
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

    /// The context a single play resolves against, for the tests that want to run one
    /// kind of play many times rather than watch a whole game.
    static func context(
        seed: UInt64, home homeIndex: Int = 0, away awayIndex: Int = 1,
        weather: WeatherState = .clear, rules: Rules = .standard
    ) -> PlayContext {
        let setup = Self.setup(
            seed: seed, home: homeIndex, away: awayIndex, weather: weather, rules: rules)
        return PlayContext(
            offense: setup.home.id,
            defense: setup.away.id,
            offenseRotation: setup.home.rotation(),
            defenseRotation: setup.away.rotation(),
            players: setup.players,
            offenseScheme: setup.home.scheme,
            defenseScheme: setup.away.scheme,
            crowdNoise: setup.stadium.noise,
            altitudeFeet: setup.stadium.altitudeFeet,
            weather: weather,
            rules: rules)
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
