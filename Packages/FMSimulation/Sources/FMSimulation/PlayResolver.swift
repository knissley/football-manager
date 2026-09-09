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
    public let rules: Rules

    public init(
        offense: TeamID,
        defense: TeamID,
        offenseRotation: [DepthChart.Rotation],
        defenseRotation: [DepthChart.Rotation],
        players: [PlayerID: Player],
        offenseScheme: TeamScheme,
        defenseScheme: TeamScheme,
        rules: Rules
    ) {
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
    ///   - context: who is on the field, and the rules in force.
    ///   - random: the play's own stream, already split from the game's seed.
    /// - Returns: the outcome and the decision points that explain it.
    func resolve(
        situation: Situation,
        calls: Calls,
        context: PlayContext,
        random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint])
}
