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

    /// Seconds from the end of a play to put the ball in play again (2025 rulebook,
    /// 4-6-1). Which clock a snap faces is `playClockAfterAPlay` and its neighbours.
    public var playClock: UInt8
    /// The shorter play clock after an administrative stoppage, from the Referee's
    /// whistle (4-6-2).
    public var playClockAfterStoppage: UInt8
    /// The play clock after a ten-second runoff, from the ready-for-play signal
    /// (4-7-1 Item 1, 4-6-3-c).
    public var playClockAfterRunoff: UInt8
    /// Inside this many seconds of a half, a defensive act that conserves time with the
    /// clock running ends the half unless the defence has a timeout left or the offence
    /// would rather play on (4-7-3). The article's own number.
    public var lastFortySecondsOfAHalf: UInt16
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
    /// Item 2): in the last forty seconds of a half it ends the half instead, unless
    /// the defence has a timeout left or the offence would rather play on (Article 3,
    /// `isInTheLastFortySeconds`). The same ten seconds come off for an excess injury
    /// timeout against the team in possession after the two-minute warning, at the
    /// defence's choice (4-5-4 Note 3). Which foul carries it is `carriesRunoff`; the
    /// decisions are the callers'.
    ///
    /// **Article 4 is not modelled**: the runoff after a replay reversal or a nullified
    /// foul, because there is no replay system and no foul is ever nullified after the
    /// fact. A pin in the engine's suite says so.
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
        playClockAfterRunoff: UInt8 = 30,
        lastFortySecondsOfAHalf: UInt16 = 40,
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
        self.playClockAfterRunoff = playClockAfterRunoff
        self.lastFortySecondsOfAHalf = lastFortySecondsOfAHalf
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

/// Which of Rule 4's closing rules a period is played under: see
/// `Rules.periodTiming(quarter:isPostseason:)`.
public enum PeriodTiming: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// A first or third period: no two-minute warning and no late window.
    case firstOrThird = 0
    /// A second period: the first half's warning, its two-minute out-of-bounds window,
    /// and the runoff after its warning.
    case second = 1
    /// A fourth period: the second half's warning, its five-minute window, and the
    /// runoff after its warning.
    case fourth = 2
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

    /// Which of Rule 4's closing rules `quarter` is played under (2025 rulebook).
    ///
    /// The two-minute warning (3-41), the late out-of-bounds windows (4-3-2-a), the
    /// restart on the snap after a foul inside those windows (4-3-2-e-1, e-2) and the
    /// ten-second runoff (4-7-1) belong to the last period of a half, and which half
    /// decides which of them: the first half's window is two minutes and the second's
    /// five. Regular-season overtime is timed as the fourth period (16-1-3-e).
    /// Postseason overtime pairs its periods into halves — a second overtime period
    /// ends as the first half does and a fourth as the fourth period does (16-1-4-h) —
    /// which leaves a first or a third timed as a first or third quarter, with no
    /// warning and no window. Past the fourth the pairing repeats: a reading of the new
    /// coin toss there (16-1-4-i) rather than a sentence in the book, and pinned as one.
    ///
    /// Every clock case that asks which stage of a half it is in reads this, so no case
    /// can read the postseason differently from another. The one timing rule that is
    /// not a half's closing rule, 4-3-2-e-3, names its own periods and is
    /// `isFourthPeriodOrRegularSeasonOvertime`.
    public func periodTiming(quarter: UInt8, isPostseason: Bool) -> PeriodTiming {
        if quarter <= quarters {
            if quarter == quarters { return .fourth }
            return quarter == quarters / 2 ? .second : .firstOrThird
        }
        guard isPostseason else { return .fourth }
        switch (quarter - quarters) % 4 {
        case 2: return .second
        case 0: return .fourth
        default: return .firstOrThird
        }
    }

    /// Whether `quarter` opens a half, so that the two-minute warning is to come again:
    /// the first and third periods of regulation, the overtime period, and in the
    /// postseason every odd overtime period, because postseason overtime periods pair
    /// into halves (16-1-4-g, 16-1-4-h).
    public func opensHalf(quarter: UInt8) -> Bool {
        if quarter > quarters { return (quarter - quarters) % 2 == 1 }
        return quarter == 1 || quarter == quarters / 2 + 1
    }

    /// The period boundaries **the engine** puts back in play with a free kick, rather
    /// than carrying on from where the period before left the ball.
    ///
    /// Two of them. The second half: the toss article names the first-half kickoff and
    /// gives the second half's first choice to the captain who lost the pregame toss
    /// (4-2-2). And the first period of overtime, which opens like a half, each side owed
    /// its opportunity to possess, of which a kickoff is the receivers' (16-1-3-a,
    /// 16-1-5-c). A period inside a half is not one: the teams change goals and
    /// possession, the down, the ball and the line to gain are unchanged (4-2-3), which
    /// 16-1-4-f carries into the ends of a first and a third overtime period. Nor is the
    /// game's opening kick, because nothing is resumed at the start of a first period, so
    /// the answer there is `false`.
    ///
    /// **The book has a third, and the engine does not model it.** 16-1-4-e gives the
    /// beginning of a *third* overtime period the first choice of 4-2-2's privileges to
    /// the captain who lost the toss before overtime, and 16-1-4-i tosses again after the
    /// fourth, so a third postseason overtime period is put back in play with a kick and
    /// by the same reading so is a fifth — which is what `opensHalf` computes and this
    /// does not. The engine restarts only the first, and 16-1-4-d then reads as another
    /// period beginning with play continuing.
    /// [#86](https://github.com/knissley/football-manager/issues/86) owns that boundary;
    /// until it lands this answers `false` there, pinned by
    /// `aThirdPostseasonOvertimePeriodIsNotRestartedWithAKick`.
    ///
    /// One predicate, because two layers ask this and a second copy of the answer is how
    /// they come to disagree: `GameState.startNextPeriod` restarts possession, the spot
    /// and the timeouts by it, and `Tools/gamelog` ends a drive by it. `AsModelled` is in
    /// the name so that neither call site reads as a claim about the sport.
    public func periodResumesWithKickoffAsModelled(quarter: UInt8) -> Bool {
        quarter == quarters / 2 + 1 || quarter == quarters + 1
    }

    /// The period a half ends on, which is the period with a two-minute warning in it.
    public func isEndOfHalf(quarter: UInt8, isPostseason: Bool) -> Bool {
        periodTiming(quarter: quarter, isPostseason: isPostseason) != .firstOrThird
    }

    /// The periods 4-3-2-e-3 names — the fourth, and regular-season overtime — in which
    /// an offensive foul that stops the clock before a snap has it start on the snap.
    /// The article is not one of a half's closing rules, so 16-1-4-h does not carry it
    /// into postseason overtime, which the article's own words leave out.
    public func isFourthPeriodOrRegularSeasonOvertime(
        quarter: UInt8, isPostseason: Bool
    )
        -> Bool
    {
        quarter == quarters || (!isPostseason && quarter > quarters)
    }

    /// Whether the clock, read at a flag, is inside the closing two minutes of a half —
    /// the window of Rule 4 Section 7 — in a period that ends one: the second, the
    /// fourth, regular-season overtime (16-1-3-e), or a second or fourth postseason
    /// overtime period (16-1-4-h). At exactly the warning the clock has just stopped,
    /// so nothing is running to conserve.
    public func isAfterTheTwoMinuteWarning(
        quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> Bool {
        guard isEndOfHalf(quarter: quarter, isPostseason: isPostseason) else { return false }
        return clockRemaining < twoMinuteWarning
    }

    /// Whether a foul before the snap is one of the acts that conserve time (2025
    /// rulebook, 4-7-1-a): a dead-ball foul, by either side, that stops a running
    /// clock. What the act costs depends on who committed it — `carriesRunoff` for the
    /// offence, `isInTheLastFortySeconds` for the defence.
    ///
    /// Only the dead-ball fouls before the snap are here. Intentional grounding, an
    /// illegal forward pass and the other live-ball acts in the article are not drawn
    /// by the engine yet; when they are (C3), they belong in this predicate.
    public func conservesTime(foul: Foul, clockWasRunning: Bool) -> Bool {
        foul.isPreSnap && clockWasRunning
    }

    /// Whether a foul before the snap carries the ten-second runoff.
    ///
    /// By the offence, after the two-minute warning of either half, with the clock
    /// running into the flag (2025 rulebook, 4-7-1 Item 1, 4-7-2). Never by the
    /// defence (4-7-1 Item 2). Regular-season overtime is timed as the fourth quarter
    /// (16-1-3-e), so its closing two minutes carry the runoff too, and so do a second
    /// and a fourth postseason overtime period's, which end as the halves do (16-1-4-h).
    public func carriesRunoff(
        foul: Foul, byOffense: Bool, quarter: UInt8, isPostseason: Bool,
        clockRemaining: UInt16, clockWasRunning: Bool
    ) -> Bool {
        guard byOffense, conservesTime(foul: foul, clockWasRunning: clockWasRunning) else {
            return false
        }
        return isAfterTheTwoMinuteWarning(
            quarter: quarter, isPostseason: isPostseason, clockRemaining: clockRemaining)
    }

    /// Whether the clock, read at a defensive act that conserves time, is inside the
    /// last forty seconds of a half (2025 rulebook, 4-7-3) — in a period that ends
    /// one, as `periodTiming` reads it, and with time still on it: a half that has
    /// already ended cannot be ended by a foul. Inside it, the half ends unless the
    /// defence has a timeout left or the offence would rather play on.
    public func isInTheLastFortySeconds(
        quarter: UInt8, isPostseason: Bool, clockRemaining: UInt16
    ) -> Bool {
        guard isEndOfHalf(quarter: quarter, isPostseason: isPostseason) else { return false }
        return clockRemaining > 0 && clockRemaining <= lastFortySecondsOfAHalf
    }

    // MARK: - The play clock

    /// The play clock after an ordinary play: `playClock` seconds from the moment the
    /// play ended (2025 rulebook, 4-6-1).
    public var playClockAfterAPlay: PlayClock {
        PlayClock(seconds: playClock, startsOnTheReady: false)
    }

    /// The play clock after an administrative stoppage — a change of possession, a
    /// charged timeout, the two-minute warning, the end of a period, a penalty
    /// enforcement, a free kick — `playClockAfterStoppage` seconds from the Referee's
    /// whistle (4-6-2, 4-6-3-a). Also what a declined runoff leaves (4-7-1 Item 1).
    public var playClockAfterAnAdministrativeStoppage: PlayClock {
        PlayClock(seconds: playClockAfterStoppage, startsOnTheReady: true)
    }

    /// The play clock after a ten-second runoff, from the ready-for-play signal
    /// (4-7-1 Item 1, 4-6-3-c).
    public var playClockAfterARunoff: PlayClock {
        PlayClock(seconds: playClockAfterRunoff, startsOnTheReady: true)
    }

    /// The play clock after a defensive act that conserves time — its dead-ball foul
    /// inside two minutes (4-7-1 Item 2) or its excess injury timeout (4-5-4 Note 1) —
    /// reset to the full `playClock`, from the ready (4-6-3-b).
    public var playClockAfterADefensiveConservation: PlayClock {
        PlayClock(seconds: playClock, startsOnTheReady: true)
    }
}
