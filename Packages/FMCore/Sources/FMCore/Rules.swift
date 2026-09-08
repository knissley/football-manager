/// The rules of the sport, as data.
///
/// Every number here is configurable so variants can be tested and so a rules change
/// is an edit rather than a hunt through the engine. The defaults are the modern
/// professional game.
///
/// Rules belong to the world, not to the engine: both the crude resolver and the
/// spatial one ask the same questions of the same values
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
public struct Rules: Sendable, Hashable, Codable {

    // MARK: - Structure

    public var quarters: UInt8
    /// Seconds in a quarter.
    public var quarterLength: UInt16
    /// Seconds remaining at which each half stops automatically.
    public var twoMinuteWarning: UInt16
    public var downsToGain: UInt8
    public var yardsToGain: UInt8

    // MARK: - Clock

    public var playClock: UInt8
    /// The shorter play clock after an administrative stoppage.
    public var playClockAfterStoppage: UInt8
    public var timeoutsPerHalf: UInt8
    /// Inside this many seconds of the first half, going out of bounds stops the clock
    /// until the snap rather than until the ready-for-play signal.
    public var outOfBoundsStopsClockFirstHalf: UInt16
    /// The same rule late in the second half, where the window is longer.
    public var outOfBoundsStopsClockSecondHalf: UInt16

    // MARK: - Scoring

    public var touchdown: Int16
    public var extraPoint: Int16
    public var twoPointConversion: Int16
    public var fieldGoal: Int16
    public var safety: Int16

    // MARK: - Spots

    /// Yards from the opponent's goal line for an extra point snap.
    public var extraPointSnapYard: UInt8
    public var twoPointSnapYard: UInt8
    /// Depth of the end zone, which a field goal must clear.
    public var endZoneDepth: UInt8
    /// How far behind the line of scrimmage a placekick is struck.
    public var fieldGoalSnapDepth: UInt8
    /// Yards from the kicking team's own goal line.
    public var kickoffFromOwnYard: UInt8
    /// Where a kickoff touchback places the ball, from the receiving team's own goal.
    public var kickoffTouchbackOwnYard: UInt8
    public var puntTouchbackOwnYard: UInt8
    /// Where the team scored upon kicks off after a safety, from its own goal.
    public var safetyKickoffOwnYard: UInt8

    // MARK: - Overtime

    public var regularSeasonOvertimeLength: UInt16
    public var postseasonOvertimeLength: UInt16
    /// Whether a regular season game may end level.
    public var regularSeasonTiesAllowed: Bool

    public init(
        quarters: UInt8 = 4,
        quarterLength: UInt16 = 900,
        twoMinuteWarning: UInt16 = 120,
        downsToGain: UInt8 = 4,
        yardsToGain: UInt8 = 10,
        playClock: UInt8 = 40,
        playClockAfterStoppage: UInt8 = 25,
        timeoutsPerHalf: UInt8 = 3,
        outOfBoundsStopsClockFirstHalf: UInt16 = 120,
        outOfBoundsStopsClockSecondHalf: UInt16 = 300,
        touchdown: Int16 = 6,
        extraPoint: Int16 = 1,
        twoPointConversion: Int16 = 2,
        fieldGoal: Int16 = 3,
        safety: Int16 = 2,
        extraPointSnapYard: UInt8 = 15,
        twoPointSnapYard: UInt8 = 2,
        endZoneDepth: UInt8 = 10,
        fieldGoalSnapDepth: UInt8 = 7,
        kickoffFromOwnYard: UInt8 = 35,
        kickoffTouchbackOwnYard: UInt8 = 30,
        puntTouchbackOwnYard: UInt8 = 20,
        safetyKickoffOwnYard: UInt8 = 20,
        regularSeasonOvertimeLength: UInt16 = 600,
        postseasonOvertimeLength: UInt16 = 900,
        regularSeasonTiesAllowed: Bool = true
    ) {
        self.quarters = quarters
        self.quarterLength = quarterLength
        self.twoMinuteWarning = twoMinuteWarning
        self.downsToGain = downsToGain
        self.yardsToGain = yardsToGain
        self.playClock = playClock
        self.playClockAfterStoppage = playClockAfterStoppage
        self.timeoutsPerHalf = timeoutsPerHalf
        self.outOfBoundsStopsClockFirstHalf = outOfBoundsStopsClockFirstHalf
        self.outOfBoundsStopsClockSecondHalf = outOfBoundsStopsClockSecondHalf
        self.touchdown = touchdown
        self.extraPoint = extraPoint
        self.twoPointConversion = twoPointConversion
        self.fieldGoal = fieldGoal
        self.safety = safety
        self.extraPointSnapYard = extraPointSnapYard
        self.twoPointSnapYard = twoPointSnapYard
        self.endZoneDepth = endZoneDepth
        self.fieldGoalSnapDepth = fieldGoalSnapDepth
        self.kickoffFromOwnYard = kickoffFromOwnYard
        self.kickoffTouchbackOwnYard = kickoffTouchbackOwnYard
        self.puntTouchbackOwnYard = puntTouchbackOwnYard
        self.safetyKickoffOwnYard = safetyKickoffOwnYard
        self.regularSeasonOvertimeLength = regularSeasonOvertimeLength
        self.postseasonOvertimeLength = postseasonOvertimeLength
        self.regularSeasonTiesAllowed = regularSeasonTiesAllowed
    }

    public static let standard = Rules()
}

extension Rules {

    /// The length of a field goal attempt, in yards.
    ///
    /// Yards to the goal line, plus the end zone, plus the depth the kick is struck
    /// from. The ball on the opponent's thirty is a forty-seven yard attempt.
    ///
    /// **One formula, in one place.** It is the sort of arithmetic that gets rewritten
    /// slightly differently at three call sites, and then a kicker's range depends on
    /// which screen is asking.
    public func fieldGoalDistance(ballOn: UInt8) -> Int {
        Int(ballOn) + Int(endZoneDepth) + Int(fieldGoalSnapDepth)
    }

    /// Seconds in a period of overtime.
    public func overtimeLength(isPostseason: Bool) -> UInt16 {
        isPostseason ? postseasonOvertimeLength : regularSeasonOvertimeLength
    }

    /// Whether a game at this stage can end level.
    public func mayEndInATie(isPostseason: Bool) -> Bool {
        !isPostseason && regularSeasonTiesAllowed
    }

    /// `Situation.ballOn` is measured from the *opponent's* goal line, so a spot
    /// described from a team's own goal has to be flipped to be stored.
    ///
    /// One conversion, named, because mixing the two conventions is the recurring
    /// off-by-a-lot bug this codebase has already decided to design out.
    public func ballOnFromOwnYard(_ ownYard: UInt8) -> UInt8 {
        100 - ownYard
    }

    public var kickoffTouchbackSpot: UInt8 { ballOnFromOwnYard(kickoffTouchbackOwnYard) }
    public var puntTouchbackSpot: UInt8 { ballOnFromOwnYard(puntTouchbackOwnYard) }

    /// Seconds in a half.
    public var halfLength: UInt16 { UInt16(quarters / 2) * quarterLength }

    /// The quarter a half ends on.
    public func isEndOfHalf(quarter: UInt8) -> Bool {
        quarter == quarters / 2 || quarter == quarters
    }
}
