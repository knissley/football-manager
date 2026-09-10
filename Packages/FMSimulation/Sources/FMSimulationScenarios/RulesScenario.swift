import FMCore
import FMSimulation

// The library of conformance scenarios, by name.
//
// A rules bug is obvious in thirty seconds of play-by-play and invisible in a table of
// means, and the conformance scenarios are the acceptance language for the rules layer —
// but until this existed nothing let a person *watch* one. `gamelog --scenario <name>`
// does, and this is the list it takes its names from.
//
// The name is a slug rather than the test's own sentence, because the sentence is what a
// reader needs and not what a shell can pass: `football · Rule 11-5-2 · after a safety the
// team scored upon free-kicks from its 20` has spaces and a middle dot in it. So the slug
// is the argument and the test's sentence is printed beside it, in `list` and again as the
// header of the scenario itself, so that a reader knows what he is looking for before the
// first play goes by.
//
// Every scenario the conformance suite runs is a case here, and it is the *only* way to
// reach one: the scripts are internal to this module. A scenario nobody can name is a
// scenario nobody can watch.

/// A rules-conformance scenario, by the name the tool takes.
public enum RulesScenario: String, CaseIterable, Sendable {

    // A safety, and what follows a score
    case safetyFreeKick = "safety-free-kick"
    case touchdownTryKickoff = "touchdown-try-kickoff"
    case fieldGoalThenKickoff = "field-goal-then-kickoff"
    case kickoffReturnTouchdown = "kickoff-return-touchdown"

    // A touchdown on the last play of a period
    case lastPlayTouchdownDownSeven = "last-play-touchdown-down-seven"
    case lastPlayTouchdownDownSix = "last-play-touchdown-down-six"
    case lastPlayTouchdownDownEight = "last-play-touchdown-down-eight"
    case lastPlayTouchdownDownTwo = "last-play-touchdown-down-two"
    case lastPlayTouchdownDownNine = "last-play-touchdown-down-nine"
    case lastPlayTouchdownDownOne = "last-play-touchdown-down-one"
    case lastPlayTouchdownLevel = "last-play-touchdown-level"
    case lastPlayTouchdownUpOne = "last-play-touchdown-up-one"
    case touchdownAsSecondQuarterExpires = "touchdown-as-second-quarter-expires"
    case touchdownAsFirstQuarterExpires = "touchdown-as-first-quarter-expires"

    // Overtime
    case scoreless = "scoreless"
    case scorelessPostseasonUntilTheSixthPeriod = "scoreless-postseason-until-the-sixth-period"
    case overtimeFirstPossessionTouchdown = "overtime-first-possession-touchdown"
    case overtimeFieldGoalsUntilOneIsUnanswered = "overtime-field-goals-until-one-is-unanswered"
    case overtimeKickoffRecoveredByTheKickers = "overtime-kickoff-recovered-by-the-kickers"
    case overtimeKickoffReturnedForTouchdown = "overtime-kickoff-returned-for-touchdown"
    case overtimeTrailingScorerGoesForTwo = "overtime-trailing-scorer-goes-for-two"
    case overtimeFirstPossessionInterceptionReturned =
        "overtime-first-possession-interception-returned"
    case overtimeOpeningDriveSafety = "overtime-opening-drive-safety"

    // The clock
    case puntReturnedAndTackled = "punt-returned-and-tackled"
    case fumbleRecoveredByTheOffense = "fumble-recovered-by-the-offense"
    case fumbleRecoveredByTheDefense = "fumble-recovered-by-the-defense"
    case kickoffReturned = "kickoff-returned"
    case kickoffFairCaught = "kickoff-fair-caught"
    case playEndingJustBeforeTheTwoMinuteWarning = "play-ending-just-before-the-two-minute-warning"
    case playRunningPastTheTwoMinuteWarning = "play-running-past-the-two-minute-warning"
    case playEndingJustBeforeTheTwoMinuteWarningOfOvertime =
        "play-ending-just-before-the-two-minute-warning-of-overtime"
    case playRunningPastTheTwoMinuteWarningOfOvertime =
        "play-running-past-the-two-minute-warning-of-overtime"
    case playEndingAtTwoMinutesOfAFirstPostseasonOvertimePeriod =
        "play-ending-at-two-minutes-of-a-first-postseason-overtime-period"
    case playEndingJustBeforeTheTwoMinuteWarningOfASecondPostseasonOvertimePeriod =
        "play-ending-just-before-the-two-minute-warning-of-a-second-postseason-overtime-period"
    case runnerOutOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriod =
        "runner-out-of-bounds-inside-five-minutes-of-a-second-postseason-overtime-period"
    case runnerOutOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriod =
        "runner-out-of-bounds-inside-five-minutes-of-a-fourth-postseason-overtime-period"

    // Fouls before the snap late in a half
    case falseStartInsideTwoMinutes = "false-start-inside-two-minutes"
    case falseStartInTheThirdQuarter = "false-start-in-the-third-quarter"
    case falseStartInTheFourthQuarterOutsideTwoMinutes =
        "false-start-in-the-fourth-quarter-outside-two-minutes"
    case falseStartInsideTwoMinutesOfOvertime = "false-start-inside-two-minutes-of-overtime"
    case falseStartInOvertimeOutsideTwoMinutes = "false-start-in-overtime-outside-two-minutes"
    case falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod =
        "false-start-inside-two-minutes-of-a-second-postseason-overtime-period"
    case falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes =
        "false-start-in-a-first-postseason-overtime-period-outside-two-minutes"
    case falseStartWithTheClockStopped = "false-start-with-the-clock-stopped"
    case falseStartAgainstATrailingDefense = "false-start-against-a-trailing-defense"
    case falseStartAtTwelveSecondsWithATimeout = "false-start-at-twelve-seconds-with-a-timeout"
    case falseStartAtEightSecondsOfTheHalf = "false-start-at-eight-seconds-of-the-half"
    case neutralZoneInfractionOnATrailingOffense = "neutral-zone-infraction-on-a-trailing-offense"
    case trailingByAPickSix = "trailing-by-a-pick-six"

    // The play clock
    case delayOfGameOnARunningClock = "delay-of-game-on-a-running-clock"
    case delayOfGameAfterATurnoverOnDowns = "delay-of-game-after-a-turnover-on-downs"

    // The last forty seconds of a half
    case neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading =
        "neutral-zone-infraction-in-the-last-forty-seconds-with-the-offense-leading"
    case neutralZoneInfractionInTheLastFortySecondsLevel =
        "neutral-zone-infraction-in-the-last-forty-seconds-level"
    case neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft =
        "neutral-zone-infraction-in-the-last-forty-seconds-with-a-defensive-timeout-left"

    // An injury after the two-minute warning
    case injuryInsideTwoMinutesWithATimeoutLeft = "injury-inside-two-minutes-with-a-timeout-left"
    case injuryInsideTwoMinutesWithNoTimeoutsLeft =
        "injury-inside-two-minutes-with-no-timeouts-left"
    case injuryInsideTwoMinutesAgainstATrailingDefense =
        "injury-inside-two-minutes-against-a-trailing-defense"

    // Tries, kicks and enforcement
    case falseStartOnATry = "false-start-on-a-try"
    case missedFieldGoalFromTheTen = "missed-field-goal-from-the-ten"
    case missedFieldGoalFromTheTwenty = "missed-field-goal-from-the-twenty"
    case defensiveHoldingAtTheThree = "defensive-holding-at-the-three"
    case falseStartAtTheOwnThree = "false-start-at-the-own-three"
    case facemaskAtTheEndOfARun = "facemask-at-the-end-of-a-run"
    case interferenceInTheEndZone = "interference-in-the-end-zone"
    case interferenceInTheEndZoneFromTheOne = "interference-in-the-end-zone-from-the-one"
    case onsideKickRecovered = "onside-kick-recovered"
}

// MARK: - Naming

extension RulesScenario {

    /// The name the tool takes on the command line, and prints.
    public var slug: String { rawValue }

    /// The scenario of that name, if there is one.
    public init?(_ slug: String) {
        self.init(rawValue: slug)
    }
}

// MARK: - The game

extension RulesScenario {

    /// The scripted game itself.
    public var game: ScriptedGame {
        switch self {
        case .safetyFreeKick: return RulesScenarios.safetyFreeKick
        case .touchdownTryKickoff: return RulesScenarios.touchdownTryKickoff
        case .fieldGoalThenKickoff: return RulesScenarios.fieldGoalThenKickoff
        case .kickoffReturnTouchdown: return RulesScenarios.kickoffReturnTouchdown

        case .lastPlayTouchdownDownSeven: return RulesScenarios.lastPlayTouchdownDownSeven
        case .lastPlayTouchdownDownSix: return RulesScenarios.lastPlayTouchdownDownSix
        case .lastPlayTouchdownDownEight: return RulesScenarios.lastPlayTouchdownDownEight
        case .lastPlayTouchdownDownTwo: return RulesScenarios.lastPlayTouchdownDownTwo
        case .lastPlayTouchdownDownNine: return RulesScenarios.lastPlayTouchdownDownNine
        case .lastPlayTouchdownDownOne: return RulesScenarios.lastPlayTouchdownDownOne
        case .lastPlayTouchdownLevel: return RulesScenarios.lastPlayTouchdownLevel
        case .lastPlayTouchdownUpOne: return RulesScenarios.lastPlayTouchdownUpOne
        case .touchdownAsSecondQuarterExpires:
            return RulesScenarios.touchdownAsSecondQuarterExpires
        case .touchdownAsFirstQuarterExpires: return RulesScenarios.touchdownAsFirstQuarterExpires

        case .scoreless: return RulesScenarios.scoreless
        case .scorelessPostseasonUntilTheSixthPeriod:
            return RulesScenarios.scorelessPostseasonUntilTheSixthPeriod
        case .overtimeFirstPossessionTouchdown:
            return RulesScenarios.overtimeFirstPossessionTouchdown
        case .overtimeFieldGoalsUntilOneIsUnanswered:
            return RulesScenarios.overtimeFieldGoalsUntilOneIsUnanswered
        case .overtimeKickoffRecoveredByTheKickers:
            return RulesScenarios.overtimeKickoffRecoveredByTheKickersAfterFieldGoal
        case .overtimeKickoffReturnedForTouchdown:
            return RulesScenarios.overtimeKickoffReturnedForTouchdownAfterFieldGoal
        case .overtimeTrailingScorerGoesForTwo:
            return RulesScenarios.overtimeTrailingScorerGoesForTwo
        case .overtimeFirstPossessionInterceptionReturned:
            return RulesScenarios.overtimeFirstPossessionInterceptionReturned
        case .overtimeOpeningDriveSafety: return RulesScenarios.overtimeOpeningDriveSafety

        case .puntReturnedAndTackled: return RulesScenarios.puntReturnedAndTackled
        case .fumbleRecoveredByTheOffense: return RulesScenarios.fumbleRecoveredByTheOffense
        case .fumbleRecoveredByTheDefense: return RulesScenarios.fumbleRecoveredByTheDefense
        case .kickoffReturned: return RulesScenarios.kickoffReturned
        case .kickoffFairCaught: return RulesScenarios.kickoffFairCaught
        case .playEndingJustBeforeTheTwoMinuteWarning:
            return RulesScenarios.playStretchedToEnd(quarter: 4, at: 121)
        case .playRunningPastTheTwoMinuteWarning:
            return RulesScenarios.playStretchedToEnd(quarter: 2, at: 117)
        case .playEndingJustBeforeTheTwoMinuteWarningOfOvertime:
            return RulesScenarios.playStretchedToEnd(quarter: 5, at: 121)
        case .playRunningPastTheTwoMinuteWarningOfOvertime:
            return RulesScenarios.playStretchedToEnd(quarter: 5, at: 117)
        case .playEndingAtTwoMinutesOfAFirstPostseasonOvertimePeriod:
            return RulesScenarios.playStretchedToEnd(quarter: 5, at: 121, postseasonDecidedIn: 6)
        case .playEndingJustBeforeTheTwoMinuteWarningOfASecondPostseasonOvertimePeriod:
            return RulesScenarios.playStretchedToEnd(quarter: 6, at: 121, postseasonDecidedIn: 7)
        case .runnerOutOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriod:
            return RulesScenarios.runnerOutOfBounds(
                quarter: 6, window: 226...300, postseasonDecidedIn: 7)
        case .runnerOutOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriod:
            return RulesScenarios.runnerOutOfBounds(
                quarter: 8, window: 226...300, postseasonDecidedIn: 9)

        case .falseStartInsideTwoMinutes: return RulesScenarios.falseStartInsideTwoMinutes
        case .falseStartInTheThirdQuarter: return RulesScenarios.falseStartInTheThirdQuarter
        case .falseStartInTheFourthQuarterOutsideTwoMinutes:
            return RulesScenarios.falseStartInTheFourthQuarterOutsideTwoMinutes
        case .falseStartInsideTwoMinutesOfOvertime:
            return RulesScenarios.falseStartInsideTwoMinutesOfOvertime
        case .falseStartInOvertimeOutsideTwoMinutes:
            return RulesScenarios.falseStartInOvertimeOutsideTwoMinutes
        case .falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod:
            return RulesScenarios.falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod
        case .falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes:
            return RulesScenarios.falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes
        case .falseStartWithTheClockStopped: return RulesScenarios.falseStartWithTheClockStopped
        case .falseStartAgainstATrailingDefense:
            return RulesScenarios.falseStartAgainstATrailingDefense
        case .falseStartAtTwelveSecondsWithATimeout:
            return RulesScenarios.falseStartAtTwelveSecondsWithATimeout
        case .falseStartAtEightSecondsOfTheHalf:
            return RulesScenarios.falseStartAtEightSecondsOfTheHalf
        case .neutralZoneInfractionOnATrailingOffense:
            return RulesScenarios.neutralZoneInfractionOnATrailingOffense
        case .trailingByAPickSix: return RulesScenarios.trailingByAPickSix

        case .delayOfGameOnARunningClock: return RulesScenarios.delayOfGameOnARunningClock
        case .delayOfGameAfterATurnoverOnDowns:
            return RulesScenarios.delayOfGameAfterATurnoverOnDowns

        case .neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading:
            return RulesScenarios.neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading
        case .neutralZoneInfractionInTheLastFortySecondsLevel:
            return RulesScenarios.neutralZoneInfractionInTheLastFortySecondsLevel
        case .neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft:
            return RulesScenarios
                .neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft

        case .injuryInsideTwoMinutesWithATimeoutLeft:
            return RulesScenarios.injuryInsideTwoMinutesWithATimeoutLeft
        case .injuryInsideTwoMinutesWithNoTimeoutsLeft:
            return RulesScenarios.injuryInsideTwoMinutesWithNoTimeoutsLeft
        case .injuryInsideTwoMinutesAgainstATrailingDefense:
            return RulesScenarios.injuryInsideTwoMinutesAgainstATrailingDefense

        case .falseStartOnATry: return RulesScenarios.falseStartOnATry
        case .missedFieldGoalFromTheTen: return RulesScenarios.missedFieldGoal(from: 10)
        case .missedFieldGoalFromTheTwenty: return RulesScenarios.missedFieldGoal(from: 20)
        case .defensiveHoldingAtTheThree: return RulesScenarios.defensiveHoldingAtTheThree
        case .falseStartAtTheOwnThree: return RulesScenarios.falseStartAtTheOwnThree
        case .facemaskAtTheEndOfARun: return RulesScenarios.facemaskAtTheEndOfARun
        case .interferenceInTheEndZone: return RulesScenarios.interferenceInTheEndZone
        case .interferenceInTheEndZoneFromTheOne:
            return RulesScenarios.interferenceInTheEndZoneFromTheOne
        case .onsideKickRecovered: return RulesScenarios.onsideKickRecovered
        }
    }

    /// Whether the scenario is a question about what the *baseline* caller does with a
    /// game rather than about what the rules do with a script.
    ///
    /// The endgame scenario scripts the football — a pick-six, then chains that move —
    /// and leaves the spike, the timeouts and the kneel to `BaselineCaller`, which is the
    /// thing under test. Running it with the scripted caller would be a different game
    /// from the one the suite asserts on, which is exactly what a printer must not show.
    public var usesBaselineCaller: Bool {
        self == .trailingByAPickSix
    }

    /// Play it, with the caller the suite plays it with.
    public func run() -> Trace {
        usesBaselineCaller ? game.run(with: BaselineCaller()) : game.run()
    }
}

// MARK: - What the scenario is there to show

extension RulesScenario {

    /// What the conformance suite asserts about this scenario, verbatim: the football
    /// sentence and the rule it comes from, as the test that runs it is named.
    ///
    /// More than one where more than one test runs the same game — a scoreless walk is
    /// four football sentences and a walk to overtime — which is the point of printing
    /// them: they are what a reader watches the play-by-play for.
    public var expectations: [String] {
        switch self {
        case .safetyFreeKick:
            return [
                "football · Rule 11-5-2 · after a safety the team scored upon free-kicks from its 20"
            ]
        case .touchdownTryKickoff:
            return [
                "football · Rule 11-3-4 · after the try the team that defended it receives the kickoff"
            ]
        case .fieldGoalThenKickoff:
            return [
                "football · Rule 11-4-6 · after a successful field goal the team scored upon receives the kickoff"
            ]
        case .kickoffReturnTouchdown:
            return [
                "football · Rule 11-3-1, 11-3-4 · a kickoff returned for a touchdown gets its try, and the returning team then kicks off"
            ]

        case .lastPlayTouchdownDownSeven:
            return [
                "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 16-1-3 · a touchdown as the fourth quarter expires, down seven, gets its try in that period at 0:00, and the kick sends the game to overtime"
            ]
        case .lastPlayTouchdownDownSix:
            return [
                "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the fourth quarter expires, down six, gets its try in that period at 0:00, and the kick wins it"
            ]
        case .lastPlayTouchdownDownEight:
            return [
                "football · Rule 4-8-2, 4-8-2-c, 11-3-2-b, 16-1-3 · a touchdown as the fourth quarter expires, down eight, gets a two-point try in that period at 0:00, and the conversion sends the game to overtime"
            ]
        case .lastPlayTouchdownDownTwo:
            return [
                "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down two, gets no try because no try could affect the outcome"
            ]
        case .lastPlayTouchdownDownNine:
            return [
                "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down nine, gets no try because no try could affect the outcome"
            ]
        case .lastPlayTouchdownDownOne:
            return [
                "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, down one, gets no try"
            ]
        case .lastPlayTouchdownLevel:
            return [
                "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, level, gets no try"
            ]
        case .lastPlayTouchdownUpOne:
            return [
                "football · Rule 4-8-2-c · a touchdown as the fourth quarter expires, up one, gets no try"
            ]
        case .touchdownAsSecondQuarterExpires:
            return [
                "football · Rule 4-8-2, 4-8-2-c, 11-3-1 · a touchdown as the second quarter expires gets its try in that period at 0:00, and the second half then opens with a kickoff"
            ]
        case .touchdownAsFirstQuarterExpires:
            return [
                "football · Rule 4-8-2, 4-8-2-c, 11-3-1, 11-3-4 · a touchdown as the first quarter expires gets its try in that period at 0:00, and the scoring team kicks off to open the second"
            ]

        case .scoreless:
            return [
                "football · Rule 4-1-1, 16-1-3 · a regular-season game level after four periods goes to one ten-minute overtime period",
                "football · Rule 16-1-3-d · regular-season overtime is never extended: level at the end of it is a tie",
                "football · Rule 16-1-3-e · each team has two timeouts in regular-season overtime",
                "football · Rule 4-4-i, 4-3-2-a-1 · a turnover on downs stops the clock until the snap",
                "football · Rule 4-3-1, 4-4-d · a kickoff touchback consumes no time",
            ]
        case .scorelessPostseasonUntilTheSixthPeriod:
            return [
                "football · Rule 16-1-4, 16-1-4-d · a postseason game level after the fifth period plays a sixth, of fifteen minutes"
            ]
        case .overtimeFirstPossessionTouchdown:
            return [
                "football · Rule 16-1-3-a, 16-1-3-b, 11-3-1 · a touchdown on the first overtime possession gets its try, and the other team then possesses"
            ]
        case .overtimeFieldGoalsUntilOneIsUnanswered:
            return [
                "football · Rule 16-1-3-b, 16-1-3-c · once both teams have possessed in overtime, level, the next score of any kind wins"
            ]
        case .overtimeKickoffRecoveredByTheKickers:
            return [
                "football · Rule 16-1-3-b, 16-1-5-c, A.R. 16.2 · after a field goal on the opening overtime possession, a kickoff the kicking team recovers ends the game"
            ]
        case .overtimeKickoffReturnedForTouchdown:
            return [
                "football · Rule 16-1-3-b, 16-1-3-c, 16-1-5-c, A.R. 16.4 · after a field goal on the opening overtime possession, a kickoff returned for a touchdown ends the game with no try"
            ]
        case .overtimeTrailingScorerGoesForTwo:
            return [
                "football · Rule 16-1-3-b, 16-1-3-c, 4-8-2-c, 11-3-1 · once both have possessed in overtime, a touchdown that leaves the scorer behind gets its try, and the conversion that puts him ahead ends it"
            ]
        case .overtimeFirstPossessionInterceptionReturned:
            return [
                "football · Rule 16-1-5-b, 16-1-3-b · an interception returned for a touchdown on the first overtime possession ends the game"
            ]
        case .overtimeOpeningDriveSafety:
            return [
                "football · Rule 16-1-3-a · a safety against the opening overtime drive wins it for the team that kicked off"
            ]

        case .puntReturnedAndTackled:
            return [
                "football · Rule 4-4-i, 4-3-2-a-1 · a punt returned and tackled in bounds stops the clock until the snap"
            ]
        case .fumbleRecoveredByTheOffense:
            return [
                "football · Rule 4-4 · a fumble recovered by the offence keeps the clock running"
            ]
        case .fumbleRecoveredByTheDefense:
            return [
                "football · Rule 4-4-i, 4-3-2-a-1 · a fumble recovered by the defence stops the clock until the snap"
            ]
        case .kickoffReturned:
            return [
                "football · Rule 4-4-a, 4-3-1, 4-4-i · a returned kickoff advances the game clock by the return, and no more"
            ]
        case .kickoffFairCaught:
            return ["football · Rule 4-3-1-c · a fair-caught kickoff starts no clock"]
        case .playEndingJustBeforeTheTwoMinuteWarning:
            return [
                "football · Rule 3-41, 4-4-h · the two-minute warning stops a running clock at exactly 2:00 and the snap restarts it"
            ]
        case .playRunningPastTheTwoMinuteWarning:
            return [
                "football · Rule 3-41 · a down under way when the clock runs past 2:00 finishes, and the clock is dead after it"
            ]
        case .playEndingJustBeforeTheTwoMinuteWarningOfOvertime:
            return [
                "football · Rule 3-41, 16-1-3-e · the two-minute warning stops a running clock at exactly 2:00 of a regular-season overtime period, and the snap restarts it"
            ]
        case .playRunningPastTheTwoMinuteWarningOfOvertime:
            return [
                "football · Rule 3-41, 16-1-3-e · a down under way when the clock runs past 2:00 of a regular-season overtime period finishes, and the clock is dead after it"
            ]
        case .playEndingAtTwoMinutesOfAFirstPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-h, 3-41 · a first postseason overtime period is timed as a first period: the clock runs through 2:00 with nothing to stop it"
            ]
        case .playEndingJustBeforeTheTwoMinuteWarningOfASecondPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-h, 3-41 · a second postseason overtime period ends as the first half does: the warning stops a running clock at exactly 2:00, and the snap restarts it"
            ]
        case .runnerOutOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-h, 4-3-2-a · a second postseason overtime period carries the first half's two-minute window, so a runner out of bounds inside its last five minutes but outside two stops the clock only until the ball is ready"
            ]
        case .runnerOutOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-h, 4-3-2-a · a fourth postseason overtime period carries the fourth period's five-minute window, so a runner out of bounds inside its last five minutes stops the clock until the snap"
            ]

        case .falseStartInsideTwoMinutes:
            return [
                "football · Rule 4-7-1 Item 1 · inside two minutes a false start with the clock running costs ten seconds, and the clock restarts on the ready"
            ]
        case .falseStartInTheThirdQuarter:
            return [
                "football · Rule 4-7-1, 4-4-e, 4-3-2-e · outside the late-game windows a false start with the clock running carries no runoff, and the clock restarts as if the foul had not occurred"
            ]
        case .falseStartInTheFourthQuarterOutsideTwoMinutes:
            return [
                "football · Rule 4-3-2-e-3, 4-4-e · an offensive foul before the snap in the fourth quarter costs the huddle and nothing else, and the clock then starts on the snap"
            ]
        case .falseStartInsideTwoMinutesOfOvertime:
            return [
                "football · Rule 16-1-3-e, 4-7-1 Item 1 · inside two minutes of regular-season overtime a false start with the clock running carries the runoff, and the clock restarts on the ready"
            ]
        case .falseStartInOvertimeOutsideTwoMinutes:
            return [
                "football · Rule 4-3-2-e-3, 16-1-3-e · an offensive foul before the snap in regular-season overtime, outside every window, costs the huddle and nothing else, and the clock then starts on the snap"
            ]
        case .falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-h, 4-7-1 Item 1 · inside two minutes of a second postseason overtime period a false start with the clock running carries the runoff, and the clock restarts on the ready"
            ]
        case .falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes:
            return [
                "football · Rule 4-3-2-e-3, 16-1-4-h · an offensive foul before the snap in a first postseason overtime period, outside every window, restarts the clock on the ready as though the flag had never flown, because 4-3-2-e-3 names the fourth period and regular-season overtime only"
            ]
        case .falseStartWithTheClockStopped:
            return [
                "football · Rule 4-7-1 Item 1 · a false start with the clock stopped carries no runoff"
            ]
        case .falseStartAgainstATrailingDefense:
            return [
                "football · Rule 4-7-1 Item 1 · the defence may decline the runoff and keep the yardage"
            ]
        case .falseStartAtTwelveSecondsWithATimeout:
            return [
                "football · Rule 4-7-1 Item 1 · the offence may take a charged timeout instead of the runoff, and the clock then starts on the snap"
            ]
        case .falseStartAtEightSecondsOfTheHalf:
            return [
                "football · Rule 4-7-1 Item 1, 4-5-4 Note 4 · a ten-second runoff at eight seconds ends the half"
            ]
        case .neutralZoneInfractionOnATrailingOffense:
            return [
                "football · Rule 4-7-1 Item 2, 4-4-e, 4-3-2-e · a defensive foul before the snap charges no time and the clock waits for the snap"
            ]
        case .trailingByAPickSix:
            return [
                "football · Rule 4-4-f, 4-3-2 · an incomplete pass, here a spike, stops the clock until the snap",
                "pin · the baseline caller spikes at hurry-up tempo, and a hurry-up snap takes less clock than a huddle (PlayCaller.swift:224; the interval is a modelling convention, not a rule)",
            ]

        case .delayOfGameOnARunningClock:
            return [
                "football · Rule 4-6-1, 4-6-4, 14-4-1 · a delay of game when the 40-second play clock expires with the ball not snapped: five yards, the down replayed, and the whole play clock gone from a running game clock"
            ]
        case .delayOfGameAfterATurnoverOnDowns:
            return [
                "football · Rule 4-6-2-a, 4-6-4 · after a change of possession the play clock is 25 seconds, and letting it expire with the game clock stopped is a delay of game that costs no time"
            ]

        case .neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading:
            return [
                "football · Rule 4-7-3 · in the last forty seconds a defensive foul that conserves time ends the half when the defence has no timeouts left and the offence, leading, elects to end it"
            ]
        case .neutralZoneInfractionInTheLastFortySecondsLevel:
            return [
                "football · Rule 4-7-3, 4-7-1 Item 2 · in the last forty seconds a defensive foul that conserves time does not end the half when the offence, level, would rather play on, and the clock then waits for the snap"
            ]
        case .neutralZoneInfractionInTheLastFortySecondsWithADefensiveTimeoutLeft:
            return [
                "football · Rule 4-7-3 · in the last forty seconds a defensive foul that conserves time does not end the half while the defence has a timeout left"
            ]

        case .injuryInsideTwoMinutesWithATimeoutLeft:
            return [
                "football · Rule 4-5-4-a, 4-3-2 · after the two-minute warning an injury to a player of the team in possession costs it a charged timeout, and the clock waits for the snap"
            ]
        case .injuryInsideTwoMinutesWithNoTimeoutsLeft:
            return [
                "football · Rule 4-5-4-b, 4-5-4 Note 3 · after the two-minute warning an injury to a player of the team in possession, with no timeouts left, is an excess timeout: the defence has ten seconds run off, and the clock starts on the ready"
            ]
        case .injuryInsideTwoMinutesAgainstATrailingDefense:
            return [
                "football · Rule 4-5-4 Note 3, 4-5-4 Note 1 · the defence may decline the injury runoff; a trailing defence does, and the clock then waits for the snap"
            ]

        case .falseStartOnATry:
            return [
                "football · Rule 11-3-1, 7-4-2 · a false start on a try moves the try back five yards",
                "football · Rule 11-3-3 Item 2, 7-4-2 · a false start on an extra point re-kicks from the 20, a 37-yard try",
            ]
        case .missedFieldGoalFromTheTen:
            return [
                "football · Rule 11-4-2 · a missed field goal struck from inside the 20 gives the defence the ball at its 20"
            ]
        case .missedFieldGoalFromTheTwenty:
            return [
                "football · Rule 11-4-2 · a missed field goal struck from beyond the 20 gives the defence the ball where it was struck"
            ]
        case .defensiveHoldingAtTheThree:
            return [
                "football · Rule 8-4-6, 12-1-6, 14-4 (closest section) · defensive holding at the 3 is half the distance and a first down"
            ]
        case .falseStartAtTheOwnThree:
            return [
                "football · Rule 7-4-2, 14-4 (closest section) · a false start at the own 3 is half the distance to the goal line"
            ]
        case .facemaskAtTheEndOfARun:
            return [
                "football · Rule 12-2-15, 14-4 (closest section) · a facemask at the end of a 20-yard run is 15 more from the end of the run, and a first down"
            ]
        case .interferenceInTheEndZone:
            return [
                "football · Rule 8-5-4 · defensive pass interference in the end zone is first and goal at the 1"
            ]
        case .interferenceInTheEndZoneFromTheOne:
            return [
                "football · Rule 8-5-4 · defensive pass interference in the end zone from inside the 2 is half the distance, and still a first down"
            ]
        case .onsideKickRecovered:
            return [
                "football · Rule 4-3-1-b, 4-3-2 · a kickoff the kicking team recovers starts no clock, and the clock waits for the snap",
                "football · Rule 6-1-6, 6-1-4-c, 6-1-4-d · an onside kick the kicking team recovers is its ball, first and ten, where it was recovered",
            ]
        }
    }
}

// MARK: - The listing

extension RulesScenario {

    /// Every scenario, as `--scenario list` prints it: the name to pass, and under it the
    /// football each one is there to show.
    ///
    /// Built here rather than in the tool so that the list a reader sees is the list the
    /// suite is checked against.
    public static func listing() -> [String] {
        var lines: [String] = []
        for scenario in allCases {
            lines.append("  \(scenario.slug)")
            for expectation in scenario.expectations {
                lines.append("      \(expectation)")
            }
        }
        return lines
    }
}
