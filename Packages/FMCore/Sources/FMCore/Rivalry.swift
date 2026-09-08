/// Where in the world a team plays.
///
/// The world has no map, so a region is not a coordinate — it is the coarsest fact that
/// makes divisions look drawn rather than dealt, and it is what lets a rivalry be
/// geographic across a conference boundary. Structure, fixed at world creation, like
/// division membership; not identity, and not simulation input.
public enum Region: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case north = 0
    case south = 1
    case east = 2
    case west = 3
}

/// An unordered pair of teams.
///
/// Normalised at construction, so the rivalry between two teams is one thing however it
/// is written down. Storing a rivalry twice under two orderings is the kind of bug that
/// surfaces as a news item about a grudge nobody else has heard of.
public struct TeamPair: Sendable, Hashable, Codable, Comparable {

    public let lower: TeamID
    public let higher: TeamID

    public init(_ a: TeamID, _ b: TeamID) {
        precondition(a != b, "a team cannot be its own rival")
        if a.rawValue < b.rawValue {
            lower = a
            higher = b
        } else {
            lower = b
            higher = a
        }
    }

    public func contains(_ team: TeamID) -> Bool { team == lower || team == higher }

    public func opponent(of team: TeamID) -> TeamID? {
        team == lower ? higher : (team == higher ? lower : nil)
    }

    public static func < (a: TeamPair, b: TeamPair) -> Bool {
        (a.lower.rawValue, a.higher.rawValue) < (b.lower.rawValue, b.higher.rawValue)
    }
}

/// Why two teams started caring about each other.
///
/// The origin is a fact and is stored. How much they care *now* is not — that is folded
/// from what has happened since.
public enum RivalryOrigin: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Same division: they play twice a year and share a bracket. The sharpest
    /// structural relationship in the sport.
    case divisional = 0
    /// Same part of the world, different division. The crosstown game.
    case regional = 1
    /// Born in January. Two teams who kept meeting when it counted.
    case postseason = 2
    /// Somebody left for the other one — a coach, or a player nobody expected to lose.
    case personal = 3
}

/// Something that happened between two teams and made it worse.
///
/// The same vocabulary serves invented history and lived history, which is the point:
/// a world's seeded past is a fabricated event log in this shape, so once a season is
/// played nothing downstream can tell the difference, and the news can *cite* the
/// history rather than reporting an intensity number nobody can account for.
public enum RivalryEventKind: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case closeGame = 0
    case decidedOnFinalPlay = 1
    case blowout = 2
    case upset = 3
    /// One of them ended the other's season.
    case playoffElimination = 4
    /// They met for a conference title or the championship itself.
    case titleGame = 5
    /// A call that decided it, and one fan base has never let it go.
    case controversialFinish = 6
    /// A run of wins long enough that it became the story.
    case streak = 7
    /// A coach crossed the divide.
    case coachDefection = 8
    /// A player they expected to keep signed with the other one.
    case playerPoached = 9

    /// How much this adds to a rivalry the season it happens.
    ///
    /// A blowout is a bad night; a playoff elimination is a decade. The spread between
    /// them is what stops intensity being a win-loss record with a different name.
    public var weight: Double {
        switch self {
        case .closeGame: return 3
        case .blowout: return 2
        case .upset: return 5
        case .decidedOnFinalPlay: return 8
        case .streak: return 6
        case .playerPoached: return 7
        case .coachDefection: return 9
        case .controversialFinish: return 12
        case .playoffElimination: return 16
        case .titleGame: return 20
        }
    }
}

/// One thing that happened, stamped with when.
public struct RivalryEvent: Sendable, Hashable, Codable {

    public let pair: TeamPair
    public let season: Int
    public let kind: RivalryEventKind
    /// Which team it happened *to*, where that makes sense — who was eliminated, who
    /// lost the coach. `nil` for events with no injured party, like a close game.
    public let aggrievedTeam: TeamID?

    public init(pair: TeamPair, season: Int, kind: RivalryEventKind, aggrievedTeam: TeamID? = nil) {
        self.pair = pair
        self.season = season
        self.kind = kind
        self.aggrievedTeam = aggrievedTeam
    }
}

/// Two teams, why they started, and what has happened since.
public struct Rivalry: Sendable, Hashable, Codable, Identifiable {

    public let pair: TeamPair
    public let origin: RivalryOrigin
    /// Oldest first. Seeded history and lived history are the same list.
    public var history: [RivalryEvent]

    public init(pair: TeamPair, origin: RivalryOrigin, history: [RivalryEvent] = []) {
        self.pair = pair
        self.origin = origin
        self.history = history
    }

    public var id: TeamPair { pair }
}

extension Rivalry {

    /// What a rivalry starts at before anything has happened, by origin alone.
    ///
    /// Two teams in a division care a little about each other on principle. Two who met
    /// once in a conference championship and never again should fade back to nothing,
    /// which is why the structural floor belongs to structure and not to history.
    public var baseIntensity: Double {
        switch origin {
        case .divisional: return 22
        case .regional: return 12
        case .postseason: return 6
        case .personal: return 6
        }
    }

    /// How much these two care, as of `season`, on a 0–100 scale.
    ///
    /// A fold with decay: what happened last year matters more than what happened a
    /// decade ago, and a rivalry nobody has fed goes quiet. Without decay, intensity is
    /// a running total that only ever rises, and after twenty seasons every pairing in
    /// the league is a blood feud.
    public func intensity(in season: Int) -> Double {
        var total = baseIntensity
        for event in history where event.season <= season {
            let age = season - event.season
            var contribution = event.kind.weight
            // Iterated rather than raised to a power: `pow` is libm, which the FM*
            // modules do not link.
            for _ in 0..<age {
                contribution *= Self.decayPerSeason
                if contribution < 0.01 { break }
            }
            total += contribution
        }
        return min(100, total)
    }

    /// Roughly a decade of memory: a season-old event still carries most of its weight,
    /// and a ten-year-old one is a fifth of it.
    public static let decayPerSeason = 0.85

    /// The events still doing the work, most recent first. What a pre-game write-up
    /// would actually mention.
    public func liveHistory(in season: Int, limit: Int = 3) -> [RivalryEvent] {
        history.filter { $0.season <= season }
            .sorted { ($0.season, $0.kind.weight) > ($1.season, $1.kind.weight) }
            .prefix(limit)
            .map { $0 }
    }

    public func heat(in season: Int) -> RivalryHeat {
        RivalryHeat(intensity: intensity(in: season))
    }
}

/// Intensity in the terms a screen or a news item would use.
public enum RivalryHeat: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case cold = 0
    case simmering = 1
    case heated = 2
    case bitter = 3

    public init(intensity: Double) {
        switch intensity {
        case ..<20: self = .cold
        case ..<40: self = .simmering
        case ..<65: self = .heated
        default: self = .bitter
        }
    }
}
