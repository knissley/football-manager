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

    /// Everyone who can take a snap this game, in depth-chart order: every man on the
    /// chart who is available, each once, at the first position he appears. This is the
    /// table `PlayRecord.onField` indexes, so its order is part of what the stream means
    /// and it is fixed before the first kickoff — a man hurt during the game keeps his
    /// index.
    ///
    /// The whole chart and not the rotation, because the rotation is what plays *today*:
    /// a fourth edge rusher has no snap share until the third is hurt, and the moment he
    /// is, next man up puts the fourth on the field. A table built from the pre-game
    /// rotation had no index for him.
    public var roster: [PlayerID] {
        var seen: Set<PlayerID> = []
        return depthChart.positions.flatMap { depthChart[$0] }
            .filter { !unavailable.contains($0) }
            .compactMap { seen.insert($0).inserted ? $0 : nil }
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
    /// Each team's roster for this game, in depth-chart order — the table every play's
    /// `onField` indexes into. `PlayRecord.player(at:rosters:)` reads it, and it is the
    /// one thing about a game a play cannot carry for itself without eight bytes a slot.
    public let rosters: [TeamID: [PlayerID]]
    public let homeScore: Int16
    public let awayScore: Int16
    /// `nil` when the game ended level, which a regular season game may.
    public let winner: TeamID?

    public init(
        game: GameID, plays: [PlayRecord], injuries: [InjuryEvent] = [],
        rosters: [TeamID: [PlayerID]] = [:], homeScore: Int16, awayScore: Int16,
        winner: TeamID?
    ) {
        self.game = game
        self.plays = plays
        self.injuries = injuries
        self.rosters = rosters
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.winner = winner
    }

    /// How many plays each man was on the field for.
    public func snapCounts() -> [PlayerID: Int] {
        plays.snapCounts(rosters: rosters)
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
        //
        // And it is made *once*. Re-spotting the try on every step is how a flag before
        // the snap was recorded and then undone: the enforced spot was overwritten with
        // the standard one before the replay. The decision is asked again only when a
        // defensive foul has moved the ball inside the two.
        if state.pendingTry, state.tryGoesForTwo == nil || state.tryNeedsRedecision {
            let provisional = state.situation()
            state.chooseTry(
                goingForTwo: caller.goesForTwo(
                    situation: provisional, classified: SituationClass(provisional)))
        }

        let context = state.context()

        // Substitution, in the order the sport does it: the offence picks a play, sends
        // out the grouping that runs it — which is public information — and the defence
        // answers what it sees. Both end up on the situation the snap is recorded with,
        // so a tendency report can ask what a team runs from twelve personnel against
        // nickel, a question the stream could not answer at all while every snap of every
        // game was eleven against base.
        var declared: OffensiveCall?
        if !state.pendingKickoff && !state.pendingTry {
            let before = state.situation()
            let call = caller.offensiveCall(
                for: before, classified: SituationClass(before), context: context,
                random: &random)
            state.offensePersonnel = caller.personnel(
                for: CrudePlaybook.family(of: call.design) ?? .insideRun,
                situation: before, classified: SituationClass(before), random: &random)

            let showing = state.situation()
            state.defensePackage = caller.package(
                for: showing, classified: SituationClass(showing), random: &random)
            declared = call
        }

        let situation = state.situation()
        let classified = SituationClass(situation)

        let calls: Calls
        if state.pendingKickoff {
            let onside = caller.kicksOnside(situation: situation, classified: classified)
            calls = Calls(
                offense: CrudePlaybook.call(onside ? .onsideKick : .kickoff),
                defense: .preventShell,
                offensiveCaller: onside ? .coordinator(PersonnelID(1)) : .automatic,
                defensiveCaller: .automatic)
        } else if state.pendingTry {
            calls = tryCalls(goesForTwo: state.tryGoesForTwo ?? false)
        } else {
            calls = Calls(
                offense: declared ?? CrudePlaybook.call(.insideRun),
                defense: caller.defensiveCall(
                    for: situation, classified: classified, context: context, random: &random),
                offensiveCaller: .coordinator(PersonnelID(1)),
                defensiveCaller: .coordinator(PersonnelID(2)))
        }

        // Who stands where, drawn from both rotations against their snap shares. It is
        // drawn here and not in the resolver because substitution is the game's to
        // decide and the record's to carry: the resolver is handed the eleven a side.
        // Drawn immediately before the snap is resolved, so the play's stream is spent
        // in the same order it was when the resolver drew the lineup itself.
        let onField = Lineup.onField(
            context, family: CrudePlaybook.family(of: calls.offense.design) ?? .insideRun,
            situation: situation, random: &random)

        let resolved = resolver.resolve(
            situation: situation, calls: calls, onField: onField, context: context,
            random: &random)

        // A flag before the snap puts two questions to the callers — a timeout instead
        // of the runoff, declining the runoff, the clock's restart — and they are asked
        // here, where the callers are, with the clock as it reads at the flag. The
        // rules layer then uses whichever of the answers the foul makes relevant.
        let deadBall = deadBallChoices(
            for: resolved.outcome, in: state, tempo: calls.offense.tempo)
        state.apply(
            resolved.outcome, calls: calls, decisions: resolved.decisions,
            onField: state.rosterIndices(of: onField), deadBall: deadBall)

        // Injuries are drawn from who was involved, after the play is recorded, so the
        // event can point at the snap it happened on.
        if let play = state.plays.last,
            let injury = Injuries.drawn(on: play, context: context, random: &random)
        {
            state.injuries.append(injury)
            if injury.leavesTheGame { state.hurt.insert(injury.player) }
        }
    }

    /// The callers' answers to a flag before the snap, or `nil` when the play was not one.
    private func deadBallChoices(
        for outcome: Outcome, in state: State, tempo: Tempo
    ) -> DeadBallChoices? {
        guard outcome.kind == .penaltyOnly else { return nil }
        let atTheFlag = state.situationAtTheFlag(tempo: tempo)
        let classified = SituationClass(atTheFlag, rules: state.setup.rules)
        return DeadBallChoices(
            offenseTakesTimeout: caller.takesTimeoutInsteadOfRunoff(
                situation: atTheFlag, classified: classified),
            defenseDeclinesRunoff: caller.declinesRunoff(
                situation: atTheFlag, classified: classified),
            offenseStartsClockOnTheSnap: caller.startsClockOnTheSnap(
                afterDefensiveFoul: atTheFlag, classified: classified))
    }

    /// A try is a decision, not a formality: down eight late, you go for two.
    ///
    /// The call is built from the decision the state already holds, which is the one
    /// the spot was chosen for; asking the caller a second time here could disagree
    /// with where the ball is.
    private func tryCalls(goesForTwo: Bool) -> Calls {
        Calls(
            offense: CrudePlaybook.call(goesForTwo ? .twoPointConversion : .extraPoint),
            defense: .goalLineStop,
            offensiveCaller: goesForTwo ? .coordinator(PersonnelID(1)) : .automatic,
            defensiveCaller: .automatic)
    }
}
