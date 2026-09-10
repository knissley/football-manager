import FMCore

/// One franchise, as a hand-written line rather than a draw.
///
/// Everything here is the part of a club that does not change when the seed does: who it
/// is, where it plays, and the building it plays in
/// ([decision 215](../../../../docs/design-decisions.md)). What is *not* here is
/// everything a career is supposed to differ in — the roster, the depth chart, the
/// strength the club was drawn at, the scheme it runs, its draft history and its
/// rivalries — all of which stay seeded draws from their labelled substreams
/// ([decision 212](../../../../docs/design-decisions.md)).
///
/// The stadium's physics come with the franchise. A dome team is a dome team in the way
/// it is called what it is called: it settles the weather its home games are played in,
/// and a weather mix that moves with the seed is most of why the calibration harness
/// could not tell an engine change from a re-roll ([decision 214](../../../../docs/design-decisions.md)).
/// Climate is the *city's*, so a roof still overrides it — see `stadium`.
public struct Franchise: Sendable, Hashable {

    /// Whether the ground has a roof over it. Two cases and not a `Bool`, because the
    /// table below is read by a person: `roof: .dome` says what `isIndoors: true` means.
    public enum Roof: Sendable, Hashable {
        case open
        case dome

        public var isIndoors: Bool { self == .dome }
    }

    public let city: String
    public let region: Region
    public let market: MarketSize
    /// The city's weather. A roofed ground does not play in it — see `stadium`.
    public let climate: Climate
    public let altitudeFeet: Int16
    public let nickname: String
    public let abbreviation: String
    public let colors: TeamColors
    public let stadiumName: String
    public let roof: Roof
    public let surface: PlayingSurface
    public let capacity: Int32
    /// How loud it gets when it matters, 0–100, as the ground actually is: a dome's
    /// figure already includes the roof keeping the noise in, rather than having a bonus
    /// applied to it later.
    public let noise: UInt8

    /// Colours are three packed RGB values so a franchise still reads as one row.
    /// `0x0C_2340` is the navy in `PalettePools`, and hex is what anyone editing a colour
    /// will have in front of them.
    public init(
        city: String,
        region: Region,
        market: MarketSize,
        climate: Climate,
        altitude: Int16,
        nickname: String,
        abbreviation: String,
        primary: UInt32,
        secondary: UInt32,
        accent: UInt32,
        stadium: String,
        roof: Roof,
        surface: PlayingSurface,
        capacity: Int32,
        noise: UInt8
    ) {
        self.city = city
        self.region = region
        self.market = market
        self.climate = climate
        altitudeFeet = altitude
        self.nickname = nickname
        self.abbreviation = abbreviation
        colors = TeamColors(
            primary: TeamColor(rawValue: primary),
            secondary: TeamColor(rawValue: secondary),
            accent: TeamColor(rawValue: accent))
        stadiumName = stadium
        self.roof = roof
        self.surface = surface
        self.capacity = capacity
        self.noise = noise
    }

    public var fullName: String { "\(city) \(nickname)" }

    /// The ground, as the engine reads it.
    ///
    /// A roof settles the weather regardless of where the stadium is, which is why a
    /// domed franchise's climate is the *city's* in the table and `.temperate` here: the
    /// engine must not be able to read a climate for a game the weather cannot reach
    /// ([decision 151](../../../../docs/design-decisions.md)).
    public var stadium: Stadium {
        Stadium(
            name: stadiumName,
            capacity: capacity,
            isIndoors: roof.isIndoors,
            surface: surface,
            climate: roof.isIndoors ? .temperate : climate,
            altitudeFeet: altitudeFeet,
            noise: noise)
    }
}

/// Where a league's franchises come from.
///
/// The curated set is the default and the one a career starts in. The randomiser is
/// [decision 154](../../../../docs/design-decisions.md)'s pool draw, kept behind this
/// option because a random rename is a real feature and a last resort — it is not
/// refined before the pre-release revisit of generation
/// ([M8](../../../../docs/roadmap.md)), and nothing ships from it.
public enum FranchiseSource: Sendable, Hashable {

    /// `FranchiseSet.initial` — the thirty-two below.
    case curated
    /// A curated set of the caller's own. The same path as `.curated`, different data.
    case set([Franchise])
    /// Drawn from the pools in `TeamPools`, ledger and all.
    case randomised

    /// The franchises this source supplies before anything is drawn. Empty for
    /// `.randomised`, which supplies none and has every team drawn instead.
    var franchises: [Franchise] {
        switch self {
        case .curated: return FranchiseSet.initial
        case .set(let franchises): return franchises
        case .randomised: return []
        }
    }
}

/// The thirty-two franchises every world starts from.
///
/// **This is a table, not a generator.** It is meant to be edited by hand — a name that
/// grates, a stadium that should have a roof, a market that should be smaller — and
/// editing it is the supported way to change the league a career starts in
/// ([decision 215](../../../../docs/design-decisions.md)). Rosters are still generated
/// from the seed, so every start is a different league in the same buildings.
///
/// **Fiction only** ([ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md)):
/// no real club's city-and-nickname pair, no real league, team or mark. The vocabulary
/// comes from the same invented places and trades the pools in `TeamPools` are built
/// from; the arrangement is hand-written.
///
/// ## How the order is read
///
/// Eight franchises per region, and a league is dealt from the front of each region in
/// file order: the first conference takes the first franchises of each region, the second
/// takes the next. A league smaller than thirty-two — the `.compact` and `.minimal`
/// shapes tests use — takes fewer from each region and takes them from the top, so the
/// order here is the order in which a franchise is in the league at all.
///
/// A shape that wants more from a region than there are franchises for it — a
/// sixty-four team league — takes the rest from the randomiser, with everything here
/// already in the name ledger so nothing drawn can collide with it.
public enum FranchiseSet {

    /// Thirty-two franchises: eight north, eight south, eight east, eight west.
    ///
    /// Colours are `PalettePools`' own values as hex — a dark primary against a light
    /// secondary, which is what `TeamColors.hasReadableContrast` asks for.
    public static let initial: [Franchise] = [
        // The table lands in the commit that turns these contracts green.
    ]

    /// The franchises of one region, in file order.
    public static func franchises(in region: Region) -> [Franchise] {
        initial.filter { $0.region == region }
    }
}
