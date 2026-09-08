import FMCore
import FMRandom

/// Builds a roster.
///
/// The individual-player generator makes believable people; this decides whether
/// they add up to a believable *team* — starters clearly better than backups, an
/// age curve with rookies and veterans in it, and a league whose talent spread
/// makes some teams contenders and others not.
public enum RosterGenerator {

    /// How good a team is meant to be, roughly in overall points either side of
    /// the league's middle.
    ///
    /// Rebuilding teams sit near -8, contenders near +8. The spread across a
    /// league is what produces a believable range of win totals, so it is a
    /// generation input rather than something to hope for.
    public struct Strength: Sendable, Hashable {
        public let offset: Double

        public init(offset: Double) {
            self.offset = offset
        }

        public static let leagueAverage = Strength(offset: 0)
        public static let contender = Strength(offset: 7)
        public static let rebuilding = Strength(offset: -7)
    }

    /// Ceiling for the player at a given depth, before noise.
    ///
    /// The drop from starter to backup is steep and then flattens: the gap
    /// between a starter and his replacement is what makes an injury matter,
    /// while the gap between the fourth and fifth receiver is nearly nothing.
    static func ceilingTarget(depth: Int, strength: Strength, position: Position) -> Double {
        let byDepth: Double
        switch depth {
        case 0: byDepth = 80
        case 1: byDepth = 71
        case 2: byDepth = 66
        default: byDepth = 62
        }

        // Team quality lifts starters most. Everyone's fifth receiver is roughly
        // the same player.
        let strengthShare = depth == 0 ? 1.0 : (depth == 1 ? 0.6 : 0.3)

        // Teams invest where it matters: a good team's left tackle is better
        // than its fullback by more than the depth chart alone suggests.
        let premium = (position.positionalValue - 0.35) * 6.0

        return byDepth + strength.offset * strengthShare + premium
    }

    /// Age for a player at a given depth.
    ///
    /// Starters skew toward their prime and depth skews young, because a roster
    /// spot behind a starter is where teams put players they are developing —
    /// which is also what makes snap share a real decision.
    static func age(
        depth: Int, position: Position, using random: inout SplittableRandom
    ) -> Int {
        let peak = Double(position.group.peakAge)
        let centre: Double
        switch depth {
        case 0: centre = peak
        case 1: centre = peak - 2
        default: centre = peak - 4
        }
        return Rounding.toNearest(centre + random.nextGaussian() * 3.0, clampedTo: 21...38)
    }

    /// A full roster.
    ///
    /// Identifiers come from the supplied sequence so a world numbers its players
    /// in a stable order and regenerates identically.
    public static func roster(
        shape: RosterShape = .standard,
        strength: Strength = .leagueAverage,
        season: Int,
        colleges: [College],
        ids: inout IdentifierSequence<PlayerSubject>,
        using random: inout SplittableRandom
    ) -> [Player] {
        var players: [Player] = []
        players.reserveCapacity(shape.rosterSize)

        for requirement in shape.requirements {
            for depth in 0..<requirement.total {
                let ceiling = ceilingTarget(
                    depth: depth, strength: strength, position: requirement.position)
                let playerAge = age(
                    depth: depth, position: requirement.position, using: &random)

                players.append(
                    PlayerGenerator.player(
                        id: ids.allocate(),
                        position: requirement.position,
                        targetCeiling: UInt8(Rounding.toNearest(ceiling, clampedTo: 45...97)),
                        age: playerAge,
                        season: season,
                        colleges: colleges,
                        using: &random
                    )
                )
            }
        }

        return players
    }

    /// The players a shape expects on the field in base personnel, best first at
    /// each position.
    ///
    /// A convenience for tests and for seeding an initial depth chart; the real
    /// depth chart is a decision the coach makes, not a sort.
    public static func projectedStarters(
        from players: [Player], shape: RosterShape = .standard
    ) -> [Player] {
        var starters: [Player] = []
        for requirement in shape.requirements where requirement.starters > 0 {
            let atPosition =
                players
                .filter { $0.position == requirement.position }
                // Sort by overall, then by identifier so ties never depend on
                // the order players happen to arrive in.
                .sorted { left, right in
                    if left.overall != right.overall { return left.overall > right.overall }
                    return left.id < right.id
                }
            starters.append(contentsOf: atPosition.prefix(requirement.starters))
        }
        return starters
    }
}
