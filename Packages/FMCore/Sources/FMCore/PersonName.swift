/// A person's name.
///
/// Generated, always. No real player, coach or official appears in this game
/// under any circumstances ([ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md)).
///
/// Given names and surnames are drawn from cultural commons rather than from any
/// roster, and combined freely. Two generated players sharing a name is not a
/// defect — it happens in every real league, and suppressing it would make the
/// world feel more synthetic rather than less.
public struct PersonName: Sendable, Hashable, Codable {

    public let given: String
    public let family: String
    /// "Jr.", "III" and so on. Rare, and purely flavour.
    public let suffix: String?

    public init(given: String, family: String, suffix: String? = nil) {
        self.given = given
        self.family = family
        self.suffix = suffix
    }

    public var full: String {
        guard let suffix else { return "\(given) \(family)" }
        return "\(given) \(family) \(suffix)"
    }

    /// How a broadcast or a box score refers to him: "M. Whitfield".
    public var short: String {
        guard let initial = given.first else { return family }
        return "\(initial). \(family)"
    }
}

extension PersonName: CustomStringConvertible {
    public var description: String { full }
}

/// A fictional college.
///
/// Invented rather than drawn from real institutions, for the same reason as
/// everything else in the world.
public struct College: Sendable, Hashable, Codable {

    public let name: String
    /// Rough talent level of the programme, which shapes how much tape exists on
    /// its prospects and therefore how noisy scouting them is.
    public let profile: CollegeProfile

    public init(name: String, profile: CollegeProfile) {
        self.name = name
        self.profile = profile
    }
}

public enum CollegeProfile: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Well covered, heavily scouted, little hidden.
    case powerProgram = 0
    case midMajor = 1
    /// Thin tape and few scouts, so estimates carry more error — the small-school
    /// prospect nobody has seen.
    case smallSchool = 2

    /// A multiplier on scouting error for prospects from this programme.
    public var scoutingNoiseMultiplier: Double {
        switch self {
        case .powerProgram: return 0.8
        case .midMajor: return 1.0
        case .smallSchool: return 1.5
        }
    }
}
