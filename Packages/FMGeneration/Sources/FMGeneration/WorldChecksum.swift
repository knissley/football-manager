import FMCore

/// One number for a whole generated world.
///
/// It exists twice over. `GoldenWorldTests` checks the number against a checked-in
/// constant, so a world that changes shape between two processes — or between two
/// commits — is caught; and `simharness` prints it in its header, so two branches can be
/// asked whether they generate the *same* league without simulating a snap. Those two
/// questions are the same question, so they get the same function: a checksum the goldens
/// pin and a tool prints is a checksum that cannot quietly stop covering something.
///
/// FNV-1a rather than `Hasher`, whose seed is randomised per process — using `Hasher`
/// here would make both callers unable to detect the thing they exist to detect
/// ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md)). Every
/// string is terminated with a byte that cannot appear in UTF-8, so two adjacent fields
/// cannot slide into each other and produce a world's number for a world it is not.
///
/// ## What it covers
///
/// - The seed and the season the world was generated for.
/// - The league: its identifier and name, and every conference and division by
///   identifier, name and membership.
/// - The number of teams and the number of colleges.
/// - Every team, in identifier order: identifier, full name, abbreviation, region,
///   market; the stadium in full — name, capacity, roof, surface, climate, altitude and
///   noise, which is what the weather is drawn from and what the crowd does to a road
///   offence; the scheme it plays, on both sides and every component of each; the
///   strength offset it was drawn at; and the schemes its roster was *built for* against
///   the one it is played in.
/// - Every player on every roster, in roster order: identifier, position and secondary
///   positions, overall and every rating, the whole physical profile, the hidden
///   attributes, traits, roster status, name, college, birth season, first season, the
///   draft record, and his scheme fit against the team's scheme.
/// - Every team's depth chart, position by position.
/// - The draft pipeline, when the world was generated with one: each class's season,
///   strength and prospect roll, and each generated player's identifier, overall and
///   ceiling.
/// - The rivalries, when the world was generated with them: the pair, the origin and
///   every event in the history.
///
/// ## What it does not cover
///
/// Anything that is not *in* the world. The rules in force, the weather drawn for a
/// particular game, the play caller and the resolver are all inputs the caller supplies
/// alongside the world, and a change to any of them leaves this number where it was —
/// which is why `scripts/harness-reach.sh` reads the engine's source trees as well as
/// this checksum before it will say a change cannot reach the harness.
public struct WorldChecksum: Sendable, Hashable {

    /// The FNV-1a 64-bit offset basis and prime.
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x100_0000_01b3

    /// Terminates a string. `0xff` is not a legal UTF-8 byte, so no string's own content
    /// can be mistaken for the end of it.
    private static let stringTerminator: UInt64 = 0xff

    public private(set) var value: UInt64 = WorldChecksum.offsetBasis

    public init() {}

    /// Mix eight bytes, least significant first.
    public mutating func mix(bits: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            value ^= UInt64((bits >> UInt64(shift)) & 0xff)
            value = value &* Self.prime
        }
    }

    public mutating func mix(_ number: some BinaryInteger) {
        mix(bits: UInt64(bitPattern: Int64(number)))
    }

    public mutating func mix(_ flag: Bool) {
        mix(bits: flag ? 1 : 0)
    }

    public mutating func mix(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* Self.prime
        }
        value ^= Self.stringTerminator
        value = value &* Self.prime
    }

    /// A `Double` is mixed by its exact bit pattern, not by a rounding of it: a world
    /// drawn a thousandth of a point differently is a different world. Via `mix(bits:)`
    /// rather than the integer overload, which would trap on a bit pattern with the sign
    /// bit set.
    public mutating func mix(_ value: Double) {
        mix(bits: value.bitPattern)
    }

    // MARK: - The world

    /// The checksum of a generated world. See the type's documentation for what it reads.
    public static func of(_ world: WorldGenerator.GeneratedWorld) -> UInt64 {
        var sum = WorldChecksum()
        sum.mix(world.seed)
        sum.mix(world.season)
        sum.mix(world.league.id.rawValue)
        sum.mix(world.league.name)
        sum.mix(world.teams.count)
        sum.mix(world.colleges.count)

        for conference in world.league.conferences {
            sum.mix(conference.id.rawValue)
            sum.mix(conference.name)
            for division in conference.divisions {
                sum.mix(division.id.rawValue)
                sum.mix(division.name)
                for team in division.teams { sum.mix(team.rawValue) }
            }
        }

        // `world.teams` is ordered by identifier, so this walk is stable.
        for team in world.teams {
            sum.mix(team.id.rawValue)
            sum.mix(team.identity.fullName)
            sum.mix(team.identity.abbreviation)
            sum.mix(team.region.rawValue)
            sum.mix(team.market.rawValue)
            sum.mix(team.stadium)
            sum.mix(team.scheme)
            sum.mix(world.strength(of: team.id).offset)

            // What the roster was assembled for against what the club actually plays.
            // Roughly one club in eight inherited a roster built for something else
            // (decision 214), and that gap is worth points of scheme fit on a snap.
            let identity = world.identity(of: team.id)
            sum.mix(identity != nil)
            sum.mix(identity?.played ?? .balanced)
            sum.mix(identity?.builtFor ?? .balanced)

            for player in world.roster(of: team.id) {
                sum.mix(player, fitting: team.scheme)
            }

            // The depth chart is a projection over the roster, so it is checksummed
            // separately: a chart that stopped agreeing with the overalls would not move
            // any of the numbers above.
            let chart = world.depthChart(of: team.id)
            for position in Position.allCases {
                for id in chart[position] { sum.mix(id.rawValue) }
            }
        }

        for generated in world.draftPipeline {
            sum.mix(generated.draftClass.season)
            sum.mix(generated.draftClass.strength.overall)
            // `byGroup` is a dictionary, so it is walked in the group's own order and
            // never in hash order (rule 2).
            for group in PositionGroup.allCases {
                sum.mix(generated.draftClass.strength.byGroup[group] ?? 0)
            }
            sum.mix(generated.draftClass.prospects.count)
            for prospect in generated.draftClass.prospects {
                sum.mix(prospect.player.rawValue)
                sum.mix(prospect.collegeYear.rawValue)
                sum.mix(prospect.declaration.rawValue)
                sum.mix(prospect.eligibleSeason)
            }
            for player in generated.players {
                sum.mix(player.id.rawValue)
                sum.mix(player.overall)
                sum.mix(player.hidden.ceiling)
            }
        }

        for rivalry in world.rivalries {
            sum.mix(rivalry.pair.lower.rawValue)
            sum.mix(rivalry.pair.higher.rawValue)
            sum.mix(rivalry.origin.rawValue)
            for event in rivalry.history {
                sum.mix(event.season)
                sum.mix(event.kind.rawValue)
                sum.mix(event.aggrievedTeam?.rawValue ?? 0)
            }
        }

        return sum.value
    }

    /// Sixteen lowercase hex digits, zero-padded, so two checksums are the same length
    /// and can be compared by eye as well as by `cmp`.
    public static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }

    // MARK: - Parts of a world

    /// Everything about where the game is played. `climate` and `isIndoors` are what
    /// `WeatherGenerator` draws from and `noise` is what the crowd does to a visiting
    /// offence, so a stadium generator that changed any of them would change a game
    /// without changing a rating.
    mutating func mix(_ stadium: Stadium) {
        mix(stadium.name)
        mix(stadium.capacity)
        mix(stadium.isIndoors)
        mix(stadium.surface.rawValue)
        mix(stadium.climate.rawValue)
        mix(stadium.altitudeFeet)
        mix(stadium.noise)
    }

    /// Every component of both sides, not just the pass lean: a defence that changed
    /// front or coverage is a different defence, and the number has to say so.
    mutating func mix(_ scheme: TeamScheme) {
        mix(scheme.offense.blocking.rawValue)
        mix(scheme.offense.passing.rawValue)
        mix(scheme.offense.passLean)
        mix(scheme.defense.front.rawValue)
        mix(scheme.defense.coverage.rawValue)
        mix(scheme.defense.pressure.rawValue)
    }

    /// A player, and his fit in the scheme his club plays.
    ///
    /// `secondaryPositions` and `hidden.durability` are mixed because the engine reads
    /// them — the first decides whether a man can fill a hole in the lineup, the second
    /// how long he is out when he goes down — and a checksum that skipped them would call
    /// two different leagues the same one.
    mutating func mix(_ player: Player, fitting scheme: TeamScheme) {
        mix(player.id.rawValue)
        mix(player.position.rawValue)
        for position in player.secondaryPositions { mix(position.rawValue) }
        mix(player.secondaryPositions.count)
        mix(player.overall)
        for key in RatingKey.allCases {
            mix(player.ratings[key] ?? 255)
        }
        mix(player.physical.heightInches)
        mix(player.physical.weightPounds)
        mix(player.physical.fortyYardDash)
        mix(player.physical.verticalJump)
        mix(player.physical.broadJump)
        mix(player.physical.threeCone)
        mix(player.physical.benchReps)
        mix(player.hidden.ceiling)
        mix(player.hidden.developmentTrait.rawValue)
        mix(player.hidden.workEthic)
        mix(player.hidden.durability)
        for trait in player.traits { mix(trait.rawValue) }
        mix(player.traits.count)
        mix(player.status.rawValue)
        mix(player.name.given)
        mix(player.name.family)
        mix(player.name.suffix ?? "")
        mix(player.birthSeason)
        mix(player.college.name)
        mix(player.college.profile.rawValue)
        // Draft history is drawn from a substream keyed on the player's identifier, so
        // nothing above would move if it started drawing from the wrong stream, or
        // stopped being drawn at all. It is mixed here for the same reason the depth
        // chart is: a stage the checksum does not read is a stage the golden cannot
        // speak for.
        mix(player.firstSeason)
        mix(player.draft?.season ?? 0)
        mix(player.draft?.round ?? 0)
        mix(player.draft?.pick ?? 0)
        mix(player.draft?.overallPick ?? 0)
        // Scheme fit is the value that was actually wrong: it is a rounded weighted
        // average, and the weighting used to be summed in hash order.
        mix(player.schemeFit(scheme))
    }
}
