/// A colour, packed into 24 bits of RGB.
///
/// The engine never reads a colour. It lives here because it is part of a team's
/// identity and is event-sourced alongside the rest of it, not because the
/// simulation has any use for it — the same line
/// [ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md) draws for a
/// player's appearance. Uniform *artwork* — stripes, helmet marks, number fonts — is
/// presentation and stays outside `FMCore` entirely.
public struct TeamColor: Sendable, Hashable, Codable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue & 0xFF_FFFF
    }

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        rawValue = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    public var red: UInt8 { UInt8((rawValue >> 16) & 0xFF) }
    public var green: UInt8 { UInt8((rawValue >> 8) & 0xFF) }
    public var blue: UInt8 { UInt8(rawValue & 0xFF) }

    /// Rough perceived lightness, 0–255, using the integer luma weights.
    ///
    /// Enough to keep a generator from pairing two colours nothing can be read
    /// against, without pulling in a colour space or any floating-point maths.
    public var luma: UInt8 {
        UInt8((UInt32(red) * 77 + UInt32(green) * 150 + UInt32(blue) * 29) >> 8)
    }
}

public struct TeamColors: Sendable, Hashable, Codable {

    public var primary: TeamColor
    public var secondary: TeamColor
    public var accent: TeamColor

    public init(primary: TeamColor, secondary: TeamColor, accent: TeamColor) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
    }

    /// Whether the primary and secondary separate enough to read against each other.
    ///
    /// A generated pairing that fails this is two teams' worth of navy, and no amount
    /// of good simulation makes a scoreboard legible after that.
    public var hasReadableContrast: Bool {
        let difference =
            primary.luma > secondary.luma
            ? primary.luma - secondary.luma : secondary.luma - primary.luma
        return difference >= 40
    }
}

/// The editable half of a team.
///
/// None of it means anything to the simulation ([decision 106](../../../../docs/design-decisions.md)),
/// which is exactly why it is safe to let a player rewrite all of it at any time.
public struct TeamIdentity: Sendable, Hashable, Codable {

    public var city: String
    public var nickname: String
    /// Two or three letters for scoreboards and standings.
    public var abbreviation: String
    public var colors: TeamColors

    public init(city: String, nickname: String, abbreviation: String, colors: TeamColors) {
        self.city = city
        self.nickname = nickname
        self.abbreviation = abbreviation
        self.colors = colors
    }

    public var fullName: String { "\(city) \(nickname)" }
}

public enum PlayingSurface: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case grass = 0
    case artificial = 1
    /// Reinforced natural turf. Behaves like grass and drains like artificial.
    case hybrid = 2
}

/// What the weather generator draws from for this stadium.
///
/// A climate rather than a latitude: the world is fictional, so there is no map to
/// derive weather from, and a named climate is what the generator actually needs.
public enum Climate: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case temperate = 0
    /// Hard winters. December games here are a genuine disadvantage to visitors.
    case cold = 1
    case hot = 2
    case arid = 3
    /// Mild, wet, and windy off the water.
    case coastal = 4
    /// Thin air, and a longer field goal.
    case mountain = 5
}

/// Where a team plays, and the parts of that the engine actually reads.
///
/// Unlike the identity above, this *is* simulation input. Indoors and climate drive
/// `WeatherState`; altitude reaches kicking distance and fatigue; noise is the
/// mechanism behind home field advantage rather than a bonus applied to it
/// ([penalties.md](../../../../docs/penalties.md)).
public struct Stadium: Sendable, Hashable, Codable {

    public var name: String
    public var capacity: Int32
    public var isIndoors: Bool
    public var surface: PlayingSurface
    public var climate: Climate
    public var altitudeFeet: Int16
    /// How loud it gets when it matters, 0–100. Raises the visiting offence's
    /// pre-snap penalties; it does not raise the home team's ratings.
    public var noise: UInt8

    public init(
        name: String,
        capacity: Int32,
        isIndoors: Bool = false,
        surface: PlayingSurface = .grass,
        climate: Climate = .temperate,
        altitudeFeet: Int16 = 0,
        noise: UInt8 = 50
    ) {
        self.name = name
        self.capacity = capacity
        self.isIndoors = isIndoors
        self.surface = surface
        self.climate = climate
        self.altitudeFeet = altitudeFeet
        self.noise = noise
    }

    /// A roof settles the weather regardless of where the stadium is.
    public var weatherIsDecidedByClimate: Bool { !isIndoors }

    /// High enough that kicks carry noticeably.
    public var isHighAltitude: Bool { altitudeFeet >= 4_000 }
}

/// How big a market a team plays in.
///
/// Reaches revenue and a free agent's willingness to sign, never the field.
public enum MarketSize: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case small = 0
    case medium = 1
    case large = 2
    case major = 3
}

/// A team, as the rest of the world refers to it.
///
/// The enduring entity: it keeps its `TeamID` through a rename, a rebrand or a move,
/// so franchise history spans all of them. There is deliberately no separate
/// "franchise" concept — one entity, one identifier, for the same reason a play has
/// one ([ADR-0011](../../../../docs/adr/0011-derived-identity-for-regenerable-streams.md)).
public struct Team: Sendable, Hashable, Codable, Identifiable {

    public let id: TeamID
    /// The identity as of now.
    ///
    /// A **cached projection** over `TeamIdentityEvent`, never the source of truth
    /// ([ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md)). Folding
    /// the whole stream to render a standings row would be unusable, so the current
    /// value is kept here; any other point in time comes from the stream.
    public var identity: TeamIdentity
    /// Also a cached projection — a relocation moves it.
    public var stadium: Stadium
    public var market: MarketSize
    public var scheme: TeamScheme

    public init(
        id: TeamID,
        identity: TeamIdentity,
        stadium: Stadium,
        market: MarketSize,
        scheme: TeamScheme
    ) {
        self.id = id
        self.identity = identity
        self.stadium = stadium
        self.market = market
        self.scheme = scheme
    }
}
