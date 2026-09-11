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
    /// The conditions the game was played in. A fact about the afternoon rather than
    /// about any down, so it is here once and on no play; the resolver read it from its
    /// context, and a consumer of the stream reads it from here.
    public let weather: WeatherState
    public let homeScore: Int16
    public let awayScore: Int16
    /// `nil` when the game ended level, which a regular season game may.
    public let winner: TeamID?

    public init(
        game: GameID, plays: [PlayRecord], injuries: [InjuryEvent] = [],
        rosters: [TeamID: [PlayerID]] = [:], weather: WeatherState = .clear,
        homeScore: Int16, awayScore: Int16, winner: TeamID?
    ) {
        self.game = game
        self.plays = plays
        self.injuries = injuries
        self.rosters = rosters
        self.weather = weather
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

    /// The same ceiling on snaps attempted rather than written, which is the one a loop
    /// can always be counted on to reach.
    private static var snapLimit: Int { 2 * playLimit }

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

        // The limit is on snaps *attempted* rather than on downs written, because not
        // every attempt writes one: a period the interval before the snap exhausts ends
        // there with no down (2025 rulebook, 4-8-1), and a loop counted on the record
        // alone would not advance through one. A game reaches the play limit long before
        // this, and every period can lose at most the one down time ran out under.
        var attempts = 0
        while !state.isOver && state.plays.count < Self.playLimit && attempts < Self.snapLimit {
            // Every play draws from its own stream, split from the game's seed by index.
            // Nothing about play N depends on how many draws play N-1 happened to make,
            // so a change to one resolver's internals cannot shift the rest of the game.
            var random = root.split(UInt64(state.plays.count))
            step(&state, random: &random)
            attempts += 1
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
        //
        // Every reason to stop the clock but one is answered here, from the situation
        // alone. The one that is not is the play clock: whether this offence is about to
        // lose it is a fact about the snap rather than about the situation, so it cannot
        // be known until the play is called and the interval drawn, and it is put to the
        // offence further down.
        var timeoutTaken = false
        if !state.pendingKickoff && !state.pendingTry {
            for isOffense in [false, true] {
                let before = state.situation()
                guard
                    caller.callsTimeout(
                        for: before, classified: SituationClass(before), isOffense: isOffense,
                        context: state.context())
                else { continue }
                timeoutTaken = state.takeTimeout(offense: isOffense) || timeoutTaken
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
                for: call.concept, situation: before, classified: SituationClass(before),
                random: &random)

            let showing = state.situation()
            state.defensePackage = caller.package(
                for: showing, classified: SituationClass(showing), random: &random)
            declared = call
        } else if state.pendingTry, state.tryGoesForTwo == true, state.tryRuns == nil {
            // A conversion is a scrimmage down, so it is substituted for like one: the
            // offence sends out a grouping from the two and then decides whether to throw
            // it or hand it off (11-3-1 allows either), and the defence answers with its
            // goal-line eleven. Decided once, with the spot, for the reason A7 made the
            // spot a single decision: a try replayed after a flag is the same try.
            let before = state.situation()
            let personnel = caller.personnel(
                for: .insideRun, situation: before, classified: SituationClass(before),
                random: &random)
            var showing = before
            showing.offensePersonnel = personnel
            state.chooseTryPlay(
                runs: caller.runsTheTwoPointTry(
                    situation: showing, classified: SituationClass(showing), random: &random),
                personnel: personnel)
        }

        // The package a defence has on the field is the package its call names. They are
        // the same eleven, and ADR-0010 makes their agreement a testable property of the
        // record — it holds both by value so a reader years later can ask what was
        // called. Of the two ways to make them agree, the substitution wins over the
        // preset's label: `caller.package(for:)` is a decision made after seeing the
        // offence's personnel, while the package on a named call is a default carried
        // along by a convenience layer over the composition. Filtering the preset list by
        // package would also collapse the menu — `goalLineStop` is the only goal-line
        // call there is, so every goal-line snap would be the same call.
        if state.pendingKickoff {
            state.defensePackage = DefensiveCall.preventShell.package
        } else if state.pendingTry {
            state.defensePackage = DefensiveCall.goalLineStop.package
        }

        var situation = state.situation()
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
            let concept: PlayConcept =
                onside
                ? .onsideKick
                : (caller.kicksForTouchback(situation: situation, classified: classified)
                    ? .deepKickoff : .kickoff)
            calls = Calls(
                offense: OffensiveCall(concept: concept),
                defense: .preventShell,
                offensiveCaller: .coordinator(PersonnelID(1)),
                defensiveCaller: .automatic)
        } else if state.pendingTry {
            calls = tryCalls(
                goesForTwo: state.tryGoesForTwo ?? false, runs: state.tryRuns ?? false)
        } else {
            var defense = caller.defensiveCall(
                for: situation, classified: classified, context: context, random: &random)
            defense.package = state.defensePackage
            calls = Calls(
                offense: declared ?? OffensiveCall(concept: .insideRun),
                defense: defense,
                offensiveCaller: .coordinator(PersonnelID(1)),
                defensiveCaller: .coordinator(PersonnelID(2)))
        }

        // The play clock, and the one thing that beats it.
        //
        // Whether the offence gets this snap away inside the interval the book gives it
        // (4-6-1, 4-6-2) is asked once the play is called, because the tempo it means to
        // play at is half the answer. It is asked **before** the offence is given its
        // chance to stop the clock, because that chance is what a bench actually has: a
        // charged timeout stops the play clock (4-3-2) and the down is played, and with
        // no timeout spent the ball stays dead for five yards (4-6-4). Drawn beside the
        // down instead — which is where it used to be — the flag was a rate nothing
        // could answer, and a timeout spent to avoid one bought nothing at all.
        //
        // Neither a free kick nor a try puts the question to a bench: a flag on one is
        // still a flag, but the timeout that answers a play clock is the offence's to
        // spend on a scrimmage down. And the offence is asked only if it has not already
        // stopped the clock for some other reason this interval, since a clock cannot be
        // stopped twice.
        var expired = resolver.overrunsThePlayClock(
            situation: situation, calls: calls, context: context, random: &random)
        if expired, !state.pendingKickoff, !state.pendingTry, !timeoutTaken,
            caller.callsTimeout(
                for: situation, classified: classified, isOffense: true,
                context: state.context(playClockExpired: true)),
            state.takeTimeout(offense: true)
        {
            expired = false
            // The timeout is charged, so the situation the snap is recorded with and the
            // clock it is taken against have both moved.
            situation = state.situation()
        }
        let atTheSnap = state.context(playClockExpired: expired)

        // Who stands where, drawn from both rotations against their snap shares. It is
        // drawn here and not in the resolver because substitution is the game's to
        // decide and the record's to carry: the resolver is handed the eleven a side.
        // Drawn immediately before the snap is resolved, so the play's stream is spent
        // in the same order it was when the resolver drew the lineup itself.
        let onField = Lineup.onField(
            atTheSnap, concept: calls.offense.concept, situation: situation, random: &random)

        let resolved = resolver.resolve(
            situation: situation, calls: calls, onField: onField, context: atTheSnap,
            random: &random)

        // A flag before the snap puts two questions to the callers — a timeout instead
        // of the runoff, declining the runoff, the clock's restart — and they are asked
        // here, where the callers are, with the clock as it reads at the flag. The
        // rules layer then uses whichever of the answers the foul makes relevant.
        let deadBall = deadBallChoices(
            for: resolved.outcome, in: state, tempo: calls.offense.tempo)
        // How many downs the game had written before this one. A down the clock never
        // reached is not written at all — the interval between downs can exhaust the
        // period, and the period then ends with nothing snapped (2025 rulebook, 4-8-1) —
        // and the injury draw below has to know, or it draws a second injury on the last
        // down that *was* played.
        let recorded = state.plays.count
        state.apply(
            resolved.outcome, calls: calls, decisions: resolved.decisions,
            onField: state.rosterIndices(of: onField), deadBall: deadBall)

        // Injuries are drawn from who was involved, after the play is recorded, so the
        // event can point at the snap it happened on. The injury timeout it brings is a
        // clock rule after the two-minute warning (4-5-4), and the choices that rule
        // puts to the callers are asked here, with the situation as it now stands.
        if state.plays.count > recorded, let play = state.plays.last,
            let injury = injuries(play, context, &random)
        {
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
    /// with where the ball is. Whether the conversion is thrown or carried is the
    /// caller's second decision (11-3-1), and the concept carries it so the record says
    /// which play was called rather than leaving it to be inferred from who was credited.
    private func tryCalls(goesForTwo: Bool, runs: Bool) -> Calls {
        let concept: PlayConcept = goesForTwo ? (runs ? .twoPointRun : .twoPointPass) : .extraPoint
        return Calls(
            offense: OffensiveCall(concept: concept),
            defense: .goalLineStop,
            offensiveCaller: goesForTwo ? .coordinator(PersonnelID(1)) : .automatic,
            defensiveCaller: .automatic)
    }
}
