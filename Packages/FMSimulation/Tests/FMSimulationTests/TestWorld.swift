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

    /// The situation a snap of `concept` is taken from, in the terms the crude engine
    /// resolves it in: the try spots for the two tries, the free-kick line for a kick,
    /// fourth down for a punt and a field goal, and first and ten at midfield for
    /// everything from scrimmage.
    static func situation(for concept: PlayConcept, rules: Rules = .standard) -> Situation {
        let ballOn: UInt8
        let down: Down
        let distance: UInt8
        switch concept {
        case .kickoff, .onsideKick:
            ballOn = rules.ballOnFromOwnYard(rules.kickoffFromOwnYard)
            down = .first
            distance = rules.yardsToGain
        case .punt:
            ballOn = 65
            down = .fourth
            distance = 8
        case .fieldGoal:
            ballOn = 25
            down = .fourth
            distance = 8
        case .extraPoint:
            ballOn = rules.extraPointSnapYard
            down = .first
            distance = max(1, rules.extraPointSnapYard)
        case .twoPointConversion:
            ballOn = rules.twoPointSnapYard
            down = .first
            distance = max(1, rules.twoPointSnapYard)
        default:
            ballOn = 50
            down = .first
            distance = rules.yardsToGain
        }
        return Situation(
            quarter: 4, clockRemaining: 300, down: down, distance: distance, ballOn: ballOn,
            possession: TeamID(1), offensePersonnel: .eleven,
            defensePackage: concept == .twoPointConversion || concept == .extraPoint
                ? .goalLine : .base)
    }

    /// `count` snaps of `concept`, resolved by the crude resolver against one lineup.
    ///
    /// A whole game is the wrong instrument for a rare exit. An ending that takes a few
    /// per cent of a play that is itself called in a third of games needs hundreds of
    /// games before it appears at all, and a suite that simulates hundreds of games to
    /// see one is a suite nobody runs. This is the same resolver on the same stream,
    /// thousands of times, in a couple of seconds — and it can say what it drew, so a
    /// test over it never passes because the rare thing did not happen.
    static func resolved(
        _ concept: PlayConcept, count: Int, seed: UInt64 = 88, worldSeed: UInt64 = 12,
        rules: Rules = .standard
    ) -> [(situation: Situation, outcome: Outcome, decisions: [DecisionPoint])] {
        let (_, chart, players) = team(seed: worldSeed)
        let rotation = chart.rotation()
        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: rules)
        let situation = situation(for: concept, rules: rules)
        let calls = Calls(
            offense: OffensiveCall(concept: concept),
            defense: concept == .twoPointConversion ? .goalLineStop : .baseCoverThree,
            offensiveCaller: .coordinator(PersonnelID(1)), defensiveCaller: .automatic)

        var random = SplittableRandom(seed: seed)
        var resolutions: [(situation: Situation, outcome: Outcome, decisions: [DecisionPoint])] = []
        resolutions.reserveCapacity(count)
        for _ in 0..<count {
            let onField = Lineup.onField(
                context, concept: concept, situation: situation, random: &random)
            let resolved = CrudeResolver().resolve(
                situation: situation, calls: calls, onField: onField, context: context,
                random: &random)
            resolutions.append((situation, resolved.outcome, resolved.decisions))
        }
        return resolutions
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
