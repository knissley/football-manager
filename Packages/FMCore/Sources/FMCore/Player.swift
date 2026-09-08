/// How quickly a player closes the gap to his ceiling.
///
/// Hidden, and revealed only by whether growth actually happens
/// ([development.md](../../../../docs/development.md)). It is the difference
/// between a real breakout and a career year.
public enum DevelopmentTrait: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case slow = 0
    case normal = 1
    case quick = 2
    case star = 3

    /// Multiplier on the rate of growth toward the ceiling. Never on the ceiling
    /// itself — a star developer reaches his limit sooner, not a higher one.
    public var growthRate: Double {
        switch self {
        case .slow: return 0.6
        case .normal: return 1.0
        case .quick: return 1.45
        case .star: return 2.1
        }
    }
}

/// What a player could become, and how fast. Never shown directly.
///
/// The ceiling is the guarantee that keeps a league from inflating: it is set
/// once at generation and never moves, so no amount of performance, coaching or
/// spending produces a player better than he was always capable of being
/// ([decision 100](../../../../docs/design-decisions.md)).
public struct HiddenAttributes: Sendable, Hashable, Codable {

    /// The highest overall this player can ever reach.
    public let ceiling: UInt8
    public let developmentTrait: DevelopmentTrait
    /// Drives how much of available practice and coaching actually lands.
    public let workEthic: UInt8
    /// Independent of `injuryResistance`: how well he recovers, not how often
    /// he goes down.
    public let durability: UInt8

    public init(
        ceiling: UInt8,
        developmentTrait: DevelopmentTrait,
        workEthic: UInt8,
        durability: UInt8
    ) {
        self.ceiling = ceiling
        self.developmentTrait = developmentTrait
        self.workEthic = workEthic
        self.durability = durability
    }
}

/// Height, weight, and the combine numbers.
///
/// Testing results sit *outside* the scouting fog — a forty time is known
/// precisely by everyone ([decision 68](../../../../docs/design-decisions.md)).
/// They correlate with the ratings that matter but never determine them, which
/// is what makes a workout riser a real and sometimes wrong story.
///
/// Times are hundredths of a second and jumps are tenths of an inch, so every
/// value is an integer and reproduces exactly.
public struct PhysicalProfile: Sendable, Hashable, Codable {

    public var heightInches: UInt8
    public var weightPounds: UInt16
    /// Hundredths of a second: 452 is 4.52.
    public var fortyYardDash: UInt16
    /// Tenths of an inch: 365 is 36.5 inches.
    public var verticalJump: UInt16
    /// Inches.
    public var broadJump: UInt16
    /// Hundredths of a second.
    public var threeCone: UInt16
    public var benchReps: UInt8

    public init(
        heightInches: UInt8,
        weightPounds: UInt16,
        fortyYardDash: UInt16,
        verticalJump: UInt16,
        broadJump: UInt16,
        threeCone: UInt16,
        benchReps: UInt8
    ) {
        self.heightInches = heightInches
        self.weightPounds = weightPounds
        self.fortyYardDash = fortyYardDash
        self.verticalJump = verticalJump
        self.broadJump = broadJump
        self.threeCone = threeCone
        self.benchReps = benchReps
    }

    /// "6-4" — the way the sport writes it.
    public var heightDescription: String {
        "\(heightInches / 12)-\(heightInches % 12)"
    }
}

public struct DraftInfo: Sendable, Hashable, Codable {
    public let season: Int
    public let round: UInt8
    public let pick: UInt8
    public let overallPick: UInt16

    public init(season: Int, round: UInt8, pick: UInt8, overallPick: UInt16) {
        self.season = season
        self.round = round
        self.pick = pick
        self.overallPick = overallPick
    }
}

public enum RosterStatus: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case active = 0
    case inactive = 1
    case injuredReserve = 2
    case practiceSquad = 3
    case freeAgent = 4
    case retired = 5

    /// Whether he counts against the 53.
    public var occupiesRosterSpot: Bool {
        self == .active || self == .inactive
    }
}

/// A player.
///
/// Identity and hidden attributes are immutable; ratings, traits and status
/// change over a career through `DevelopmentEvent`s rather than by assignment,
/// so how a player became what he is stays answerable
/// ([ADR-0009](../../../../docs/adr/0009-event-sourcing-by-default.md)).
public struct Player: Sendable, Hashable, Codable, Identifiable {

    public let id: PlayerID
    public let name: PersonName
    /// The season he was born, so age is derived rather than stored and drifting.
    public let birthSeason: Int
    public let college: College
    public let draft: DraftInfo?

    public let position: Position
    /// Other positions he can fill, for depth chart validity and versatility.
    public var secondaryPositions: [Position]

    public var physical: PhysicalProfile
    public var ratings: Ratings
    public var traits: [TraitID]

    public let hidden: HiddenAttributes
    public var status: RosterStatus

    public init(
        id: PlayerID,
        name: PersonName,
        birthSeason: Int,
        college: College,
        draft: DraftInfo? = nil,
        position: Position,
        secondaryPositions: [Position] = [],
        physical: PhysicalProfile,
        ratings: Ratings,
        traits: [TraitID] = [],
        hidden: HiddenAttributes,
        status: RosterStatus = .active
    ) {
        self.id = id
        self.name = name
        self.birthSeason = birthSeason
        self.college = college
        self.draft = draft
        self.position = position
        self.secondaryPositions = secondaryPositions
        self.physical = physical
        self.ratings = ratings
        self.traits = traits
        self.hidden = hidden
        self.status = status
    }

    public func age(in season: Int) -> Int {
        season - birthSeason
    }

    /// Accrued seasons, which drives free agency class and veteran minimums.
    public func experience(in season: Int) -> Int {
        guard let draft else { return max(0, season - birthSeason - 22) }
        return max(0, season - draft.season)
    }

    public var isRookie: Bool {
        guard let draft else { return false }
        return draft.season == birthSeason + age(in: draft.season)
    }

    public var overall: UInt8 {
        PositionWeights.overall(ratings, at: position)
    }

    public func overall(at position: Position) -> UInt8 {
        PositionWeights.overall(ratings, at: position)
    }

    /// How much room is left between what he is and what he could be.
    ///
    /// Hidden from the player; used by development and by scouting estimates.
    public var remainingUpside: Int {
        Int(hidden.ceiling) - Int(overall)
    }

    /// A player at his ceiling cannot improve, however he performs or whatever
    /// is spent on him. This is the invariant that keeps the league from
    /// inflating.
    public var hasReachedCeiling: Bool {
        overall >= hidden.ceiling
    }

    public func canPlay(_ candidate: Position) -> Bool {
        candidate == position || secondaryPositions.contains(candidate)
    }
}
