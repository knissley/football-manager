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

    /// What the league these franchises play in is called, or `nil` where the source has
    /// no name of its own and the pools supply one.
    ///
    /// Both curated sources answer with the table's name. A hand-written set is a league
    /// somebody wrote down, and a name that re-rolled with the seed would put back the
    /// per-seed identity [decision 215](../../../../docs/design-decisions.md) exists to
    /// take out — a caller with its own clubs and its own name renames `League.name`,
    /// which is editable like every other name in the world. `.randomised` answers `nil`
    /// and keeps its draw ([#82](https://github.com/knissley/football-manager/issues/82)).
    var leagueName: String? {
        switch self {
        case .curated, .set: return FranchiseSet.leagueName
        case .randomised: return nil
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

    /// The league the thirty-two play in.
    ///
    /// Curated for the reason the clubs are: a career opens in the *same league*, not
    /// merely in the same buildings, and a name that re-rolled with the seed was one
    /// more piece of identity a calibration run could not hold still
    /// ([decision 215](../../../../docs/design-decisions.md)). One line beside the
    /// table, edited by hand like the rest of it. `FranchiseSource.randomised` keeps the
    /// pool draw.
    ///
    /// **Fiction, and reviewed as fiction**
    /// ([ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md), rule 8):
    /// the word names the sprawl of a league whose clubs travel from one coast to the
    /// other, in the same invented register as the cities below. It is no real league's
    /// name and no real club's, its initials are no real league's either, and it claims
    /// nothing national, federal or united — this world has no nation for a league to be
    /// named after. That review is the reason the name is written here rather than drawn
    /// from `StructurePools.leagueNames`, which is as unrefined as the rest of the pools
    /// and holds more than one line that would not survive it.
    ///
    /// No abbreviation: `League` has no field for one, and inventing one nothing reads
    /// would be a second name to keep true. If it acquires one, it is written down here
    /// rather than drawn.
    public static let leagueName = "Overland Football League"

    /// Thirty-two franchises: eight north, eight south, eight east, eight west.
    ///
    /// Colours are `PalettePools`' own values as hex — a dark primary against a light
    /// secondary, which is what `TeamColors.hasReadableContrast` asks for.
    public static let initial: [Franchise] = [

        // MARK: North — hard winters, water and heavy industry

        Franchise(
            city: "Birchford", region: .north, market: .medium, climate: .cold, altitude: 640,
            nickname: "Whiteout", abbreviation: "BRF",
            primary: 0x14_3428, secondary: 0xB0_D278, accent: 0xF0_ECE0,
            stadium: "Northgate Park", roof: .open, surface: .hybrid, capacity: 66_200, noise: 74),
        Franchise(
            city: "Norwold", region: .north, market: .major, climate: .cold, altitude: 320,
            nickname: "Quarrymen", abbreviation: "NRW",
            primary: 0x28_1642, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Centennial Bowl", roof: .dome, surface: .artificial, capacity: 74_600,
            noise: 92),
        Franchise(
            city: "Frostmere", region: .north, market: .small, climate: .cold, altitude: 900,
            nickname: "Blacksmiths", abbreviation: "FRM",
            primary: 0x18_181A, secondary: 0xC8_C8CE, accent: 0xEC_BE3E,
            stadium: "Kilnstead Grounds", roof: .open, surface: .grass, capacity: 55_400, noise: 85),
        Franchise(
            city: "Granite Harbor", region: .north, market: .large, climate: .coastal,
            altitude: 120,
            nickname: "Shipwrights", abbreviation: "GRH",
            primary: 0x0E_3A4A, secondary: 0xF6_D6A0, accent: 0xF0_ECE0,
            stadium: "Drydock Field", roof: .open, surface: .grass, capacity: 69_400, noise: 76),
        Franchise(
            city: "Kettlebrook", region: .north, market: .large, climate: .cold, altitude: 780,
            nickname: "Ironworkers", abbreviation: "KTB",
            primary: 0x0C_2340, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Foundry Yard", roof: .open, surface: .grass, capacity: 71_500, noise: 79),
        Franchise(
            city: "Alderwick", region: .north, market: .medium, climate: .cold, altitude: 430,
            nickname: "Stags", abbreviation: "ALW",
            primary: 0x5C_101C, secondary: 0xB0_D278, accent: 0xF0_ECE0,
            stadium: "Old Mill Grounds", roof: .open, surface: .grass, capacity: 63_400, noise: 72),
        Franchise(
            city: "Pinecrest", region: .north, market: .medium, climate: .cold, altitude: 1_150,
            nickname: "Goshawks", abbreviation: "PIN",
            primary: 0x3A_3E14, secondary: 0xF6_D6A0, accent: 0xF0_ECE0,
            stadium: "Lakeside Field", roof: .open, surface: .hybrid, capacity: 64_900, noise: 75),
        Franchise(
            city: "Steelfall", region: .north, market: .large, climate: .temperate, altitude: 260,
            nickname: "Riverboats", abbreviation: "STF",
            primary: 0x60_2C0C, secondary: 0xC8_C8CE, accent: 0xF0_ECE0,
            stadium: "Cathedral Stadium", roof: .open, surface: .artificial, capacity: 68_300,
            noise: 78),

        // MARK: South — heat, water and the trades that follow both

        Franchise(
            city: "Bayou Landing", region: .south, market: .medium, climate: .hot, altitude: 20,
            nickname: "Herons", abbreviation: "BYL",
            primary: 0x0E_3A4A, secondary: 0xB0_D278, accent: 0xF0_ECE0,
            stadium: "Cypress Field", roof: .open, surface: .grass, capacity: 65_500, noise: 73),
        Franchise(
            city: "Verano Springs", region: .south, market: .major, climate: .hot, altitude: 40,
            nickname: "Wildfire", abbreviation: "VRN",
            primary: 0x60_2C0C, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Solstice Stadium", roof: .dome, surface: .artificial, capacity: 76_400,
            noise: 94),
        Franchise(
            city: "Goldleaf", region: .south, market: .small, climate: .hot, altitude: 350,
            nickname: "Swelter", abbreviation: "GDL",
            primary: 0x3A_3E14, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Municipal Grounds", roof: .open, surface: .grass, capacity: 57_800, noise: 70),
        Franchise(
            city: "Magnolia Reach", region: .south, market: .large, climate: .hot, altitude: 90,
            nickname: "Rattlers", abbreviation: "MGR",
            primary: 0x7A_1A14, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Delta Park", roof: .open, surface: .artificial, capacity: 70_100, noise: 77),
        Franchise(
            city: "Sunderly", region: .south, market: .large, climate: .hot, altitude: 30,
            nickname: "Longshoremen", abbreviation: "SDL",
            primary: 0x0C_2340, secondary: 0xE8_7A8C, accent: 0xF0_ECE0,
            stadium: "Tidewater Coliseum", roof: .dome, surface: .hybrid, capacity: 68_800,
            noise: 91),
        Franchise(
            city: "Sable Crossing", region: .south, market: .large, climate: .temperate,
            altitude: 480,
            nickname: "Wranglers", abbreviation: "SCR",
            primary: 0x18_181A, secondary: 0xF6_D6A0, accent: 0xEC_BE3E,
            stadium: "Stockyard Field", roof: .open, surface: .hybrid, capacity: 67_900, noise: 76),
        Franchise(
            city: "Camellia Point", region: .south, market: .medium, climate: .temperate,
            altitude: 210,
            nickname: "Tanners", abbreviation: "CML",
            primary: 0x5C_101C, secondary: 0xF6_D6A0, accent: 0xF0_ECE0,
            stadium: "Azalea Stadium", roof: .open, surface: .grass, capacity: 62_700, noise: 71),
        Franchise(
            city: "Tallow Bend", region: .south, market: .medium, climate: .hot, altitude: 65,
            nickname: "Monsoon", abbreviation: "TLB",
            primary: 0x48_143E, secondary: 0xE8_7A8C, accent: 0xF0_ECE0,
            stadium: "Levee Arena", roof: .dome, surface: .artificial, capacity: 64_100,
            noise: 89),

        // MARK: East — ports, mill towns and the weather off the water

        Franchise(
            city: "Halvern", region: .east, market: .large, climate: .cold, altitude: 60,
            nickname: "Undertow", abbreviation: "HLV",
            primary: 0x28_1642, secondary: 0x9E_D6EC, accent: 0xF0_ECE0,
            stadium: "Quayside Coliseum", roof: .dome, surface: .artificial, capacity: 72_300,
            noise: 93),
        Franchise(
            city: "Kingsbridge", region: .east, market: .large, climate: .temperate, altitude: 95,
            nickname: "Sentinels", abbreviation: "KBR",
            primary: 0x48_143E, secondary: 0xC8_C8CE, accent: 0xF0_ECE0,
            stadium: "Trestle Field", roof: .open, surface: .hybrid, capacity: 70_600, noise: 79),
        Franchise(
            city: "Dunmore Heights", region: .east, market: .medium, climate: .cold, altitude: 540,
            nickname: "Wardens", abbreviation: "DNM",
            primary: 0x14_3428, secondary: 0xC8_C8CE, accent: 0xF0_ECE0,
            stadium: "Highline Stadium", roof: .open, surface: .artificial, capacity: 64_400,
            noise: 74),
        Franchise(
            city: "Wrenford", region: .east, market: .medium, climate: .temperate, altitude: 180,
            nickname: "Foxes", abbreviation: "WRN",
            primary: 0x5C_101C, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Memorial Field", roof: .open, surface: .grass, capacity: 63_900, noise: 72),
        Franchise(
            city: "Ashport", region: .east, market: .major, climate: .coastal, altitude: 15,
            nickname: "Kestrels", abbreviation: "ASH",
            primary: 0x0C_2340, secondary: 0x9E_D6EC, accent: 0xF0_ECE0,
            stadium: "Gaslight Park", roof: .open, surface: .grass, capacity: 77_200, noise: 83),
        Franchise(
            city: "Thorne Harbor", region: .east, market: .large, climate: .coastal, altitude: 25,
            nickname: "Barracudas", abbreviation: "THB",
            primary: 0x0E_3A4A, secondary: 0xE8_7A8C, accent: 0xF0_ECE0,
            stadium: "Windward Park", roof: .open, surface: .hybrid, capacity: 67_600, noise: 77),
        Franchise(
            city: "Lockridge", region: .east, market: .small, climate: .cold, altitude: 720,
            nickname: "Millers", abbreviation: "LKR",
            primary: 0x60_2C0C, secondary: 0xB0_D278, accent: 0xF0_ECE0,
            stadium: "Beacon Grounds", roof: .open, surface: .grass, capacity: 56_900, noise: 69),
        Franchise(
            city: "Fallstead", region: .east, market: .medium, climate: .temperate, altitude: 300,
            nickname: "Griffins", abbreviation: "FST",
            primary: 0x3A_3E14, secondary: 0xE8_7A8C, accent: 0xF0_ECE0,
            stadium: "Lantern Field", roof: .open, surface: .artificial, capacity: 65_100,
            noise: 74),

        // MARK: West — high desert, mountains and one long coast

        Franchise(
            city: "Junipero Mesa", region: .west, market: .medium, climate: .arid, altitude: 3_100,
            nickname: "Jackals", abbreviation: "JNM",
            primary: 0x3A_3E14, secondary: 0xF4_9428, accent: 0xF0_ECE0,
            stadium: "Trailhead Coliseum", roof: .dome, surface: .artificial, capacity: 63_800,
            noise: 88),
        Franchise(
            city: "Vermillion Flats", region: .west, market: .medium, climate: .arid,
            altitude: 2_100,
            nickname: "Vipers", abbreviation: "VMF",
            primary: 0x18_181A, secondary: 0xF4_9428, accent: 0xF0_ECE0,
            stadium: "Sagebrush Stadium", roof: .open, surface: .artificial, capacity: 64_700,
            noise: 75),
        Franchise(
            city: "Silverpeak", region: .west, market: .medium, climate: .mountain, altitude: 5_200,
            nickname: "Ibex", abbreviation: "SVP",
            primary: 0x0C_2340, secondary: 0xC8_C8CE, accent: 0xF0_ECE0,
            stadium: "Alpenglow Grounds", roof: .open, surface: .hybrid, capacity: 61_400,
            noise: 77),
        Franchise(
            city: "Redmesa", region: .west, market: .large, climate: .arid, altitude: 4_400,
            nickname: "Prospectors", abbreviation: "RDM",
            primary: 0x7A_1A14, secondary: 0xF6_D6A0, accent: 0xF0_ECE0,
            stadium: "Copperworks Field", roof: .open, surface: .grass, capacity: 68_600, noise: 78),
        Franchise(
            city: "Sundown Bay", region: .west, market: .major, climate: .coastal, altitude: 30,
            nickname: "Condors", abbreviation: "SDB",
            primary: 0x0E_3A4A, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Cliffwalk Park", roof: .open, surface: .grass, capacity: 75_800, noise: 82),
        Franchise(
            city: "Cascade Junction", region: .west, market: .large, climate: .temperate,
            altitude: 640,
            nickname: "Otters", abbreviation: "CSJ",
            primary: 0x14_3428, secondary: 0x9E_D6EC, accent: 0xF0_ECE0,
            stadium: "Timberline Field", roof: .open, surface: .grass, capacity: 67_300, noise: 76),
        Franchise(
            city: "Wildhorse Ridge", region: .west, market: .small, climate: .arid, altitude: 1_800,
            nickname: "Smelters", abbreviation: "WHR",
            primary: 0x60_2C0C, secondary: 0xEC_BE3E, accent: 0xF0_ECE0,
            stadium: "Ashfield Coliseum", roof: .open, surface: .artificial, capacity: 58_600,
            noise: 71),
        Franchise(
            city: "Alta Verde", region: .west, market: .large, climate: .mountain, altitude: 4_900,
            nickname: "Wyverns", abbreviation: "ALV",
            primary: 0x48_143E, secondary: 0xB0_D278, accent: 0xF0_ECE0,
            stadium: "Ridgeline Park", roof: .open, surface: .hybrid, capacity: 67_100, noise: 80),
    ]

    /// The franchises of one region, in file order.
    public static func franchises(in region: Region) -> [Franchise] {
        initial.filter { $0.region == region }
    }
}
