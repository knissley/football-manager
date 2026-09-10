/// The rules of the sport, as data.
///
/// Every number here is configurable so variants can be tested and so a rules change
/// is an edit rather than a hunt through the engine. The defaults are the modern
/// professional game.
///
/// Rules belong to the world, not to the engine: both the crude resolver and the
/// spatial one ask the same questions of the same values
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
///
/// **The defaults are one season's book, and `rulebookSeason` says which.** A value here
/// that came from a different season than that one is a silent contradiction: the
/// touchback sat at the 2024 spot while the overtime rules were the 2025 ones for weeks,
/// and nothing in the tree recorded it. Before moving a number, read the article in
/// [`docs/reference/playing-rules.md`](../../../../docs/reference/playing-rules.md).
///
/// **Bumping the season invalidates calibration.** A band in
/// `Tools/simharness/Sources/simharness/Targets.swift` carries the real-league seasons it
/// was sourced from and a `rulesSensitiveTo` set of the rule areas it depends on; the
/// harness reads `Rules.standard.rulebookSeason`, compares it against those, and prints
/// every row it has made stale. So a rulebook bump is: change the defaults here, add the
/// `RuleChange` for what moved, and re-source the rows the harness then lists. Never
/// widen a band to make one of them pass.
public struct Rules: Sendable, Hashable, Codable {

    // MARK: - The book

    /// The season of the rulebook these defaults were read from.
    ///
    /// It is data rather than a comment because the harness reads it: see the note on the
    /// type. Changing it without changing the values below is how the two came apart.
    public var rulebookSeason: Int

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
    /// Where a free kick that reaches the end zone **without first touching the ground or
    /// a player in the landing zone** is spotted, from the receiving team's own goal
    /// (2025 rulebook, 6-1-5-b, 6-1-5-c, 6-1-5-d): downed there, out of bounds behind the
    /// goal line, or off the goal post or uprights. It was the 30 in the 2024 book.
    ///
    /// The book's other touchback — a kick that comes down in the landing zone first and
    /// is then dead in the end zone, which is spotted at the 20 (6-1-5-a) — is not a
    /// value here because the crude resolver never produces one: a kick it puts in the
    /// landing zone is returned. See the kickoff in `CrudeResolver`.
    public var kickoffTouchbackOwnYard: UInt8
    public var puntTouchbackOwnYard: UInt8
    /// Where the team scored upon kicks off after a safety, from its own goal.
    public var safetyKickoffOwnYard: UInt8
    /// The first period in which the kicking team may declare an onside kick.
    ///
    /// The 2025 book lets it declare at any time during the game, so this is `1`; the
    /// 2024 book allowed it only in the fourth quarter. Being trailing is required under
    /// both and is not configurable — see `mayDeclareOnsideKick` (6-1-1-c, 6-1-6).
    public var onsideKickEarliestQuarter: UInt8

    // MARK: - Overtime

    public var regularSeasonOvertimeLength: UInt16
    public var postseasonOvertimeLength: UInt16
    /// Whether a regular season game may end level.
    public var regularSeasonTiesAllowed: Bool

    public init(
        rulebookSeason: Int = 2025,
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
        kickoffTouchbackOwnYard: UInt8 = 35,
        puntTouchbackOwnYard: UInt8 = 20,
        safetyKickoffOwnYard: UInt8 = 20,
        onsideKickEarliestQuarter: UInt8 = 1,
        regularSeasonOvertimeLength: UInt16 = 600,
        postseasonOvertimeLength: UInt16 = 900,
        regularSeasonTiesAllowed: Bool = true
    ) {
        self.rulebookSeason = rulebookSeason
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
        self.onsideKickEarliestQuarter = onsideKickEarliestQuarter
        self.regularSeasonOvertimeLength = regularSeasonOvertimeLength
        self.postseasonOvertimeLength = postseasonOvertimeLength
        self.regularSeasonTiesAllowed = regularSeasonTiesAllowed
    }

    /// The 2025 rulebook, which is what the engine plays.
    public static let standard = Rules()

    /// The seasons whose books are written down here.
    public static let supportedRulebooks = [2024, 2025]

    /// The rules in force under a season's book, or `nil` for a season nobody has read.
    ///
    /// The variants live here rather than in the harness that plays them, so that a rule
    /// value has one home: a tool that built its own copy of an older book would drift
    /// from this one and nothing would notice.
    ///
    /// 2024 differs from 2025 in the kicking game alone — the touchback at the 30 rather
    /// than the 35 (6-1-5), and an onside kick only in the fourth quarter (6-1-6). Both
    /// are the changes the 2025 book's own list names.
    public static func rulebook(_ season: Int) -> Rules? {
        switch season {
        case 2025:
            return .standard
        case 2024:
            var earlier = Rules.standard
            earlier.rulebookSeason = 2024
            earlier.kickoffTouchbackOwnYard = 30
            earlier.onsideKickEarliestQuarter = 4
            return earlier
        default:
            return nil
        }
    }
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

    /// Whether the rules let the kicking team declare an onside kick now (2025 rulebook,
    /// 6-1-1-c, 6-1-6): at any time during the game, and only while it is trailing.
    ///
    /// **Both halves of that matter and they are easy to swap.** Declaring at any time is
    /// the 2025 change from a fourth quarter that was the 2024 rule, and it is
    /// `onsideKickEarliestQuarter`. Being behind is not a 2025 change and is not
    /// optional: a later book drops it, this one does not, and a team level or ahead may
    /// not ask.
    ///
    /// `scoreDifferential` is the kicking team's, because the kicking team has the ball
    /// on a free kick.
    ///
    /// This is the *rule*. Whether a coach wants one is `PlayCaller.kicksOnside`, and the
    /// two are kept apart so that no caller can declare one the book does not allow.
    public func mayDeclareOnsideKick(quarter: UInt8, scoreDifferential: Int16) -> Bool {
        quarter >= onsideKickEarliestQuarter && scoreDifferential < 0
    }

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

    /// The periods put back in play with a free kick rather than carried on from where
    /// the period before left the ball: every period that opens a half, except the first,
    /// which opens the game.
    ///
    /// The second half: the toss article names the first-half kickoff and gives the
    /// second half's first choice to the captain who lost the pregame toss (4-2-2). The
    /// first period of overtime, which opens after a toss of its own (16-1-2), each side
    /// owed its opportunity to possess, of which a kickoff is the receivers' (16-1-3-a,
    /// 16-1-5-c). A third postseason overtime period, whose first choice of 4-2-2's
    /// privileges 16-1-4-e gives to the captain who lost the toss before overtime. And a
    /// fifth, after the toss 16-1-4-i calls at the end of a fourth — from which the
    /// pairing repeats, by the reading `periodTiming` pins, so a seventh opens as a third
    /// does. A period inside a half is not one: the teams change goals and possession,
    /// the down, the ball and the line to gain are unchanged (4-2-3), which 16-1-4-f
    /// carries into the ends of a first and a third overtime period.
    ///
    /// One predicate, because two layers ask this and a second copy of the answer is how
    /// they come to disagree: `GameState.startNextPeriod` restarts possession, the spot
    /// and the timeouts by it, and `Tools/gamelog` ends a drive by it. It is `opensHalf`
    /// less the game's opening period, so the timeout rule and the timing rule read the
    /// halves the same way.
    public func periodResumesWithKickoff(quarter: UInt8) -> Bool {
        quarter != 1 && opensHalf(quarter: quarter)
    }

    /// Whether a coin is tossed before `quarter` begins: before the game (4-2-2), before
    /// overtime (16-1-2), and again before a fifth overtime period (16-1-4-i) — and, by
    /// the reading `periodTiming` pins past the fourth, before every fourth period after
    /// that. A half that opens without a toss opens with the first choice of the captain
    /// who lost the one before (4-2-2, 16-1-4-e). The engine does not draw the toss;
    /// what stands in for it is `GameState.startNextPeriod`'s to say.
    public func periodFollowsACoinToss(quarter: UInt8) -> Bool {
        if quarter <= quarters { return quarter == 1 }
        return (quarter - quarters) % 4 == 1
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
