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

    /// One snap the resolver has finished with: what it was asked, what came out, and
    /// what it decided on the way.
    typealias Resolution = (situation: Situation, outcome: Outcome, decisions: [DecisionPoint])

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

    // MARK: - The shared corpus

    /// The corpus of games every sampling suite reads: one game per seed between the
    /// league's first two clubs, each stamped with its seed as its identifier.
    ///
    /// Six suites were reading the same forty games — same seeds, same clubs, same
    /// identifiers — and each was paying to simulate them, because every one built its own
    /// `static let sample`. A game is a pure function of its setup, so the second playing
    /// cannot tell anybody anything the first did not. This is played once, whoever asks
    /// first, and everybody else reads it.
    ///
    /// **A test that means to check replay must call `game` instead.** That is the whole
    /// of the difference between the two: `game` simulates, and this remembers. A
    /// determinism test served from a shared value compares it with itself and passes
    /// whatever the engine does.
    ///
    /// **Forty games, and the number is derived rather than chosen.** The rarest thing any
    /// suite asserts over this corpus is a two-point conversion *scored*, which the engine
    /// produces sixteen times in the first eighty of these games — a fifth of a game — so
    /// forty expect eight and miss altogether about three times in ten thousand. The
    /// next-rarest are a defensive touchdown (0.31 a game, twelve and a half expected) and
    /// a two-point run being called at all (0.25 a game, ten expected). Anything rarer
    /// than that does not belong in a sample and is asserted against a fixture that forces
    /// it: the safety is the one that came up, at 0.075 a game, where forty games miss one
    /// time in twenty.
    ///
    /// A suite that wants fewer takes a prefix — the games are the same games — and says
    /// in its own comment why the number it takes is enough for what it asks.
    ///
    /// Measured over seeds 1...80 of this corpus on the tree this was written against.
    static let corpus: [GameResult] = (UInt64(1)...40).map { game(seed: $0, game: GameID($0)) }

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

    /// The situation a snap of `concept` is taken from, in the terms the crude engine
    /// resolves it in: the try spots for the two tries, the free-kick line for a kick,
    /// fourth down for a punt and a field goal, and first and ten at midfield for
    /// everything from scrimmage.
    ///
    /// **Exhaustive with no `default`, deliberately.** A free kick that falls through to
    /// the scrimmage case is set up at midfield on first and ten against a base package,
    /// and every sweep over the concepts then measures the wrong play without saying so.
    static func situation(for concept: PlayConcept, rules: Rules = .standard) -> Situation {
        let ballOn: UInt8
        let down: Down
        let distance: UInt8
        switch concept {
        case .kickoff, .onsideKick, .deepKickoff:
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
        case .twoPointPass, .twoPointRun:
            ballOn = rules.twoPointSnapYard
            down = .first
            distance = max(1, rules.twoPointSnapYard)
        case .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen,
            .playAction, .kneel, .spike:
            ballOn = 50
            down = .first
            distance = rules.yardsToGain
        }
        return Situation(
            quarter: 4, clockRemaining: 300, down: down, distance: distance, ballOn: ballOn,
            possession: TeamID(1), offensePersonnel: .eleven,
            defensePackage: concept.kind == .twoPointConversion || concept == .extraPoint
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
        rules: Rules = .standard,
        offense: OffensiveCall? = nil,
        defense: DefensiveCall? = nil,
        from spot: Situation? = nil
    ) -> [Resolution] {
        let (_, chart, players) = team(seed: worldSeed)
        let rotation = chart.rotation()
        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: rules)
        let situation = spot ?? situation(for: concept, rules: rules)
        let calls = Calls(
            offense: offense ?? OffensiveCall(concept: concept),
            defense: defense
                ?? (concept.kind == .twoPointConversion ? .goalLineStop : .baseCoverThree),
            offensiveCaller: .coordinator(PersonnelID(1)), defensiveCaller: .automatic)

        var random = SplittableRandom(seed: seed)
        var resolutions: [Resolution] = []
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

    // MARK: - The forced draw

    /// Every cell of the coverage sweep, and the reason each one is in it.
    ///
    /// A coverage question — *can the engine produce this at all* — is not a question
    /// about games, and a batch of games is a poor instrument for it: what a game reaches
    /// depends on what its caller happened to call and how the field happened to fall, so
    /// a case that is reachable one snap in a thousand turns up or does not according to
    /// the draw. Widening the batch moves the coin flip without settling it, and the
    /// batch was widened three times before anybody said so out loud.
    ///
    /// So the sweep *constructs* the conditions instead. Each cell names a down the
    /// engine has to be able to play, and a case that no cell reaches is a case the
    /// engine cannot produce — which is a finding and not a resample.
    ///
    /// What this deliberately does **not** cover is whether a caller ever calls a
    /// concept in a real game. That is the other half of the join, and it is asserted
    /// where a caller is: `SchemaAndConceptTests.conceptAgreesWithTheOutcome` walks the
    /// standard corpus and requires every concept in the book to have been called.
    static func coverageSweep() -> [Resolution] {
        var swept: [Resolution] = []

        // Every concept from its own spot, which is where most of the vocabulary lives:
        // the kinds, the endings a play from scrimmage and a kick have, the positions a
        // grouping puts on the field, and the roles they are credited in. Two hundred and
        // fifty of each, which is enough for the exits that a concept reaches a few per
        // cent of the time — the resolver's rarest per-snap branches are asserted against
        // their own draw instead, and do not depend on this number.
        for concept in PlayConcept.allCases {
            swept += resolved(concept, count: 250)
        }

        // Backed up against his own goal line, where a play from scrimmage that loses
        // yardage ends in the end zone. Nothing anywhere else on the field can end
        // `.safety`, so a sweep taken from midfield alone would report the ending
        // unreachable. Measured from the one: 38% of inside runs and 8% of medium passes
        // come back a safety, so 250 of each is a hundred-odd of them.
        let ownGoalLine = Situation(
            quarter: 2, clockRemaining: 600, down: .second, distance: 10, ballOn: 99,
            possession: TeamID(1))
        for concept in [PlayConcept.insideRun, .mediumPass] {
            swept += resolved(concept, count: 250, from: ownGoalLine)
        }

        // Man coverage, because a coverage technique is recorded from the call: every
        // cell above is a zone call, and off-man is only written when somebody is asked
        // to play man. The blitz is in the same cell because the two travel together in
        // the presets and neither is what is being counted.
        for concept in [PlayConcept.quickPass, .mediumPass, .deepPass] {
            swept += resolved(concept, count: 250, defense: .manFreeBlitz)
        }

        // Punts, at volume, for the one foul the resolver draws itself rather than
        // through `Penalties`: a cover man touching a punt before the returner does.
        // It needs a kick the receivers let go — about a third of punts from this spot —
        // and then a 1.8% roll, which measured out at a quarter of a per cent per punt
        // over the cells above. Four thousand expect ten of them and see none about one
        // time in twenty thousand; four hundred expect one, which is the coin flip this
        // sweep exists to stop.
        swept += resolved(.punt, count: 4_000)

        return swept
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
