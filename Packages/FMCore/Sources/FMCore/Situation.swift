public enum Down: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4

    public var next: Down? {
        Down(rawValue: rawValue + 1)
    }
}

/// Skill-position personnel, in the digit convention: `11` is one back and one
/// tight end, so three receivers; `21` is two backs and one tight end.
///
/// Five skill players are on the field alongside the offensive line, so the
/// receiver count follows from the other two rather than being stored.
public struct PersonnelGroup: Sendable, Hashable, Codable {

    public let runningBacks: UInt8
    public let tightEnds: UInt8

    public init(runningBacks: UInt8, tightEnds: UInt8) {
        precondition(runningBacks + tightEnds <= 5, "at most five skill players")
        self.runningBacks = runningBacks
        self.tightEnds = tightEnds
    }

    public var wideReceivers: UInt8 {
        5 - runningBacks - tightEnds
    }

    /// The two-digit code the sport uses: backs then tight ends.
    public var code: UInt8 {
        runningBacks * 10 + tightEnds
    }

    public static let eleven = PersonnelGroup(runningBacks: 1, tightEnds: 1)
    public static let twelve = PersonnelGroup(runningBacks: 1, tightEnds: 2)
    public static let thirteen = PersonnelGroup(runningBacks: 1, tightEnds: 3)
    public static let twentyOne = PersonnelGroup(runningBacks: 2, tightEnds: 1)
    public static let twentyTwo = PersonnelGroup(runningBacks: 2, tightEnds: 2)
    public static let ten = PersonnelGroup(runningBacks: 1, tightEnds: 0)
    public static let empty = PersonnelGroup(runningBacks: 0, tightEnds: 0)
}

/// The defensive package on the field, named by its defensive back count.
public enum DefensivePackage: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case base = 0
    case nickel = 1
    case dime = 2
    case quarter = 3
    case goalLine = 4
    case prevent = 5

    public var defensiveBacks: UInt8 {
        switch self {
        case .base: return 4
        case .nickel: return 5
        case .dime: return 6
        case .quarter: return 7
        case .goalLine: return 3
        case .prevent: return 7
        }
    }
}

public enum Precipitation: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case none = 0
    case rain = 1
    case heavyRain = 2
    case snow = 3
}

public struct WeatherState: Sendable, Hashable, Codable {

    /// Degrees Fahrenheit. The sport's own unit, and it keeps the numbers on a
    /// scale that reads correctly to the audience.
    public var temperature: Int16
    public var windSpeed: UInt8
    public var precipitation: Precipitation
    public var isIndoors: Bool

    public init(
        temperature: Int16 = 62,
        windSpeed: UInt8 = 0,
        precipitation: Precipitation = .none,
        isIndoors: Bool = false
    ) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.precipitation = precipitation
        self.isIndoors = isIndoors
    }

    public static let clear = WeatherState()
    public static let dome = WeatherState(temperature: 70, isIndoors: true)
}

/// Where on the field the ball is, in the terms the sport uses to talk about it.
public enum FieldZone: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case ownDeep
    case ownTerritory
    case midfield
    case opponentTerritory
    case redZone
    case goalLine
}

/// The state of the game before a snap.
///
/// `ballOn` is yards from the *opponent's* goal line — 75 means backed up on
/// your own 25, 5 means about to score. One representation, used everywhere,
/// because mixing "yards from own goal" and "yards to go" is a recurring source
/// of off-by-a-lot bugs. Formatting into "own 25" is a presentation concern.
public struct Situation: Sendable, Hashable, Codable {

    public var quarter: UInt8
    /// Seconds remaining in the quarter.
    public var clockRemaining: UInt16
    public var down: Down
    /// Yards needed for a new set of downs.
    public var distance: UInt8
    /// Yards from the opponent's goal line, 1...99.
    public var ballOn: UInt8
    public var possession: TeamID
    /// Score from the possessing team's point of view.
    public var scoreDifferential: Int16
    public var offenseTimeouts: UInt8
    public var defenseTimeouts: UInt8
    public var offensePersonnel: PersonnelGroup
    public var defensePackage: DefensivePackage
    public var weather: WeatherState

    public init(
        quarter: UInt8,
        clockRemaining: UInt16,
        down: Down,
        distance: UInt8,
        ballOn: UInt8,
        possession: TeamID,
        scoreDifferential: Int16 = 0,
        offenseTimeouts: UInt8 = 3,
        defenseTimeouts: UInt8 = 3,
        offensePersonnel: PersonnelGroup = .eleven,
        defensePackage: DefensivePackage = .base,
        weather: WeatherState = .clear
    ) {
        self.quarter = quarter
        self.clockRemaining = clockRemaining
        self.down = down
        self.distance = distance
        self.ballOn = ballOn
        self.possession = possession
        self.scoreDifferential = scoreDifferential
        self.offenseTimeouts = offenseTimeouts
        self.defenseTimeouts = defenseTimeouts
        self.offensePersonnel = offensePersonnel
        self.defensePackage = defensePackage
        self.weather = weather
    }

    public var fieldZone: FieldZone {
        switch ballOn {
        case ..<6: return .goalLine
        case ..<21: return .redZone
        case ..<50: return .opponentTerritory
        case 50: return .midfield
        case ..<80: return .ownTerritory
        default: return .ownDeep
        }
    }

    public var isRedZone: Bool {
        ballOn <= 20
    }

    /// Inside the ten, distance is measured to the goal line rather than to a
    /// first-down marker — there is no first and ten from the opponent's six.
    public var isGoalToGo: Bool {
        distance >= ballOn
    }

    /// Both halves end with a stoppage at two minutes, and behaviour changes
    /// sharply on either side of it.
    ///
    /// The half boundaries and the threshold are the rules' (`Rules.quarters`,
    /// `Rules.twoMinuteWarning`), not literals: a two-period variant has its drill at the
    /// end of its first period. Overtime counts as the end of the game here, as it did
    /// when the periods were hard-coded.
    public func isTwoMinuteDrill(rules: Rules = .standard) -> Bool {
        (quarter == rules.quarters / 2 || quarter >= rules.quarters)
            && clockRemaining <= rules.twoMinuteWarning
    }

    /// A rough situational bucket for tendency tables and AI play calling.
    public var isObviousPassing: Bool {
        (down == .third || down == .fourth) && distance >= 7
    }

    /// Structural validity. Checked at construction sites rather than assumed,
    /// because an impossible situation surfaces as strange behaviour deep in the
    /// engine rather than as an obvious failure.
    ///
    /// There is no ceiling on the period: a postseason game plays overtime periods until
    /// it is decided (`[2025 · 16-1-4]`), so a sixth or a seventh is a real situation.
    public var isValid: Bool {
        quarter >= 1
            && ballOn >= 1 && ballOn <= 99
            && distance >= 1
            && offenseTimeouts <= 3 && defenseTimeouts <= 3
            && (isGoalToGo || distance <= 99)
    }
}
