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
  `test:firstDown`, `test:turnoverOnDowns`; a fourth down lost to a foul's loss of down is
  the series too —
  `test:groundingOnFourthDownInsideTwoMinutesTurnsItOverAndRestartsOnTheReady`
- **3-8-3** — The line to gain sits ten yards downfield of wherever the series began, or on
  the goal line when that is closer, which is what first and goal is. — `test:firstAndGoal`
- **3-36-3** — Time in: the game clock is running. It is the condition 4-7-1 Item 1 puts
  on the offence's runoff, and a try never meets it (3-40), nor does a down that ran the
  period out (4-8-1). — `test:groundedTryInsideTwoMinutesRunsNothingOff`,
  `test:groundingAsTheHalfExpiresElectsNothing`
- **3-40** — A try is one untimed scrimmage down, played to add one point by a kick or two
  by a touchdown. Untimed is the word that matters to the clock: time is not in during it
  (3-36-3), so an act on a try that conserves time carries no runoff. —
  `test:groundedTryInsideTwoMinutesRunsNothingOff`
- **3-41** — The two-minute warning. The down under way when the clock runs past 2:00
  finishes and the clock is then dead; the warning is an automatic timeout at the
  conclusion of that down, so an act during it came before the warning and 4-7-1 does not
  reach it — `test:groundingOnTheDownThatBringsTheWarningRunsNothingOff`; it belongs to the second and fourth periods, and to
  the periods Rule 16 times as them — regular-season overtime (16-1-3-e) and a second or
  fourth postseason overtime period (16-1-4-h). — `test:warningBetweenDowns`,
  `test:warningDuringADown`, `test:noWarningMidHalf`, `test:warningInRegularSeasonOvertime`,
  `test:warningInPostseasonOvertime`; that it was taken is on the record of the first snap
  after it — `test:warningIsOnTheRecord`
- **3-42** — A T-formation quarterback is a player aligned a yard or less behind the
  snapper. It is the definition 8-2-1 Item 3 spends on the spike, and it is an alignment,
  not a grip: hands under centre are one way to satisfy it, not the test. — not modelled:
  the engine has no quarterback alignment, so nothing it simulates can fail the condition

## Rule 4 — Game timing

- **4-1-1** — Four 15-minute periods. A tie at the end of them goes to overtime under Rule
  16. — `test:quarters`, `test:structure`, `test:regulationTieGoesToOvertime`
- **4-1-2**, **4-1-3** — Halftime is 13 minutes; the other intermissions are at least two.
  — not modelled: the engine has no intermission clock
- **4-2-2**, **4-2-2-a** — The coin toss, not more than three minutes before the first-half
  kickoff; the winner takes one of two privileges — to receive the kickoff or to kick off
  (a), or the choice of goal (b) — and the loser the other. The second-half first choice
  belongs to the captain who lost the pregame toss, unless the winner deferred. —
  `test:halftimePossession`, `test:thirdPostseasonOvertimePeriodOpensWithAKickoff`,
  `test:tossLoserMayElectToKickOffAThirdPostseasonOvertimePeriod`, `test:coinTosses`; the
  choice of (a) is the captain's, `PlayCaller.electsToReceive`, defaulting to receive; the
  toss itself, a deferral and the choice of goal are not modelled — the side that kicks
  off after a toss stands for the captain who lost it
- **4-2-3** — The sides swap ends once the first quarter is over, and again once the third
  is. Nothing travels with them: whose ball it is, which down comes next, where the ball
  sits relative to the field, and the line to gain all carry over untouched. — the change
  of ends is not modelled, and it need not be: a spot is stored relative to whoever has the
  ball, so there is no end of the field to swap. `test:ownYardConversion`,
  `test:scoreIsPossessionRelative`; that play carries on across such a boundary is
  `test:secondPostseasonOvertimePeriodCarriesOn`
- **4-3-1** — On a free kick the clock starts on a legal touching of the ball inside the
  field of play, and on nothing earlier. — `test:returnedKickoffAdvancesTheClock`
- **4-3-1-a**, **4-3-1-b**, **4-3-1-c** — It does not start on a touchback, on a kick the
  kicking team recovers before any other legal touching, or on a fair catch. —
  `test:touchbackConsumesNoTime`, `test:kickoffRecoveredByTheKickersStartsNoClock`,
  `test:fairCaughtKickoffStartsNoClock`
- **4-3-2** — Otherwise the clock starts on the snap. — `test:spikeStopsTheClock`; a
  charged timeout is therefore an interval an offence kneeling the game out does not
  get, which is half of the victory-formation arithmetic —
  `test:aKneltOutLeadStaysKnelt`
- **4-3-2-a**, **4-3-2-a-2**, **4-3-2-a-3** — After a runner goes out of bounds it starts
  on the ready for play, except that it starts on the snap after the two-minute warning of
  the first half (a-2) and inside the last five minutes of the second half (a-3), which
  overtime carries as Rule 16 times its periods. The window is judged where the runner
  stepped out: on the clock after the play's own time has come off, not on the clock at
  the previous whistle, which is up to a huddle and a play earlier. —
  `test:outOfBoundsEarly`, `test:outOfBoundsLate`, `test:outOfBoundsInRegularSeasonOvertime`,
  `test:outOfBoundsInPostseasonOvertime`,
  `test:outOfBoundsInsideFiveMinutesOfTheFourthQuarterWaitsForTheSnap`,
  `test:outOfBoundsAcrossFiveMinutesOfTheFourthQuarterWaitsForTheSnap`,
  `test:outOfBoundsAcrossTheTwoMinuteWarningOfTheSecondQuarterWaitsForTheSnap`
- **4-3-2-a-1** — After a change of possession it waits for the snap. —
  `test:changeOfPossessionStops`, `test:turnoverOnDownsStopsTheClock`; the clause is
  scoped to a runner out of bounds, and it is not an exception to 4-3-2-g's restart after
  a runoff —
  `test:groundingOnFourthDownInsideTwoMinutesTurnsItOverAndRestartsOnTheReady`
- **4-3-2-e** — Where either side's flag has stopped the clock, between downs or at the end
  of one, the clock starts again once the penalty is settled exactly where it would have
  started had no flag been thrown. **The article names declination beside enforcement**, so
  a foul the non-offending side turns down restarts the clock on the same terms an accepted
  one does; nothing in it asks which branch was taken. **Inference, not text:** what a
  declination does not bring is 4-6-2-e's twenty-five-second play clock, which that article
  gives to an enforcement and a declination is not one — so the forty of 4-6-1 runs from
  the end of the play. 4-6-2's list is open, so the book does not settle that half. —
  `test:acceptedFoulDuringADownStopsTheClockForEnforcement`,
  `test:declinedFoulDuringADownStopsTheClockAtTheEndOfTheDown`
- **4-3-2-e-1**, **4-3-2-e-2**, **4-3-2-e-3** — Its three exceptions, in which the clock
  waits for the snap: a flag past the first half's warning (e-1); a flag in the closing
  five minutes of the second half (e-2); and, during the fourth period or regular-season
  overtime, an offensive foul committed once the officials have marked the ball ready,
  killing a clock that had not yet reached its snap (e-3). **Inference, not text:** e-3
  therefore reaches only a flag between downs, since a flag during a down does not stop a
  clock before a snap — 4-4-e stops that clock as the down ends — so a fourth-quarter
  holding call on a run restarts on the ready like any other period's.
  In postseason overtime e-1 and e-2 follow the halves 16-1-4-h makes of its periods; e-3
  names its own periods and does not reach it. The windows of e-1 and e-2 are judged at
  the flag, with the interval before it charged to a running clock — the clock where the
  ball is dead, as for a runner out of bounds. —
  `test:falseStartInTheThirdQuarterCostsNoTime`,
  `test:offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap`,
  `test:offensiveFoulInOvertimeStartsTheClockOnTheSnap`,
  `test:offensiveFoulBeforeTheSnapInPostseasonOvertime`,
  `test:offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady`,
  `test:acceptedFoulDuringADownInsideFiveMinutesWaitsForTheSnap`,
  `test:offensiveFoulDuringAFourthQuarterDownRestartsTheClockOnTheReady`,
  `test:declinedFoulDuringADownInsideFiveMinutesWaitsForTheSnap`
- **4-3-2-g** — After a ten-second runoff the clock starts on the ready for play. The
  article names no exception for a change of possession, so a runoff on a fourth-down
  grounding starts the new offence's clock on the ready too. —
  `test:falseStartInsideTwoMinutesCostsTenSeconds`,
  `test:groundingInsideTwoMinutesRunsTenSecondsOff`,
  `test:groundingOnFourthDownInsideTwoMinutesTurnsItOverAndRestartsOnTheReady`
- **4-3-2-h** — The try is untimed. — `test:touchdownAsTheSecondQuarterExpires`
- **4-4-a** — A free kick down stops the clock. — `test:returnedKickoffAdvancesTheClock`
- **4-4-c** — A runner going out of bounds stops it. — `test:outOfBoundsLate`
- **4-4-d** — A ball dead on or behind a goal line stops it. — `test:touchbackConsumesNoTime`
- **4-4-e** — A flag thrown at any point in a down stops it, and it stops as that down
  ends. The condition is that somebody fouled: what is afterwards done with the penalty is
  not part of it. — `test:acceptedFoulDuringADownStopsTheClockForEnforcement`,
  `test:declinedFoulDuringADownStopsTheClockAtTheEndOfTheDown`
- **4-4-f** — An incomplete pass stops it. — `test:spikeStopsTheClock`, `test:incompletion`,
  `test:spikeCostsItsOwnSecondAndStopsTheClock`
- **4-4-g** — A foul on a ball that is dead already, or that kills the ball on the spot,
  stops it there and then: this is the flag before the snap, and it is why no play time is
  charged for one. — `test:deadBallFoulBeforeTheSnapChargesNoTime`
- **4-4-h** — The two-minute warning stops it. — `test:twoMinuteWarningStopsAtTwoMinutes`,
  `test:twoMinuteWarningStopsAtTwoMinutesOfOvertime`
- **4-4-i** — A change of possession stops it. — `test:changeOfPossessionStops`,
  `test:puntReturnedAndTackledStopsTheClock`,
  `test:fumbleRecoveredByTheDefenseStopsTheClock`
- **4-4-j** — A charged timeout stops it. — `test:timeoutsAreSpentAndVisible`
- Not in the list, and the omission is the rule: **gaining a first down does not stop the
  clock**. — `test:firstDownDoesNotStop`
- **4-5-1** — Three charged timeouts per team per half; they do not carry over. —
  `test:timeoutsStayLegal`, `test:kneelsOnlyWhenTheDefenceCannotStopTheClock`; every one
  charged is on the record of the snap it preceded, with the side that took it —
  `test:timeoutsAreOnTheRecord`
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
- **4-6-1** — 40 seconds from the end of the previous play in which to snap, and letting
  them run out is delay of game. —
  `test:delayOfGameWhenThePlayClockExpires`,
  `test:anExpiredPlayClockWithNoTimeoutIsADelayOfGame`, `test:playClockValues`,
  `test:everySnapRecordsItsPlayClock`,
  `test:theSecondSnapAfterATwoMinuteWarningIsBackOnTheFortySecondClock`; those forty
  seconds are also the offence's to
  spend, which is what a knee-down sequence counts —
  `test:aKneltOutLeadStaysKnelt`,
  `test:fourthDownIsATurnoverOnDownsWhileTheDownCanBeSnapped`
- **4-6-1 in this engine** — The article says nothing about kneeling, and the inference
  drawn from it here is only this: read with 4-8-1, an offence on fourth down with the
  clock running and less than a play clock left may let the forty seconds go, take the
  delay of game, and see the period end with **no snap at all**. That is the sport's
  answer, and it is not a knee — a knee is a snap. This engine has no outcome meaning
  *let the play clock expire*, so its caller kneels that down instead. **That is a
  modelling substitution, not the article.** It no longer puts a down on the record that
  the clock could not have snapped — the period ends in the interval before that snap and
  nothing is written (4-8-1) — so what is left of it is a fourth down elected where the
  sport would have taken the five yards. —
  [#49](https://github.com/knissley/football-manager/issues/49) owns the calibration it
  moves; `test:fourthDownKneelStandsInForDecliningTheSnap`,
  `test:theKneltOutGameEndsOnAThirdDownKnee` pin it meanwhile
- **4-6-2** — 25 seconds from the whistle after an administrative stoppage: a change of
  possession, a charged timeout, the two-minute warning, the end of a period, penalty
  enforcement, a free kick. The article adds that these stoppages take the 25-second
  interval unless some other rule prescribes otherwise, and that they take it even where
  a 40-second count is part-way through — so a warning taken between downs replaces the
  forty the interval had been running on rather than leaving it to finish. —
  `test:delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock`,
  `test:theSnapAfterATwoMinuteWarningBetweenDownsIsAgainstTwentyFiveSeconds`,
  `test:theSecondSnapAfterATwoMinuteWarningIsBackOnTheFortySecondClock`,
  `test:playClockValues`
- **4-6-3** — What a stoppage leaves on the play clock: 25 after a charged timeout, the
  two-minute warning, the end of a period or a penalty enforcement (a); 40 after a
  defensive act that conserves time or an excess timeout charged to the defence (b); 30
  after a ten-second runoff (c). — `test:playClockValues`,
  `test:aChargedTimeoutBeatsThePlayClock`,
  `test:theSnapAfterATwoMinuteWarningBetweenDownsIsAgainstTwentyFiveSeconds`; the
  resume-where-it-stopped cases are not modelled, since the engine has no stoppage that
  leaves a play clock half run
- **4-6-4** — When the play clock expires the ball stays dead: the whistle is the foul,
  five yards from the succeeding spot with the down unchanged (14-4-1). —
  `test:delayOfGameWhenThePlayClockExpires`,
  `test:anExpiredPlayClockWithNoTimeoutIsADelayOfGame`; and the article says *expires*, so
  a clock stopped before it runs out leaves nothing to enforce — a charged timeout (4-3-2)
  is the offence's answer to one it is not going to beat, which is
  `test:aChargedTimeoutBeatsThePlayClock` and
  `test:anOffenceSpendsATimeoutRatherThanTakeTheFiveYards`
- **4-7-1** — Once a half is inside its two-minute warning, neither side may buy the clock
  back by any of six acts: a flag between downs, by either side, that kills a running
  clock; intentional grounding; an illegal forward pass; a backward pass thrown out of
  bounds; a spike or a throw-away inside the field of play once a down is over, a
  touchdown excepted; and an illegal bat or kick out of bounds. Five yards, or more where
  some other penalty is bigger. — `test:window`, `test:conservingActs`
- **4-7-1 Item 1** — When the offence does one of them with the clock running, ten seconds
  come off, the play clock goes back to 30, and the game clock restarts on the ready. The
  offence may spend a charged timeout instead, and then the clock starts on the snap. The
  defence may always decline the runoff and keep the yardage, and declining the yardage
  declines the runoff with it. "While time is in" excludes a try, an untimed down (3-40),
  and "after the two-minute warning" excludes the down that brings the warning (3-41). —
  `test:tenSeconds`,
  `test:falseStartInsideTwoMinutesCostsTenSeconds`, `test:trailingDefenseDeclinesTheRunoff`,
  `test:offenseTakesATimeoutInsteadOfTheRunoff`,
  `test:falseStartWithTheClockStoppedCostsNoTime`,
  `test:groundingInsideTwoMinutesRunsTenSecondsOff`,
  `test:groundedTryInsideTwoMinutesRunsNothingOff`,
  `test:groundingOnTheDownThatBringsTheWarningRunsNothingOff`,
  `test:groundingAsTheHalfExpiresElectsNothing`, `test:noRunoffOnAnEndedHalf`; the restart
  on the ready is 4-3-2-g's and holds after a change of possession too —
  `test:groundingOnFourthDownInsideTwoMinutesTurnsItOverAndRestartsOnTheReady`;
  **not reached**: declining the yardage declines the runoff with it, with the play clock
  at 25 and the clock on the snap, and the defence never declines a grounding, since
  accepting it costs the offence the same down and ten yards besides
- **4-7-1 Item 2** — The same act by the defence is not a runoff: the play clock resets to
  40 and the clock starts on the ready unless the offence wants the snap. —
  `test:deadBallFoulBeforeTheSnapChargesNoTime`
- **4-7-2** — An illegal substitution after the two-minute warning, while the ball is dead
  and the clock running, is five yards and a runoff. — `test:window`
- **4-7-3** — Inside the last 40 seconds of either half the half simply ends, where the
  defence commits one of Article 1's time-conserving acts or is charged an excess timeout
  for an injured player — unless it still has timeouts, or the offence would rather have
  the clock start on the snap, or play on after it starts on the ready. —
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
  the down is played out first. — `test:touchdownAsTheFirstQuarterExpires`; the converse
  is what ends a knelt-out game, since a period that expires *between* downs ends where
  it stands and there is no further down —
  `test:fourthDownIsATurnoverOnDownsWhileTheDownCanBeSnapped`,
  `test:periodExpiringBetweenDownsRecordsNoDown`. The interval to a snap is between
  downs, so a period it exhausts ends with nothing snapped and nothing recorded, and it
  follows that the clock on a play's record is the clock the ball was snapped on —
  `test:everyPlayIsRecordedWithTheClockItWasSnappedOn`
- **4-8-2** — A period may be extended by one untimed down when something in the down that
  expired it calls for one. — `test:touchdownAsTheSecondQuarterExpires`,
  `test:walkOffTryIsTheCallerChoice`; and nothing extends one that expires between downs,
  which is what a knee-down sequence is counting on — `test:aKneltOutLeadStaysKnelt`
- **4-8-2-b** — A foul by the offence extends nothing: the period ends with the down, and
  a half that is over has no time in for a conserving act to be charged against, so no
  runoff, timeout or declination is elected on it —
  `test:groundingAsTheHalfExpiresElectsNothing`, `test:noRunoffOnAnEndedHalf`
- **4-8-2-c** — A touchdown on the last play of a period still gets its try. It is waived
  only during sudden-death overtime, or when time in the fourth period has expired and a
  successful try could not affect the outcome. — `test:lastPlayTouchdownDownSeven`,
  `test:lastPlayTouchdownLevel`, `test:lastPlayTouchdownDownNine`

## Rule 5 — Players

- **5-1-1** — 11 players a side. Twelve in the formation is a foul before the snap and a
  foul on the snap. — `test:groupingsFieldEleven`, `test:tempoCausesSubstitutionFouls`

## Rule 6 — Free kicks

The dynamic kickoff, made permanent for 2025. **The zones the kick is aimed at are in the
engine; the formation is not.** `Rules` carries the landing zone, the touchback at the 35
and 6-2-4's award, and the resolver aims at them — but nobody lines up, so the setup zone,
the restraining lines and every alignment foul are absent, and so is the second touchback
spot, which needs a kick to come down in the landing zone and then reach the end zone.

- **6-1-1-a** — Each half opens with a kickoff, and so does play after a try and after a
  field goal that scores. —
  `test:secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf`,
  `test:kickoffsChangePossessionAndOpenEveryRestartedPeriod`,
  `test:touchdownAsTheSecondQuarterExpires`, `test:afterTheTryTheDefendingTeamReceives`,
  `test:afterAFieldGoalTheTeamScoredUponReceives`
- **6-1-1-b** — The kick after a safety may be a punt as well as a drop kick or a place
  kick. — `test:afterASafetyTheTeamScoredUponKicks`
- **6-1-1-c**, **6-1-6** — Only a trailing team may attempt an onside kick, and it must
  declare it to the Referee before the play clock starts. It may declare at any point in
  the game; fourth quarter only was the 2024 rule. —
  `test:onsideKicksAreDeclaredWheneverTrailing`, `test:onsideDeclarationFollowsTheBook`
- **6-1-2-a**, **6-1-2-b** — The kick is from the kicking team's 35 — its 20 for a safety
  kick — unless a distance penalty has moved that line. — `test:aPenaltyMovesTheKickAndChangesIt`,
  `test:theAwardIsMeasuredFromTheKick`; where the kicking team's other ten line up is not
  modelled, since nobody lines up at all
- **6-1-2-c**, **6-1-2-d** — The receiving team's restraining line is its own 35, and the
  setup zone is the five yards between its 35 and its 30. — not yet enforced and no issue
  carries it: nobody lines up for a free kick in the crude resolver, so there is no
  alignment to be illegal
- **6-1-2-e** — The landing zone is the receiving team's 20 out to its goal line. —
  `test:theLandingZoneIsTheLastTwenty`, `test:aKickIntoTheLandingZoneIsReturned`
- **6-1-3-a**, **6-1-3-c** — The kicking team's ten put a front foot on their restraining
  line and keep both feet down, and nobody but the kicker and the men deep may move until
  the kick has come down in the end zone or the landing zone, or been touched there. — not
  yet enforced and no issue carries it: nobody lines up for a free kick in the crude
  resolver, so there is no alignment to be illegal
- **6-1-3-b** — At least nine receiving players must be in the setup zone, at least six of
  them with a foot on the restraining line — seven if the team puts more than nine in the
  zone. Its **Item 2** is the 2025 modification: three men at most may stand off that line,
  and only one to a lane. — not yet enforced and no issue carries it: nobody lines up for
  a free kick in the crude resolver, so there is no alignment to be illegal
- **6-1-4** — A kick that comes down in the landing zone is live and gets returned; no fair
  catch is available on it, because a free kick may be fair caught only while it is still
  in the air. — `test:returnedKickChangesHands`, `test:kickReturnedForScore`,
  `test:aKickIntoTheLandingZoneIsReturned`
- **6-1-4-c**, **6-1-4-d** — Once the kick has reached the end zone or the landing zone, the
  kicking team may take it, and a legal recovery is its ball where the play died. —
  `test:onsideRecoveryKeepsPossession`, `test:onsideRecovered`
- **6-1-5** — A kick that reaches the end zone without touching down in the landing zone
  first — downed there, out of bounds behind the goal line, or off the goal post — is a
  touchback at the **35**. This is the 2025 change; it was the 30 in 2024. A kick that
  reaches the end zone and stays inbounds is still alive. —
  `test:kickoffTouchbackIsAtTheThirtyFive`, `test:aKickoffTouchbackOutrunsAPunts`; the
  live kick into the end zone is not yet enforced and no issue carries it: a kick the crude
  resolver sends to the end zone is dead there for the touchback, so no ball is left alive
  in it to return or down
- **6-1-5-a** — Landing zone first, then the end zone: a touchback at the **20**. — not yet
  enforced and no issue carries it: the crude resolver returns every kick it puts in the
  landing zone, so no kick reaches the end zone that way
- **6-1-6-b**, **6-1-6-c** — On a declared onside kick the kicking team's restraining line
  is still its 35 (its 20 on a safety kick), with the rest of the unit's front feet on that
  line and no more than five players either side of the ball. — not yet enforced and no
  issue carries it: nobody lines up for a free kick in the crude resolver, so there is no
  alignment to be illegal
- **6-1-6-e**, **6-1-6-g** — The kicking team may recover only once the ball has reached the
  receiving team's restraining line, ten yards on, or a receiver has touched it first. —
  `test:onsideRecoveryKeepsPossession`,
  `test:anOnsideKickIsRecoveredAtTheReceiversRestrainingLine`
- **6-1-6-h**, **6-1-6-k** — The receiving team puts eight or nine players in the onside
  setup zone, and a kick that goes untouched beyond that zone is dead, the receiving team's,
  and costs the kicking team 15 yards. — not yet enforced and no issue carries it: nobody
  lines up for a free kick in the crude resolver, and its onside kick is always either
  recovered or returned, so no kick is ever left untouched beyond the zone
- **6-1-7** — A free kick ends once a side has the ball, or once the ball is dead with
  nobody having it; from the moment the receivers secure it, a running play has begun. —
  `test:kickoffsChangePossessionAndOpenEveryRestartedPeriod`,
  `test:secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf`,
  `test:onsideRecoveryKeepsPossession`
- **6-2-3** — A receiving-team player may not run into the **free** kicker before he
  recovers his balance: five yards. This is Rule 6, so it governs a free kick and nothing
  else, and the article's own cross-reference sends a personal foul against that kicker to
  12-2-8-i. It is not 12-2-12, which is a different article protecting a different kicker
  on a kick from scrimmage. — not yet enforced and no issue carries it: the crude resolver
  draws a foul on the kicker on a punt and a place kick only, so nobody can run into a free
  kicker
- **6-2-4** — A kick that crosses a sideline before reaching a goal line, or that first hits
  the turf or a man in front of the landing zone, hands the receiving team its choice of
  three spots: the ball 25 yards on from where it was kicked, at the inbounds line; the spot
  where it left the field; or wherever it came down, but that one only when it is nearer
  than 25 yards on. A safety kick pays 30 rather than 25. —
  `test:aKickOutOfBoundsIsTwentyFiveYardsOn`,
  `test:aShortKickIsSpottedWhereItLiesWhenThatIsNearer`,
  `test:aShortOrOutOfBoundsKickIsGivenAway`; the safety kick's 30 is not modelled, because
  `Rules.advance` is a function of the situation and the outcome and neither says which
  kind of free kick this was

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
- **7-6-1** — The next snap comes from wherever the last down finished, moved only by an
  enforced penalty, or brought in to the inbounds line when the down ended outside it. —
  `test:secondHalfKickoffReturnedAfterAnInjuryRunoffEndsTheFirstHalf`

## Rule 8 — Forward pass

- **8-1-3** — A forward pass is *completed* when the offence catches it and *intercepted*
  when the defence does; the article names the two together and the catch is the same act
  either way. So an interception is a catch but it is not a completion, which is what
  decides whether a foul before it is inside 8-6-1-d. —
  `test:defensiveFoulBeforeADeepInterceptionIsEnforcedFromTheDeadBallSpot`
- **8-2-1** — A passer about to lose ground to the rush who throws a forward pass nowhere
  near any receiver who was eligible at the snap has grounded it, and the ball falling
  incomplete is not part of the definition. *Read in the 2026 edition, the only one the
  session that entered it could reach; that edition's own list of what it changed names
  6-1-3, 6-1-5, 6-1-6 and 19-2 and nothing in Rule 8 or in 4-7, so this is the 2025
  article. A reading in the 2025 book is still owed, and this note comes off when it is
  done.* — `test:groundingCostsTheDownAndTenYardsFromThePreviousSpot`,
  `test:groundingInsideTwoMinutesRunsTenSecondsOff`; drawn by the crude resolver as the
  illegal share of its throwaways (C3 #44)
- **8-2-1 Item 1** — Not grounding when the passer is, or has been, outside the pocket area
  and the ball comes down at or past the line of scrimmage extended, whoever could have
  caught it; he is outside it the moment any part of him or of the ball is. —
  **modelling**: the crude resolver places nobody, so it cannot know where the passer or the
  ball was. A throwaway is drawn as one this item allows against the passer's `awareness`
  and `underPressure`, and as grounding otherwise — `test:everyFoulIsCalled` drives that
  draw; the spatial engine measures it (M5)
- **8-2-1 Item 2** — Not grounding when a defender's contact took the pass off its line
  after the throwing motion had started toward a receiver, or knocked a pass thrown from
  outside the pocket down short of the line. — not modelled: the resolver has no contact
  on the throw
- **8-2-Penalty** — Loss of down and ten yards from the previous spot; loss of down at the
  spot of the throw instead when that spot is more than ten yards behind the previous spot
  or past half the distance to the goal; a safety when the passer, all of him and the ball,
  is in his own end zone as he throws. The clause sends the reader to 4-7 for what the act
  costs inside two minutes. — `test:groundingCostsTheDownAndTenYardsFromThePreviousSpot`;
  **modelling**: the resolver has no spot of the throw, so every grounding is walked off as
  the first clause, and where the ten yards would reach past half the distance the engine
  walks off half the distance — a stand-in for clause (b), which sends the ball to the spot
  of the pass when that spot is more than ten yards behind the previous spot or more than
  half the distance, and not 14-2-1, whose ceiling names grounding as one of its two
  exceptions —
  `test:groundingBackedUpIsCappedAtHalfTheDistanceAsAStandIn` (a pin); the
  spot-of-the-throw clause and the safety are not reached
- **8-2-1 Item 3** — A T-formation quarterback may stop the clock without fouling for
  intentional grounding if, the moment the ball reaches him, he starts one unbroken throwing
  motion and puts the ball straight into the ground. 3-42 makes that any player aligned a
  yard or less behind the snapper, so the article is wider than hands under centre. The pass
  is incomplete, so 4-4-f stops the clock and 4-3-2 holds it to the next snap. The article
  is about the throw and says nothing about the seconds before the snap: a clock running
  into a spike keeps running until the ball is snapped. —
  `test:spikeCostsItsOwnSecondAndStopsTheClock`,
  `test:spikeAtFiveSecondsIsFollowedByTheNextDown`
- **8-2-1 Item 4** — A passer who has held the ball for tactical reasons may not then throw
  it into the ground in front of him, pressure or no pressure. — not modelled: the resolver
  draws a spike as a called play and never as a late decision by a passer already holding
  the ball
- **8-3-1** — An ineligible player downfield on a pass: five yards from the previous spot. —
  `test:enforcementFamilies`
- **8-4-2**, **8-4-3** — What illegal contact *is*, inside the five-yard zone and beyond
  it, and both are written for a down the man who took the snap is still spending in the
  pocket with the ball. Inside the zone it is a chuck in a receiver's back, a chuck held
  on once he is past the point level with the defender, or a second chuck after the first
  was broken off; beyond it, it is a defender starting contact with a receiver trying to get
  away from him, or holding on to a receiver he has ridden out of the zone. Hands used to
  fend off contact a receiver is bringing are not it, and neither is incidental contact
  beyond the zone (8-4-4). —
  `test:illegalContactEndsWhenThePasserLeavesThePocket`; **modelling**: the engine draws
  one contact verdict per coverage matchup and does not model the acts separately, so
  which of these a flag was is not in the record
- **8-4-4** — Illegal contact: five yards and an automatic first down. The clause is the
  section's Penalty, printed after this article and covering 8-4-1 to 8-4-4. —
  `test:everyFoulIsCalled`
- **8-4-5** — An illegal cut block: a block below the waist on an eligible receiver split
  more than two yards outside his own tackle, wherever on the field it happens; or on one
  lined up tighter than that, once he is past the line, since up to the line he may be cut
  legally. Fifteen yards and an automatic first down. — not modelled: `Foul` has no case
  for it and no draw produces one
- **8-4-6** — Defensive holding: five yards and an automatic first down. —
  `test:defensiveHoldingAtTheThreeIsHalfTheDistance`
- **8-4-7** — The defence's coverage restrictions have an end, and the article gives them
  two. They stop as soon as the man who took the snap gives the pass up — he hands it off,
  pitches it, throws it in either direction, puts it on the ground, or is tackled — and
  from there a defender may push a receiver off and ward him away under 12-1-5. They stop
  a second way when the quarterback carries the ball out of the pocket, and this one is
  selective: illegal contact ends and the illegal cut block ends, while the restriction on
  defensive holding does not. The article closes with a third case, the punt formation:
  against a team showing punt (3-17-7) the acts that would be illegal contact are allowed,
  short of anything that is holding. —
  `test:illegalContactEndsWhenThePasserLeavesThePocket`,
  `test:defensiveHoldingSurvivesThePasserLeavingThePocket`; **modelling**: the scramble is
  the whole of what the engine knows about the pocket — on a down that ended as a pass
  nothing in the record says where the passer was — and the giving-up clause and the punt
  clause have nothing to switch off, because the coverage contact is drawn before the
  quarterback has decided anything and a punt draws none at all
- **8-5-1** — Interference of either kind needs a forward pass thrown from behind the
  line to exist at all, legal or not and whether or not it gets past the line: the foul is
  contact past the first yard downfield that spoils an eligible receiver's chance at the
  ball. The defence's restrictions run from the throw until the ball is touched and the
  offence's from the snap; contact nearer the line than that is holding instead. —
  `test:noInterferenceWithoutAThrow`, `test:interferenceIsOnTheTarget`
- **8-5-4** — A second way the offence draws interference, and the whole of what this
  article is: a block on a defender more than a yard past the line, either clearly before
  the throw or, with the ball in the air, near the man it is going to. An ineligible
  player downfield is 8-3-1's Note instead. Nothing here is about what interference costs
  or where it is enforced from — that is the section's Penalty below, and 8-6-1-b. — the
  block is not modelled as its own act; the offence's interference is drawn as 8-5-2's
  push-off on the target's matchup, which is `test:interferenceIsOnTheTarget`
- **8-5-Penalty** — What interference costs. The clause closes Rule 8 §5 and the book
  cites it this way. The defence's is a first down at the spot of the foul; where that
  spot is behind the defence's goal line it is first and goal at the 1 — or half the
  distance from the previous spot, when the previous spot was inside the 2. The
  offence's is ten yards from the previous spot — and since the clause takes no down, the
  down is replayed, which is our inference from it and not a sentence in it. —
  `test:spotFouls`, `test:interferenceInTheEndZoneSpotsAtTheOne`,
  `test:interferenceInTheEndZoneFromInsideTheTwo`, `test:offensiveInterference`
- **8-6-1** — Between the snap and the moment a forward pass from behind the line is over,
  a foul by either team is enforced from the previous spot. The catch is the boundary: with
  the ball in a receiver's hands the down has become a run, and the running rules govern
  what follows. The same sentence is Rule 14's, as **14-4-5**. It is the general rule and
  not the whole of it — the exceptions below are what govern interference and a personal
  foul. — `test:roughingOnAnIncompletion`
- **8-6-1-b** — Interference by the defence is enforced from the spot of the foul. —
  `test:interferenceDownfield`
- **8-6-1-d** — A personal or unsportsmanlike foul by the defence before a forward pass
  thrown from behind the line is *completed* is enforced from the dead-ball spot or the
  previous spot, whichever favours the offence; if the play scores, on the try. And if the
  passing team is fouled and then loses the ball after a completion, it keeps the ball and
  the foul comes off the previous spot. "Before a completion" reaches an interception,
  because an interception is not a completion (**8-1-3**) — so the choice of the two spots
  is the rule for a defensive personal foul on a play that ends in a pick, and the general
  sentence of 8-6-1 is not. The same exception is Rule 14's, as **14-4-5-d**. —
  `test:roughingOnACompletion`,
  `test:defensiveFoulBeforeAnInterceptionIsEnforcedFromThePreviousSpot`,
  `test:defensiveFoulBeforeADeepInterceptionIsEnforcedFromTheDeadBallSpot`
- **8-7-3 Item 1** — Whoever comes up with a fumble may run with it, whichever side he is
  on, and whether or not the ball has already touched the ground. Three downs are the
  exception — a try, a fourth down, and any down after the warning at two minutes. —
  `test:kickoffFumbledAndCarriedInIsTheKickersTouchdown` for the kicking team carrying in
  a fumbled kickoff; **modelling**: the crude resolver never fumbles a kick, and the
  fourth-down, two-minute and try exceptions are not modelled

## Rule 10 — Opportunity to catch a kick

- **10-2-1** — A fair catch is what a returner gets for a valid signal and then an
  unmolested take, on a scrimmage kick past the line or on a free kick, and only while the
  kick is still airborne. His team snaps where he caught it. —
  `test:fairCaughtKickoffStartsNoClock`, `test:puntHandsOver`
- **10-2-4** — After a fair catch the receiving team may ask for a fair catch kick instead
  of a snap. — not modelled: the engine has no fair catch kick

## Rule 11 — Scoring

- **11-1-2-a** — A touchdown is six. — `test:touchdown`
- **11-2-1** — A touchdown is scored when a runner carries the ball on, above or behind the
  plane of the opponents' goal line, whichever side he is on: the kicking team carrying in
  a fumbled kickoff scores as the offence does. —
  `test:kickoffFumbledAndCarriedInIsTheKickersTouchdown`
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
  point to the opponent. — not yet enforced and no issue carries it: the resolver ends
  every try as the offence's own success or failure, so the defence never has the ball
  on one
- **11-3-3** — Fouls on a try, and where the re-try is snapped from; half the distance on a
  try is measured from the other try spot. Its **Item 2** is a foul that kills the play
  before the snap, treated as it would be before a scrimmage play; **Item 3-a** repeats the
  try after a foul by the scoring team during a successful one; **Item 4-a** puts a foul by
  the defending team on the ensuing kickoff. — `test:falseStartOnTheKickMovesItBack`,
  `test:offsideOnTheConversionMovesItIn`, `test:falseStartOnATryMovesTheTry`,
  `test:anOffensiveFoulOnASuccessfulTryRepeatsIt`, `test:holdingOnASuccessfulTryRepeatsIt`,
  `test:aDefensiveFoulOnASuccessfulTryMovesTheFreeKick`; **Item 3-b** ends a try on a
  foul that carries a loss of down — unsuccessful, and not replayed — which a grounded
  two-point pass now is, with the kickoff from its ordinary spot because Item 3-c reaches
  only a foul after a change of possession —
  `test:groundedTryInsideTwoMinutesRunsNothingOff`. Nothing in the article exempts a try
  from the half-distance ceiling of 14-2-1;
  its interference exception applies that ceiling itself, in two places —
  `test:offsideOnATryFromTheSevenIsHalfTheDistance`
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
- **11-6-2-a**, **11-6-3** — A kickoff dead in the receivers' possession in their end zone
  is a touchback, and they snap next at their restart spot for a free kick. —
  `test:secondHalfKickoffAfterAnInjuryRunoffEndsTheFirstHalf`, `test:touchbackConsumesNoTime`;
  the spot is `Rules.kickoffTouchbackOwnYard`, a 2024 value until D1
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
- **12-2-12** — The kicker's protection on a kick from scrimmage, in two halves with a
  penalty apiece. Roughing the kicker (Item 1) is fifteen yards from the previous spot and
  an automatic first down, and the article marks it a personal foul. Running into him
  (Item 2) is five from the previous spot with no automatic first down, and the article
  marks it as not one. **That marking is what 14-2-3 turns on, not the section the foul is
  printed in** — so of these two, only roughing is carried to a succeeding spot. —
  `test:roughingOnAMissedFieldGoalIsAFirstDown`, `test:runningIntoTheKickerReplaysTheDown`,
  `test:runningIntoTheKickerOnAMadeFieldGoalIsDeclined`,
  `test:personalFoulsAreNamedByTheBook`
- **12-2-16** — Horse-collar tackle: fifteen and an automatic first down. —
  `test:everyFoulIsCalled`
- **12-3-1** — Unsportsmanlike conduct after the play: fifteen from the succeeding spot, and
  an automatic first down when it is the defence's. — `test:conductFoulAfterThePlay`

## Rule 14 — Penalty enforcement

- **14-2-1** — The half-distance ceiling. A distance penalty never carries the ball past
  the midpoint between the spot it is enforced from and the goal line the offending team
  defends; where the full walk-off would go beyond that midpoint, the ball is placed on the
  midpoint instead. The article states itself as a general rule that overrides every other
  enforcement of a distance penalty, general or specific, and names two exceptions only:
  intentional grounding (8-2-1) and a palpably unfair act (12-3-4). The measurement starts
  at whichever spot the foul is enforced from, the other try spot included (14-3-4-f), and
  nothing in 11-3-3 lifts the ceiling for a try — that article leans on the same
  half-distance twice inside its own interference exception. **The ceiling bites well short
  of a goal line**: five yards from the 7 and fifteen from the 20 are both more than half,
  and neither would have reached the goal line. —
  `test:halfTheDistanceFromTheEnforcementSpot`,
  `test:defensiveHoldingAtTheSevenIsHalfTheDistance`,
  `test:facemaskAtTheTwentyIsHalfTheDistance`,
  `test:falseStartAtTheOwnSevenIsHalfTheDistance`,
  `test:offsideOnATryFromTheSevenIsHalfTheDistance`,
  `test:roughingOnAMissedFieldGoalIsAFirstDown`,
  `test:facemaskByTheFormerOffenseOnAReturn`; **modelling**: the engine spots on whole
  yards and the article's midpoint often is not one, so the walk-off is rounded down and
  the ball is left on the nearer whole yard the ceiling still allows — the 4 from the 7,
  where the article's midpoint is the three and a half. The article says nothing about
  rounding
- **14-2-3** — A personal or unsportsmanlike foul during a down in which the opponent kicks
  a field goal or scores a safety is enforced on the free kick; on a touchdown it is
  enforced on the try, whether it came during the down, after the whistle or between downs;
  the offended team may instead take customary enforcement and give up the points. —
  `test:defensiveFoulOnATouchdown`, `test:roughingOnAMadeFieldGoalMovesTheFreeKick`,
  `test:aPersonalFoulDuringASafetyMovesTheFreeKick`, `test:aFoulDuringATouchdownGoesOnTheTry`,
  `test:anOrdinaryFoulOnAMadeKickIsDeclined`, `test:roughingOnAMadeFieldGoalMovesTheKickoff`;
  the option to give up the points is not modelled, since no caller would take it
- **14-2-4** — A personal or unsportsmanlike foul by a team whose opponent has the ball at
  the end of the down may be enforced from the dead-ball spot. —
  `test:facemaskByTheFormerOffenseOnAReturn`
- **14-3-4** — The spots a penalty can be enforced from: the previous spot, the spot of the
  foul, the spot of a backward pass or fumble, the dead-ball spot, the succeeding spot, the
  other try spot, and the spot of a change of possession. — `test:enforcementFamilies`
- **14-3-5** — The basic spot, which is the reference point the three-and-one method
  measures from. It applies to a foul during a running play, or during a backward pass or
  fumble, and to nothing else. For a foul during a run not followed by a change of
  possession it is the dead-ball spot (**14-3-5-a**); when the run is followed by a change
  of possession it is the spot where possession was lost (**14-3-5-b**); during a backward
  pass or fumble, the spot of the pass or the fumble. The basic spot is where the
  three-and-one method starts, not where it always ends: when it is behind the line of
  scrimmage, **14-3-6**'s exception takes a defensive foul back to the previous spot. —
  `test:facemaskAtTheEndOfARun`,
  `test:defensiveFoulOnARunThatEndsInAFumbleIsEnforcedFromTheSpotOfTheFumble`,
  `test:defensiveFoulOnAStripSackIsEnforcedFromThePreviousSpot`; the record carries the
  spot where possession was lost, `test:takeawaysCarryTheSpot`
- **14-3-6** — The three-and-one method. A foul during a run, a backward pass or a fumble is
  enforced from the basic spot when the defence fouls anywhere, or the offence fouls in
  advance of it; when the offence fouls behind the basic spot, from the spot of the foul.
  Exceptions: an offensive foul behind the line of scrimmage comes off the previous spot
  instead, and so does a defensive one whenever the basic spot is behind the line — behind
  or beyond it, the defence's foul comes off the previous spot all the same. The article
  carries three further offensive exceptions this entry does not state: the own end zone,
  the offence fouling beyond the line when the basic spot is behind it, and a foul in the
  defence's end zone before a touchdown. —
  `test:blockInTheBackDuringARun`, `test:blockInTheBackBehindTheLine`,
  `test:contactFoulOnALoss`, `test:holdingOnAGain`, `test:contactFoulOnAStripSack`,
  `test:defensiveFoulOnAStripSackIsEnforcedFromThePreviousSpot`
- **14-4-1** — Two items, split by when the flag flew. A flag that comes down before the
  ball is snapped (Item 1) walks off from the succeeding spot, and the same down is played
  again. One that comes down as it is snapped (Item 2) walks off from the previous spot
  instead, and the down is played over. Both items carry one proviso the entry left out: if
  enforcing the penalty itself produces a first down, it is a first down, and the down
  neither stays nor repeats. — `test:preSnapKillsThePlay`,
  `test:falseStartAtTheOwnThreeIsHalfTheDistance`
- **14-4-3** — When a **run** with a foul in it ends in a change of possession, the spot
  possession went is the basic spot and the three-and-one method applies: a defensive foul
  gives the ball back to the offence before enforcement (**14-4-3-a**); an offensive foul
  must be declined by the defence to keep the ball, unless it was a personal or
  unsportsmanlike foul (**14-4-3-b**), in which case the defence keeps the ball and the
  foul is enforced from the dead-ball spot. The three-and-one method is what applies, so
  **14-3-6**'s exception applies with it: possession lost behind the line puts a defensive
  foul back on the previous spot. — `test:facemaskByTheFormerOffenseOnAReturn`,
  `test:defensiveFoulOnARunThatEndsInAFumbleIsEnforcedFromTheSpotOfTheFumble`,
  `test:defensiveFoulOnAStripSackIsEnforcedFromThePreviousSpot`
- **14-4-5** — Until a forward pass from behind the line is over, a flag on either side
  comes off the previous spot, and the down turns into a running play only once somebody
  catches the ball. So the catch is never the basic spot for a foul that came before it.
  The same sentence is Rule 8's, as **8-6-1**. — `test:roughingOnAnIncompletion`
- **14-4-5-d** — The exception that governs the personal foul. A personal or
  unsportsmanlike foul by the defence before a forward pass thrown from behind the line is
  *completed* is walked off from the better of two spots for the offence — where it
  snapped, or where the ball was dead; and if the passing team is fouled and then loses it
  after a completion, it keeps the ball and the foul comes off the previous spot. An
  interception is not a completion (**8-1-3**), so a defensive personal foul on a play that
  ends in a pick is inside this exception: the offence takes the better of the two spots,
  which is the previous spot when the interceptor was dropped behind it and the dead-ball
  spot when he was dropped in front of it. The same exception is Rule 8's, as **8-6-1-d**.
  — `test:defensiveFoulBeforeAnInterceptionIsEnforcedFromThePreviousSpot`,
  `test:defensiveFoulBeforeADeepInterceptionIsEnforcedFromTheDeadBallSpot`; **modelling**:
  the record carries no time within a down, so a foul by the intercepting team on its own
  return is indistinguishable from one before the catch and is enforced as the latter, and
  a pass completed and *then* fumbled away is enforced from the fumble although this
  article gives the previous spot when the foul preceded the catch — the crude resolver
  reaches neither today,
  [#58](https://github.com/knissley/football-manager/issues/58)
- **14-4-6-b** — When the ball comes loose behind the line of scrimmage, every foul, by
  either side, is enforced from the previous spot; the offence's foul in its own end zone
  is a safety if the defence takes it there. This is the same answer 14-3-6's exception
  gives a defensive foul, reached by the article about the fumble rather than the article
  about the method. — `test:defensiveFoulOnAStripSackIsEnforcedFromThePreviousSpot`,
  `test:contactFoulOnAStripSack`
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
- **16-1-4-e**, **16-1-4-g**, **16-1-4-i** — Two-minute intermissions between periods and
  no halftime after the second; three timeouts per half; a fresh coin toss at the end of a
  fourth overtime period. 16-1-4-e gives the beginning of the **third** overtime period
  the first choice of 4-2-2's two privileges to the captain who lost the toss before
  overtime, so a third period is put back in play with a free kick, as is a fifth after
  the toss of 16-1-4-i; a half being two periods (16-1-4-e, f, h), the three timeouts are
  renewed at the third and the fifth. —
  `test:thirdPostseasonOvertimePeriodOpensWithAKickoff`,
  `test:tossLoserMayElectToKickOffAThirdPostseasonOvertimePeriod`,
  `test:postseasonOvertimeTimeoutsAreThreePerHalf`,
  `test:fifthPostseasonOvertimePeriodOpensWithAKickoff`,
  `test:aThirdPostseasonOvertimePeriodIsRestartedWithAKick`, `test:coinTosses`; the
  intermissions are not modelled, nor is the toss itself: the side that kicks off after
  one stands for the captain who lost it, and after a fourth overtime period that is the
  side with the ball, pinned by
  `test:fifthPostseasonOvertimePeriodKickerIsTheSideThatHadTheBall`. Past the fourth the
  pairing repeats — a seventh period opens as a third does — which is a reading rather
  than a sentence in the book, pinned by
  `test:postseasonOvertimeBeyondTheFourthPeriodRepeatsThePairing`
- **16-1-4-f** — The sides swap ends after the first extra period and after the third, and
  the article sends the reader to 4-2-3 for how: whose ball it is, the down, the ball and
  the line to gain all carry over. — `test:secondPostseasonOvertimePeriodCarriesOn`,
  `test:periodResumesWithKickoffAnswers`; the change of ends itself is not modelled, for
  the reason 4-2-3 gives
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
