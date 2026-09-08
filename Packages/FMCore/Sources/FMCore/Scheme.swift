/// How a team blocks the run.
public enum RunBlockingScheme: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Linemen move laterally and the back picks a lane. Wants agility and
    /// range over mass.
    case zone = 0
    /// Linemen fire out and move a man. Wants mass and leverage.
    case gap = 1
    /// Both, depending on the call. Asks a little of everything and rewards
    /// versatility over specialisation.
    case mixed = 2
}

/// What a team is trying to do when it throws.
public enum PassingIdentity: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Rhythm throws, timing, yards after catch.
    case westCoast = 0
    /// Get it out fast and let receivers work. Protection matters less.
    case quickGame = 1
    /// Take shots. Needs time, arm and separation down the field.
    case vertical = 2
    /// Throw it everywhere, tempo, spread the field.
    case airRaid = 3
    /// Set up the pass with the run. Wants a play-action passer and blockers
    /// who sell it.
    case playAction = 4
}

/// How many hands are in the ground up front.
public enum DefensiveFront: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Four down linemen. Wants edge rushers who beat tackles one on one.
    case fourMan = 0
    /// Three down and a standing rusher. Wants an anchor in the middle and
    /// linebackers who can do several jobs.
    case threeMan = 1
    /// Changes by call.
    case multiple = 2
}

/// The coverage a defence lives in.
public enum CoverageShell: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Corners on receivers, everywhere. Wants corners who can cover alone.
    case manPress = 0
    /// One deep safety, zones underneath.
    case singleHigh = 1
    /// Two deep safeties, pattern matching. Wants safeties who read.
    case quartersMatch = 2
    /// Two deep, soft. Concedes underneath and refuses to be beaten over the
    /// top.
    case twoHighSoft = 3
}

public enum PressureRate: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case conservative = 0
    case balanced = 1
    case blitzHeavy = 2
}

/// A team's offensive identity.
///
/// Composable underneath a set of named families, so the families are a
/// convenience over a representation the engine actually reads — the same shape
/// as gameplan presets over a rule set. A deeper tier that lets a coach mix
/// components freely is additive rather than a second system.
public struct OffensiveScheme: Sendable, Hashable, Codable {

    public let blocking: RunBlockingScheme
    public let passing: PassingIdentity
    /// Where the run/pass balance sits by default, 0 being all run.
    public let passLean: Double

    public init(blocking: RunBlockingScheme, passing: PassingIdentity, passLean: Double) {
        self.blocking = blocking
        self.passing = passing
        self.passLean = min(max(passLean, 0), 1)
    }

    public static let powerRun = OffensiveScheme(
        blocking: .gap, passing: .playAction, passLean: 0.42)
    public static let zoneRun = OffensiveScheme(
        blocking: .zone, passing: .playAction, passLean: 0.47)
    public static let westCoast = OffensiveScheme(
        blocking: .mixed, passing: .westCoast, passLean: 0.58)
    public static let spread = OffensiveScheme(
        blocking: .zone, passing: .quickGame, passLean: 0.62)
    public static let airRaid = OffensiveScheme(
        blocking: .zone, passing: .airRaid, passLean: 0.72)
    public static let verticalShots = OffensiveScheme(
        blocking: .gap, passing: .vertical, passLean: 0.60)

    public static let families: [OffensiveScheme] = [
        .powerRun, .zoneRun, .westCoast, .spread, .airRaid, .verticalShots,
    ]
}

/// A team's defensive identity.
public struct DefensiveScheme: Sendable, Hashable, Codable {

    public let front: DefensiveFront
    public let coverage: CoverageShell
    public let pressure: PressureRate

    public init(front: DefensiveFront, coverage: CoverageShell, pressure: PressureRate) {
        self.front = front
        self.coverage = coverage
        self.pressure = pressure
    }

    public static let fourThreeUnder = DefensiveScheme(
        front: .fourMan, coverage: .singleHigh, pressure: .balanced)
    public static let threeFourOkie = DefensiveScheme(
        front: .threeMan, coverage: .singleHigh, pressure: .balanced)
    public static let nickelMatch = DefensiveScheme(
        front: .fourMan, coverage: .quartersMatch, pressure: .balanced)
    public static let pressManBlitz = DefensiveScheme(
        front: .fourMan, coverage: .manPress, pressure: .blitzHeavy)
    public static let bendDontBreak = DefensiveScheme(
        front: .multiple, coverage: .twoHighSoft, pressure: .conservative)

    public static let families: [DefensiveScheme] = [
        .fourThreeUnder, .threeFourOkie, .nickelMatch, .pressManBlitz, .bendDontBreak,
    ]
}

/// A team's identity on both sides of the ball.
public struct TeamScheme: Sendable, Hashable, Codable {
    public var offense: OffensiveScheme
    public var defense: DefensiveScheme

    public init(offense: OffensiveScheme, defense: DefensiveScheme) {
        self.offense = offense
        self.defense = defense
    }

    public static let balanced = TeamScheme(offense: .westCoast, defense: .fourThreeUnder)
}

/// How much of a scheme a coach has actually run.
///
/// Experience is tracked per *component*, not per family, which is both more
/// accurate and more forgiving: a west-coast coordinator moving to spread keeps
/// his zone-blocking background, while one moving to power run keeps almost
/// nothing. Sharing components means sharing familiarity.
///
/// This is the cost of changing identity, and the important thing about it is
/// that it **decays**. An unfamiliar coordinator is worse, then less worse, then
/// fine. A penalty that fades is a different thing entirely from a gate that
/// only opens when the right name appears on a hiring list.
public struct SchemeExperience: Sendable, Hashable, Codable {

    /// Proficiency of someone who has never run a component. He is a
    /// professional, not a novice — he runs it worse, not badly.
    public static let unfamiliarProficiency = 0.60

    /// Seasons to reach full command of a component.
    public static let seasonsToMastery = 4

    /// Additional penalty during the first season in a new scheme, on top of
    /// unfamiliarity: the install itself is disruptive.
    public static let installPenalty = 0.10

    /// Changing identity mid-season, when there is no camp to install it in.
    public static let midSeasonPenalty = 0.25

    private var runBlocking: [RunBlockingScheme: Int] = [:]
    private var passing: [PassingIdentity: Int] = [:]
    private var front: [DefensiveFront: Int] = [:]
    private var coverage: [CoverageShell: Int] = [:]

    public init() {}

    public mutating func recordSeason(offense: OffensiveScheme) {
        runBlocking[offense.blocking, default: 0] += 1
        passing[offense.passing, default: 0] += 1
    }

    public mutating func recordSeason(defense: DefensiveScheme) {
        front[defense.front, default: 0] += 1
        coverage[defense.coverage, default: 0] += 1
    }

    public func seasons(running blocking: RunBlockingScheme) -> Int {
        runBlocking[blocking] ?? 0
    }

    public func seasons(running identity: PassingIdentity) -> Int {
        passing[identity] ?? 0
    }

    private static func proficiency(seasons: Int) -> Double {
        let progress = min(1.0, Double(max(0, seasons)) / Double(seasonsToMastery))
        return unfamiliarProficiency + (1 - unfamiliarProficiency) * progress
    }

    /// How well this coach runs an offensive scheme, from
    /// `unfamiliarProficiency` to 1.
    ///
    /// Scales his *decision quality*, never his players' ability — a coordinator
    /// out of his depth calls worse plays, he does not make anyone slower
    /// ([decision 40](../../../../docs/design-decisions.md)).
    public func proficiency(in scheme: OffensiveScheme) -> Double {
        let blocking = Self.proficiency(seasons: seasons(running: scheme.blocking))
        let throwing = Self.proficiency(seasons: seasons(running: scheme.passing))
        return (blocking + throwing) / 2
    }

    public func proficiency(in scheme: DefensiveScheme) -> Double {
        let alignment = Self.proficiency(seasons: front[scheme.front] ?? 0)
        let shell = Self.proficiency(seasons: coverage[scheme.coverage] ?? 0)
        return (alignment + shell) / 2
    }

    /// Proficiency in a scheme's first season, including the install cost.
    public func firstSeasonProficiency(in scheme: OffensiveScheme) -> Double {
        max(0, proficiency(in: scheme) - Self.installPenalty)
    }

    /// Proficiency when identity changes with no camp to install it.
    public func midSeasonProficiency(in scheme: OffensiveScheme) -> Double {
        max(0, proficiency(in: scheme) - Self.midSeasonPenalty)
    }
}
