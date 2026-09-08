/// What a person in the league does.
///
/// One role enum and one identifier space for everyone who is not a player,
/// because they are all the same kind of thing: a person with a name, an age and
/// a career that ends. Modelling coaches, scouts, agents, writers and officials
/// separately would mean writing the same lifecycle five times and getting it
/// slightly different each time.
public enum PersonnelRole: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case headCoach = 0
    case offensiveCoordinator = 1
    case defensiveCoordinator = 2
    case positionCoach = 3
    case generalManager = 4
    case scout = 5
    case agent = 6
    case writer = 7
    case official = 8
    case trainer = 9

    public var isCoaching: Bool {
        switch self {
        case .headCoach, .offensiveCoordinator, .defensiveCoordinator, .positionCoach:
            return true
        default:
            return false
        }
    }

    /// Whether the role belongs to a club rather than to the league or to
    /// itself. Officials work for the league; agents and writers work for
    /// nobody.
    public var isEmployedByTeam: Bool {
        switch self {
        case .agent, .writer, .official: return false
        default: return true
        }
    }
}

/// The shape of a career in a role: when people enter it and when they leave.
///
/// Different from a player's in kind, not just in length — a coordinator starts
/// in his thirties and can work into his seventies, while a corner is finished
/// at thirty-two.
public struct CareerSpan: Sendable, Hashable, Codable {

    public let entryAge: ClosedRange<Int>
    public let retirementAge: ClosedRange<Int>

    public init(entryAge: ClosedRange<Int>, retirementAge: ClosedRange<Int>) {
        self.entryAge = entryAge
        self.retirementAge = retirementAge
    }

    public static func span(for role: PersonnelRole) -> CareerSpan {
        switch role {
        case .headCoach:
            return CareerSpan(entryAge: 36...52, retirementAge: 58...74)
        case .offensiveCoordinator, .defensiveCoordinator:
            return CareerSpan(entryAge: 32...48, retirementAge: 56...72)
        case .positionCoach:
            return CareerSpan(entryAge: 28...44, retirementAge: 55...70)
        case .generalManager:
            return CareerSpan(entryAge: 35...52, retirementAge: 60...74)
        case .scout:
            return CareerSpan(entryAge: 26...45, retirementAge: 58...72)
        case .agent:
            return CareerSpan(entryAge: 27...45, retirementAge: 58...75)
        case .writer:
            return CareerSpan(entryAge: 24...42, retirementAge: 60...76)
        case .official:
            return CareerSpan(entryAge: 33...45, retirementAge: 58...68)
        case .trainer:
            return CareerSpan(entryAge: 26...42, retirementAge: 58...70)
        }
    }
}

/// Someone in the league who is not a player.
///
/// Coaches, scouts, agents, writers, officials and trainers all age, all retire,
/// and are all replaced by people generated to take their place. Without this, a
/// career in its fiftieth season is covered by the same columnist who started
/// it, which is the sort of detail that quietly tells a player the world is a
/// fixture rather than a place.
///
/// The retirement age is generated once and hidden, exactly like a player's
/// ceiling: you find out someone is near the end by watching, not by reading a
/// number. It is also what makes succession a thing a general manager has to
/// think about.
public struct Personnel: Sendable, Hashable, Codable, Identifiable {

    public let id: PersonnelID
    public let name: PersonName
    public let birthSeason: Int
    public let role: PersonnelRole
    /// The season this person first worked in the league.
    public let careerStartSeason: Int
    /// Hidden. The age at which they intend to stop.
    public let retirementAge: Int

    public init(
        id: PersonnelID,
        name: PersonName,
        birthSeason: Int,
        role: PersonnelRole,
        careerStartSeason: Int,
        retirementAge: Int
    ) {
        self.id = id
        self.name = name
        self.birthSeason = birthSeason
        self.role = role
        self.careerStartSeason = careerStartSeason
        self.retirementAge = retirementAge
    }

    public func age(in season: Int) -> Int {
        season - birthSeason
    }

    /// Seasons worked, which is what a reputation is built on.
    public func experience(in season: Int) -> Int {
        max(0, season - careerStartSeason)
    }

    public func isActive(in season: Int) -> Bool {
        season >= careerStartSeason && age(in: season) < retirementAge
    }

    /// Whether this season is their last.
    public func retires(after season: Int) -> Bool {
        isActive(in: season) && age(in: season + 1) >= retirementAge
    }

    /// The season they will step away, so a world can be projected forward and
    /// replacements planned rather than conjured the moment a vacancy appears.
    public var retirementSeason: Int {
        birthSeason + retirementAge
    }
}
