import FMCore
import FMRandom

/// Everything a resolver needs to know about who is playing.
///
/// Deliberately not the whole world: a resolver gets the two teams' personnel and the
/// rules, and nothing about standings, contracts or history. A resolver that needed the
/// league table to decide a play would be authoring outcomes rather than resolving them.
public struct PlayContext: Sendable {

    public let offense: TeamID
    public let defense: TeamID
    /// Who is on the field for each side, already filtered for availability.
    public let offenseRotation: [DepthChart.Rotation]
    public let defenseRotation: [DepthChart.Rotation]
    /// Every player either team might use, by identifier.
    public let players: [PlayerID: Player]
    public let offenseScheme: TeamScheme
    public let defenseScheme: TeamScheme
    /// How loud it is, 0–100, and whether the offence is the visiting team.
    ///
    /// Home field advantage is a **mechanism** rather than a bonus: noise raises the
    /// visiting offence's pre-snap penalties, drives stall, and the advantage falls out
    /// ([penalties.md](../../../../docs/penalties.md)).
    public let crowdNoise: UInt8
    /// Thin air carries a kick. Generated for every stadium since the world existed, and
    /// until now it reached no game.
    public let altitudeFeet: Int16
    /// The conditions. On the context and not on the situation, because facts about the
    /// afternoon belong to the game, not to the down: the game's result carries them once
    /// for whoever reads the stream, and this is where the resolver reads them.
    public let weather: WeatherState
    public let offenseIsHome: Bool
    /// Whether the clock is running into this snap.
    ///
    /// A pre-snap fact both callers need and neither can derive: the same down and
    /// distance is a different problem depending on whether the huddle is free. It is
    /// what separates spiking the ball from simply running the next play.
    public let clockIsRunning: Bool
    /// The play clock in force before this snap (2025 rulebook, 4-6).
    ///
    /// Which clock it is — forty from the end of the play, twenty-five from the whistle
    /// after a change of possession — is a rule, so the rules layer supplies it. A
    /// resolver that lets it expire is then reporting a fact about the clock, not
    /// drawing a rate.
    public let playClock: PlayClock
    /// Whether that clock has run out with the ball not snapped, so the ball stays dead
    /// and the whistle is the foul (2025 rulebook, 4-6-4).
    ///
    /// Decided before this snap and above the resolver, because stopping the clock
    /// first is a decision somebody makes: a charged timeout leaves the game clock
    /// waiting for the snap it was already waiting for (4-3-2), and a bench that cannot
    /// see the flag coming is guessing rather than choosing. What is left for a
    /// resolver is to report it.
    public let playClockExpired: Bool
    /// Whether the offence comes to this snap out of a charged timeout, either side's
    /// (2025 rulebook, 4-5-1).
    ///
    /// A timeout is a stoppage for the benches to talk, and the offence stands through
    /// it with the ball: what a huddle is for has already happened by the time the
    /// twenty-five seconds of 4-6-3-a start. Every other administrative stoppage on that
    /// list is the officials' business rather than the offence's, and a change of
    /// possession puts a side on the field that has prepared nothing — which is why the
    /// short clock after one is the tightest interval in the game.
    public let offenseIsSetFromATimeout: Bool
    /// Each player's day, in rating points, fixed for the whole game.
    ///
    /// A game-level fact, so it is computed once and read here rather than drawn per
    /// play. See `Form` for why a resolver without it cannot produce a record.
    public let form: [PlayerID: Double]
    public let rules: Rules

    public init(
        offense: TeamID,
        defense: TeamID,
        offenseRotation: [DepthChart.Rotation],
        defenseRotation: [DepthChart.Rotation],
        players: [PlayerID: Player],
        offenseScheme: TeamScheme,
        defenseScheme: TeamScheme,
        crowdNoise: UInt8 = 50,
        altitudeFeet: Int16 = 0,
        weather: WeatherState = .clear,
        offenseIsHome: Bool = true,
        clockIsRunning: Bool = false,
        playClock: PlayClock? = nil,
        playClockExpired: Bool = false,
        offenseIsSetFromATimeout: Bool = false,
        form: [PlayerID: Double] = [:],
        rules: Rules
    ) {
        self.crowdNoise = crowdNoise
        self.altitudeFeet = altitudeFeet
        self.weather = weather
        self.offenseIsHome = offenseIsHome
        self.clockIsRunning = clockIsRunning
        self.playClock = playClock ?? rules.playClockAfterAPlay
        self.playClockExpired = playClockExpired
        self.offenseIsSetFromATimeout = offenseIsSetFromATimeout
        self.form = form
        self.offense = offense
        self.defense = defense
        self.offenseRotation = offenseRotation
        self.defenseRotation = defenseRotation
        self.players = players
        self.offenseScheme = offenseScheme
        self.defenseScheme = defenseScheme
        self.rules = rules
    }

    public func player(_ id: PlayerID) -> Player? { players[id] }

    /// A player's rating as generated: no scheme on it, no day.
    ///
    /// A generated player carries every key, so one he lacks means a hand-built player
    /// and a mistake to catch — in debug an assertion naming him and the key, in release
    /// `Ratings.untrainedFloor`, a man who has never done the thing. It used to be his
    /// overall, which made a back's route running his overall and let the best receiver
    /// in the league bring an 83 run block to a tight end slot.
    public func rating(_ key: RatingKey, of player: Player) -> Double {
        guard let value = player.ratings[key] else {
            assertionFailure(
                "\(player.name.given) \(player.name.family) (\(player.position)) carries no \(key)"
            )
            return Double(Ratings.untrainedFloor)
        }
        return Double(value)
    }

    /// A player's effective rating today: what he is, how he fits what he is being
    /// asked to do, and what kind of day he is having.
    ///
    /// Scheme fit is the piece an earlier version left out entirely — the resolver never
    /// mentioned a scheme, so a player in a system built around him performed exactly as
    /// he would in one that wasted him. That made `SchemeFit` an elaborate no-op and
    /// removed the whole reason a team has an identity.
    ///
    /// An identifier the context has no player for reads as an ordinary player: a slot
    /// nobody is standing in is a hole in a lineup, and a play can be resolved around
    /// one. That is a different case from a key the player lacks, which `rating(_:of:)`
    /// catches — and it is read first, so that the complaint names him.
    public func effective(_ key: RatingKey, for id: PlayerID?, onOffense: Bool) -> Double {
        guard let id, let player = players[id] else { return 60 }
        let base = rating(key, of: player)
        let scheme = onOffense ? offenseScheme : defenseScheme
        // Fit moves a player a few points either way, which is enough to matter over a
        // season without overturning talent.
        let fit = Double(player.schemeFit(scheme)) * 0.35
        return base + fit + (form[id] ?? 0)
    }
}

extension PlayContext {

    /// What the play clock in force reads when an offence playing at `tempo` means to
    /// snap.
    ///
    /// The tempo is everything the offence has to fit into the interval: getting the
    /// call in, breaking the huddle, lining up (`Tempo.secondsBetweenSnaps` — a model,
    /// not a rule). An offence that comes to the snap out of a charged timeout has done
    /// all but the last of that while the clock was stopped, so what is left of the
    /// twenty-five seconds 4-6-3-a puts on the clock is the time it takes to line up,
    /// which is the interval a hurry-up offence works in. The book fixes how long the
    /// clock is; how ready the offence is when it starts is the model's to say.
    ///
    /// One definition, because two readers need the same answer: the draw that decides
    /// whether the offence is beaten by the clock, and the `.playClock` decision point
    /// the rules layer writes onto the record. A record that said one thing while the
    /// draw used another would describe a game that did not happen.
    public static func remainingAtIntendedSnap(
        _ playClock: PlayClock, at tempo: Tempo, setFromATimeout: Bool
    ) -> UInt8 {
        playClock.remainingAtIntendedSnap(at: setFromATimeout ? .hurryUp : tempo)
    }

    /// The same, for the snap this context describes.
    public func remainingAtIntendedSnap(at tempo: Tempo) -> UInt8 {
        Self.remainingAtIntendedSnap(
            playClock, at: tempo, setFromATimeout: offenseIsSetFromATimeout)
    }
}

/// The seam between the sport's rules and the physics
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
///
/// A resolver answers one question — *what happened on this snap* — and knows nothing
/// about clocks, downs, possession or scoring. Those are rules, they live in
/// `GameSimulator`, and they are written once for both the crude resolver and the
/// spatial one that replaces it at M5.
///
/// **The contract that matters**: the `Outcome` and the `DecisionPoint`s must describe
/// the same play. If the decisions report pressure at 2.1 seconds and a sack, the sack
/// is credited to that rusher. A resolver whose causal chain merely looks plausible
/// would let the analysis layer appear to work while reading noise, which is the named
/// risk of building M2 against scaffolding.
public protocol PlayResolver: Sendable {

    /// Resolve one snap.
    ///
    /// - Parameters:
    ///   - situation: the state before the ball is snapped.
    ///   - calls: what each side chose.
    ///   - onField: the twenty-two men standing there, by slot. Who plays is
    ///     substitution, which the game decides and the record carries; the resolver
    ///     is handed the eleven a side and asks nothing about who else was available.
    ///   - context: the rotations, the rules in force, and the conditions.
    ///   - random: the play's own stream, already split from the game's seed.
    /// - Returns: the outcome and the decision points that explain it.
    func resolve(
        situation: Situation,
        calls: Calls,
        onField: Lineup,
        context: PlayContext,
        random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint])

    /// Whether the offence is beaten by the play clock in force: it does not get the
    /// ball snapped inside the interval the book gives it (2025 rulebook, 4-6-1, 4-6-2).
    ///
    /// Asked **before** the snap and before the benches are asked for a timeout, because
    /// the timeout is the answer to it: a charged timeout stops the clock (4-3-2), and a
    /// bench asked after the flag has flown is not being asked anything. What the answer
    /// costs — five yards and the down replayed (4-6-4, 14-4-1) — is the rules layer's,
    /// which is why this returns a fact about the interval and not an `Outcome`.
    ///
    /// How punctual an offence is belongs here rather than in the rules layer for the
    /// same reason a false start does: it is a property of the eleven men and the tempo
    /// they are being asked to play at. A resolver that does not model the interval
    /// leaves it alone and every snap is taken.
    func overrunsThePlayClock(
        situation: Situation,
        calls: Calls,
        context: PlayContext,
        random: inout SplittableRandom
    ) -> Bool
}

extension PlayResolver {

    /// A resolver with no model of the interval between downs never loses the play
    /// clock, so every snap it is asked about is one that was taken.
    public func overrunsThePlayClock(
        situation: Situation, calls: Calls, context: PlayContext,
        random: inout SplittableRandom
    ) -> Bool {
        false
    }
}
