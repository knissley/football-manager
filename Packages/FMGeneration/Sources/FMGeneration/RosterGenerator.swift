import FMCore
import FMRandom

/// Builds the rosters a new career *starts* with.
///
/// **This runs once, at world creation.** It describes the league you inherit —
/// nothing here decides how a roster should be built afterwards. Every later
/// change comes from drafting, signing, trading and cutting, which live in
/// `FMSimulation` and are decisions, not generation.
///
/// The distinction matters for one specific reason. An AI team must reach a
/// roster shape the hard way: under a cap, with imperfect information, through
/// choices it can get wrong. If it borrowed the heuristics below it would be
/// assigning itself ceilings instead of earning them, which is cheating with
/// extra steps. The two share a *target* — `RosterShape` in `FMCore` — and
/// nothing else. See docs/architecture.md.
///
/// The individual-player generator makes believable people; this decides whether
/// they add up to a believable *team*, and whether the league they form has a
/// talent spread that makes some clubs contenders and others not.
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
    /// Describes how real rosters are *shaped* at a moment in time: steep from
    /// starter to backup, then flattening, because the fourth and fifth
    /// receivers on any team are much the same player.
    ///
    /// This is an observation about starting conditions, not a rule about how a
    /// roster ought to be built. Assembling a team with no drop-off behind the
    /// starters, or with a great backup quarterback and nothing else, is a
    /// perfectly legitimate thing for a general manager to do — and generation
    /// has no opinion about it.
    static func ceilingTarget(depth: Int, strength: Strength, position: Position) -> Double {
        let byDepth: Double
        switch depth {
        case 0: byDepth = 80
        case 1: byDepth = 71
        case 2: byDepth = 66
        default: byDepth = 62
        }

        // Better teams differ from worse ones mostly at the top of the depth
        // chart. Everyone's fifth receiver is roughly the same player.
        let strengthShare = depth == 0 ? 1.0 : (depth == 1 ? 0.6 : 0.3)

        // Rosters reflect what positions are worth: a left tackle outranks a
        // fullback by more than the depth chart alone would suggest.
        let premium = (position.positionalValue - 0.35) * 6.0

        return byDepth + strength.offset * strengthShare + premium
    }

    /// Age for a player at a given depth.
    ///
    /// Starters skew toward their prime and depth skews young, because that is
    /// what rosters look like: the spot behind a starter is where a developing
    /// player usually sits. Again a description of the initial league, not a
    /// constraint on what you do with yours.
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
