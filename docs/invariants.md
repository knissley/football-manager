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

A rule is not a rate. Entries 1 to 92 are rules, and a scenario is what checks one. Entries
93 to 118 are what a league of games has to *look* like, and a harness band over a sourced
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
    after the fifth period plays a sixth, and its periods pair into halves. A third overtime
    period is put back in play with a free kick, the captain who lost the toss before
    overtime having the first choice of 4-2-2's privileges, and so is a fifth after the new
    toss; each side has three timeouts in each half; a second or a fourth period carries on
    from the spot, the teams changing goals with possession, the down, the ball and the
    line to gain unchanged. `[2025 · 16-1-4, 16-1-4-d, 16-1-4-e, 16-1-4-f, 16-1-4-g,
    16-1-4-i, 16-1-2, 4-2-2, 4-2-3]` — `test:postseasonPlaysASixthPeriod`,
    `test:thirdPostseasonOvertimePeriodOpensWithAKickoff`,
    `test:tossLoserMayElectToKickOffAThirdPostseasonOvertimePeriod`,
    `test:secondPostseasonOvertimePeriodCarriesOn`,
    `test:postseasonOvertimeTimeoutsAreThreePerHalf`,
    `test:fifthPostseasonOvertimePeriodOpensWithAKickoff`,
    `test:aThirdPostseasonOvertimePeriodIsRestartedWithAKick`,
    `test:periodResumesWithKickoffAnswers`, `test:coinTosses`; **modelling**: no toss is
    drawn — the side that kicks off after one stands for the captain who lost it, and after
    a fourth overtime period that is the side with the ball, pinned by
    `test:fifthPostseasonOvertimePeriodKickerIsTheSideThatHadTheBall`; the change of ends
    is not modelled either, for the reason 4-2-3 gives
12. The second half opens with a kickoff, the captain who lost the pregame toss having the
    first choice of 4-2-2's privileges: to receive, or to kick off. The kick hands the ball
    to the receivers however the first half ended — on a play, or between downs on an
    injury timeout's runoff or the last-forty-seconds election: a touchback is theirs at
    their restart spot, a return theirs where it ended. `[2025 · 4-2-2, 4-2-2-a, 6-1-1-a,
    6-1-7, 11-6-2, 11-6-3, 7-6-1, 4-5-4 Note 4]` — `test:halftimePossession`,
    `test:secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf`,
    `test:secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf`,
    `test:kickoffsChangePossessionAndOpenEveryRestartedPeriod`; the choice is the
    captain's, a `PlayCaller`
    decision (`electsToReceive`) that defaults to receive and is read off the stream as
    the kickoff it decides, the same way a two-point or an onside call is; **modelling**:
    neither the toss nor a deferral is drawn — the side that kicks off to open the game
    stands for the captain who lost the toss, so with the default the side that received
    the opening kick kicks off the second half — and the choice of goal is not modelled,
    for the reason 4-2-3 gives
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
    `test:missedExtraPoint`, `test:failedTwoPoint`, `test:conversionsGoBothWays`;
    a two-point try is thrown *or carried*, and both happen —
    `test:twoPointTriesCanBeRuns`
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
    [#48](https://github.com/knissley/football-manager/issues/48). Until it is, the crude
    resolver does not put the ball on the ground during a try at all: a fumble it could
    only resolve as a failed try would be a wrong outcome dressed as a right one.
28. After the try, the team that was on defence for it receives the kickoff — however the
    try ended, including one the defence intercepts, because the whistle closes the try out
    whether or not anybody scored on it, and the ball does not change hands for the free
    kick that follows.
    `[2025 · 11-3-2-e, 11-3-4]` — `test:afterTheTryTheDefendingTeamReceives`,
    `test:aTwoPointTryTheDefenceInterceptsStillEndsInAKickoffByTheScorer`,
    `test:aTwoPointTryThatIsInterceptedIsStillTheTry`
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
40. An incomplete pass stops the clock until the snap, a spike included. A quarterback
    who throws the ball into the ground straight off the snap stops it legally, so a spike
    costs the second the snap and the throw take and no more: the next down is snapped on
    the clock the spike left, whatever that clock reads, and a spike inside ten seconds
    does not end the period. What is charged *before* the spike is a separate question the
    clock rules answer separately — nothing had stopped the clock, so the seconds the
    offence spends reaching the line come off it.
    `[2025 · 4-4-f, 8-2-1 Item 3, 4-3-2]` — `test:spikeStopsTheClock`, `test:incompletion`,
    `test:deadBallStops`, `test:spikeCostsItsOwnSecondAndStopsTheClock`,
    `test:spikeAtFiveSecondsIsFollowedByTheNextDown`; the caller's own habit — a spike at
    hurry-up tempo — is pinned by
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
    that it waits for the snap once possession has changed, after the two-minute warning
    of the first half and inside the closing five minutes of the second. The window is
    judged where the runner stepped out — the clock after the play's own time has come
    off — and not where the play before him ended: a runner out at 4:50 on a play snapped
    at 5:07 is inside it. `[2025 · 4-4-c, 4-3-2-a, 4-3-2-a-2, 4-3-2-a-3]` —
    `test:outOfBoundsEarly`, `test:outOfBoundsLate`,
    `test:outOfBoundsInsideFiveMinutesOfTheFourthQuarterWaitsForTheSnap`,
    `test:outOfBoundsAcrossFiveMinutesOfTheFourthQuarterWaitsForTheSnap`; in the first
    half the boundary is the warning's own, taken as the down that crosses 2:00 ends
    (3-41), so the window and the warning give one answer there —
    `test:outOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarterWaitsForTheSnap`;
    **modelling**: where a play ends laterally is drawn against the concept and the clock
    — an outside run reaches the boundary and an inside run does not, a trailing offence
    inside two minutes seeks it and one protecting a lead late stays in —
    `test:theSidelineIsAClockDecision`, `test:theSidelineDependsOnTheCall`,
    `test:breakawaysAreNotSidelineByConstruction`
45. The two-minute warning stops a running clock at exactly 2:00 without anyone asking, and
    the snap restarts it. It belongs to the second and fourth periods, once each.
    `[2025 · 3-41, 4-4-h]` — `test:warningBetweenDowns`, and the record says it was
    taken, on the first snap after it — `test:warningIsOnTheRecord`;
    `test:twoMinuteWarningStopsAtTwoMinutes`, `test:noWarningMidHalf`, `test:warningTakenOnce`,
    `test:warningResets`
46. A down under way when the clock runs past 2:00 finishes, and the clock is dead after it.
    `[2025 · 3-41]` — `test:warningDuringADown`, `test:downUnderWayAtTwoMinutesFinishes`,
    `test:twoMinuteWarningDetection`
47. A foul stops the clock, and where it stops it depends on when it flew: a foul during a
    down stops the clock at the end of that down (4-4-e), and one with the ball already
    dead stops it as it flies (4-4-g). Enforcement is not free either way. Outside the
    late-game windows the clock then restarts as though the flag had never flown — on the
    ready-for-play signal, if it was running — and inside the window after the first half's
    warning or the last five minutes of the second it waits for the snap.
    `[2025 · 4-4-e, 4-4-g, 4-3-2-e, 4-3-2-e-1, 4-3-2-e-2]` —
    `test:falseStartInTheThirdQuarterCostsNoTime`,
    `test:acceptedFoulDuringADownStopsTheClockForEnforcement`,
    `test:acceptedFoulDuringADownInsideFiveMinutesWaitsForTheSnap`; **modelling**: only the
    accepted branch is read. 4-4-e stops the clock for a foul during a down whether or not
    the penalty is taken, and 4-3-2-e restarts it once the penalty is settled either way,
    but `State.runClock` gates the whole restart on `penalty.wasAccepted`, so a foul the
    non-offending side turns down leaves the clock as the play's ending left it. That is
    not a rare corner: the harness's `declined` line under Penalties reads 12.3% at seed 7
    and 12.7% at seed 11 over four hundred games.
    [#102](https://github.com/knissley/football-manager/issues/102) owns it
48. An offensive foul that stops the clock before the snap anywhere in the fourth period
    restarts it on the snap, and e-3 reaches no further than that: an offensive foul during
    a fourth-quarter down stops the clock at the end of the down rather than before a snap,
    so it restarts on the ready like any other period's. `[2025 · 4-3-2-e-3, 4-4-e]` —
    `test:offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap`,
    `test:offensiveFoulDuringAFourthQuarterDownRestartsTheClockOnTheReady`
49. A foul before the snap charges no play time, because no play happened.
    `[2025 · 4-4-g]` — `test:deadBallFoulBeforeTheSnapChargesNoTime`,
    `test:preSnapKillsThePlay`, `test:elapsedDependsOnThePreviousStoppage`
50. A period that expires between downs ends where it stands. The interval before a snap is
    not a down, so nothing extends the period through it and the down the offence was
    walking up to is never snapped and never recorded. It follows that the clock a play is
    recorded with is the clock the ball was snapped on, and not the clock at the previous
    whistle: the interval comes off before the down exists. The live-ball case is the other
    one — a period whose time expires while the ball is in play runs on until the down ends.
    `[2025 · 4-8-1, 4-3-2]` — `test:periodExpiringBetweenDownsRecordsNoDown`,
    `test:everyPlayIsRecordedWithTheClockItWasSnappedOn`; the live-ball converse is
    `test:touchdownAsTheFirstQuarterExpires`, `test:touchdownAsTheSecondQuarterExpires`
51. Three charged timeouts per team per half, they do not carry over, and they never go
    negative. `[2025 · 4-5-1]` — `test:timeoutsStayLegal`, `test:timeoutsAreSpentAndVisible`;
    and every one charged is on the record of the snap it preceded, with the side that took
    it — `test:timeoutsAreOnTheRecord`
52. The play clock is 40 seconds from the end of the previous play and 25 from the whistle
    after an administrative stoppage — 30 after a runoff, and back to 40 after a defensive
    act that conserves time — and letting it expire with the ball not snapped is delay of
    game: five yards from the succeeding spot, the down unchanged, and on a running game
    clock the whole play clock gone before the whistle.
    `[2025 · 4-6-1, 4-6-2, 4-6-3, 4-6-4, 14-4-1]` —
    `test:delayOfGameWhenThePlayClockExpires`,
    `test:delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock`,
    `test:playClockValues`, `test:everySnapRecordsItsPlayClock`,
    `test:anExpiredPlayClockWithNoTimeoutIsADelayOfGame`; **modelling**: the
    offence's tempo is how much of whatever clock is in force it means to leave itself,
    and how often it overruns that slack is a draw that halves with every eight seconds
    of it — the delay-of-game rate is derived from the clock rather than tuned as a flat
    roll, and `row:penalty.delayOfGame` is what measures it. `test:tempoOrdering` pins
    the tempo table, and that a tempo keeps its share of slack on a shorter clock is a
    further **modelling** choice, pinned by `test:tempoScalesToTheClock`
    A play clock about to expire is a decision before it is a foul: a charged timeout
    stops it, so the down is played for the price of a timeout rather than five yards,
    and the game clock goes on waiting for the snap it was already waiting for. The
    offence is asked with the interval's verdict already in hand, so a timeout spent on
    a play clock is spent on a down that was really in danger. `[2025 · 4-3-2, 4-5-1,
    4-6-3-a, 4-6-4]` — `test:aChargedTimeoutBeatsThePlayClock`,
    `test:anOffenceSpendsATimeoutRatherThanTakeTheFiveYards`; a further **modelling**
    choice: an offence that has stood through a charged timeout comes to the snap with
    its call in and its grouping set, so those twenty-five seconds are counted against
    lining up rather than against a huddle that has already happened — the book fixes the
    clock's length and says nothing about how ready the offence is. Pinned by
    `test:theSnapOutOfATimeoutIsPrepared`

## The ten-second runoff

53. The runoff is ten seconds. `[2025 · 4-7-1 Item 1]` — `test:tenSeconds`
54. Inside the last two minutes of either half, an offensive act that conserves time with
    the clock running costs those ten seconds, the play clock goes to 30, and the game clock
    restarts on the ready rather than the snap. `[2025 · 4-7-1, 4-7-1 Item 1]` —
    `test:falseStartInsideTwoMinutesCostsTenSeconds`, `test:window`
55. Fourth-period timing rules apply in regular-season overtime, so the runoff applies there
    too. `[2025 · 16-1-3-e, 4-7-1 Item 1]` —
    `test:falseStartInsideTwoMinutesOfOvertimeCostsTenSeconds`
56. There is no runoff when the clock was already stopped. `[2025 · 4-7-1 Item 1]` —
    `test:falseStartWithTheClockStoppedCostsNoTime`
57. The defence may always decline the runoff and keep the yardage, and declining the
    yardage declines the runoff with it. `[2025 · 4-7-1 Item 1]` —
    `test:trailingDefenseDeclinesTheRunoff`, `test:runoffDecisionDefaults`
58. The offence may spend a charged timeout instead of the runoff, and the clock then starts
    on the snap. `[2025 · 4-7-1 Item 1]` — `test:offenseTakesATimeoutInsteadOfTheRunoff`,
    `test:runoffDecisionDefaults`
59. A half can end on a runoff. `[2025 · 4-5-4 Note 4]` —
    `test:runoffAtEightSecondsEndsTheHalf`
60. There is never a runoff against the defence: its dead-ball foul resets the play clock to
    40 and starts the game clock on the ready unless the offence wants the snap.
    `[2025 · 4-7-1 Item 2, 4-5-4 Note 9]` — `test:deadBallFoulBeforeTheSnapChargesNoTime`,
    `test:window`
61. An illegal substitution after the two-minute warning, with the ball dead and the clock
    running, is five yards and a runoff. `[2025 · 4-7-2]` — `test:window`
62. In the last 40 seconds of either half a defensive foul that conserves time ends the
    half, unless the defence has a timeout left or the offence would rather play on.
    `[2025 · 4-7-3, 4-7-1-a]` —
    `test:defensiveFoulInTheLastFortySecondsEndsTheHalfAtTheOffensesElection`,
    `test:defensiveFoulInTheLastFortySecondsWhenTheOffenseWouldRatherPlayOn`,
    `test:defensiveFoulInTheLastFortySecondsWithADefensiveTimeoutLeft`,
    `test:lastFortySeconds`, `test:conservingActs`; the article's second clause, an excess
    timeout for an injured defender, ends the half on the same terms (4-5-4-b) —
    `test:injuryToADefenderInTheLastFortySecondsEndsTheHalf`; the election is the offence's, a
    `PlayCaller` decision written into the play's decision log; **modelling**: the
    defence's option to spend a timeout in lieu of the clock starting (4-7-1 Item 2) is
    not modelled — a defence with a timeout keeps the half alive by having one, and spends
    it as any timeout, before the next snap
63. A replay reversal or a nullified foul after the two-minute warning that leaves the clock
    where a correct ruling would not have stopped it runs ten seconds off, which neither
    team may decline. `[2025 · 4-7-4]` — **modelling**: excluded until a replay system
    exists. There is no replay in this engine and no foul is ever nullified after the
    fact, so nothing can produce that runoff; `test:noRunoffFollowsAReplay` pins that
    every runoff a game produces, and every clock election the record can carry, is a
    foul's, the last forty seconds' or an injury timeout's
64. After the two-minute warning an injury timeout is charged to the injured player's
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

65. Half the distance to the goal is measured from the spot of enforcement, whichever spot
    that is. `[2025 · 14-2-1]` — `test:halfTheDistanceFromTheEnforcementSpot`,
    `test:defensiveHoldingAtTheThreeIsHalfTheDistance`,
    `test:falseStartAtTheOwnThreeIsHalfTheDistance`
66. Every foul is enforced from one of the spots the book lists — the previous spot, the
    spot of the foul, the succeeding spot, the dead-ball spot and the rest — and never from
    somewhere convenient. `[2025 · 14-3-4]` — `test:enforcementFamilies`
67. A flag that comes down before the ball is snapped walks off from the succeeding spot
    and the same down is played again; one that comes down as it is snapped walks off from
    the previous spot instead, and the down is played over. Either way, if enforcing the
    penalty produces a first down, it is a first down instead. `[2025 · 14-4-1]` —
    `test:falseStartAtTheOwnThreeIsHalfTheDistance`, `test:preSnapKillsThePlay`
68. The basic spot for a foul during a run not followed by a change of possession is the
    dead-ball spot, so a facemask at the end of a 20-yard run is fifteen more from where the
    run ended, and a first down. `[2025 · 14-3-5-a, 14-3-6, 12-2-15]` —
    `test:facemaskAtTheEndOfARun`, `test:facemaskAtTheEndOfARunIsEnforcedFromTheEndOfTheRun`
69. Under the three-and-one method a defensive foul during a run is enforced from the basic
    spot and so is an offensive foul in advance of it, while an offensive foul behind the
    basic spot is enforced from the spot of the foul. `[2025 · 14-3-6]` —
    `test:blockInTheBackDuringARun`, `test:holdingOnAGain`
70. Its exception: an offensive foul behind the line of scrimmage is enforced from the
    previous spot, and so is a defensive one when the basic spot is behind the line.
    `[2025 · 14-3-6]` — `test:blockInTheBackBehindTheLine`, `test:contactFoulOnALoss`
71. Between the snap and the moment a forward pass from behind the line is over, a foul by
    either team is enforced from the previous spot; the catch is the boundary, and what
    follows it is a run. `[2025 · 8-6-1]` — `test:roughingOnAnIncompletion`,
    `test:enforcementFamilies`
72. A personal foul by the defence before a completion is enforced from the dead-ball spot
    or the previous spot, whichever favours the offence. `[2025 · 8-6-1-d]` —
    `test:roughingOnACompletion`
73. Defensive pass interference is a first down at the spot of the foul.
    `[2025 · 8-5-Penalty, 8-6-1-b]` — `test:spotFouls`, `test:interferenceDownfield`
74. Defensive pass interference in the end zone is first and goal at the 1, or half the
    distance to the goal when the previous spot was inside the 2.
    `[2025 · 8-5-Penalty, 8-6-1-b]` — `test:interferenceInTheEndZone`,
    `test:interferenceInTheEndZoneSpotsAtTheOne`,
    `test:interferenceInTheEndZoneFromInsideTheTwo`
75. Offensive pass interference is ten yards from the previous spot, and the down is
    replayed. `[2025 · 8-5-Penalty]` — `test:offensiveInterference`
76. A defensive interference flag is the reason the pass was not caught: the foul is
    contact past the first yard downfield that spoils an eligible receiver's chance at the
    ball, and the defence's restrictions run from the throw until the ball is touched, so
    on the matchup it is called a flag and a catch cannot both have happened.
    `[2025 · 8-5-1]` — `test:interferenceMeansNoCatch`,
    `test:acceptedInterferenceIsNeverOnACompletion`
    **modelling**: the engine draws interference on the target's matchup and on no other,
    which is its own simplification and not the article's — 8-5-1 protects every eligible
    receiver — so what it cannot produce is a flag away from the ball, on a matchup the
    throw was never going to.
77. Contact that would otherwise be interference is permissible when the pass is clearly
    uncatchable by the players involved, the article's own exception being the offence's
    blocking downfield. `[2025 · 8-5-3-c, 8-3-2, 8-5-4]` —
    `test:noInterferenceOnAnUncatchableBall`
    **modelling**: the offence's downfield block is not drawn as an act of its own, so the
    exception has nothing to except and neither kind is called on a throw the record says
    nobody could reach.
78. A shove or a push-off that buys a receiver room is interference by the offence, and the
    penalty takes ten yards from the previous spot — which brings back whatever the down
    produced, a catch included. `[2025 · 8-5-2, 8-5-Penalty]` —
    `test:offensiveInterferenceCanSitOnACatch`, `test:offensiveInterference`
79. Unsportsmanlike conduct after the play is fifteen yards from the succeeding spot, and an
    automatic first down when it is the defence's. `[2025 · 12-3-1]` —
    `test:conductFoulAfterThePlay`
80. When a run with a foul in it is followed by a change of possession, a personal foul by
    the team that lost the ball is enforced from the dead-ball spot and the defence keeps
    the ball. `[2025 · 14-4-3-b]` — `test:facemaskByTheFormerOffenseOnAReturn`,
    `test:blockInTheBackOnAReturn`
81. A defensive foul during a touchdown leaves the score standing; an offensive contact foul
    during its own touchdown nullifies it, enforced from the previous spot.
    `[2025 · 14-2-3, 14-3-6]` — `test:defensiveFoulOnATouchdown`,
    `test:offensiveContactFoulOnItsOwnScore`
82. The non-penalised team takes whichever of the two outcomes is better for it, and a
    double foul with no change of possession offsets and replays the down.
    `[2025 · 14-5-1]` — `test:flagsAreEnforced`
83. A personal or unsportsmanlike foul during a down in which the opponent kicks a field
    goal or scores a safety is enforced on the free kick, and one during a touchdown is
    enforced on the try; a dead-ball foul after any score goes on whichever of the two
    follows it. `[2025 · 14-2-3, 11-3-3 Item 1, 11-3-3 Item 7]` —
    `test:roughingOnAMadeFieldGoalMovesTheFreeKick`,
    `test:aPersonalFoulDuringASafetyMovesTheFreeKick`, `test:aFoulDuringATouchdownGoesOnTheTry`,
    `test:defensiveFoulOnATouchdown`, `test:roughingOnAMadeFieldGoalMovesTheKickoff`,
    `test:anOrdinaryFoulOnAMadeKickIsDeclined`, `test:personalFoulsAreNamedByTheBook`,
    `test:runningIntoTheKickerOnAMadeFieldGoalIsDeclined`
    An offensive foul during a *successful try* repeats the try, and a defensive one
    leaves the point and is enforced on the succeeding free kick.
    `[2025 · 11-3-3 Item 3-a, 11-3-3 Item 4-a]` —
    `test:anOffensiveFoulOnASuccessfulTryRepeatsIt`,
    `test:aDefensiveFoulOnASuccessfulTryMovesTheFreeKick`,
    `test:holdingOnASuccessfulTryRepeatsIt`.
    And the kicker on a kick from scrimmage is protected either way, by the two halves of
    one article with a penalty apiece: roughing him (Item 1) is fifteen yards from the
    previous spot and an automatic first down, and the article marks it a personal foul;
    running into him (Item 2) is five from the previous spot with no automatic first down,
    and the article marks it not one. The article says nothing about the down — five from
    the previous spot replays it only where they leave the ball short of the line to gain,
    because reaching it is a new series like any other `[2025 · 7-3-1-b, 3-8-4]`. That
    marking, and not the section the foul is printed under, is what 14-2-3 turns on, so of
    the two only roughing is carried to a succeeding spot; and neither by itself wipes a
    kick that was already away, because the rush is over before the ball comes down.
    `[2025 · 12-2-12]` —
    `test:roughingOnAMissedFieldGoalIsAFirstDown`, `test:runningIntoTheKickerReplaysTheDown`,
    `test:runningIntoTheKickerOnAMadeFieldGoalIsDeclined`
84. The basic spot when a **run** is followed by a change of possession is the spot where
    possession was lost, and a defensive foul there gives the ball back to the offence
    before enforcement — unless that spot is **behind the line of scrimmage**, in which
    case a defensive foul, whether it was behind the line or beyond it, comes off the
    previous spot instead. The strip sack is what makes the exception the common half of
    this invariant rather than the rare one: measuring from where the ball came loose
    would take the sack's yards off the offence a second time.
    `[2025 · 14-3-5-b, 14-4-3-a, 14-3-6 Exception 1, 14-4-6-b]` —
    `test:defensiveFoulOnARunThatEndsInAFumbleIsEnforcedFromTheSpotOfTheFumble` for the
    gain, `test:defensiveFoulOnAStripSackIsEnforcedFromThePreviousSpot` and
    `test:contactFoulOnAStripSack` for the loss; the record's half of it — every takeaway
    says where possession was lost — is `test:takeawaysCarryTheSpot`. The same flag on a
    **pass** is a different rule: until a forward pass from behind the line is over, a flag
    on either side comes off the previous spot, and the down turns into a running play only
    once somebody catches the ball; and a defensive **personal** foul before that pass is
    completed is walked off from the better of two spots for the offence — where it
    snapped, or where the ball was dead. An interception is not a completion, which puts a
    foul that preceded
    one inside that exception rather than outside it, so the offence takes the better of
    the two spots: where it snapped when the interceptor was dropped behind that, and where
    he was dropped when he was dropped in front of it.
    `[2025 · 14-4-5-d, 8-6-1-d, 8-1-3]` —
    `test:defensiveFoulBeforeAnInterceptionIsEnforcedFromThePreviousSpot` for the first arm,
    `test:defensiveFoulBeforeADeepInterceptionIsEnforcedFromTheDeadBallSpot` for the second;
    **modelling**, and both cases unreachable by the crude resolver today: the record says
    nothing about *when* in a down a flag flew, so a foul by the intercepting team during
    its own return is the same record as one before the catch and is walked off the same
    way, which is right for the second and wrong for the first; and a pass **completed and
    then fumbled away** is enforced from the fumble, where 14-4-5-d gives the previous spot
    if the foul preceded the catch — the record cannot tell the two apart.
    [#58](https://github.com/knissley/football-manager/issues/58) carries both

## Kickoffs and onside kicks

85. An onside kick the kicking team legally recovers is its ball, first and ten, where the
    play died, and it may not recover before the ball reaches the receiving team's
    restraining line ten yards on, so either side comes up with it at or beyond there.
    `[2025 · 6-1-4-c, 6-1-4-d, 6-1-6, 6-1-6-e, 6-1-6-g]` —
    `test:onsideRecoveryKeepsPossession`, `test:onsideRecovered`,
    `test:anOnsideKickIsRecoveredAtTheReceiversRestrainingLine`. And a kickoff the returner
    fumbles and the kicking team carries in is the kicking team's touchdown, its try, and
    its kickoff — any player of either team may advance a fumble, and a runner crossing the
    goal line scores. `[2025 · 8-7-3 Item 1, 11-2-1, 11-3-1, 11-3-4]` —
    `test:kickoffFumbledAndCarriedInIsTheKickersTouchdown`; **modelling**: the crude
    resolver never fumbles a kick, so only a script reaches it
86. Only a trailing team may attempt an onside kick, it must declare it, and it may do so at
    any point in the game. `[2025 · 6-1-1-c, 6-1-6]` —
    `test:onsideKicksAreDeclaredWheneverTrailing`, `test:onsideDeclarationFollowsTheBook`;
    the declaration itself is not in the stream, so what the engine models is the rule's
    two conditions and not the notice to the Referee
87. A kickoff is from the kicking team's 35 and a safety kick from its 20 — unless a
    distance penalty has moved that line — and the landing zone is the receiving team's 20
    out to its goal line. `[2025 · 6-1-2-a, 6-1-2-b, 6-1-2-e]` —
    `test:theLandingZoneIsTheLastTwenty`, `test:aPenaltyMovesTheKickAndChangesIt`,
    `test:theAwardIsMeasuredFromTheKick`. The receiving team's setup zone and everything
    the formation article requires of it `[2025 · 6-1-2-c, 6-1-2-d, 6-1-3-b]` are
    **not yet enforced** and no issue carries them: nobody lines up for a free kick in the
    crude resolver, so there is no alignment to be illegal
88. A kick that reaches the end zone without coming down in the landing zone first is a
    touchback at the receiving team's 35. `[2025 · 6-1-5]` —
    `test:kickoffTouchbackIsAtTheThirtyFive`, `test:aKickoffTouchbackOutrunsAPunts`. The
    book's other touchback, at the 20 for a kick that comes down in the landing zone first
    `[2025 · 6-1-5-a]`, is **not yet enforced** and no issue carries it: the crude resolver
    returns every kick it puts in the landing zone, so it never reaches that case, and the
    spatial resolver is where a kick that bounces into the end zone comes from
89. A kick that goes out of bounds or comes down short of the landing zone hands the
    receiving team its choice of spots, 25 yards on from the kick being the usual one.
    `[2025 · 6-2-4]` — `test:aKickOutOfBoundsIsTwentyFiveYardsOn`,
    `test:aShortKickIsSpottedWhereItLiesWhenThatIsNearer`,
    `test:aShortOrOutOfBoundsKickIsGivenAway`. The safety kick's 30 rather than 25 is
    **not yet enforced** and no issue carries it: `Rules.advance` is a function of the
    situation and the outcome, and neither says which kind of free kick this was
90. A returned kick changes hands where the return ended, and a kick returned all the way is
    a touchdown for the returning team. `[2025 · 6-1-4]` — `test:returnedKickChangesHands`,
    `test:kickReturnedForScore`

## The field, the series and the stream

91. A series is four scrimmage downs to reach the line to gain, which sits ten yards
    downfield of where the series began or on the goal line when that is closer; reaching it
    starts a new series and failing on fourth down hands the ball over at the spot.
    `[2025 · 3-8-2, 3-8-3, 7-3-1]` — `test:firstDown`, `test:firstAndGoal`,
    `test:turnoverOnDowns`, `test:fourthDownConversion`, `test:gainMovesForward`,
    `test:lossMovesBack`
92. Every ball is on a legal spot, in a legal down and distance, in a period the rules
    define. `[2025 · 1-1-1, 3-8-2, 4-1-1]` — `test:spotsAreAlwaysLegal`,
    `test:situationsAreValid`, `test:streamIsOrdered`
93. **Contract**, not a rule: the package a defensive call names is the package the
    situation says is on the field. Both are held by value in the record so a reader
    years later can ask what was called ([ADR-0010](adr/0010-plays-designs-and-calls.md)),
    and a record that answers the question two ways cannot be read. —
    `test:theCallAndTheFieldAgreeOnThePackage`

## What a season of games looks like

Not rules. Each line is a band over a real-league season, measured by `Tools/simharness`.
The band and the season are in the [calibration table](match-engine.md#calibration), and
what every one of them was derived from is in
[`reference/calibration-sources.md`](reference/calibration-sources.md).

94. A team scores about what a real team scores, and the game's points come mostly from
    touchdowns and then from field goals. — `row:points`, `row:pointsFromTouchdowns`,
    `row:pointsFromFieldGoals`, `row:gamesWithin3`, `row:gamesWithin7`
95. Games end tied about as rarely as they really do, reach overtime about as often, and
    play about as much of the overtime period. — `row:tiesPerGame`, `row:overtimeRate`,
    `row:overtimeLength`
96. A team throws for and runs for about what a real team does, at about the same yards a
    carry, a completion, an attempt and a play. — `row:passingYards`, `row:rushingYards`,
    `row:yardsPerCarry`, `row:yardsPerAttempt`, `row:yardsPerCompletion`, `row:yardsPerPlay`
97. Passes are completed, pressured, sacked and intercepted at about the real rates. —
    `row:completionPercentage`, `row:sackRate`, `row:interceptionRate`, `row:pressureRate`,
    `row:completionsZeroOrFewer`
98. A game holds about as many snaps as a real one, and a team runs about as many plays from
    scrimmage. — `row:playsPerGame`, `row:playsFromScrimmage`
99. Third down comes up at about the real distance and is converted at about the real rate,
    and first down gains about what it really gains. — `row:thirdDownDistance`,
    `row:thirdDownConversion`, `row:firstDownGain`, `row:firstDownsPerTeamGame`
100. The shape of a carry is right and not just its mean: about as many are stuffed, gain two
    or fewer, reach ten, and break twenty. — `row:carriesStuffed`, `row:carries2orFewer`,
    `row:carries10plus`, `row:carries20plus`
101. The shape of a dropback is right too — losses, no-gains, ten, twenty and forty-plus. —
    `row:dropbackLoss`, `row:dropbackNoGain`, `row:dropback10plus`, `row:dropback20plus`,
    `row:dropback40plus`
102. Drives end in a punt, a touchdown or on downs at about the real rates, and there are
    about as many of them a game. — `row:driveEndPunt`, `row:driveEndTouchdown`,
    `row:driveEndDowns`, `row:drivesPerTeamGame`, `row:playsPerDrive`
103. The shape of a drive is right: three-and-outs, short drives, middling ones and long
    ones. — `row:drives3orFewer`, `row:drives4to7`, `row:drives8plus`, `row:threeAndOut`
104. A trip inside the 20 ends in a touchdown about as often as it really does. —
    `row:redZoneTouchdownRate`
105. Drives start about where they really start, and about as often inside their own half. —
     `row:averageStart.2025`, `row:averageStart.2024`, `row:ownHalfStarts.2025`,
     `row:ownHalfStarts.2024`, `row:snapsInsideOwn10`
106. Teams punt about as often, for about the real gross and net, about as many punts come
     back, and a returned kick comes back about as far. — `row:puntsPerTeamGame`,
     `row:netPunt`, `row:grossPunt`, `row:puntsReturned`, `row:puntReturnYards`,
     `row:kickoffReturnYards.2025`, `row:kickoffReturnYards.2024`; all four distances are
     read off the record, which says where every kick was fielded —
     `test:kickDistancesAreDerivable`, `test:onlyKicksAreFielded`
107. Field goals are attempted about as often, from about the real spread of distances, and
     made at about the real rate from each. — `row:fieldGoalsPerTeamGame`,
     `row:fieldGoalsUnder30`, `row:fieldGoals30to39`, `row:fieldGoals40to49`,
     `row:fieldGoals50plus`, `row:fieldGoalAttemptsUnder30`, `row:fieldGoalAttempts30to39`,
     `row:fieldGoalAttempts40to49`, `row:fieldGoalAttempts50plus`
108. Extra points are made, and two-point tries taken and converted, at about the real
     rates. — `row:extraPointsMade`, `row:twoPointTries`, `row:twoPointConversion`
109. Fourth down is punted, kicked and gone for at about the real rates, and converted at
     about the real one. — `row:fourthDownPunted`, `row:fourthDownKicked`,
     `row:fourthDownWentForIt`, `row:fourthDownAttempts`, `row:fourthDownConversion`,
     `row:fourthAndOneWentForIt`
110. The ball is turned over, lost and fallen on at about the real rates, and about as many
     touchdowns are scored by somebody other than the offence. — `row:turnovers`,
     `row:fumblesLost`, `row:fumblesKept`, `row:defensiveReturnTouchdowns`,
     `row:nonOffensiveTouchdowns.2025`, `row:nonOffensiveTouchdowns.2024`,
     `row:kickReturnTouchdowns.2025`, `row:kickReturnTouchdowns.2024`, `row:safeties`
111. Kickoffs are returned and taken for touchbacks at the rates the kickoff rule in force
     produces, and onside kicks are attempted and recovered at about the real rates. —
     `row:kickoffsReturned.2025`, `row:kickoffsReturned.2024`, `row:kickoffTouchbacks.2025`,
     `row:kickoffTouchbacks.2024`, `row:onsideKicks.2025`, `row:onsideKicks.2024`,
     `row:onsideRecovery.2025`, `row:onsideRecovery.2024`
112. About as many flags fly as really do, spread over the fouls that really get called, and
     the road team commits a few more pre-snap fouls than the home team. —
     `row:penaltiesPerGame`, `row:penalty.offensiveHolding`, `row:penalty.falseStart`,
     `row:penalty.defensivePassInterference`, `row:penalty.defensiveHolding`,
     `row:penalty.unnecessaryRoughness`, `row:penalty.delayOfGame`, `row:penalty.offside`,
     `row:penalty.illegalFormation`, `row:penalty.roughingThePasser`,
     `row:penalty.neutralZoneInfraction`, `row:preSnapRoadVsHome`
113. Personnel looks like the sport's: 11 personnel against nickel most of the time, base
     against heavier looks, and a run gains more into a box it does not outnumber by much. —
     `row:personnel11`, `row:packageNickel`, `row:packageBase`, `row:ypcEvenCount`,
     `row:ypcOutnumberedByOne`
114. The endgame is played: teams kneel, spike, scramble and spend timeouts about as often
     as they really do. — `row:kneelsPerGame`, `row:spikesPerGame`, `row:scramblesPerGame`,
     `row:timeoutsPerGame`
115. Every man on the field is in the record, and each position group takes about as many
     snaps a game as it really does: one quarterback and five linemen a snap, a back and a
     tight end and change, close to three receivers, a front seven of six or seven and
     four or five defensive backs. — `row:snaps.quarterback`, `row:snaps.backfield`,
     `row:snaps.receiver`, `row:snaps.tightEnd`, `row:snaps.offensiveLine`,
     `row:snaps.frontSeven`, `row:snaps.defensiveBack`; the record's half of it is
     `test:everyPlayCarriesTwentyTwoSlots`, `test:creditsAgreeWithTheField`,
     `test:quarterbackSnapsSumToScrimmagePlays`; and every flag names a player the record
     identifies, on the offending team and on its side of the ball, whether or not the
     play credited him — `test:offendersAreReal`
116. Over a season, team win totals spread about as widely as they really do. —
     `row:winTotalSigma`, which cannot be measured before there is a schedule, at M3

## What the harness cannot check yet

117. A completion is a completion whether it gained a yard, none, or lost one. The record
     says a pass was caught, and the harness reads that rather than inferring it from
     positive yards. `[2025 · 8-1-3]` — `test:completionsForNothingAreComplete`,
     `test:passResultAgreesWithTheEnding`, `row:completionPercentage`; S14 in the
     [audit](audit-is-this-football.md)
118. Players miss games at about the rate they really do, and heavy rain takes points off a
     game. Nobody has cited either band, so `row:playerGamesLost` and `row:heavyRainPoints`
     print `unsourced` and are never `ok`. — **not yet enforced**: the sourcing is
     [#2](https://github.com/knissley/football-manager/issues/2)'s remaining tail
119. Receivers drop about as many as they really do, defenders knock away about as many,
     and a defensive interference flag is thrown about as often as one is enforced. The
     first two have no band anybody has cited — the play-by-play charts neither a drop nor
     a break-up — and the third is a count of flags rather than of enforced fouls, which
     nobody has computed either, so `row:dropsPerTarget`, `row:passesDefensedPerGame` and
     `row:interferenceDrawnPerGame` print `unsourced` and are never `ok`. What each band
     would have to be computed from is in
     [`reference/calibration-sources.md`](reference/calibration-sources.md). —
     **not yet enforced**: the sourcing is
     [#2](https://github.com/knissley/football-manager/issues/2)'s remaining tail, and the
     rates themselves are
     [#49](https://github.com/knissley/football-manager/issues/49)'s
120. A defensive interference flag on a pass that was then completed is the engine
     contradicting itself rather than a rate to be sourced, so `row:interferenceOnCompletions`
     carries a band of zero that no season stands behind and is graded by
     `test:interferenceMeansNoCatch` instead. `[2025 · 8-5-1]` —
     `test:acceptedInterferenceIsNeverOnACompletion`, `row:interferenceOnCompletions`
