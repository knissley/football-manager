/// The shape of a single defensive call.
///
/// A `DefensiveScheme` is what a team *is* across a season; this is what it does
/// on one snap. The scheme narrows the menu — a two-high soft team owns few
/// press-man calls and runs them badly — but the call is chosen play by play,
/// by a coordinator or by the player, from the same list either way.
///
/// Composable rather than a flat list of named calls, for the same reason
/// schemes are: the engine reasons about the *components* (is anybody covering
/// the flat, how many rushers, is there help over the top), and named calls are
/// a convenience layer generated over the composition. That way a play designer
/// can produce a call the engine already understands, instead of the engine
/// needing a new case.
///
/// Deliberately parallel to what an offensive playbook entry will be. The
/// offensive side is still only a `PlayID` pointing at a playbook that does not
/// exist yet; when it lands it should read like this file.
public struct DefensiveCall: Sendable, Hashable, Codable {

    public var coverage: Coverage
    public var rush: PassRush
    public var frontAlignment: FrontAlignment
    public var package: DefensivePackage
    /// Where the defence expects the ball to go. Wrong guesses are supposed to
    /// hurt — this is the bet `play-calling.md` describes, made explicit.
    public var runFit: RunFit
    /// Disguise the shell until the snap. Costs a beat of reaction time and
    /// asks more of the secondary's discipline; buys a worse read for the
    /// quarterback.
    public var disguised: Bool

    public init(
        coverage: Coverage,
        rush: PassRush = .fourMan,
        frontAlignment: FrontAlignment = .even,
        package: DefensivePackage = .base,
        runFit: RunFit = .balanced,
        disguised: Bool = false
    ) {
        self.coverage = coverage
        self.rush = rush
        self.frontAlignment = frontAlignment
        self.package = package
        self.runFit = runFit
        self.disguised = disguised
    }
}

/// The coverage behind the front, named the way the sport names it.
public enum Coverage: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// No deep safety. Everything is man, everybody is on an island.
    case coverZero = 0
    /// Man underneath, one deep safety.
    case manFree = 1
    /// Man underneath, two deep safeties.
    case twoMan = 2
    /// Three deep, four under. The default answer to most things.
    case coverThree = 3
    /// Two deep, five under. Soft in the middle, hard on the sideline.
    case coverTwo = 4
    /// Four deep, three under. Concedes everything short.
    case quarters = 5
    /// Pattern-match: zone rules that convert to man off the release.
    case matchQuarters = 6
    /// Deep everything. Late-game only, and it concedes yards on purpose.
    case prevent = 7
    /// No coverage call — everyone is playing the run.
    case runBlitz = 8

    /// Every defender's assignment is a receiver, so a pick or a rub beats it
    /// and a scrambling quarterback is unaccounted for.
    public var isMan: Bool {
        switch self {
        case .coverZero, .manFree, .twoMan: return true
        default: return false
        }
    }

    /// Nobody is deeper than the deepest receiver, so a double move is fatal.
    public var deepDefenders: UInt8 {
        switch self {
        case .coverZero, .runBlitz: return 0
        case .manFree, .coverThree: return 1
        case .twoMan, .coverTwo: return 2
        case .quarters, .matchQuarters: return 4
        case .prevent: return 4
        }
    }

    /// Coverages that trade a defender for a rusher, and therefore need the
    /// rush to arrive.
    public var isPressureCoverage: Bool {
        self == .coverZero || self == .runBlitz
    }
}

/// How many bodies go after the quarterback, and where the extras come from.
public enum PassRush: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Three rush, eight drop. Concede the pocket, take away the throw.
    case threeMan = 0
    case fourMan = 1
    /// Five rushers: one linebacker or defensive back added.
    case fiveManBlitz = 2
    /// Six or more. Somebody is uncovered by construction.
    case sixManBlitz = 3
    /// Four rushers, but not the four who lined up — a tackle drops, a
    /// linebacker comes. Beats a protection call, loses to a quick throw.
    case zoneBlitz = 4
    /// Show pressure, rush four. The bluff.
    case simulated = 5

    public var rushers: UInt8 {
        switch self {
        case .threeMan: return 3
        case .fourMan, .zoneBlitz, .simulated: return 4
        case .fiveManBlitz: return 5
        case .sixManBlitz: return 6
        }
    }

    /// More rushers than the offence can block, so somebody comes free and the
    /// ball has to come out.
    public var isBlitz: Bool {
        self == .fiveManBlitz || self == .sixManBlitz
    }
}

/// How the front is aligned against the offensive line.
public enum FrontAlignment: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Balanced. No declared strength.
    case even = 0
    /// Shifted to the tight end. Strong against the run to that side, soft away.
    case overShifted = 1
    /// Shifted away from the tight end, inviting the run into help.
    case underShifted = 2
    /// Everybody in a gap, nobody head-up. Penetrates; gives up cutback lanes.
    case slanted = 3
    /// Extra body on the line, safety down. Run defence at the cost of the pass.
    case bear = 4

    /// Fronts that commit to a side, and can therefore be run away from.
    public var isDeclared: Bool {
        self == .overShifted || self == .underShifted
    }
}

/// The gap discipline the front plays with — the run half of the same bet.
public enum RunFit: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Read the block, then fit. Gives up a yard, gives up nothing more.
    case balanced = 0
    /// Attack downhill. Stuffs the play it guesses right and is gone if wrong.
    case aggressive = 1
    /// Two gaps a man, hold the point. Slow, and very hard to crease.
    case twoGap = 2
    /// Spill everything outside to the alley defender.
    case spill = 3
    /// Sell out for the stop. Short yardage only, and a play-action away from a
    /// touchdown.
    case sellOut = 4
}

extension DefensiveCall {

    /// A defence with more rushers than deep help. Everything about the call is
    /// a wager on the ball coming out late.
    public var isAllOut: Bool {
        rush.isBlitz && coverage.deepDefenders <= 1
    }

    /// The call concedes yards deliberately, so a completion underneath is a
    /// *success* for the defence and should be reported as one.
    public var concedesUnderneath: Bool {
        coverage == .prevent || coverage == .quarters || rush == .threeMan
    }

    /// Sound against a two-minute drill: enough deep help that the sideline
    /// throw is the only cheap one, and a rush that does not vacate the middle.
    public var isTwoMinuteSound: Bool {
        coverage.deepDefenders >= 2 && !rush.isBlitz
    }

    /// What the call is fundamentally weak against, which is what makes calling
    /// it a decision rather than a preference. Used by the analysis layer to
    /// explain a play, and by the tendency model to know what to punish.
    public var vulnerability: CallVulnerability {
        if coverage == .runBlitz || runFit == .sellOut { return .playAction }
        if isAllOut { return .quickGame }
        if coverage.isMan { return .crossers }
        if rush == .threeMan { return .theRun }
        if rush == .zoneBlitz { return .hotThrow }
        if frontAlignment.isDeclared { return .runAwayFromStrength }
        if coverage.deepDefenders >= 4 { return .theRun }
        return .seams
    }
}

/// The soft spot a call leaves, in the offence's terms.
///
/// There is no `none` case, and that is the design: every defensive call trades
/// something away. A call that covered everything would make the offence's
/// decisions meaningless, and would leave the analysis layer with nothing to say
/// about why a play worked.
public enum CallVulnerability: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// The rush cannot get home before a three-step throw.
    case quickGame = 0
    /// Man coverage and traffic: rubs, mesh, anything crossing the field.
    case crossers = 1
    /// Nobody is left to fit the run.
    case theRun = 2
    /// The front declared a side and the ball went the other way.
    case runAwayFromStrength = 3
    /// The defence bit on the run fake with no help behind it.
    case playAction = 4
    /// The soft spots between zone defenders — the seam behind the flat, the
    /// hole between the corners. What sound zone gives up by construction.
    case seams = 5
    /// A defender rushed and somebody replaced him late. The quick throw to the
    /// area he left is open before the pressure arrives.
    case hotThrow = 6
}

extension DefensiveCall {

    // MARK: - Common calls
    //
    // Convenience over the composition, exactly as named schemes are. These are
    // starting points for a playbook, not a closed list — the engine only ever
    // reads the components.

    public static let baseCoverThree = DefensiveCall(coverage: .coverThree)
    public static let nickelTwoMan = DefensiveCall(
        coverage: .twoMan, package: .nickel)
    public static let quartersMatch = DefensiveCall(
        coverage: .matchQuarters, package: .nickel)
    public static let coverTwoZone = DefensiveCall(coverage: .coverTwo, package: .nickel)
    public static let fireZone = DefensiveCall(
        coverage: .coverThree, rush: .zoneBlitz, package: .nickel)
    public static let manFreeBlitz = DefensiveCall(
        coverage: .manFree, rush: .fiveManBlitz, package: .nickel, disguised: true)
    public static let allOut = DefensiveCall(
        coverage: .coverZero, rush: .sixManBlitz, package: .nickel)
    public static let goalLineStop = DefensiveCall(
        coverage: .runBlitz, rush: .fiveManBlitz, frontAlignment: .bear,
        package: .goalLine, runFit: .sellOut)
    public static let dimeRush = DefensiveCall(
        coverage: .quarters, rush: .fourMan, package: .dime)
    public static let preventShell = DefensiveCall(
        coverage: .prevent, rush: .threeMan, package: .prevent, runFit: .spill)
    public static let runStuff = DefensiveCall(
        coverage: .manFree, rush: .fourMan, frontAlignment: .bear, runFit: .aggressive)
}
