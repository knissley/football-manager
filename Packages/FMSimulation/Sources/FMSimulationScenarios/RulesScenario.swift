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
    case twoPointTryIntercepted = "two-point-try-intercepted"

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
    case thirdPostseasonOvertimePeriod = "third-postseason-overtime-period"
    case thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff =
        "third-postseason-overtime-period-with-the-toss-loser-kicking-off"
    case fifthPostseasonOvertimePeriod = "fifth-postseason-overtime-period"

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
    case runnerOutOfBoundsInsideFiveMinutesOfTheFourthQuarter =
        "runner-out-of-bounds-inside-five-minutes-of-the-fourth-quarter"
    case runnerOutOfBoundsAcrossFiveMinutesOfTheFourthQuarter =
        "runner-out-of-bounds-across-five-minutes-of-the-fourth-quarter"
    case runnerOutOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarter =
        "runner-out-of-bounds-across-the-two-minute-warning-of-the-second-quarter"
    case periodExpiringBetweenDowns = "period-expiring-between-downs"
    case twoMinuteDrill = "two-minute-drill"

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

    // Fouls during a down
    case defensiveHoldingOnAPlayEndingInBounds = "defensive-holding-on-a-play-ending-in-bounds"
    case defensiveHoldingInsideFiveMinutesOfTheFourthQuarter =
        "defensive-holding-inside-five-minutes-of-the-fourth-quarter"
    case offensiveHoldingInTheFourthQuarterOutsideFiveMinutes =
        "offensive-holding-in-the-fourth-quarter-outside-five-minutes"

    // The spike
    case spikeSnappedAtTwentySeconds = "spike-snapped-at-twenty-seconds"
    case spikeSnappedAtFiveSecondsOnThirdDown = "spike-snapped-at-five-seconds-on-third-down"

    // The play clock
    case delayOfGameOnARunningClock = "delay-of-game-on-a-running-clock"
    case delayOfGameAfterATurnoverOnDowns = "delay-of-game-after-a-turnover-on-downs"
    case thePlayClockExpiresOnThirdAndOne = "the-play-clock-expires-on-third-and-one"
    case aTimeoutBeatsThePlayClockOnThirdAndOne = "a-timeout-beats-the-play-clock-on-third-and-one"

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
    case injuryToADefenderInTheLastFortySeconds = "injury-to-a-defender-in-the-last-forty-seconds"

    // The kickoff that opens a half
    case secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf =
        "second-half-kickoff-after-an-injury-runoff-ends-the-first-half"
    case secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf =
        "second-half-kickoff-returned-after-an-injury-runoff-ends-the-first-half"

    // Tries, kicks and enforcement
    case falseStartOnATry = "false-start-on-a-try"
    case missedFieldGoalFromTheTen = "missed-field-goal-from-the-ten"
    case missedFieldGoalFromTheTwenty = "missed-field-goal-from-the-twenty"
    case defensiveHoldingAtTheThree = "defensive-holding-at-the-three"
    case defensiveHoldingAtTheSeven = "defensive-holding-at-the-seven"
    case falseStartAtTheOwnThree = "false-start-at-the-own-three"
    case falseStartAtTheOwnSeven = "false-start-at-the-own-seven"
    case facemaskAtTheEndOfARun = "facemask-at-the-end-of-a-run"
    case facemaskAtTheTwenty = "facemask-at-the-twenty"
    case twoPointTryWalkedOutAndBackIn = "two-point-try-walked-out-and-back-in"
    case interferenceInTheEndZone = "interference-in-the-end-zone"
    case interferenceInTheEndZoneFromTheOne = "interference-in-the-end-zone-from-the-one"
    case onsideKickRecovered = "onside-kick-recovered"
    case roughingTheKickerOnAMadeFieldGoal = "roughing-the-kicker-on-a-made-field-goal"
    case roughingTheKickerOnAMissedFieldGoal = "roughing-the-kicker-on-a-missed-field-goal"
    case runningIntoTheKickerOnAMadeFieldGoal =
        "running-into-the-kicker-on-a-made-field-goal"
    case runningIntoTheKickerOnAMissedFieldGoal =
        "running-into-the-kicker-on-a-missed-field-goal"
    case holdingOnASuccessfulTry = "holding-on-a-successful-try"
    case roughnessByTheDefenseOnARunThatEndsInAFumbleLost =
        "roughness-by-the-defense-on-a-run-that-ends-in-a-fumble-lost"
    case roughnessByTheDefenseBeforeAnInterception =
        "roughness-by-the-defense-before-an-interception"
    case roughnessByTheDefenseOnAStripSack = "roughness-by-the-defense-on-a-strip-sack"
    case roughnessByTheDefenseBeforeADeepInterception =
        "roughness-by-the-defense-before-a-deep-interception"
    case kickoffFumbledAndReturnedByTheKickers = "kickoff-fumbled-and-returned-by-the-kickers"
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
        case .twoPointTryIntercepted: return RulesScenarios.twoPointTryIntercepted

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
        case .thirdPostseasonOvertimePeriod: return RulesScenarios.thirdPostseasonOvertimePeriod
        case .thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff:
            return RulesScenarios.thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff
        case .fifthPostseasonOvertimePeriod: return RulesScenarios.fifthPostseasonOvertimePeriod

        case .puntReturnedAndTackled: return RulesScenarios.puntReturnedAndTackled
        case .fumbleRecoveredByTheOffense: return RulesScenarios.fumbleRecoveredByTheOffense
        case .fumbleRecoveredByTheDefense: return RulesScenarios.fumbleRecoveredByTheDefense
        case .kickoffReturned: return RulesScenarios.kickoffReturned
        case .kickoffFairCaught: return RulesScenarios.kickoffFairCaught
        case .playEndingJustBeforeTheTwoMinuteWarning:
            return RulesScenarios.playStretchedToEnd(quarter: 4, at: 121)
        // Snapped above 2:00 and dead below it, so the warning falls in the down and
        // not in the interval before it.
        case .playRunningPastTheTwoMinuteWarning:
            return RulesScenarios.playStretchedToEnd(quarter: 2, at: 117, snappedAfter: 120)
        case .playEndingJustBeforeTheTwoMinuteWarningOfOvertime:
            return RulesScenarios.playStretchedToEnd(quarter: 5, at: 121)
        case .playRunningPastTheTwoMinuteWarningOfOvertime:
            return RulesScenarios.playStretchedToEnd(quarter: 5, at: 117, snappedAfter: 120)
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
        case .runnerOutOfBoundsInsideFiveMinutesOfTheFourthQuarter:
            return RulesScenarios.runnerOutOfBounds(quarter: 4, window: 226...300)
        case .runnerOutOfBoundsAcrossFiveMinutesOfTheFourthQuarter:
            return RulesScenarios.playStretchedToEnd(
                quarter: 4, at: 290, endedIn: .outOfBounds, snappedAfter: 300)
        case .runnerOutOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarter:
            return RulesScenarios.playStretchedToEnd(
                quarter: 2, at: 110, endedIn: .outOfBounds, snappedAfter: 120)
        // A play ends at 0:20 of the first quarter with the clock running, and the
        // offence's tempo is longer than what is left: the interval alone exhausts the
        // period.
        case .periodExpiringBetweenDowns:
            return RulesScenarios.playStretchedToEnd(quarter: 1, at: 20)
        case .twoMinuteDrill: return RulesScenarios.twoMinuteDrill

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

        case .defensiveHoldingOnAPlayEndingInBounds:
            return RulesScenarios.defensiveHoldingOnAPlayEndingInBounds
        case .defensiveHoldingInsideFiveMinutesOfTheFourthQuarter:
            return RulesScenarios.defensiveHoldingInsideFiveMinutesOfTheFourthQuarter
        case .offensiveHoldingInTheFourthQuarterOutsideFiveMinutes:
            return RulesScenarios.offensiveHoldingInTheFourthQuarterOutsideFiveMinutes

        case .spikeSnappedAtTwentySeconds: return RulesScenarios.spikeSnapped(at: 20)
        case .spikeSnappedAtFiveSecondsOnThirdDown: return RulesScenarios.spikeSnapped(at: 5)

        case .delayOfGameOnARunningClock: return RulesScenarios.delayOfGameOnARunningClock
        case .delayOfGameAfterATurnoverOnDowns:
            return RulesScenarios.delayOfGameAfterATurnoverOnDowns
        case .thePlayClockExpiresOnThirdAndOne:
            return RulesScenarios.thePlayClockExpiresOnThirdAndOne
        case .aTimeoutBeatsThePlayClockOnThirdAndOne:
            var game = RulesScenarios.thePlayClockExpiresOnThirdAndOne
            game.caller = RulesScenarios.spendsATimeoutOnThePlayClock
            return game

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
        case .injuryToADefenderInTheLastFortySeconds:
            return RulesScenarios.injuryToADefenderInTheLastFortySeconds

        case .secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf:
            return RulesScenarios.injuryRunoffEndsTheFirstHalf(kick: .kickoffTouchback)
        case .secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf:
            return RulesScenarios.injuryRunoffEndsTheFirstHalf(
                kick: .kickoffReturn(toOwn: 25, seconds: 8))

        case .falseStartOnATry: return RulesScenarios.falseStartOnATry
        case .missedFieldGoalFromTheTen: return RulesScenarios.missedFieldGoal(from: 10)
        case .missedFieldGoalFromTheTwenty: return RulesScenarios.missedFieldGoal(from: 20)
        case .defensiveHoldingAtTheThree: return RulesScenarios.defensiveHoldingAtTheThree
        case .defensiveHoldingAtTheSeven: return RulesScenarios.defensiveHoldingAtTheSeven
        case .falseStartAtTheOwnThree: return RulesScenarios.falseStartAtTheOwnThree
        case .falseStartAtTheOwnSeven: return RulesScenarios.falseStartAtTheOwnSeven
        case .facemaskAtTheEndOfARun: return RulesScenarios.facemaskAtTheEndOfARun
        case .facemaskAtTheTwenty: return RulesScenarios.facemaskAtTheTwenty
        case .twoPointTryWalkedOutAndBackIn: return RulesScenarios.twoPointTryWalkedOutAndBackIn
        case .interferenceInTheEndZone: return RulesScenarios.interferenceInTheEndZone
        case .interferenceInTheEndZoneFromTheOne:
            return RulesScenarios.interferenceInTheEndZoneFromTheOne
        case .onsideKickRecovered: return RulesScenarios.onsideKickRecovered
        case .roughingTheKickerOnAMadeFieldGoal:
            return RulesScenarios.kickerFoul(.roughingTheKicker, good: true)
        case .roughingTheKickerOnAMissedFieldGoal:
            return RulesScenarios.kickerFoul(.roughingTheKicker, good: false)
        case .runningIntoTheKickerOnAMadeFieldGoal:
            return RulesScenarios.kickerFoul(.runningIntoTheKicker, good: true)
        case .runningIntoTheKickerOnAMissedFieldGoal:
            return RulesScenarios.kickerFoul(.runningIntoTheKicker, good: false)
        case .holdingOnASuccessfulTry: return RulesScenarios.holdingOnASuccessfulTry
        case .roughnessByTheDefenseOnARunThatEndsInAFumbleLost:
            return RulesScenarios.roughnessByTheDefenseOnARunThatEndsInAFumbleLost
        case .roughnessByTheDefenseBeforeAnInterception:
            return RulesScenarios.roughnessByTheDefenseBeforeAnInterception
        case .roughnessByTheDefenseOnAStripSack:
            return RulesScenarios.roughnessByTheDefenseOnAStripSack
        case .roughnessByTheDefenseBeforeADeepInterception:
            return RulesScenarios.roughnessByTheDefenseBeforeADeepInterception
        case .kickoffFumbledAndReturnedByTheKickers:
            return RulesScenarios.kickoffFumbledAndReturnedByTheKickers
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
        case .twoPointTryIntercepted:
            return [
                "football · Rule 11-3-2-e, 11-3-4 · a two-point try the defence intercepts scores nothing, and the side that scored the touchdown still kicks off"
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
        case .thirdPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-e, 4-2-2 · a postseason game level after two overtime periods opens the third with a kickoff, the captain who lost the toss before overtime having the first choice and electing to receive",
                "football · Rule 16-1-4-f, 4-2-3 · at the end of a first postseason overtime period the teams change goals and play on: possession, the down, the ball and the line to gain are unchanged, and no kick is made",
                "football · Rule 16-1-4-g · each team has three timeouts in each postseason overtime half: a side that spent its three across the first and second overtime periods has three again when the third opens, and a side that spent none still has three",
            ]
        case .thirdPostseasonOvertimePeriodWithTheTossLoserKickingOff:
            return [
                "football · Rule 16-1-4-e, 4-2-2-a · the captain with the first choice at a third postseason overtime period may elect to kick off, and then kicks off"
            ]
        case .fifthPostseasonOvertimePeriod:
            return [
                "football · Rule 16-1-4-i, 16-1-2, 4-2-2, 16-1-4-g · at the end of a fourth postseason overtime period the coin is tossed again, so a fifth is put back in play with a kickoff and each side has three timeouts for the half it opens",
                "pin · the toss before a fifth postseason overtime period (16-1-4-i) is not drawn: as at the first, the side with the ball at the end of the period before kicks off and stands for the captain who lost it",
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
        case .runnerOutOfBoundsInsideFiveMinutesOfTheFourthQuarter:
            return [
                "football · Rule 4-3-2-a-3, 4-4-c · a runner out of bounds on a play snapped inside the last five minutes of the fourth quarter stops the clock until the snap"
            ]
        case .runnerOutOfBoundsAcrossFiveMinutesOfTheFourthQuarter:
            return [
                "football · Rule 4-3-2-a-3, 4-4-c · a runner out of bounds inside the last five minutes of the fourth quarter, on a play snapped with more than five minutes left, stops the clock until the snap: the window is judged where the ball became dead"
            ]
        case .runnerOutOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarter:
            return [
                "football · Rule 4-3-2-a-2, 3-41, 4-4-h · a runner out of bounds after the two-minute warning of the second quarter, on a play snapped before it, stops the clock until the snap: the warning is taken as that down ends"
            ]
        case .periodExpiringBetweenDowns:
            return [
                "football · Rule 4-8-1, 4-3-2 · a period the interval between downs exhausts ends there, and no down is snapped or recorded"
            ]
        case .twoMinuteDrill:
            return [
                "football · Rule 4-3-2, 3-41 · the clock a play is recorded with is the clock it was snapped on, through a two-minute drill"
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
        case .defensiveHoldingOnAPlayEndingInBounds:
            return [
                "football · Rule 4-4-e, 4-3-2-e · an accepted foul during a down that ends in bounds stops the clock at the end of it, and the clock restarts on the ready as though the flag had never flown"
            ]
        case .defensiveHoldingInsideFiveMinutesOfTheFourthQuarter:
            return [
                "football · Rule 4-3-2-e-2, 4-4-e · inside the last five minutes of the second half an accepted foul during a down has the clock start on the snap"
            ]
        case .offensiveHoldingInTheFourthQuarterOutsideFiveMinutes:
            return [
                "football · Rule 4-3-2-e-3, 4-4-e · e-3 reaches only an offensive foul that stops the clock before a snap, so an offensive foul during a fourth-quarter down outside every window restarts the clock on the ready"
            ]

        case .trailingByAPickSix:
            return [
                "football · Rule 4-4-f, 4-3-2 · an incomplete pass, here a spike, stops the clock until the snap",
                "pin · the baseline caller spikes at hurry-up tempo, and a hurry-up snap takes less clock than a huddle (PlayCaller.swift:224; the interval is a modelling convention, not a rule)",
            ]

        case .spikeSnappedAtTwentySeconds:
            return [
                "football · Rule 4-4-f, 8-2-1 Item 3, 4-3-2 · a spike is an incomplete forward pass thrown to stop the clock, so it costs its own second and the next snap comes at the clock it left"
            ]
        case .spikeSnappedAtFiveSecondsOnThirdDown:
            return [
                "football · Rule 4-4-f, 8-2-1 Item 3 · a third-down spike snapped with five seconds left does not end the period: the fourth down is snapped a second later"
            ]

        case .delayOfGameOnARunningClock:
            return [
                "football · Rule 4-6-1, 4-6-4, 14-4-1 · a delay of game when the 40-second play clock expires with the ball not snapped: five yards, the down replayed, and the whole play clock gone from a running game clock"
            ]
        case .delayOfGameAfterATurnoverOnDowns:
            return [
                "football · Rule 4-6-2-a, 4-6-4 · after a change of possession the play clock is 25 seconds, and letting it expire with the game clock stopped is a delay of game that costs no time"
            ]
        case .thePlayClockExpiresOnThirdAndOne:
            return [
                "football · Rule 4-6-1, 4-6-4, 14-4-1 · a play clock that expires on a bench with no answer to it is five yards and the same down"
            ]
        case .aTimeoutBeatsThePlayClockOnThirdAndOne:
            return [
                "football · Rule 4-3-2, 4-6-3-a, 4-6-4 · a charged timeout stops a play clock the offence is not going to beat, so there is no delay of game and the snap that follows is against twenty-five seconds"
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
        case .injuryToADefenderInTheLastFortySeconds:
            return [
                "football · Rule 4-7-3, 4-5-4-b · in the last forty seconds an excess timeout for an injured defender with the clock running ends the half when the defence has no timeouts left and the offence, leading, elects to end it"
            ]

        case .secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf:
            return [
                "football · Rule 4-5-4 Note 4, 6-1-1-a, 6-1-7, 11-6-2, 11-6-3 · a first half that ends on an excess injury timeout's runoff is followed by the second-half kickoff, kicked by the side that received the opening one; a touchback is the receiving team's ball, and it snaps next at its own restart spot"
            ]
        case .secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf:
            return [
                "football · Rule 4-5-4 Note 4, 6-1-1-a, 6-1-7, 7-6-1 · a first half that ends on an excess injury timeout's runoff is followed by the second-half kickoff, kicked by the side that received the opening one; a returned kick is the receiving team's ball where the return ended, and it snaps next from there"
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
        case .defensiveHoldingAtTheSeven:
            return [
                "football · Rule 14-2-1, 8-4-6 · five yards against the defence from the 7 is half the distance, because five is more than half of seven"
            ]
        case .falseStartAtTheOwnThree:
            return [
                "football · Rule 7-4-2, 14-4 (closest section) · a false start at the own 3 is half the distance to the goal line"
            ]
        case .falseStartAtTheOwnSeven:
            return [
                "football · Rule 14-2-1, 7-4-2 · a false start seven yards out from the offence's own goal line is half the distance back, not five yards"
            ]
        case .facemaskAtTheEndOfARun:
            return [
                "football · Rule 12-2-15, 14-4 (closest section) · a facemask at the end of a 20-yard run is 15 more from the end of the run, and a first down"
            ]
        case .facemaskAtTheTwenty:
            return [
                "football · Rule 14-2-1, 12-2-15 · fifteen yards against the defence from the 20 is half the distance, because fifteen is more than half of twenty"
            ]
        case .twoPointTryWalkedOutAndBackIn:
            return [
                "football · Rule 14-2-1, 11-3-3, 11-3-3 Item 2 · a five-yard defensive foul on a try snapped from the 7 is half the distance, and a try is not exempt from the ceiling"
            ]
        case .interferenceInTheEndZone:
            return [
                "football · Rule 8-5-Penalty, 8-6-1-b · defensive pass interference in the end zone is first and goal at the 1"
            ]
        case .interferenceInTheEndZoneFromTheOne:
            return [
                "football · Rule 8-5-Penalty, 8-6-1-b · defensive pass interference in the end zone from inside the 2 is half the distance, and still a first down"
            ]
        case .onsideKickRecovered:
            return [
                "football · Rule 4-3-1-b, 4-3-2 · a kickoff the kicking team recovers starts no clock, and the clock waits for the snap",
                "football · Rule 6-1-6, 6-1-4-c, 6-1-4-d · an onside kick the kicking team recovers is its ball, first and ten, where it was recovered",
            ]
        case .roughingTheKickerOnAMadeFieldGoal:
            return [
                "football · Rule 14-2-3, 12-2-12 · roughing the kicker on a made field goal scores the three and moves the free kick fifteen yards"
            ]
        case .roughingTheKickerOnAMissedFieldGoal:
            return [
                "football · Rule 12-2-12, 14-2-1 · roughing the kicker on a missed field goal is a first down, the fifteen capped at half the distance from the 20"
            ]
        case .runningIntoTheKickerOnAMadeFieldGoal:
            return [
                "football · Rule 12-2-12 Item 2, 14-2-3 · running into the kicker on a made field goal is declined and the free kick is not moved"
            ]
        case .runningIntoTheKickerOnAMissedFieldGoal:
            return [
                "football · Rule 12-2-12 Item 2 · running into the kicker on a missed field goal is five yards and the down is replayed"
            ]
        case .holdingOnASuccessfulTry:
            return [
                "football · Rule 11-3-3 Item 3-a · an offensive foul on a successful try repeats the try rather than ending it"
            ]
        case .roughnessByTheDefenseOnARunThatEndsInAFumbleLost:
            return [
                "football · Rule 14-3-5-b, 14-4-3-a, 12-2-8 · a defensive personal foul during a run that ends in a fumble lost gives the ball back to the offence fifteen yards past the spot of the fumble, and a first down"
            ]
        case .roughnessByTheDefenseBeforeAnInterception:
            return [
                "football · Rule 14-4-5-d, 8-6-1-d, 12-2-8 · a defensive personal foul before a forward pass is intercepted and returned behind the previous spot is enforced from the previous spot, so the offence keeps the ball fifteen yards past where it snapped, and a first down"
            ]
        case .roughnessByTheDefenseOnAStripSack:
            return [
                "football · Rule 14-3-6 Exception 1, 14-4-6-b, 12-2-8 · a defensive personal foul on a sack that ends in a fumble lost behind the line is enforced from the previous spot and not from the fumble, and a first down"
            ]
        case .roughnessByTheDefenseBeforeADeepInterception:
            return [
                "football · Rule 14-4-5-d, 8-6-1-d, 8-1-3 · a defensive personal foul before a forward pass is intercepted and downed downfield of the snap is enforced from the dead-ball spot, which is the better of the two spots the offence may have"
            ]
        case .kickoffFumbledAndReturnedByTheKickers:
            return [
                "football · Rule 8-7-3 Item 1, 11-2-1, 11-3-1, 11-3-4 · a kickoff fumbled by the returner and carried in by the kicking team is the kicking team's touchdown, its try, and its kickoff"
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
