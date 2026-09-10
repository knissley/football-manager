# The playing rules, by article

**Status: built.** Every entry is a rule of the **2025** rulebook, in our own words, with
the article number to find the original by. This is the external truth to check a claim
against instead of remembering one.

**Rulebook: 2025 season**, which is the season CLAUDE.md pins the engine to. A 2026 book
exists and has moved some of this again; a 2026 rule is out of scope here, and reporting
that describes one is not evidence about this book.

## How to read it

`4-3-2-a-1` is Rule 4, Section 3, Article 2, clause (a), item (1). Entries are in rule
order, so a citation anywhere in this repository can be looked up by reading down. Where an
article is checked by a test, the test is named as `test:<function name>`; where the engine
does not implement the article yet, the entry says so and names the issue.

**No rulebook text is reproduced.** Terms of art coincide with the book's because they have
no synonyms worth having. Where a sentence already existed in
`.claude/skills/football-domain/references/game-rules.md` — the same rules read by area
rather than by number — it is reused rather than paraphrased a second time, because two
paraphrases of one rule are two things to keep true.

Which rules must be true of a game, and what checks each, is
[`../invariants.md`](../invariants.md). This file is the index; that file is the promise.

## Rule 1 — The field

- **1-1-1** — The field is 360 feet by 160 feet, with goal lines 10 yards in from each end
  line: 100 yards between goal lines and two 10-yard end zones. — `test:spotsAreAlwaysLegal`

## Rule 3 — Definitions

- **3-8-2** — A series is four scrimmage downs to reach the line to gain. —
  `test:firstDown`, `test:turnoverOnDowns`
- **3-8-3** — The line to gain sits ten yards downfield of wherever the series began, or on
  the goal line when that is closer, which is what first and goal is. — `test:firstAndGoal`
- **3-41** — The two-minute warning. The down under way when the clock runs past 2:00
  finishes and the clock is then dead; it belongs to the second and fourth periods, and to
  the periods Rule 16 times as them — regular-season overtime (16-1-3-e) and a second or
  fourth postseason overtime period (16-1-4-h). — `test:warningBetweenDowns`,
  `test:warningDuringADown`, `test:noWarningMidHalf`, `test:warningInRegularSeasonOvertime`,
  `test:warningInPostseasonOvertime`

## Rule 4 — Game timing

- **4-1-1** — Four 15-minute periods. A tie at the end of them goes to overtime under Rule
  16. — `test:quarters`, `test:structure`, `test:regulationTieGoesToOvertime`
- **4-1-2**, **4-1-3** — Halftime is 13 minutes; the other intermissions are at least two.
  — not modelled: the engine has no intermission clock
- **4-2-2** — The coin toss, not more than three minutes before the first-half kickoff. The
  second-half first choice belongs to the captain who lost the pregame toss, unless the
  winner deferred. — `test:halftimePossession`; neither the toss nor a deferral is modelled
- **4-2-3** — The teams change goals at the end of the first and third periods; possession,
  the down, the position of the ball and the line to gain are unchanged. — not modelled, and
  it need not be: a spot is stored relative to whoever has the ball, so there is no end of
  the field to swap. `test:ownYardConversion`, `test:scoreIsPossessionRelative`
- **4-3-1** — A free kick starts the game clock when the ball is legally touched in the
  field of play. — `test:returnedKickoffAdvancesTheClock`
- **4-3-1-a**, **4-3-1-b**, **4-3-1-c** — It does not start on a touchback, on a kick the
  kicking team recovers before any other legal touching, or on a fair catch. —
  `test:touchbackConsumesNoTime`, `test:kickoffRecoveredByTheKickersStartsNoClock`,
  `test:fairCaughtKickoffStartsNoClock`
- **4-3-2** — Otherwise the clock starts on the snap. — `test:spikeStopsTheClock`
- **4-3-2-a** — After a runner goes out of bounds it starts on the ready for play, except
  in the late windows: the first half's two minutes and the second's five, which overtime
  carries as Rule 16 times its periods. — `test:outOfBoundsEarly`, `test:outOfBoundsLate`,
  `test:outOfBoundsInRegularSeasonOvertime`, `test:outOfBoundsInPostseasonOvertime`
- **4-3-2-a-1** — After a change of possession it waits for the snap. —
  `test:changeOfPossessionStops`, `test:turnoverOnDownsStopsTheClock`
- **4-3-2-e-1**, **4-3-2-e-2**, **4-3-2-e-3** — After a foul the clock restarts as though
  the flag had never flown, except on the snap after the first half's two-minute warning,
  inside the last five minutes of the second half, and after an offensive foul that stops
  the clock before the snap anywhere in the fourth period or regular-season overtime. In
  postseason overtime e-1 and e-2 follow the halves 16-1-4-h makes of its periods; e-3
  names its own periods and does not reach it. —
  `test:falseStartInTheThirdQuarterCostsNoTime`,
  `test:offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap`,
  `test:offensiveFoulInOvertimeStartsTheClockOnTheSnap`,
  `test:offensiveFoulBeforeTheSnapInPostseasonOvertime`,
  `test:offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady`
- **4-3-2-g** — After a ten-second runoff the clock starts on the ready for play. —
  `test:falseStartInsideTwoMinutesCostsTenSeconds`
- **4-3-2-h** — The try is untimed. — `test:touchdownAsTheSecondQuarterExpires`
- **4-4-a** — A free kick down stops the clock. — `test:returnedKickoffAdvancesTheClock`
- **4-4-c** — A runner going out of bounds stops it. — `test:outOfBoundsLate`
- **4-4-d** — A ball dead on or behind a goal line stops it. — `test:touchbackConsumesNoTime`
- **4-4-e** — A foul stops it. — `test:deadBallFoulBeforeTheSnapChargesNoTime`
- **4-4-f** — An incomplete pass stops it. — `test:spikeStopsTheClock`, `test:incompletion`
- **4-4-h** — The two-minute warning stops it. — `test:twoMinuteWarningStopsAtTwoMinutes`,
  `test:twoMinuteWarningStopsAtTwoMinutesOfOvertime`
- **4-4-i** — A change of possession stops it. — `test:changeOfPossessionStops`,
  `test:puntReturnedAndTackledStopsTheClock`,
  `test:fumbleRecoveredByTheDefenseStopsTheClock`
- **4-4-j** — A charged timeout stops it. — `test:timeoutsAreSpentAndVisible`
- Not in the list, and the omission is the rule: **gaining a first down does not stop the
  clock**. — `test:firstDownDoesNotStop`
- **4-5-1** — Three charged timeouts per team per half; they do not carry over. —
  `test:timeoutsStayLegal`
- **4-5-3**, **4-5-4-a**, **4-5-4-b**, **4-5-4 Note 1** — Before the two-minute warning an
  injury timeout leaves the clock as it would have been. After it, the injured player's
  team is charged a team timeout if it has one, and the clock then starts on the snap as
  after any charged timeout (4-3-2);
  with none left the Referee calls an excess timeout, after which the clock starts on the
  ready unless the opponent chooses the snap, and the play clock resets to 40 when the
  excess timeout is the defence's. None of it applies when the injury came of a foul by
  an opponent, or on a down with a change of possession, a score or a try. —
  `test:injuryTimeoutAfterTheWarningIsCharged`, `test:injuryRunoffDeclinedByATrailingDefense`;
  a second excess timeout's five yards (Note 2) and an injury to both sides at once
  (Note 5) are not modelled
- **4-5-4 Note 3** — An excess timeout for injury against the team in possession carries a
  ten-second runoff at the defence's choice, after which the play clock is 30 and the
  clock starts on the ready. — `test:excessInjuryTimeoutAfterTheWarningCarriesTheRunoff`,
  `test:injuryRunoffDeclinedByATrailingDefense`
- **4-5-4 Note 4** — A half can end on a runoff. — `test:runoffAtEightSecondsEndsTheHalf`
- **4-5-4 Note 9** — There is never a ten-second runoff against the defence. — `test:window`
- **4-6-1** — 40 seconds from the end of the previous play, and letting it expire is delay
  of game. — `test:delayOfGameWhenThePlayClockExpires`, `test:playClockValues`,
  `test:everySnapRecordsItsPlayClock`
- **4-6-2** — 25 seconds from the whistle after an administrative stoppage: a change of
  possession, a charged timeout, the two-minute warning, the end of a period, penalty
  enforcement, a free kick. —
  `test:delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock`,
  `test:playClockValues`
- **4-6-3** — What a stoppage leaves on the play clock: 25 after a charged timeout, the
  two-minute warning, the end of a period or a penalty enforcement (a); 40 after a
  defensive act that conserves time or an excess timeout charged to the defence (b); 30
  after a ten-second runoff (c). — `test:playClockValues`; the resume-where-it-stopped
  cases are not modelled, since the engine has no stoppage that leaves a play clock
  half run
- **4-6-4** — When the play clock expires the ball stays dead: the whistle is the foul,
  five yards from the succeeding spot with the down unchanged (14-4-1). —
  `test:delayOfGameWhenThePlayClockExpires`
- **4-7-1** — Neither side may conserve time after the two-minute warning of either half by
  any of six acts: a flag between downs by either side that kills a running clock;
  intentional grounding; an illegal forward pass; a backward pass thrown out of bounds; a
  spike or a throw-away in the field of play once a down is over, a touchdown excepted; and
  an illegal bat or kick out of bounds. Five yards, or more if some other penalty is
  bigger. — `test:window`, `test:conservingActs`
- **4-7-1 Item 1** — When the offence does one of them with the clock running, ten seconds
  come off, the play clock goes back to 30, and the game clock restarts on the ready. The
  offence may spend a charged timeout instead, and then the clock starts on the snap. The
  defence may always decline the runoff and keep the yardage, and declining the yardage
  declines the runoff with it. — `test:tenSeconds`,
  `test:falseStartInsideTwoMinutesCostsTenSeconds`, `test:trailingDefenseDeclinesTheRunoff`,
  `test:offenseTakesATimeoutInsteadOfTheRunoff`,
  `test:falseStartWithTheClockStoppedCostsNoTime`
- **4-7-1 Item 2** — The same act by the defence is not a runoff: the play clock resets to
  40 and the clock starts on the ready unless the offence wants the snap. —
  `test:deadBallFoulBeforeTheSnapChargesNoTime`
- **4-7-2** — An illegal substitution after the two-minute warning, while the ball is dead
  and the clock running, is five yards and a runoff. — `test:window`
- **4-7-3** — In the last 40 seconds of either half, a defensive foul that conserves time,
  or an excess timeout for an injured defensive player, ends the half — unless the defence
  has timeouts left or the offence would rather play on. —
  `test:defensiveFoulInTheLastFortySecondsEndsTheHalfAtTheOffensesElection`,
  `test:defensiveFoulInTheLastFortySecondsWhenTheOffenseWouldRatherPlayOn`,
  `test:defensiveFoulInTheLastFortySecondsWithADefensiveTimeoutLeft`,
  `test:lastFortySeconds`
- **4-7-4** — A replay reversal or a nullified foul after the two-minute warning that
  leaves the clock where a correct ruling would not have stopped it runs ten seconds off.
  Neither team may decline it; either may spend a timeout to prevent it. — not modelled:
  there is no replay system and no foul is ever nullified after the fact, so nothing can
  produce the runoff; `test:noRunoffFollowsAReplay` pins the exclusion
- **4-8-1** — A period whose time runs out with the ball still live does not end there:
  the down is played out first. — `test:touchdownAsTheFirstQuarterExpires`
- **4-8-2** — A period may be extended by one untimed down when something in the down that
  expired it calls for one. — `test:touchdownAsTheSecondQuarterExpires`,
  `test:walkOffTryIsTheCallerChoice`
- **4-8-2-c** — A touchdown on the last play of a period still gets its try. It is waived
  only during sudden-death overtime, or when time in the fourth period has expired and a
  successful try could not affect the outcome. — `test:lastPlayTouchdownDownSeven`,
  `test:lastPlayTouchdownLevel`, `test:lastPlayTouchdownDownNine`

## Rule 5 — Players

- **5-1-1** — 11 players a side. Twelve in the formation is a foul before the snap and a
  foul on the snap. — `test:groupingsFieldEleven`, `test:tempoCausesSubstitutionFouls`

## Rule 6 — Free kicks

The dynamic kickoff, made permanent for 2025. **None of Section 1's geometry is in the
engine**: `Rules` carries one touchback spot and `Advancement` one touchback, so there is
no landing zone, no setup zone and no second touchback spot. That is
[#46](https://github.com/knissley/football-manager/issues/46)'s problem, and the entries
below are what it is held to.

- **6-1-1-b** — The kick after a safety may be a punt as well as a drop kick or a place
  kick. — `test:afterASafetyTheTeamScoredUponKicks`
- **6-1-1-c**, **6-1-6** — Only a trailing team may attempt an onside kick, and it must
  declare it to the Referee before the play clock starts. It may declare at any point in
  the game; fourth quarter only was the 2024 rule. — not yet enforced,
  [#41](https://github.com/knissley/football-manager/issues/41)
- **6-1-2-a**, **6-1-2-b** — The kick is from the kicking team's 35 — its 20 for a safety
  kick — and the other ten of the kicking team line up on the receiving team's 40. — not
  yet enforced, [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-2-c**, **6-1-2-d** — The receiving team's restraining line is its own 35, and the
  setup zone is the five yards between its 35 and its 30. — not yet enforced,
  [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-2-e** — The landing zone is the receiving team's 20 out to its goal line. — not yet
  enforced, [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-3-a**, **6-1-3-c** — The kicking team's ten put a front foot on their restraining
  line and keep both feet down, and nobody but the kicker and the men deep may move until
  the kick has come down in the end zone or the landing zone, or been touched there. — not
  yet enforced, [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-3-b** — At least nine receiving players must be in the setup zone, at least six of
  them with a foot on the restraining line — seven if the team puts more than nine in the
  zone. Its **Item 2** is the 2025 modification: three men at most may stand off that line,
  and only one to a lane. — not yet enforced,
  [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-4** — A kick that comes down in the landing zone is live and gets returned; no fair
  catch is available on it, because a free kick may be fair caught only while it is still
  in the air. — `test:returnedKickChangesHands`, `test:kickReturnedForScore`
- **6-1-4-c**, **6-1-4-d** — Once the kick has reached the end zone or the landing zone, the
  kicking team may take it, and a legal recovery is its ball where the play died. —
  `test:onsideRecoveryKeepsPossession`, `test:onsideRecovered`
- **6-1-5** — A kick that reaches the end zone without touching down in the landing zone
  first — downed there, out of bounds behind the goal line, or off the goal post — is a
  touchback at the **35**. This is the 2025 change; it was the 30 in 2024. A kick that
  reaches the end zone and stays inbounds is still alive. — not yet enforced,
  [#41](https://github.com/knissley/football-manager/issues/41),
  [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-5-a** — Landing zone first, then the end zone: a touchback at the **20**. — not yet
  enforced, [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-6-b**, **6-1-6-c** — On a declared onside kick the kicking team's restraining line
  is still its 35 (its 20 on a safety kick), with the rest of the unit's front feet on that
  line and no more than five players either side of the ball. — not yet enforced,
  [#46](https://github.com/knissley/football-manager/issues/46)
- **6-1-6-e**, **6-1-6-g** — The kicking team may recover only once the ball has reached the
  receiving team's restraining line, ten yards on, or a receiver has touched it first. —
  `test:onsideRecoveryKeepsPossession`
- **6-1-6-h**, **6-1-6-k** — The receiving team puts eight or nine players in the onside
  setup zone, and a kick that goes untouched beyond that zone is dead, the receiving team's,
  and costs the kicking team 15 yards. — not yet enforced,
  [#46](https://github.com/knissley/football-manager/issues/46)
- **6-2-4** — A kick that crosses a sideline before reaching a goal line, or that first hits
  the turf or a man in front of the landing zone, hands the receiving team its choice of
  three spots: the ball 25 yards on from where it was kicked, at the inbounds line; the spot
  where it left the field; or wherever it came down, but that one only when it is nearer
  than 25 yards on. A safety kick pays 30 rather than 25. — not yet enforced,
  [#46](https://github.com/knissley/football-manager/issues/46)

## Rule 7 — Ball in play, dead ball, scrimmage

- **7-3-1** — Four downs to advance to the line to gain. — `test:firstDown`,
  `test:fourthDownConversion`
- **7-4-2** — False start: five yards, enforced before the snap. —
  `test:falseStartAtTheOwnThreeIsHalfTheDistance`, `test:falseStartOnTheKickMovesItBack`
- **7-4-3** — Encroachment: five yards, pre-snap, defence. — `test:everyFoulIsCalled`
- **7-4-5** — Offside: five yards, and the offence may get a free play. —
  `test:offsideOnTheConversionMovesItIn`
- **7-4-8** — Illegal motion: five yards. — `test:everyFoulIsCalled`
- **7-5-1** — Illegal formation by the offence: five yards. — `test:everyFoulIsCalled`

## Rule 8 — Forward pass

- **8-3-1** — An ineligible player downfield on a pass: five yards from the previous spot. —
  `test:enforcementFamilies`
- **8-4-4** — Illegal contact: five yards and an automatic first down. —
  `test:everyFoulIsCalled`
- **8-4-6** — Defensive holding: five yards and an automatic first down. —
  `test:defensiveHoldingAtTheThreeIsHalfTheDistance`
- **8-5-1** — Interference of either kind needs a forward pass thrown from behind the
  line to exist at all, legal or not and whether or not it gets past the line: the foul is
  contact past the first yard downfield that spoils an eligible receiver's chance at the
  ball. The defence's restrictions run from the throw until the ball is touched and the
  offence's from the snap; contact nearer the line than that is holding instead. —
  `test:noInterferenceWithoutAThrow`, `test:interferenceIsOnTheTarget`
- **8-5-4** — Pass interference. The defence's is a first down at the spot of the foul; in
  the end zone it is first down at the 1, or half the distance to the goal when the previous
  spot was inside the 2. The offence's is ten from the previous spot and the down is
  replayed. — `test:spotFouls`, `test:interferenceInTheEndZoneSpotsAtTheOne`,
  `test:interferenceInTheEndZoneFromInsideTheTwo`, `test:offensiveInterference`
- **8-6-1** — Between the snap and the moment a forward pass from behind the line is over,
  a foul by either team is enforced from the previous spot. The catch is the boundary: with
  the ball in a receiver's hands the down has become a run, and the running rules govern
  what follows. — `test:roughingOnAnIncompletion`
- **8-6-1-b** — Interference by the defence is enforced from the spot of the foul. —
  `test:interferenceDownfield`
- **8-6-1-d** — A personal foul by the defence before a completion is enforced from the
  dead-ball spot or the previous spot, whichever favours the offence; if the play scores,
  on the try. — `test:roughingOnACompletion`

## Rule 10 — Opportunity to catch a kick

- **10-2-1** — A fair catch is what a returner gets for a valid signal and then an
  unmolested take, on a scrimmage kick past the line or on a free kick, and only while the
  kick is still airborne. His team snaps where he caught it. —
  `test:fairCaughtKickoffStartsNoClock`, `test:puntHandsOver`
- **10-2-4** — After a fair catch the receiving team may ask for a fair catch kick instead
  of a snap. — not modelled: the engine has no fair catch kick

## Rule 11 — Scoring

- **11-1-2-a** — A touchdown is six. — `test:touchdown`
- **11-1-2-b** — A field goal is three. — `test:fieldGoal`
- **11-1-2-c** — A safety is two. — `test:safety`, `test:safetyPaysTheDefence`
- **11-1-2-d** — A try is one by kick and two by pass or run. —
  `test:extraPointIsOnePoint`, `test:twoPointIsTwoPoints`
- **11-3-1** — After a touchdown the scoring team gets one untimed scrimmage down. The snap
  is 15 yards from the defence's goal line for a kick, two yards for a pass or run, at the
  offence's choice, changeable after a penalty or a timeout. —
  `test:triesAreSnappedFromTheRightSpot`, `test:walkOffTryIsTheCallerChoice`
- **11-3-2-b**, **11-3-2-c** — Either team can score on a try: a try that ends in a
  touchdown is two points whoever scores it, and what would be a safety on a try is one
  point to the opponent. — not yet enforced,
  [#48](https://github.com/knissley/football-manager/issues/48)
- **11-3-3** — Fouls on a try, and where the re-try is snapped from; half the distance on a
  try is measured from the other try spot. Its **Item 2** is the one the engine leans on: a
  foul that kills the play before the snap is treated as it would be before a scrimmage
  play. — `test:falseStartOnTheKickMovesItBack`, `test:offsideOnTheConversionMovesItIn`,
  `test:falseStartOnATryMovesTheTry`
- **11-3-4** — After a try, the team on defence for it receives the succeeding free kick. —
  `test:afterTheTryTheDefendingTeamReceives`, `test:kickoffReturnTouchdownGetsItsTry`
- **11-4-1** — A field goal has to be place-kicked or drop-kicked, struck at or behind the
  line, and reach the goal without grazing the turf or one of the kicker's own men. —
  `test:kicksAreInRange`
- **11-4-2** — A missed field goal that crosses the line and is not touched by the receivers
  comes back to where it was struck, or to their own 20 if it was struck from nearer than
  that. — `test:missedFieldGoalFromInsideTheTwenty`,
  `test:missedFieldGoalFromBeyondTheTwenty`
- **11-4-6** — After a field goal the team scored upon receives the succeeding free kick. —
  `test:afterAFieldGoalTheTeamScoredUponReceives`
- **11-5-2** — After a safety the team scored upon puts the ball in play with a free kick
  from its own 20. — `test:afterASafetyTheTeamScoredUponKicks`
- **11-6-2-c**, **11-6-3** — A punt that reaches the end zone untouched by the receivers is
  a touchback, and they snap at their own 20. — `test:touchbacksDiffer`

## Rule 12 — Player conduct

- **12-1-3-a** — Illegal use of hands by the offence: ten yards. — `test:everyFoulIsCalled`
- **12-1-3-b** — Illegal block in the back: ten yards. — `test:blockInTheBackDuringARun`,
  `test:blockInTheBackOnAReturn`
- **12-1-3-c** — Offensive holding: ten yards, replay the down. — `test:holdingOnAGain`,
  `test:holdsAreExplicable`
- **12-1-6** — Defensive holding: five yards and an automatic first down. —
  `test:defensiveHoldingAtTheThreeIsHalfTheDistance`
- **12-2-7** — Blindside block: fifteen yards. — `test:everyFoulIsCalled`
- **12-2-8** — Unnecessary roughness: fifteen, an automatic first down if by the defence. —
  `test:everyFoulIsCalled`
- **12-2-10** — Impermissible use of the helmet: fifteen, an automatic first down if by the
  defence. — `test:everyFoulIsCalled`
- **12-2-11** — Roughing the passer: fifteen and an automatic first down. —
  `test:roughingOnACompletion`, `test:roughingOnAnIncompletion`
- **12-2-15** — Facemask: fifteen, an automatic first down if by the defence. —
  `test:facemaskAtTheEndOfARun`, `test:facemaskByTheFormerOffenseOnAReturn`
- **12-2-16** — Horse-collar tackle: fifteen and an automatic first down. —
  `test:everyFoulIsCalled`
- **12-3-1** — Unsportsmanlike conduct after the play: fifteen from the succeeding spot, and
  an automatic first down when it is the defence's. — `test:conductFoulAfterThePlay`

## Rule 14 — Penalty enforcement

- **14-2-1** — Half the distance to the goal is measured from the spot of enforcement,
  whichever spot that is. — `test:halfTheDistanceFromTheEnforcementSpot`
- **14-2-3** — A personal or unsportsmanlike foul during a down in which the opponent kicks
  a field goal or scores a safety is enforced on the free kick; during a touchdown, any foul
  is enforced on the try; the offended team may instead take customary enforcement and give
  up the points. — `test:defensiveFoulOnATouchdown` covers the score standing; enforcement
  on the try or the kickoff is not yet enforced,
  [#48](https://github.com/knissley/football-manager/issues/48)
- **14-2-4** — A personal or unsportsmanlike foul by a team whose opponent has the ball at
  the end of the down may be enforced from the dead-ball spot. —
  `test:facemaskByTheFormerOffenseOnAReturn`
- **14-3-4** — The spots a penalty can be enforced from: the previous spot, the spot of the
  foul, the spot of a backward pass or fumble, the dead-ball spot, the succeeding spot, the
  other try spot, and the spot of a change of possession. — `test:enforcementFamilies`
- **14-3-5** — The basic spot. For a foul during a run not followed by a change of
  possession it is the dead-ball spot (**14-3-5-a**); when the run is followed by a change
  of possession it is the spot where possession was lost; during a backward pass or fumble,
  the spot of the pass or the fumble. — `test:facemaskAtTheEndOfARun`; the change-of-
  possession spot is not in the record,
  [#58](https://github.com/knissley/football-manager/issues/58)
- **14-3-6** — The three-and-one method. A foul during a run, a backward pass or a fumble is
  enforced from the basic spot when the defence fouls anywhere, or the offence fouls in
  advance of it; when the offence fouls behind the basic spot, from the spot of the foul.
  Exceptions: the offence's fouls behind the line of scrimmage are enforced from the
  previous spot, and so are the defence's when the basic spot is behind the line. —
  `test:blockInTheBackDuringARun`, `test:blockInTheBackBehindTheLine`,
  `test:contactFoulOnALoss`, `test:holdingOnAGain`
- **14-4-1** — A foul before the snap is enforced from the succeeding spot and the down
  stays; a foul at the snap from the previous spot, and the down is repeated. —
  `test:preSnapKillsThePlay`, `test:falseStartAtTheOwnThreeIsHalfTheDistance`
- **14-4-3** — When a run with a foul in it is followed by a change of possession: a
  defensive foul gives the ball back to the offence before enforcement; an offensive foul
  must be declined by the defence to keep the ball, unless it was a personal or
  unsportsmanlike foul (**14-4-3-b**), in which case the defence keeps the ball and the foul
  is enforced from the dead-ball spot. — `test:facemaskByTheFormerOffenseOnAReturn`
- **14-5-1** — A double foul with no change of possession offsets, and the down is replayed
  at the previous spot; neither team may decline. — `test:flagsAreEnforced`

## Rule 15 — Instant replay

- **15-9** — Replay assist may advise the on-field crew on more objective aspects of a play.
  This is a 2025 modification. — not modelled: there is no officiating crew in the engine

## Rule 16 — Overtime

**Regular season** — a single 10-minute period, after a break of three minutes at most.

- **16-1-3** — The period itself. — `test:regulationTieGoesToOvertime`, `test:overtime`
- **16-1-3-a** — Each side is owed a turn with the ball, whatever the first turn produced.
  The article names one exception: a team that kicks off and then scores a safety against
  the receivers' opening drive has won on the spot. —
  `test:overtimeFirstPossessionTouchdown`, `test:overtimeOpeningDriveSafetyWinsIt`
- **16-1-3-b** — Once both have had that opportunity, whoever has more points has won. —
  `test:overtimeAfterBothPossessedEndsOnAnyScore`, `test:overtimeDefensiveScoreEndsIt`
- **16-1-3-c** — If the side that had it first came away with nothing, or the two are still
  level once both have had their turn, the next points of any kind win it. —
  `test:overtimeAfterBothPossessedEndsOnAnyScore`, `test:overtimeTrailingScorerTryDecides`
- **16-1-3-d** — The period is never extended, not for a second team that has not possessed
  and not for a possession still running. Level at the end is a tie. —
  `test:regularSeasonOvertimeExpiringLevelIsATie`, `test:ties`
- **16-1-3-e** — Two timeouts each; fourth-quarter timing rules otherwise apply, the
  two-minute warning among them. — `test:overtimeTimeoutsAreTwo`,
  `test:falseStartInsideTwoMinutesOfOvertimeCostsTenSeconds`,
  `test:warningInRegularSeasonOvertime`, `test:twoMinuteWarningStopsAtTwoMinutesOfOvertime`,
  `test:downUnderWayAtTwoMinutesOfOvertimeFinishes`, `test:outOfBoundsInRegularSeasonOvertime`,
  `test:offensiveFoulInOvertimeStartsTheClockOnTheSnap`

**Postseason** — 15-minute periods, as many as it takes.

- **16-1-4**, **16-1-4-a** to **16-1-4-c** — The possession rules are the same. —
  `test:postseasonPlaysASixthPeriod`
- **16-1-4-d** — Level at the end of a period, or a second team's initial possession
  unfinished, means another period. — `test:postseasonPlaysASixthPeriod`
- **16-1-4-e**, **16-1-4-g**, **16-1-4-i** — Three timeouts per half, two-minute
  intermissions between periods, and a fresh coin toss after the fourth. 16-1-4-e also
  gives the beginning of the **third** overtime period the first choice of 4-2-2's two
  privileges to the captain who lost the toss before overtime, so a third period is put
  back in play with a free kick, as is a fifth after the toss of 16-1-4-i. — not
  modelled: the engine restarts only the first overtime period and plays on from the same
  spot at every later boundary, which is
  [#86](https://github.com/knissley/football-manager/issues/86)'s and is pinned by
  `test:aThirdPostseasonOvertimePeriodIsNotRestartedWithAKick`. Not modelled either is the
  toss itself, though the one after a fourth overtime period is read as restarting the
  pairing 16-1-4-h describes, so a fifth period is timed as a first: a reading, pinned by
  `test:postseasonOvertimeBeyondTheFourthPeriodRepeatsThePairing`
- **16-1-4-f** — The teams change goals at the end of the first and third overtime
  periods, under 4-2-3: possession, the down, the ball and the line to gain are
  unchanged. — `test:periodResumesWithKickoffAsModelledAnswers`; the change of ends
  itself is not modelled, for the reason 4-2-3 gives
- **16-1-4-h** — Postseason overtime timing: a second overtime period ends as the first
  half does and a fourth as the fourth period does, so the warning, the out-of-bounds
  windows and the runoff belong to those two and a first or third overtime period has
  none of them. Whether it carries 4-3-2-e-3, a whole-period rule, into a fourth overtime
  period outside five minutes is not settled by the book; the engine reads it as not, and
  `test:offensiveFoulInAFourthPostseasonOvertimePeriodOutsideFiveMinutes` pins that
  reading. — `test:firstPostseasonOvertimePeriodHasNoWarning`,
  `test:secondPostseasonOvertimePeriodHasTheFirstHalfsWarning`,
  `test:falseStartInsideTwoMinutesOfASecondPostseasonOvertimePeriodCostsTenSeconds`,
  `test:outOfBoundsInsideFiveMinutesOfASecondPostseasonOvertimePeriodRestartsOnTheReady`,
  `test:outOfBoundsInsideFiveMinutesOfAFourthPostseasonOvertimePeriodWaitsForTheSnap`,
  `test:offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady`,
  `test:postseasonOvertimeRunoff`, `test:warningInPostseasonOvertime`,
  `test:outOfBoundsInPostseasonOvertime`, `test:offensiveFoulBeforeTheSnapInPostseasonOvertime`
- **16-1-5-b** — Possession is gained by catching, intercepting or recovering a loose ball,
  so a defence that takes the ball away has had its possession. —
  `test:overtimeDefensiveScoreEndsIt`
- **16-1-5-c** — On kicking plays the opportunity to possess is defined: a kickoff is the
  receiving team's opportunity, and if the kicking team legally recovers it the receiving
  team is still deemed to have had it. — `test:overtimeKickoffRecoveredByTheKickersEndsIt`
- **A.R. 16.1** — A return touchdown on the *opening* overtime kickoff gets its try, because
  the kicking team is still owed its turn. — `test:kickoffReturnTouchdownGetsItsTry`
- **A.R. 16.2** — After a field goal on the opening possession, a kickoff the kicking team
  recovers ends the game. — `test:overtimeKickoffRecoveredByTheKickersEndsIt`
- **A.R. 16.4** — After a field goal on the opening possession, a kickoff returned for a
  touchdown ends the game, with no try. — `test:overtimeKickoffReturnedForTouchdownEndsIt`

## Not playing rules

Roster and game-day limits — 53 on the active roster, 48 active on game day, the minimum
games on injured reserve, the return-from-IR designations, practice-squad elevations — are
in the league's constitution and bylaws rather than the playing rules, so they carry no rule
number here. The money side of them is in
[`../../.claude/skills/football-domain/references/salary-cap.md`](../../.claude/skills/football-domain/references/salary-cap.md),
and they want a reference of their own.
