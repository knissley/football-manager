import FMCore
import FMRandom

/// One team, as a game needs it.
public struct GameTeam: Sendable {

    public let id: TeamID
    public let depthChart: DepthChart
    public let scheme: TeamScheme
    /// Anyone who cannot play. Next man up follows from the ordering.
    public let unavailable: Set<PlayerID>

    public init(
        id: TeamID, depthChart: DepthChart, scheme: TeamScheme,
        unavailable: Set<PlayerID> = []
    ) {
        self.id = id
        self.depthChart = depthChart
        self.scheme = scheme
        self.unavailable = unavailable
    }

    public func rotation() -> [DepthChart.Rotation] {
        depthChart.rotation(unavailable: unavailable)
    }
}

/// Everything a game is a pure function of.
///
/// This is `initialState` in the replay tuple: a game re-simulates identically from a
/// setup and a seed ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md)).
public struct GameSetup: Sendable {

    public let game: GameID
    public let home: GameTeam
    public let away: GameTeam
    public let players: [PlayerID: Player]
    /// Where the game is played. Its noise is the mechanism behind home field advantage.
    public let stadium: Stadium
    public let weather: WeatherState
    public let rules: Rules
    public let seed: UInt64
    public let isPostseason: Bool

    public init(
        game: GameID,
        home: GameTeam,
        away: GameTeam,
        players: [PlayerID: Player],
        stadium: Stadium = Stadium(name: "Neutral Field", capacity: 68_000),
        weather: WeatherState = .clear,
        rules: Rules = .standard,
        seed: UInt64,
        isPostseason: Bool = false
    ) {
        self.game = game
        self.home = home
        self.away = away
        self.players = players
        self.stadium = stadium
        self.weather = weather
        self.rules = rules
        self.seed = seed
        self.isPostseason = isPostseason
    }
}

/// What a simulated game produced.
///
/// The play stream is the product; the score is a *query* over it, and is computed here
/// only because the caller almost always wants it
/// ([ADR-0007](../../../../docs/adr/0007-event-stream-contract.md)).
public struct GameResult: Sendable {

    public let game: GameID
    public let plays: [PlayRecord]
    /// Everyone hurt in this game, in the order it happened.
    ///
    /// Returned alongside the stream rather than folded into it: an injury is its own
    /// event stream, and the season layer is what turns "out for three" into a player
    /// missing weeks nine through eleven.
    public let injuries: [InjuryEvent]
    public let homeScore: Int16
    public let awayScore: Int16
    /// `nil` when the game ended level, which a regular season game may.
    public let winner: TeamID?

    public init(
        game: GameID, plays: [PlayRecord], injuries: [InjuryEvent] = [], homeScore: Int16,
        awayScore: Int16, winner: TeamID?
    ) {
        self.game = game
        self.plays = plays
        self.injuries = injuries
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.winner = winner
    }

    public var isTie: Bool { winner == nil }
}

/// Runs a game by the rules, asking a resolver what happened on each snap.
///
/// The rules live here and the physics does not
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)). Swapping the crude
/// resolver for the spatial one at M5 changes what a play produces and nothing about
/// how a game is played.
public struct GameSimulator<Resolver: PlayResolver, Caller: PlayCaller>: Sendable {

    public let resolver: Resolver
    public let caller: Caller

    public init(resolver: Resolver, caller: Caller) {
        self.resolver = resolver
        self.caller = caller
    }

    /// A hard ceiling on snaps, so a resolver bug that never advances the ball fails
    /// loudly at the end of a test rather than hanging a season.
    private static var playLimit: Int { 400 }

    public func simulate(_ setup: GameSetup) -> GameResult {
        var state = State(setup: setup)
        let root = SplittableRandom(seed: setup.seed)

        while !state.isOver && state.plays.count < Self.playLimit {
            // Every play draws from its own stream, split from the game's seed by index.
            // Nothing about play N depends on how many draws play N-1 happened to make,
            // so a change to one resolver's internals cannot shift the rest of the game.
            var random = root.split(UInt64(state.plays.count))
            step(&state, random: &random)
        }

        return state.result()
    }

    // MARK: - One snap

    private func step(_ state: inout State, random: inout SplittableRandom) {
        // Timeouts first, and both sides get asked. They are not plays, so they happen
        // before one and change the situation the callers then read.
        if !state.pendingKickoff && !state.pendingTry {
            for isOffense in [false, true] {
                let before = state.situation()
                guard
                    caller.callsTimeout(
                        for: before, classified: SituationClass(before), isOffense: isOffense,
                        context: state.context())
                else { continue }
                state.spendTimeout(offense: isOffense)
            }
        }

        // A try is snapped from a different yard line depending on which one it is, so
        // the decision has to be made before the situation is built rather than after.
        // It used to be made after, which left every conversion attempt starting from
        // the fifteen and needing fifteen yards: across eight hundred team-games not one
        // of them was ever converted.
        if state.pendingTry {
            let provisional = state.situation()
            state.moveToTrySpot(
                goingForTwo: Self.goesForTwo(
                    situation: provisional, classified: SituationClass(provisional)))
        }

        let situation = state.situation()
        let context = state.context()
        let classified = SituationClass(situation)

        let calls =
            state.pendingKickoff
            ? Calls(
                offense: CrudePlaybook.call(.kickoff), defense: .preventShell,
                offensiveCaller: .automatic, defensiveCaller: .automatic)
            : state.pendingTry
                ? tryCalls(situation: situation, classified: classified, random: &random)
                : Calls(
                    offense: caller.offensiveCall(
                        for: situation, classified: classified, context: context,
                        random: &random),
                    defense: caller.defensiveCall(
                        for: situation, classified: classified, context: context,
                        random: &random),
                    offensiveCaller: .coordinator(PersonnelID(1)),
                    defensiveCaller: .coordinator(PersonnelID(2)))

        let resolved = resolver.resolve(
            situation: situation, calls: calls, context: context, random: &random)

        state.apply(resolved.outcome, calls: calls, decisions: resolved.decisions)

        // Injuries are drawn from who was involved, after the play is recorded, so the
        // event can point at the snap it happened on.
        if let play = state.plays.last,
            let injury = Injuries.drawn(on: play, context: context, random: &random)
        {
            state.injuries.append(injury)
            if injury.leavesTheGame { state.hurt.insert(injury.player) }
        }
    }

    /// A try is a decision, not a formality: down eight late, you go for two.
    ///
    /// The score here is *before* the touchdown has its try, so trailing by two after
    /// scoring means the conversion ties it, and trailing by five means it cuts the lead
    /// to a field goal. Those are the ones worth taking.
    static func goesForTwo(situation: Situation, classified: SituationClass) -> Bool {
        classified.time.isEndgame && situation.scoreDifferential < 0
            && situation.scoreDifferential >= -10
    }

    private func tryCalls(
        situation: Situation, classified: SituationClass, random: inout SplittableRandom
    ) -> Calls {
        let goesForTwo = Self.goesForTwo(situation: situation, classified: classified)
        return Calls(
            offense: CrudePlaybook.call(goesForTwo ? .twoPointConversion : .extraPoint),
            defense: .goalLineStop,
            offensiveCaller: goesForTwo ? .coordinator(PersonnelID(1)) : .automatic,
            defensiveCaller: .automatic)
    }
}
