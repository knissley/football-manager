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

    /// Who, if anyone, was hurt on a play: the play as recorded, the context it was
    /// played in, and the play's own random stream.
    ///
    /// An injury is drawn from the play's participants rather than by the resolver, so
    /// that the model survives the resolver being replaced. It is a seam here for one
    /// reason: a rules scenario has to be able to *dictate* an injury — the injury
    /// timeout after the two-minute warning is a clock rule (2025 rulebook, 4-5-4), and
    /// a rule nobody can script is a rule nobody can watch.
    public typealias InjuryDraw =
        @Sendable (PlayRecord, PlayContext, inout SplittableRandom) ->
        InjuryEvent?

    public let resolver: Resolver
    public let caller: Caller
    public let injuries: InjuryDraw

    /// The engine's own injury draw, from the play's participants (`Injuries`), which
    /// every game takes unless a scenario says otherwise.
    public static var drawnInjuries: InjuryDraw {
        { play, context, random in Injuries.drawn(on: play, context: context, random: &random) }
    }

    public init(
        resolver: Resolver, caller: Caller, injuries: @escaping InjuryDraw = Self.drawnInjuries
    ) {
        self.resolver = resolver
        self.caller = caller
        self.injuries = injuries
    }

    /// A hard ceiling on snaps, so a resolver bug that never advances the ball fails
    /// loudly at the end of a test rather than hanging a season.
    private static var playLimit: Int { 400 }

    /// Whether this free kick is kicked onside: the book has to permit one and the coach
    /// has to want one, in that order.
    ///
    /// The two halves are kept apart on purpose. Whether a team **may** declare is
    /// `Rules.mayDeclareOnsideKick` — at any time during the game, and only while
    /// trailing (2025 rulebook, 6-1-1-c, 6-1-6) — so no caller, present or written later,
    /// can declare one the book does not allow. Whether it **wants** one is the caller's
    /// judgement and nothing else. The gate used to live inside the baseline caller's
    /// judgement as a bare `quarter >= 4`, which meant the rule and the taste were the
    /// same line and every caller inherited a rulebook.
    static func declaresOnsideKick(
        caller: Caller, situation: Situation, classified: SituationClass, rules: Rules
    ) -> Bool {
        rules.mayDeclareOnsideKick(
            quarter: situation.quarter, scoreDifferential: situation.scoreDifferential)
            && caller.kicksOnside(situation: situation, classified: classified)
    }

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
        // A half that opens with one side's first choice of 4-2-2's privileges — the
        // second half, and a third postseason overtime period (16-1-4-e) — puts the
        // choice to that side's caller before its kickoff, and before anything else in
        // the step. A period ends on a play, but also between downs — on an injury
        // timeout's runoff, or on the last-forty-seconds election — and whichever way
        // the half ended, the kick that follows is the next thing this loop builds.
        // Settled after `apply` instead, a half ended between downs had its kick played
        // with the toss loser kicking, and the answer that came a step later handed the
        // ball back to the kicker. The situation is the chooser's: it has the ball to
        // kick off with until it answers.
        if state.firstChoicePending {
            let opening = state.situation()
            state.settleFirstChoice(
                receives: caller.electsToReceive(
                    situation: opening,
                    classified: SituationClass(opening, rules: state.setup.rules)))
        }

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
            let onside = Self.declaresOnsideKick(
                caller: caller, situation: situation, classified: classified,
                rules: state.setup.rules)
            // Three free kicks, and which one this is was called by somebody: the
            // ordinary kick is aimed at the landing zone to be returned, the deep one is
            // struck through the end zone for the touchback, and the onside kick is
            // declared. None of them is the default any more, so none is `.automatic`.
            let family: PlayFamily =
                onside
                ? .onsideKick
                : (caller.kicksForTouchback(situation: situation, classified: classified)
                    ? .deepKickoff : .kickoff)
            calls = Calls(
                offense: CrudePlaybook.call(family),
                defense: .preventShell,
                offensiveCaller: .coordinator(PersonnelID(1)),
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

        let resolved = resolver.resolve(
            situation: situation, calls: calls, context: context, random: &random)

        // A flag before the snap puts two questions to the callers — a timeout instead
        // of the runoff, declining the runoff, the clock's restart — and they are asked
        // here, where the callers are, with the clock as it reads at the flag. The
        // rules layer then uses whichever of the answers the foul makes relevant.
        let deadBall = deadBallChoices(
            for: resolved.outcome, in: state, tempo: calls.offense.tempo)
        state.apply(
            resolved.outcome, calls: calls, decisions: resolved.decisions, deadBall: deadBall)

        // Injuries are drawn from who was involved, after the play is recorded, so the
        // event can point at the snap it happened on. The injury timeout it brings is a
        // clock rule after the two-minute warning (4-5-4), and the choices that rule
        // puts to the callers are asked here, with the situation as it now stands.
        if let play = state.plays.last, let injury = injuries(play, context, &random) {
            state.injuries.append(injury)
            if injury.leavesTheGame { state.hurt.insert(injury.player) }
            if let team = team(of: injury.player, on: play, context: context) {
                let after = state.situation()
                let classified = SituationClass(after, rules: state.setup.rules)
                state.applyInjuryTimeout(
                    injuredTeam: team, on: play,
                    choices: InjuryChoices(
                        defenseTakesRunoff: caller.takesRunoff(
                            forInjuryTimeout: after, classified: classified),
                        offenseStartsClockOnTheSnap: caller.startsClockOnTheSnap(
                            afterDefensiveFoul: after, classified: classified),
                        offenseEndsTheHalf: caller.endsTheHalf(
                            afterDefensiveTimeConservation: after, classified: classified)))
            }
        }
    }

    /// Which team the hurt man plays for: the side of the slot he was credited in, or,
    /// when a scenario hurt somebody it never credited, the rotation he was drawn from.
    private func team(of player: PlayerID, on play: PlayRecord, context: PlayContext) -> TeamID? {
        if let credited = play.outcome.participants.first(where: { $0.player == player }) {
            return credited.slot.isOffense ? context.offense : context.defense
        }
        if context.offenseRotation.contains(where: { $0.player == player }) {
            return context.offense
        }
        if context.defenseRotation.contains(where: { $0.player == player }) {
            return context.defense
        }
        return nil
    }

    /// The callers' answers to a flag before the snap, or `nil` when the play was not one.
    private func deadBallChoices(
        for outcome: Outcome, in state: State, tempo: Tempo
    ) -> DeadBallChoices? {
        guard outcome.kind == .penaltyOnly else { return nil }
        let atTheFlag = state.situationAtTheFlag(
            tempo: tempo, foul: outcome.penalties.first?.foul)
        let classified = SituationClass(atTheFlag, rules: state.setup.rules)
        return DeadBallChoices(
            offenseTakesTimeout: caller.takesTimeoutInsteadOfRunoff(
                situation: atTheFlag, classified: classified),
            defenseDeclinesRunoff: caller.declinesRunoff(
                situation: atTheFlag, classified: classified),
            offenseStartsClockOnTheSnap: caller.startsClockOnTheSnap(
                afterDefensiveFoul: atTheFlag, classified: classified),
            offenseEndsTheHalf: caller.endsTheHalf(
                afterDefensiveTimeConservation: atTheFlag, classified: classified))
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
