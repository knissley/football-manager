/// How good a year this is, relative to a normal one.
///
/// Classes vary strongly — some years are loaded, some are barren, and a year can be
/// deep at one position and empty at another. That is what makes *this is the year to
/// trade up* a real thought and a quarterback run a real event.
///
/// The variation is **mean-reverting**, which is what keeps it compatible with the
/// conservation law ([development.md](../../../../docs/development.md)). A loaded class
/// makes the next few likelier to be thin, so the league's talent oscillates visibly
/// and comes back to its mean over a decade. Independent rolls would let fifty seasons
/// drift somewhere records are no longer comparable.
public struct ClassStrength: Sendable, Hashable, Codable {

    /// Offset in overall-rating points applied to the class, roughly −6…+6.
    public let overall: Double
    /// Per-group offsets on top of `overall`, so a class can be rich at one position
    /// and empty at another in the same year.
    public let byGroup: [PositionGroup: Double]

    public init(overall: Double, byGroup: [PositionGroup: Double] = [:]) {
        self.overall = overall
        self.byGroup = byGroup
    }

    public static let normal = ClassStrength(overall: 0)

    public func offset(for group: PositionGroup) -> Double {
        overall + (byGroup[group] ?? 0)
    }

    /// The label a league would actually use. Descriptive only — nothing reads this to
    /// make a decision.
    public var descriptor: String {
        switch overall {
        case ..<(-3.5): return "historically weak"
        case ..<(-1.5): return "thin"
        case ..<1.5: return "ordinary"
        case ..<3.5: return "strong"
        default: return "historically loaded"
        }
    }

    /// The group this year is unusually rich at, if there is one. What a quarterback
    /// run is made of.
    public var headline: PositionGroup? {
        // Sorted so the answer does not depend on dictionary iteration order.
        byGroup.filter { $0.value >= 2.5 }
            .sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
            .first?.key
    }
}

/// One year's draft class.
public struct DraftClass: Sendable, Hashable, Codable {

    /// The season this class is drafted into.
    public let season: Int
    public let strength: ClassStrength
    /// Everyone eligible, in no significant order — a board is somebody's opinion, and
    /// this is not anybody's opinion.
    public let prospects: [Prospect]

    public init(season: Int, strength: ClassStrength, prospects: [Prospect]) {
        self.season = season
        self.strength = strength
        self.prospects = prospects
    }

    /// Those actually entering. Underclassmen who stayed in school are carried in the
    /// class they were eligible for so the pipeline is inspectable, but they are not in
    /// the pool anybody drafts from.
    public var entering: [Prospect] { prospects.filter(\.isInThisClass) }

    public var earlyEntrants: [Prospect] { prospects.filter(\.isEarlyEntrant) }

    public var returning: [Prospect] { prospects.filter { !$0.isInThisClass } }
}
