import FMCore
import FMRandom

/// How a team's identity shapes the roster it starts with.
///
/// Two separate effects, and conflating them would be wrong.
///
/// **Where the talent goes.** A power-run club has invested in its line and its
/// back and not in a quarterback; an air-raid club has done the opposite. This
/// moves the *ceiling* a position is generated at, so a run-heavy team does not
/// simply roll a generational passer it would have no idea what to do with.
///
/// **What kind of player.** Within a position, a gap-blocking team's guards are
/// maulers and a zone team's are athletes. This moves the *shape* of the ratings
/// without moving the overall, so both are equally good players who are good at
/// different things.
public enum SchemeIdentity {

    /// Ceiling adjustment in overall points for a position under a scheme.
    ///
    /// Driven mostly by where the scheme's pass/run balance sits, because that
    /// is what a club's investment actually follows. Bounded to a few points:
    /// enough that identity is legible on a roster, not so much that a
    /// run-heavy team cannot employ a good quarterback at all.
    static func ceilingDelta(for position: Position, in scheme: TeamScheme) -> Double {
        let lean = scheme.offense.passLean
        let fromNeutral = lean - 0.55

        switch position {
        case .quarterback:
            return fromNeutral * 30
        case .wideReceiver:
            return fromNeutral * 24
        case .runningBack:
            return -fromNeutral * 22
        case .fullback:
            return -fromNeutral * 26
        case .leftTackle, .rightTackle:
            // Tackles matter in both worlds: protecting a passer, or sealing an
            // edge. The least affected line positions.
            return -fromNeutral * 6
        case .leftGuard, .rightGuard, .center:
            return -fromNeutral * 14
        case .tightEnd:
            // A blocking identity keeps a real tight end; an air raid does not.
            switch scheme.offense.passing {
            case .airRaid: return -2.5
            case .playAction: return 2.5
            default: return 0
            }
        case .edge:
            // A defence that rushes four and covers behind it needs its rushers
            // to win alone.
            return scheme.defense.pressure == .conservative ? 2.5 : 0
        case .defensiveTackle:
            // Somebody has to hold two blockers.
            return scheme.defense.front == .threeMan ? 3.0 : 0
        case .cornerback:
            return scheme.defense.coverage == .manPress ? 3.0 : 0
        case .safety:
            return scheme.defense.coverage == .quartersMatch ? 2.5 : 0
        case .linebacker:
            return scheme.defense.front == .threeMan ? 2.0 : 0
        case .kicker, .punter, .longSnapper:
            return 0
        }
    }

    /// How strongly generated ratings lean toward what a scheme values.
    ///
    /// A team's players fit its scheme because that is who it acquired, not
    /// because the scheme improved them. The bias moves the *shape* of a
    /// player's ratings; his overall is still corrected to the target
    /// afterwards, so fit shows up as a bonus in his own scheme rather than as
    /// free rating points.
    static let fitBias = 9.0

    /// Rating adjustments to bias generation toward a scheme's preferences.
    static func ratingBias(
        for position: Position, in scheme: TeamScheme
    ) -> [RatingKey: Double] {
        SchemeFit.modifiers(for: position, in: scheme).mapValues { $0 * fitBias / 0.1 }
    }
}

extension SchemeIdentity {

    /// A scheme for a team, drawn from the named families.
    public static func scheme(using random: inout SplittableRandom) -> TeamScheme {
        let offense = OffensiveScheme.families[
            Int(random.next(upperBound: UInt64(OffensiveScheme.families.count)))]
        let defense = DefensiveScheme.families[
            Int(random.next(upperBound: UInt64(DefensiveScheme.families.count)))]
        return TeamScheme(offense: offense, defense: defense)
    }

    /// How often a generated team's identity does not suit its roster.
    ///
    /// A run-heavy club with a gifted young passer is a team that ought to
    /// change, and a good AI will. It gives the trade market real logic on day
    /// one, and it is the player's own situation arriving from the other side —
    /// so it is deliberate rather than a generation flaw.
    public static let mismatchProbability = 0.12

    /// The scheme a team plays, and the scheme its roster was actually built
    /// for. Usually the same.
    public struct Identity: Sendable, Hashable {
        /// The scheme the team actually runs.
        public let played: TeamScheme
        /// The scheme its roster suits, which is usually the same one.
        public let builtFor: TeamScheme

        public init(played: TeamScheme, builtFor: TeamScheme) {
            self.played = played
            self.builtFor = builtFor
        }

        public var isMismatched: Bool { played != builtFor }
    }

    public static func identity(using random: inout SplittableRandom) -> Identity {
        let played = scheme(using: &random)
        guard random.nextBool(probability: mismatchProbability) else {
            return Identity(played: played, builtFor: played)
        }
        // The roster was assembled for something else — by a previous regime,
        // or by a draft that did not go to plan.
        var builtFor = scheme(using: &random)
        var attempts = 0
        while builtFor == played && attempts < 8 {
            builtFor = scheme(using: &random)
            attempts += 1
        }
        return Identity(played: played, builtFor: builtFor)
    }
}
