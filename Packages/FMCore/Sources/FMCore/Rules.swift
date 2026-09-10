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
    /// Charged timeouts per team in a regular-season overtime period (2025 rulebook,
    /// 16-1-3-e). Postseason overtime keeps `timeoutsPerHalf` (16-1-4-g).
    public var regularSeasonOvertimeTimeouts: UInt8
    /// Inside this many seconds of the first half, going out of bounds stops the clock
    /// until the snap rather than until the ready-for-play signal.
    public var outOfBoundsStopsClockFirstHalf: UInt16
    /// The same rule late in the second half, where the window is longer.
    public var outOfBoundsStopsClockSecondHalf: UInt16
    /// Seconds run off the game clock when the offence conserves time illegally after
    /// the two-minute warning of either half with the clock running.
    ///
    /// Modelled from the 2025 rulebook, Rule 4 Section 7: a dead-ball foul by the
    /// offence that stops a running clock carries the runoff on top of its yardage
    /// (Article 1, Item 1), and so does an illegal substitution (Article 2). The
    /// offence may spend a charged timeout instead, and the clock then starts on the
    /// snap; the defence may decline the runoff and keep the yardage; after a runoff the
    /// clock starts on the ready-for-play signal (4-3-2-g), and a half can end on one
    /// (4-5-4 Note 4). The same act by the defence never carries a runoff (Article 1,
    /// Item 2). Which foul carries it is `carriesRunoff`; the decisions are the
    /// callers'.
    ///
    /// **Article 3 is not modelled**: a defensive foul that conserves time in the last
    /// forty seconds can end the half unless the offence elects to play on, and here
    /// the offence always elects to play on. Nor is Article 4, the runoff after a replay
    /// reversal or a nullified foul, because there is no replay.
    public var tenSecondRunoff: UInt16

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
        regularSeasonOvertimeTimeouts: UInt8 = 2,
        outOfBoundsStopsClockFirstHalf: UInt16 = 120,
        outOfBoundsStopsClockSecondHalf: UInt16 = 300,
        tenSecondRunoff: UInt16 = 10,
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
        self.regularSeasonOvertimeTimeouts = regularSeasonOvertimeTimeouts
        self.outOfBoundsStopsClockFirstHalf = outOfBoundsStopsClockFirstHalf
        self.outOfBoundsStopsClockSecondHalf = outOfBoundsStopsClockSecondHalf
        self.tenSecondRunoff = tenSecondRunoff
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

    /// Whether `quarter` is played under the fourth period's timing rules: the fourth
    /// period itself, and regular-season overtime, whose general provisions are the
    /// fourth quarter's (2025 rulebook, 16-1-3-e). Postseason overtime reads its own
    /// periods differently (16-1-4-h) and is not modelled here.
    public func hasFourthPeriodTiming(quarter: UInt8, isPostseason: Bool) -> Bool {
        quarter == quarters || (!isPostseason && quarter > quarters)
    }

    /// Whether the clock, read at a flag, is inside the closing two minutes of a half —
    /// the window of Rule 4 Section 7 — with regular-season overtime carrying the
    /// fourth period's timing (16-1-3-e). At exactly the warning the clock has just
    /// stopped, so nothing is running to conserve.
    public func isAfterTheTwoMinuteWarning(
        quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> Bool {
        guard
            quarter == quarters / 2
                || hasFourthPeriodTiming(quarter: quarter, isPostseason: isPostseason)
        else { return false }
        return clockRemaining < twoMinuteWarning
    }

    /// Whether a foul before the snap carries the ten-second runoff.
    ///
    /// By the offence, after the two-minute warning of either half, with the clock
    /// running into the flag (2025 rulebook, 4-7-1 Item 1, 4-7-2). Never by the
    /// defence (4-7-1 Item 2). Regular-season overtime is timed as the fourth quarter
    /// (16-1-3-e), so its closing two minutes carry the runoff too.
    ///
    /// Only the dead-ball fouls before the snap are here. Intentional grounding, an
    /// illegal forward pass and the other live-ball acts in the article are not drawn
    /// by the engine yet; when they are (C3), they belong in this predicate.
    public func carriesRunoff(
        foul: Foul, byOffense: Bool, quarter: UInt8, isPostseason: Bool,
        clockRemaining: UInt16, clockWasRunning: Bool
    ) -> Bool {
        guard byOffense, foul.isPreSnap, clockWasRunning else { return false }
        return isAfterTheTwoMinuteWarning(
            quarter: quarter, isPostseason: isPostseason, clockRemaining: clockRemaining)
    }
}
