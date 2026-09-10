# Invariants

**Status: built.** Every numbered line below either names a check that runs today or says
plainly that the engine does not satisfy it yet, with the issue that will. Nothing here is
aspiration, and nothing here is a claim that the tree already does it: the two are told
apart on every line.

This is the list of things that must be true of a game this engine plays. It exists because
the football-domain skill already said the clock stops on a change of possession while the
code ran it through one for weeks. The sentence and the test were never connected, so
nothing noticed. Here they are connected, and a test checks the connection.

**A rules change adds a line here.** A PR that teaches the engine a rule adds the truth it
taught, its citation, and the test that turned green, in the same commit as the code.

## How to read an entry

Each entry is one plain sentence about the sport, in our own words, then the rule that says
so, then what checks it:

- `[2025 · 4-4-i]` is Rule 4, Section 4, clause (i) of the **2025** rulebook, the season
  CLAUDE.md pins us to. The number is how you find the original; no rulebook text is
  reproduced in this repository. The index of the articles is
  [`reference/playing-rules.md`](reference/playing-rules.md).
- `test:<function name>` names a Swift test function in one of the four packages' test
  targets. `InvariantsTraceabilityTests` fails if the function does not exist.
- `row:<row id>` names a calibration row in
  `Tools/simharness/Sources/simharness/Targets.swift`, whose band came from a real-league
  season and a named source. The same test fails if the row does not exist, and what every
  band was derived from is in
  [`reference/calibration-sources.md`](reference/calibration-sources.md).
- **not yet enforced** names the issue that will enforce it. The truth holds of the sport
  either way, which is why it is listed: this file is the whole of what must be true, not
  the subset that already is.
- **modelling** marks a place where the engine deliberately does something simpler than the
  sport. The rule is still the rule; the note says what we do instead.

A rule is not a rate. Entries 1 to 88 are rules, and a scenario is what checks one. Entries
89 to 111 are what a league of games has to *look* like, and a harness band over a sourced
season is what checks one. A band is evidence about a rate and never about a rule.

## Game length and overtime

1. A game is four 15-minute periods. `[2025 · 4-1-1]` — `test:quarters`,
   `test:structure`, `test:periods`
2. A regular-season game level after four periods plays one overtime period of ten minutes.
   `[2025 · 4-1-1, 16-1-3]` — `test:regulationTieGoesToOvertime`, `test:ties`,
   `test:overtime`
3. Regular-season overtime is never extended, and a game level at the end of it is a tie.
   `[2025 · 16-1-3-d]` — `test:regularSeasonOvertimeExpiringLevelIsATie`, `test:ties`
4. Each team is owed a possession in overtime, whatever the first one produced, and once
   both have had one the team with more points has won. `[2025 · 16-1-3-a, 16-1-3-b]` —
   `test:overtimeFirstPossessionTouchdown`
5. Once both teams have possessed and the score is level, the next points of any kind end
   it. `[2025 · 16-1-3-c]` — `test:overtimeAfterBothPossessedEndsOnAnyScore`
6. A defence that takes the ball away has thereby had its possession, so a first-possession
   turnover puts the game into sudden death and a defensive touchdown on it ends the game.
   `[2025 · 16-1-5-b, 16-1-3-b]` — `test:overtimeDefensiveScoreEndsIt`
7. A team that kicks off in overtime and scores a safety against the receivers' opening
   drive has won on the spot. `[2025 · 16-1-3-a]` — `test:overtimeOpeningDriveSafetyWinsIt`
8. A kickoff is the receiving team's opportunity to possess even when the kicking team
   legally recovers it, so after a field goal on the opening overtime possession a kickoff
   the kickers recover ends the game. `[2025 · 16-1-5-c, A.R. 16.2]` —
   `test:overtimeKickoffRecoveredByTheKickersEndsIt`
9. After a field goal on the opening overtime possession, a kickoff returned for a touchdown
   ends the game, and there is no try. `[2025 · 16-1-5-c, A.R. 16.4]` —
   `test:overtimeKickoffReturnedForTouchdownEndsIt`
10. Each team has two timeouts in regular-season overtime. `[2025 · 16-1-3-e]` —
    `test:overtimeTimeoutsAreTwo`
11. A postseason game plays 15-minute overtime periods until somebody wins, so a game level
    after the fifth period plays a sixth. `[2025 · 16-1-4, 16-1-4-d, 16-1-4-e, 16-1-4-f,
    16-1-4-i]` — `test:postseasonPlaysASixthPeriod`; **modelling**: the book puts a *third*
    overtime period back in play with a free kick, because 16-1-4-e gives its first choice
    of 4-2-2's privileges to the captain who lost the toss before overtime, and 16-1-4-i
    tosses again after a fourth; at the other boundaries the teams only change goals
    (16-1-4-f, 4-2-3) and play continues from the same spot. The engine restarts the first
    overtime period and no later one, which is
    [#86](https://github.com/knissley/football-manager/issues/86)'s — pinned by
    `test:aThirdPostseasonOvertimePeriodIsNotRestartedWithAKick`
12. The second half opens with a kickoff by the team that received the opening one.
    `[2025 · 4-2-2]` — `test:halftimePossession`; **modelling**: the second-half choice
    belongs to the captain who lost the pregame toss, and neither the toss nor a deferral is
    modelled — the engine simply alternates
13. The clock only ever runs down within a period. `[2025 · 4-1-1]` —
    `test:clockIsMonotonic`, `test:clockFloor`
14. A regular-season overtime period has a two-minute warning, because fourth-period timing
    rules apply to it: the clock stops at 2:00 between downs, a down under way finishes,
    the five-minute out-of-bounds window is in it, and the offence's foul before the snap
    starts the clock on the snap there as it does in the fourth period.
    `[2025 · 3-41, 16-1-3-e, 4-3-2-a, 4-3-2-e-3]` — `test:warningInRegularSeasonOvertime`,
    `test:twoMinuteWarningStopsAtTwoMinutesOfOvertime`,
    `test:downUnderWayAtTwoMinutesOfOvertimeFinishes`,
    `test:outOfBoundsInRegularSeasonOvertime`,
    `test:offensiveFoulInOvertimeStartsTheClockOnTheSnap`
15. Postseason overtime pairs its periods into halves for timing, and every clock rule reads
    the pairing the same way: a second overtime period ends as the first half does — the
    warning, the two-minute out-of-bounds window and the runoff — and a fourth as the fourth
    period does, with its five-minute window; a first or a third has neither warning nor
    window. In a first, second or third overtime period, which 4-3-2-e-3's own words
    leave out, the offence's foul before the snap starts the clock on the snap only inside
    those windows; whether 16-1-4-h carries e-3 into a fourth overtime period outside its
    five-minute window the book does not settle, and the engine's reading — that it does
    not — is **modelling**, pinned by
    `test:offensiveFoulInAFourthPostseasonOvertimePeriodOutsideFiveMinutes`.
    `[2025 · 16-1-4-h, 3-41, 4-3-2-a, 4-3-2-e, 4-7-1]` —
    `test:firstPostseasonOvertimePeriodHasNoWarning`,
    `test:secondPostseasonOvertimePeriodHasTheFirstHalfsWarning`,
    `test:falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriodCostsTenSeconds`,
    `test:outOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriodRestartsOnTheReady`,
    `test:outOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriodWaitsForTheSnap`,
    `test:offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady`,
    `test:postseasonOvertimeRunoff`, `test:offensiveFoulBeforeTheSnapInPostseasonOvertime`,
    `test:warningInPostseasonOvertime`, `test:outOfBoundsInPostseasonOvertime`; past the
    fourth overtime period the pairing repeats, which is a **modelling** reading of the
    new coin toss there (16-1-4-i) rather than a sentence in the book, and
    `test:postseasonOvertimeBeyondTheFourthPeriodRepeatsThePairing` pins it

## The try

16. A touchdown is six points and owes a try: one untimed scrimmage down, during which the
    game clock does not run. `[2025 · 11-1-2-a, 11-3-1]` — `test:touchdown`,
    `test:touchdownUnchanged`, `test:touchdownSequence`
17. A try is snapped from the defence's 15 for a kick and from its 2 for a pass or a run,
    unless a flag on the try moved it. `[2025 · 11-3-1, 11-3-3]` —
    `test:triesAreSnappedFromTheRightSpot`
18. A made kick is one point and a converted pass or run is two; a failed try of either kind
    is nothing. `[2025 · 11-1-2-d]` — `test:extraPointIsOnePoint`, `test:twoPointIsTwoPoints`,
    `test:missedExtraPoint`, `test:failedTwoPoint`, `test:conversionsGoBothWays`
19. A foul before the snap on a try is treated as it would be before a scrimmage play, so a
    false start on an extra point re-kicks from five yards back — the 20, a 37-yard kick.
    `[2025 · 11-3-3 Item 2, 7-4-2]` — `test:falseStartOnTheKickMovesItBack`,
    `test:falseStartOnATryMovesTheTry`
20. Defensive offside on a two-point try is half the distance to the goal, so the replay
    comes from the 1. `[2025 · 11-3-3 Item 2, 7-4-5, 14-2-1]` —
    `test:offsideOnTheConversionMovesItIn`
21. A touchdown on the last play of a period still gets its try, and the period is extended
    by that untimed down: the try belongs to the period the touchdown ended, at 0:00.
    `[2025 · 4-8-1, 4-8-2, 4-8-2-c]` — `test:touchdownAsTheFirstQuarterExpires`,
    `test:touchdownAsTheSecondQuarterExpires`, `test:walkOffTryIsTheCallerChoice`
22. Down seven as the fourth period expires, the touchdown gets its try, and the kick sends
    the game to overtime. `[2025 · 4-8-2-c, 11-3-1, 16-1-3]` —
    `test:lastPlayTouchdownDownSeven`
23. Down six as the fourth period expires, the touchdown gets its try, and the kick wins it.
    `[2025 · 4-8-2-c, 11-3-1]` — `test:lastPlayTouchdownDownSix`
24. Down eight as the fourth period expires, the touchdown gets a two-point try, and the
    conversion sends the game to overtime. `[2025 · 4-8-2-c, 11-3-2-b, 16-1-3]` —
    `test:lastPlayTouchdownDownEight`
25. The try is waived when time in the fourth period has expired and no try could affect the
    outcome — level, up one, down one, down two, down nine. `[2025 · 4-8-2-c]` —
    `test:lastPlayTouchdownLevel`, `test:lastPlayTouchdownUpOne`,
    `test:lastPlayTouchdownDownOne`, `test:lastPlayTouchdownDownTwo`,
    `test:lastPlayTouchdownDownNine`
26. Once both teams have possessed in overtime, a touchdown that leaves the scorer behind
    still gets its try, and the conversion that puts him ahead ends the game.
    `[2025 · 16-1-3-c, 4-8-2-c, 11-3-1]` — `test:overtimeTrailingScorerTryDecides`
27. Either team can score on a try: a try that ends in a touchdown is two points to whoever
    scored it, and what would be a safety on a try is one point to the opponent.
    `[2025 · 11-3-2-b, 11-3-2-c]` — **not yet enforced**,
    [#48](https://github.com/knissley/football-manager/issues/48)
28. After the try, the team that was on defence for it receives the kickoff.
    `[2025 · 11-3-4]` — `test:afterTheTryTheDefendingTeamReceives`
29. A kickoff returned for a touchdown gets its try, and the returning team then kicks off.
    `[2025 · 11-3-1, 11-3-4]` — `test:kickoffReturnTouchdownGetsItsTry`

## Scoring and free kicks

30. The scoreboard is the scoring plays in the stream, summed, and never a number kept
    beside it. `[2025 · 11-1-2]` — `test:scoreMatchesTheStream`,
    `test:scoreboardMatchesTheStream`, `test:pointsSitOnScoringPlays`,
    `test:pointsMatchScoring`, `test:scoreboardArithmetic`
31. A field goal is three points, and after one the team scored upon receives the kickoff.
    `[2025 · 11-1-2-b, 11-4-6]` — `test:fieldGoal`,
    `test:afterAFieldGoalTheTeamScoredUponReceives`
32. A field goal must be place-kicked or drop-kicked from at or behind the line and reach
    the goal without touching the ground or one of the kicker's own men.
    `[2025 · 11-4-1]` — `test:kicksAreInRange`; **modelling**: the kick is a distance
    against a curve, and a block is a branch of its own rather than a rule about touching
33. A missed field goal that crosses the line and is not touched by the receivers gives them
    the ball where it was struck, or their own 20 when the kick came from nearer than that.
    `[2025 · 11-4-2]` — `test:missedFieldGoalFromBeyondTheTwenty`,
    `test:missedFieldGoalFromInsideTheTwenty`, `test:missedFieldGoal`
34. A safety is two points to the defence. `[2025 · 11-1-2-c]` — `test:safety`,
    `test:safetyPaysTheDefence`
35. After a safety the team that was scored upon puts the ball in play with a free kick from
    its own 20, and that kick alone may be a punt. `[2025 · 11-5-2, 6-1-1-b]` —
    `test:afterASafetyTheTeamScoredUponKicks`, `test:safety`, `test:safetyPaysTheDefence`
36. A punt that reaches the end zone untouched by the receivers is a touchback and they snap
    at their own 20, which is not where a kickoff touchback is spotted.
    `[2025 · 11-6-2-c, 11-6-3]` — `test:touchbacksDiffer`, `test:punts`
37. A fair catch is available on a scrimmage kick past the line and on a free kick, but only
    while the kick is airborne; the catching team snaps where he caught it.
    `[2025 · 10-2-1, 10-2-4]` — `test:puntHandsOver`, `test:fairCaughtKickoffStartsNoClock`

## Clock stoppages and restarts

38. A tackle in bounds keeps the clock running, and so does a fumble the offence falls on.
    `[2025 · 4-4]` — `test:liveBallRuns`,
    `test:fumbleRecoveredByTheOffenseKeepsTheClockRunning`, `test:fumbleRecovered`
39. Every change of possession stops the clock and it does not start again until the snap —
    on downs, on a punt returned and tackled in bounds, and on a fumble the defence
    recovers. `[2025 · 4-4-i, 4-3-2-a-1]` — `test:changeOfPossessionStops`,
    `test:turnoverOnDownsStopsTheClock`, `test:puntReturnedAndTackledStopsTheClock`,
    `test:fumbleRecoveredByTheDefenseStopsTheClock`
40. An incomplete pass stops the clock until the snap, a spike included.
    `[2025 · 4-4-f, 4-3-2]` — `test:spikeStopsTheClock`, `test:incompletion`,
    `test:deadBallStops`; the caller's own habit — a spike at hurry-up tempo — is pinned by
    `test:spikeIsCalledAtHurryUpTempo`, which is a modelling convention and not a rule
41. A ball dead on or behind a goal line stops the clock until the snap, so a kickoff
    touchback consumes no time. `[2025 · 4-4-d, 4-3-1]` — `test:touchbackConsumesNoTime`
42. A free kick starts the clock only on legal touching in the field of play: a fair catch
    or a kick the kickers recover starts no clock, and a returned kick advances the clock by
    the return and no more. `[2025 · 4-3-1-a, 4-3-1-b, 4-3-1-c, 4-4-a]` —
    `test:fairCaughtKickoffStartsNoClock`, `test:kickoffRecoveredByTheKickersStartsNoClock`,
    `test:returnedKickoffAdvancesTheClock`
43. Gaining a first down does not stop the clock: it is not among the stoppages Rule 4
    lists, and the omission is the rule. `[2025 · 4-3, 4-4]` — `test:firstDownDoesNotStop`
44. A runner going out of bounds stops the clock until the ball is ready for play, except
    that it waits for the snap once possession has changed, inside the closing two minutes
    of the first half and inside the closing five of the second. `[2025 · 4-4-c, 4-3-2-a]` —
    `test:outOfBoundsEarly`, `test:outOfBoundsLate`; **modelling**: a tackle ends out of
    bounds at a flat rate whatever the play and whatever the clock is doing,
    [#28](https://github.com/knissley/football-manager/issues/28)
45. The two-minute warning stops a running clock at exactly 2:00 without anyone asking, and
    the snap restarts it. It belongs to the second and fourth periods, once each.
    `[2025 · 3-41, 4-4-h]` — `test:warningBetweenDowns`, and the record says it was
    taken, on the first snap after it — `test:warningIsOnTheRecord`;
    `test:twoMinuteWarningStopsAtTwoMinutes`, `test:noWarningMidHalf`, `test:warningTakenOnce`,
    `test:warningResets`
46. A down under way when the clock runs past 2:00 finishes, and the clock is dead after it.
    `[2025 · 3-41]` — `test:warningDuringADown`, `test:downUnderWayAtTwoMinutesFinishes`,
    `test:twoMinuteWarningDetection`
47. Outside the late-game windows a foul restarts the clock as though the flag had never
    flown. `[2025 · 4-4-e, 4-3-2-e]` — `test:falseStartInTheThirdQuarterCostsNoTime`
48. An offensive foul that stops the clock before the snap anywhere in the fourth period
    restarts it on the snap. `[2025 · 4-3-2-e-3]` —
    `test:offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap`
49. A foul before the snap charges no play time, because no play happened.
    `[2025 · 4-4-e]` — `test:deadBallFoulBeforeTheSnapChargesNoTime`,
    `test:preSnapKillsThePlay`, `test:elapsedDependsOnThePreviousStoppage`
50. Three charged timeouts per team per half, they do not carry over, and they never go
    negative. `[2025 · 4-5-1]` — `test:timeoutsStayLegal`, `test:timeoutsAreSpentAndVisible`;
    and every one charged is on the record of the snap it preceded, with the side that took
    it — `test:timeoutsAreOnTheRecord`
51. The play clock is 40 seconds from the end of the previous play and 25 from the whistle
    after an administrative stoppage — 30 after a runoff, and back to 40 after a defensive
    act that conserves time — and letting it expire with the ball not snapped is delay of
    game: five yards from the succeeding spot, the down unchanged, and on a running game
    clock the whole play clock gone before the whistle.
    `[2025 · 4-6-1, 4-6-2, 4-6-3, 4-6-4, 14-4-1]` —
    `test:delayOfGameWhenThePlayClockExpires`,
    `test:delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock`,
    `test:playClockValues`, `test:everySnapRecordsItsPlayClock`; **modelling**: the
    offence's tempo is how much of whatever clock is in force it means to leave itself,
    and how often it overruns that slack is a draw that halves with every eight seconds
    of it — the delay-of-game rate is derived from the clock rather than tuned as a flat
    roll, and `row:penalty.delayOfGame` is what measures it. `test:tempoOrdering` pins
    the tempo table, and that a tempo keeps its share of slack on a shorter clock is a
    further **modelling** choice, pinned by `test:tempoScalesToTheClock`

## The ten-second runoff

52. The runoff is ten seconds. `[2025 · 4-7-1 Item 1]` — `test:tenSeconds`
53. Inside the last two minutes of either half, an offensive act that conserves time with
    the clock running costs those ten seconds, the play clock goes to 30, and the game clock
    restarts on the ready rather than the snap. `[2025 · 4-7-1, 4-7-1 Item 1]` —
    `test:falseStartInsideTwoMinutesCostsTenSeconds`, `test:window`
54. Fourth-period timing rules apply in regular-season overtime, so the runoff applies there
    too. `[2025 · 16-1-3-e, 4-7-1 Item 1]` —
    `test:falseStartInsideTwoMinutesOfOvertimeCostsTenSeconds`
55. There is no runoff when the clock was already stopped. `[2025 · 4-7-1 Item 1]` —
    `test:falseStartWithTheClockStoppedCostsNoTime`
56. The defence may always decline the runoff and keep the yardage, and declining the
    yardage declines the runoff with it. `[2025 · 4-7-1 Item 1]` —
    `test:trailingDefenseDeclinesTheRunoff`, `test:runoffDecisionDefaults`
57. The offence may spend a charged timeout instead of the runoff, and the clock then starts
    on the snap. `[2025 · 4-7-1 Item 1]` — `test:offenseTakesATimeoutInsteadOfTheRunoff`,
    `test:runoffDecisionDefaults`
58. A half can end on a runoff. `[2025 · 4-5-4 Note 4]` —
    `test:runoffAtEightSecondsEndsTheHalf`
59. There is never a runoff against the defence: its dead-ball foul resets the play clock to
    40 and starts the game clock on the ready unless the offence wants the snap.
    `[2025 · 4-7-1 Item 2, 4-5-4 Note 9]` — `test:deadBallFoulBeforeTheSnapChargesNoTime`,
    `test:window`
60. An illegal substitution after the two-minute warning, with the ball dead and the clock
    running, is five yards and a runoff. `[2025 · 4-7-2]` — `test:window`
61. In the last 40 seconds of either half a defensive foul that conserves time ends the
    half, unless the defence has a timeout left or the offence would rather play on.
    `[2025 · 4-7-3, 4-7-1-a]` —
    `test:defensiveFoulInTheLastFortySecondsEndsTheHalfAtTheOffensesElection`,
    `test:defensiveFoulInTheLastFortySecondsWhenTheOffenseWouldRatherPlayOn`,
    `test:defensiveFoulInTheLastFortySecondsWithADefensiveTimeoutLeft`,
    `test:lastFortySeconds`, `test:conservingActs`; the election is the offence's, a
    `PlayCaller` decision written into the play's decision log; **modelling**: the
    defence's option to spend a timeout in lieu of the clock starting (4-7-1 Item 2) is
    not modelled — a defence with a timeout keeps the half alive by having one, and spends
    it as any timeout, before the next snap
62. A replay reversal or a nullified foul after the two-minute warning that leaves the clock
    where a correct ruling would not have stopped it runs ten seconds off, which neither
    team may decline. `[2025 · 4-7-4]` — **modelling**: excluded until a replay system
    exists. There is no replay in this engine and no foul is ever nullified after the
    fact, so nothing can produce that runoff; `test:noRunoffFollowsAReplay` pins that
    every runoff a game produces, and every clock election the record can carry, is a
    foul's, the last forty seconds' or an injury timeout's
63. After the two-minute warning an injury timeout is charged to the injured player's
    team as a team timeout if it has one, and the clock then waits for the snap; with none
    left it is an excess timeout, and one against the team in possession that stopped a
    running clock carries a ten-second runoff at the defence's choice, after which the
    clock starts on the ready — or, declined, waits for the snap.
    `[2025 · 4-5-4-a, 4-3-2, 4-5-4-b, 4-5-4 Note 1, 4-5-4 Note 3, 4-5-4 Note 4, 4-5-3]` —
    `test:injuryTimeoutAfterTheWarningIsCharged`,
    `test:excessInjuryTimeoutAfterTheWarningCarriesTheRunoff`,
    `test:injuryRunoffDeclinedByATrailingDefense`; the runoff is the defence's choice, a
    `PlayCaller` decision written into the play's decision log; **modelling**: before the
    warning an injury changes nothing on the clock (4-5-3), and the five-yard penalty for
    a second excess timeout in a half (4-5-4 Note 2) and an injury to both sides on one
    down (4-5-4 Note 5) are not modelled

## Where a foul is enforced from

64. Half the distance to the goal is measured from the spot of enforcement, whichever spot
    that is. `[2025 · 14-2-1]` — `test:halfTheDistanceFromTheEnforcementSpot`,
    `test:defensiveHoldingAtTheThreeIsHalfTheDistance`,
    `test:falseStartAtTheOwnThreeIsHalfTheDistance`
65. Every foul is enforced from one of the spots the book lists — the previous spot, the
    spot of the foul, the succeeding spot, the dead-ball spot and the rest — and never from
    somewhere convenient. `[2025 · 14-3-4]` — `test:enforcementFamilies`
66. A foul before the snap is enforced from the succeeding spot and the down stays; a foul
    at the snap from the previous spot, and the down is repeated. `[2025 · 14-4-1]` —
    `test:falseStartAtTheOwnThreeIsHalfTheDistance`, `test:preSnapKillsThePlay`
67. The basic spot for a foul during a run not followed by a change of possession is the
    dead-ball spot, so a facemask at the end of a 20-yard run is fifteen more from where the
    run ended, and a first down. `[2025 · 14-3-5-a, 14-3-6, 12-2-15]` —
    `test:facemaskAtTheEndOfARun`, `test:facemaskAtTheEndOfARunIsEnforcedFromTheEndOfTheRun`
68. Under the three-and-one method a defensive foul during a run is enforced from the basic
    spot and so is an offensive foul in advance of it, while an offensive foul behind the
    basic spot is enforced from the spot of the foul. `[2025 · 14-3-6]` —
    `test:blockInTheBackDuringARun`, `test:holdingOnAGain`
69. Its exception: an offensive foul behind the line of scrimmage is enforced from the
    previous spot, and so is a defensive one when the basic spot is behind the line.
    `[2025 · 14-3-6]` — `test:blockInTheBackBehindTheLine`, `test:contactFoulOnALoss`
70. Between the snap and the moment a forward pass from behind the line is over, a foul by
    either team is enforced from the previous spot; the catch is the boundary, and what
    follows it is a run. `[2025 · 8-6-1]` — `test:roughingOnAnIncompletion`,
    `test:enforcementFamilies`
71. A personal foul by the defence before a completion is enforced from the dead-ball spot
    or the previous spot, whichever favours the offence. `[2025 · 8-6-1-d]` —
    `test:roughingOnACompletion`
72. Defensive pass interference is a first down at the spot of the foul.
    `[2025 · 8-5-4, 8-6-1-b]` — `test:spotFouls`, `test:interferenceDownfield`
73. Defensive pass interference in the end zone is first and goal at the 1, or half the
    distance to the goal when the previous spot was inside the 2. `[2025 · 8-5-4, 8-6-1-b]` —
    `test:interferenceInTheEndZone`, `test:interferenceInTheEndZoneSpotsAtTheOne`,
    `test:interferenceInTheEndZoneFromInsideTheTwo`
74. Offensive pass interference is ten yards from the previous spot, and the down is
    replayed. `[2025 · 8-5-4]` — `test:offensiveInterference`
75. Unsportsmanlike conduct after the play is fifteen yards from the succeeding spot, and an
    automatic first down when it is the defence's. `[2025 · 12-3-1]` —
    `test:conductFoulAfterThePlay`
76. When a run with a foul in it is followed by a change of possession, a personal foul by
    the team that lost the ball is enforced from the dead-ball spot and the defence keeps
    the ball. `[2025 · 14-4-3-b]` — `test:facemaskByTheFormerOffenseOnAReturn`,
    `test:blockInTheBackOnAReturn`
77. A defensive foul during a touchdown leaves the score standing; an offensive contact foul
    during its own touchdown nullifies it, enforced from the previous spot.
    `[2025 · 14-2-3, 14-3-6]` — `test:defensiveFoulOnATouchdown`,
    `test:offensiveContactFoulOnItsOwnScore`
78. The non-penalised team takes whichever of the two outcomes is better for it, and a
    double foul with no change of possession offsets and replays the down.
    `[2025 · 14-5-1]` — `test:flagsAreEnforced`
79. A personal or unsportsmanlike foul during a down in which the opponent kicks a field
    goal or scores a safety is enforced on the free kick, and any foul during a touchdown is
    enforced on the try. `[2025 · 14-2-3]` — **not yet enforced**,
    [#48](https://github.com/knissley/football-manager/issues/48): the score stands and the
    flag is recorded declined
80. The basic spot when a run is followed by a change of possession is the spot where
    possession was lost, and a defensive foul there gives the ball back to the offence
    before enforcement. `[2025 · 14-3-5-b, 14-4-3-a]` —
    `test:defensiveFoulOnATakeawayIsEnforcedFromTheSpotPossessionWasLost`; the record's
    half of it — every takeaway says where possession was lost — is
    `test:takeawaysCarryTheSpot`

## Kickoffs and onside kicks

81. An onside kick the kicking team legally recovers is its ball, first and ten, where the
    play died. `[2025 · 6-1-4-c, 6-1-4-d, 6-1-6]` — `test:onsideRecoveryKeepsPossession`,
    `test:onsideRecovered`. And a kickoff the returner fumbles and the kicking team carries
    in is the kicking team's touchdown, its try, and its kickoff — any player of either
    team may advance a fumble, and a runner crossing the goal line scores.
    `[2025 · 8-7-3 Item 1, 11-2-1, 11-3-1, 11-3-4]` —
    `test:kickoffFumbledAndCarriedInIsTheKickersTouchdown`; **modelling**: the crude
    resolver never fumbles a kick, so only a script reaches it
82. Only a trailing team may attempt an onside kick, it must declare it, and it may do so at
    any point in the game. `[2025 · 6-1-1-c, 6-1-6]` — **not yet enforced**,
    [#41](https://github.com/knissley/football-manager/issues/41): the caller still requires
    the fourth quarter, which was the 2024 rule, and `test:onsideJudgement` pins that
83. A kickoff is from the kicking team's 35 and a safety kick from its 20, and the receiving
    team's setup zone and the landing zone are where the 2025 book puts them.
    `[2025 · 6-1-2-a, 6-1-2-b, 6-1-2-e, 6-1-3-b]` — **not yet enforced**,
    [#46](https://github.com/knissley/football-manager/issues/46): the dynamic kickoff is
    not in the engine, which has one touchback spot and no zones at all
84. A kick that reaches the end zone without coming down in the landing zone first is a
    touchback at the receiving team's 35; one that lands in the landing zone and then goes
    into the end zone is a touchback at its 20. `[2025 · 6-1-5, 6-1-5-a]` —
    **not yet enforced**, [#41](https://github.com/knissley/football-manager/issues/41) and
    [#46](https://github.com/knissley/football-manager/issues/46): `Rules` carries one
    touchback spot and it is still the 2024 value, the 30
85. A kick that goes out of bounds or comes down short of the landing zone hands the
    receiving team its choice of spots, 25 yards on from the kick being the usual one, and
    30 on a safety kick. `[2025 · 6-2-4]` — **not yet enforced**,
    [#46](https://github.com/knissley/football-manager/issues/46): with no landing zone
    there is no short kick either
86. A returned kick changes hands where the return ended, and a kick returned all the way is
    a touchdown for the returning team. `[2025 · 6-1-4]` — `test:returnedKickChangesHands`,
    `test:kickReturnedForScore`

## The field, the series and the stream

87. A series is four scrimmage downs to reach the line to gain, which sits ten yards
    downfield of where the series began or on the goal line when that is closer; reaching it
    starts a new series and failing on fourth down hands the ball over at the spot.
    `[2025 · 3-8-2, 3-8-3, 7-3-1]` — `test:firstDown`, `test:firstAndGoal`,
    `test:turnoverOnDowns`, `test:fourthDownConversion`, `test:gainMovesForward`,
    `test:lossMovesBack`
88. Every ball is on a legal spot, in a legal down and distance, in a period the rules
    define. `[2025 · 1-1-1, 3-8-2, 4-1-1]` — `test:spotsAreAlwaysLegal`,
    `test:situationsAreValid`, `test:streamIsOrdered`

## What a season of games looks like

Not rules. Each line is a band over a real-league season, measured by `Tools/simharness`.
The band and the season are in the [calibration table](match-engine.md#calibration), and
what every one of them was derived from is in
[`reference/calibration-sources.md`](reference/calibration-sources.md).

89. A team scores about what a real team scores, and the game's points come mostly from
    touchdowns and then from field goals. — `row:points`, `row:pointsFromTouchdowns`,
    `row:pointsFromFieldGoals`, `row:gamesWithin3`, `row:gamesWithin7`
90. Games end tied about as rarely as they really do, reach overtime about as often, and
    play about as much of the overtime period. — `row:tiesPerGame`, `row:overtimeRate`,
    `row:overtimeLength`
91. A team throws for and runs for about what a real team does, at about the same yards a
    carry, a completion, an attempt and a play. — `row:passingYards`, `row:rushingYards`,
    `row:yardsPerCarry`, `row:yardsPerAttempt`, `row:yardsPerCompletion`, `row:yardsPerPlay`
92. Passes are completed, pressured, sacked and intercepted at about the real rates. —
    `row:completionPercentage`, `row:sackRate`, `row:interceptionRate`, `row:pressureRate`,
    `row:completionsZeroOrFewer`
93. A game holds about as many snaps as a real one, and a team runs about as many plays from
    scrimmage. — `row:playsPerGame`, `row:playsFromScrimmage`
94. Third down comes up at about the real distance and is converted at about the real rate,
    and first down gains about what it really gains. — `row:thirdDownDistance`,
    `row:thirdDownConversion`, `row:firstDownGain`, `row:firstDownsPerTeamGame`
95. The shape of a carry is right and not just its mean: about as many are stuffed, gain two
    or fewer, reach ten, and break twenty. — `row:carriesStuffed`, `row:carries2orFewer`,
    `row:carries10plus`, `row:carries20plus`
96. The shape of a dropback is right too — losses, no-gains, ten, twenty and forty-plus. —
    `row:dropbackLoss`, `row:dropbackNoGain`, `row:dropback10plus`, `row:dropback20plus`,
    `row:dropback40plus`
97. Drives end in a punt, a touchdown or on downs at about the real rates, and there are
    about as many of them a game. — `row:driveEndPunt`, `row:driveEndTouchdown`,
    `row:driveEndDowns`, `row:drivesPerTeamGame`, `row:playsPerDrive`
98. The shape of a drive is right: three-and-outs, short drives, middling ones and long
    ones. — `row:drives3orFewer`, `row:drives4to7`, `row:drives8plus`, `row:threeAndOut`
99. A trip inside the 20 ends in a touchdown about as often as it really does. —
    `row:redZoneTouchdownRate`
100. Drives start about where they really start, and about as often inside their own half. —
     `row:averageStart.2025`, `row:averageStart.2024`, `row:ownHalfStarts.2025`,
     `row:ownHalfStarts.2024`, `row:snapsInsideOwn10`
101. Teams punt about as often, for about the real gross and net, about as many punts come
     back, and a returned kick comes back about as far. — `row:puntsPerTeamGame`,
     `row:netPunt`, `row:grossPunt`, `row:puntsReturned`, `row:puntReturnYards`,
     `row:kickoffReturnYards.2025`, `row:kickoffReturnYards.2024`; all four distances are
     read off the record, which says where every kick was fielded —
     `test:kickDistancesAreDerivable`, `test:onlyKicksAreFielded`
102. Field goals are attempted about as often, from about the real spread of distances, and
     made at about the real rate from each. — `row:fieldGoalsPerTeamGame`,
     `row:fieldGoalsUnder30`, `row:fieldGoals30to39`, `row:fieldGoals40to49`,
     `row:fieldGoals50plus`, `row:fieldGoalAttemptsUnder30`, `row:fieldGoalAttempts30to39`,
     `row:fieldGoalAttempts40to49`, `row:fieldGoalAttempts50plus`
103. Extra points are made, and two-point tries taken and converted, at about the real
     rates. — `row:extraPointsMade`, `row:twoPointTries`, `row:twoPointConversion`
104. Fourth down is punted, kicked and gone for at about the real rates, and converted at
     about the real one. — `row:fourthDownPunted`, `row:fourthDownKicked`,
     `row:fourthDownWentForIt`, `row:fourthDownAttempts`, `row:fourthDownConversion`,
     `row:fourthAndOneWentForIt`
105. The ball is turned over, lost and fallen on at about the real rates, and about as many
     touchdowns are scored by somebody other than the offence. — `row:turnovers`,
     `row:fumblesLost`, `row:fumblesKept`, `row:defensiveReturnTouchdowns`,
     `row:nonOffensiveTouchdowns.2025`, `row:nonOffensiveTouchdowns.2024`,
     `row:kickReturnTouchdowns.2025`, `row:kickReturnTouchdowns.2024`, `row:safeties`
106. Kickoffs are returned and taken for touchbacks at the rates the kickoff rule in force
     produces, and onside kicks are attempted and recovered at about the real rates. —
     `row:kickoffsReturned.2025`, `row:kickoffsReturned.2024`, `row:kickoffTouchbacks.2025`,
     `row:kickoffTouchbacks.2024`, `row:onsideKicks.2025`, `row:onsideKicks.2024`,
     `row:onsideRecovery.2025`, `row:onsideRecovery.2024`
107. About as many flags fly as really do, spread over the fouls that really get called, and
     the road team commits a few more pre-snap fouls than the home team. —
     `row:penaltiesPerGame`, `row:penalty.offensiveHolding`, `row:penalty.falseStart`,
     `row:penalty.defensivePassInterference`, `row:penalty.defensiveHolding`,
     `row:penalty.unnecessaryRoughness`, `row:penalty.delayOfGame`, `row:penalty.offside`,
     `row:penalty.illegalFormation`, `row:penalty.roughingThePasser`,
     `row:penalty.neutralZoneInfraction`, `row:preSnapRoadVsHome`
108. Personnel looks like the sport's: 11 personnel against nickel most of the time, base
     against heavier looks, and a run gains more into a box it does not outnumber by much. —
     `row:personnel11`, `row:packageNickel`, `row:packageBase`, `row:ypcEvenCount`,
     `row:ypcOutnumberedByOne`
109. The endgame is played: teams kneel, spike, scramble and spend timeouts about as often
     as they really do. — `row:kneelsPerGame`, `row:spikesPerGame`, `row:scramblesPerGame`,
     `row:timeoutsPerGame`
110. Every man on the field is in the record, and each position group takes about as many
     snaps a game as it really does: one quarterback and five linemen a snap, a back and a
     tight end and change, close to three receivers, a front seven of six or seven and
     four or five defensive backs. — `row:snaps.quarterback`, `row:snaps.backfield`,
     `row:snaps.receiver`, `row:snaps.tightEnd`, `row:snaps.offensiveLine`,
     `row:snaps.frontSeven`, `row:snaps.defensiveBack`; the record's half of it is
     `test:everyPlayCarriesTwentyTwoSlots`, `test:creditsAgreeWithTheField`,
     `test:quarterbackSnapsSumToScrimmagePlays`; and every flag names a player the record
     identifies, on the offending team and on its side of the ball, whether or not the
     play credited him — `test:offendersAreReal`
111. Over a season, team win totals spread about as widely as they really do. —
     `row:winTotalSigma`, which cannot be measured before there is a schedule, at M3

## What the harness cannot check yet

112. A completion is a completion whether it gained a yard, none, or lost one. The record
     says a pass was caught, and the harness reads that rather than inferring it from
     positive yards. `[2025 · 8-1-3]` — `test:completionsForNothingAreComplete`,
     `test:passResultAgreesWithTheEnding`, `row:completionPercentage`; S14 in the
     [audit](audit-is-this-football.md)
113. Players miss games at about the rate they really do, and heavy rain takes points off a
     game. Nobody has cited either band, so `row:playerGamesLost` and `row:heavyRainPoints`
     print `unsourced` and are never `ok`. — **not yet enforced**: the sourcing is
     [#2](https://github.com/knissley/football-manager/issues/2)'s remaining tail
