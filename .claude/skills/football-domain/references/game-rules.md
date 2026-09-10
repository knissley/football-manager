# Game rules we model

**Rulebook: 2025 season.** Every rule below is a rule of that book, read in it. A 2026
book exists and has moved some of this again — CLAUDE.md pins the target at 2025, so a
2026 rule is out of scope here and reporting that describes one is not evidence about this
book. Where the code still carries an older value, it is listed under [what the code
carries today](#what-the-code-carries-today) with the issue that fixes it — the book is
the target, the tree is the state.

Defaults for the `Rules` object. All of these are configurable so variants can be
tested; these are the values a generated league starts with.

## How to read the citations

`[2025 · 6-1-5]` is Rule 6, Section 1, Article 5 of the 2025 rulebook; a fourth part is
the clause, so `[2025 · 4-7-1-b]` is that article's (b). No rulebook text is reproduced
here: the rules are in our own words and the number is how you find the original. Terms of
art are the exception, and have to be — a *free kick*, the *line to gain*, *half the
distance to the goal* have no synonyms worth having, so short phrases coincide with the
book's even where no sentence does.

Every rule statement below was checked against the 2025 book itself. A line that is not a
rule — a modelling convention, a calibration band, a fact about our engine — says which it
is instead and cites that. Anything still marked `(unverified: cite on next pass)` is a
line nobody has checked; grep for that phrase before trusting a number.

The tables carry a second half to the cite column: **what checks the row**.
`test:<function name>` names a test function in one of the packages' test targets, and
`row:<row id>` a calibration row in `Tools/simharness/Sources/simharness/Targets.swift`.
`InvariantsTraceabilityTests` in the FMSimulation test target fails if a name here does not
exist, so a row cannot claim a check it has not got. The rules that no table covers are
indexed by article number in `docs/reference/playing-rules.md`, and what must be true of a
game — including the rules the engine does not enforce yet — is `docs/invariants.md`.

## Field and structure

- The field is 360 feet by 160 feet, with goal lines 10 yards in from each end line: 100
  yards between goal lines and two 10-yard end zones. `[2025 · 1-1-1]`
- 11 players a side. Twelve in the formation is a foul before the snap and a foul on the
  snap. `[2025 · 5-1-1]`
- A series is four scrimmage downs to reach the line to gain. `[2025 · 3-8-2]`,
  `[2025 · 7-3-1]`
- The line to gain sits ten yards downfield of wherever the series began, **or on the goal
  line when that is closer** — which is what first and goal is. `[2025 · 3-8-3]`

## Game length

- Four 15-minute periods. A tie at the end of them goes to overtime under Rule 16.
  `[2025 · 4-1-1]`
- Halftime is 13 minutes; the other intermissions are at least two. `[2025 · 4-1-2]`,
  `[2025 · 4-1-3]`
- The two-minute warning stops the game without anyone asking: whichever down is under way
  when the clock runs past 2:00 finishes, and then the clock is dead. It belongs to the
  **second and fourth periods**, and to the periods Rule 16 times as them: the
  regular-season overtime period, which is played under the fourth quarter's timing rules,
  and in the postseason a second or a fourth overtime period, whose ends are timed as the
  halves' are — never a first or a third. `[2025 · 3-41]`, `[2025 · 16-1-3-e]`,
  `[2025 · 16-1-4-h]`
- Play clock: 40 seconds from the end of the previous play; 25 seconds from the whistle
  after an administrative stoppage — change of possession, charged timeout, two-minute
  warning, end of a period, penalty enforcement, a free kick. `[2025 · 4-6-1]`,
  `[2025 · 4-6-2]` A stoppage resets it: to 25 after a timeout, the warning, a period's end
  or a penalty enforcement; to 40 after a defensive act that conserves time; to 30 after a
  runoff. `[2025 · 4-6-3]` Letting it expire with the ball not snapped is delay of game,
  and the ball stays dead. `[2025 · 4-6-1]`, `[2025 · 4-6-4]`
- Three charged timeouts per team per half. They do not carry over. `[2025 · 4-5-1]`

## Clock stoppage

This is where accuracy matters most. Any of these kills the clock as the down closes, and
the second column says what starts it again. `[2025 · 4-4]`, `[2025 · 4-3]`

| Event | Restarts on | Cite · checked by |
| --- | --- | --- |
| Incomplete pass | Snap | `4-4-f`, `4-3-2` · `test:spikeStopsTheClock` |
| Ball dead on or behind a goal line | Snap | `4-4-d` · `test:touchbackConsumesNoTime` |
| Free kick or fair catch kick down | Legal touching in the field of play — not on a touchback, a kick the kicking team recovers before any other legal touching, or a fair catch; the down over, the clock waits for the snap | `4-4-a`, `4-3-1-a` to `4-3-1-c`, `4-3-2` · `test:returnedKickoffAdvancesTheClock`, `test:fairCaughtKickoffStartsNoClock`, `test:kickoffRecoveredByTheKickersStartsNoClock` |
| Charged timeout | Snap | `4-4-j`, `4-3-2` · `test:timeoutsAreSpentAndVisible` |
| **Change of possession** | Snap | `4-4-i`, `4-3-2-a-1` · `test:changeOfPossessionStops`, `test:turnoverOnDownsStopsTheClock`, `test:puntReturnedAndTackledStopsTheClock` |
| Foul | As though the flag had never flown — except on the snap after the two-minute warning of the first half, inside the last five minutes of the second half, or after an offensive foul that stops the clock before the snap anywhere in the fourth period or regular-season overtime. The first two follow the halves Rule 16 makes of postseason overtime; the third names its periods, and a first, second or third postseason overtime period is not among them by its own words — whether 16-1-4-h carries it into a fourth outside five minutes the book does not settle, and the engine's reading that it does not is pinned by `test:offensiveFoulInAFourthPostseasonOvertimePeriodOutsideFiveMinutes` | `4-4-e`, `4-3-2-e-1` to `4-3-2-e-3`, `16-1-3-e`, `16-1-4-h` · `test:falseStartInTheThirdQuarterCostsNoTime`, `test:offensiveFoulInTheFourthQuarterStartsTheClockOnTheSnap`, `test:offensiveFoulInOvertimeStartsTheClockOnTheSnap`, `test:offensiveFoulInAFirstPostseasonOvertimePeriodRestartsTheClockOnTheReady` |
| Two-minute warning | Snap — in the second and fourth periods, in regular-season overtime, and in a second or fourth postseason overtime period | `4-4-h`, `3-41`, `16-1-3-e`, `16-1-4-h` · `test:twoMinuteWarningStopsAtTwoMinutes`, `test:twoMinuteWarningStopsAtTwoMinutesOfOvertime`, `test:secondPostseasonOvertimePeriodHasTheFirstHalfsWarning`, `test:firstPostseasonOvertimePeriodHasNoWarning` |
| Runner out of bounds | **Ready for play** — except that it waits for the snap once possession has changed, in the first half's closing two minutes, and in the second half's closing five; overtime carries the window of the half Rule 16 times it as | `4-4-c`, `4-3-2-a`, `16-1-3-e`, `16-1-4-h` · `test:outOfBoundsEarly`, `test:outOfBoundsLate`, `test:outOfBoundsInRegularSeasonOvertime`, `test:outOfBoundsInPostseasonOvertime` |
| After a 10-second runoff | Ready for play | `4-3-2-g` · `test:falseStartInsideTwoMinutesCostsTenSeconds` |
| Play clock expired | As any foul before the snap — but the flag flies when the play clock runs out, so a running game clock has lost the whole play clock before it: forty after a play, twenty-five from the whistle after a change of possession | `4-6-1`, `4-6-2`, `4-6-4` · `test:delayOfGameWhenThePlayClockExpires`, `test:delayOfGameAfterAChangeOfPossessionIsAgainstATwentyFiveSecondClock` |
| Defensive act that conserves time in the last 40 seconds of a half | The half ends — unless the defence has a timeout left or the offence would rather play on, in which case as after any defensive foul inside two minutes | `4-7-3` · `test:defensiveFoulInTheLastFortySecondsEndsTheHalfAtTheOffensesElection`, `test:defensiveFoulInTheLastFortySecondsWhenTheOffenseWouldRatherPlayOn`, `test:defensiveFoulInTheLastFortySecondsWithADefensiveTimeoutLeft` |
| Injury timeout after the two-minute warning | Snap, when the injured player's team is charged a team timeout. An excess timeout against the team in possession that stopped a running clock carries a ten-second runoff at the defence's choice and then the ready; declined, the snap. Before the warning, as if it had not occurred | `4-5-4-a`, `4-3-2`, `4-5-4-b`, `4-5-4 Note 1`, `4-5-4 Note 3`, `4-5-3` · `test:injuryTimeoutAfterTheWarningIsCharged`, `test:excessInjuryTimeoutAfterTheWarningCarriesTheRunoff`, `test:injuryRunoffDeclinedByATrailingDefense` |
| During the Try | The Try is untimed | `4-3-2-h`, `11-3-1` · `test:touchdownAsTheSecondQuarterExpires` |
| First down gained | Does not stop the clock | not in `4-4` · `test:firstDownDoesNotStop` |

The out-of-bounds rule is the one most often modeled wrong, and it's exactly the rule
that governs whether a two-minute drill works.

Live-play duration of roughly 4–7 seconds is a modelling convention, not a rule; the rest
of the interval between snaps is the offense's tempo choice against the play clock — and
the play clock in force is a rule the engine counts, so a delay of game is that clock
expiring rather than a rate drawn beside it.

## The ten-second runoff

The clock penalty that makes the end of a half a rules problem rather than an arithmetic
one. In our own words:

- Inside the final two minutes of either half, neither side may buy time with any of six
  acts: a flag thrown between downs by either side that kills a running clock; intentional
  grounding; an illegal forward pass; a backward pass thrown out of bounds; a spike or a
  throw-away in the field of play once a down is over, a touchdown excepted; and an illegal
  bat or kick that puts the ball out of bounds. Five yards, or more if some other penalty
  is bigger. `[2025 · 4-7-1]`
- **When the offence does one of them with the clock running, ten seconds come off**, the
  play clock goes back to 30, and the game clock restarts at the ready-for-play signal
  rather than at the snap. `[2025 · 4-7-1]` Item 1
- The offence may use a charged timeout instead of the runoff, and then the clock starts
  on the snap. `[2025 · 4-7-1]` Item 1
- **The defence may always decline the runoff and keep the yardage. Declining the yardage
  declines the runoff with it** — two decisions, not one, and a model that offers only the
  second gets the end of a half wrong. `[2025 · 4-7-1]` Item 1
- An illegal substitution after the two-minute warning, while the ball is dead and the
  clock running, is five yards **and** a runoff. `[2025 · 4-7-2]`
- The same act by the defence is not a runoff: the play clock resets to 40 and the clock
  starts on the ready signal unless the offence wants the snap. There is never a runoff
  against the defence. `[2025 · 4-7-1]` Item 2, `[2025 · 4-5-4]` Note 9
- A half can end on a runoff. `[2025 · 4-5-4]` Note 4
- **In the last forty seconds of either half the defence cannot buy the end of the half
  with a foul either**: a defensive act that conserves time with the clock running ends
  the half, unless the defence has a timeout left or the offence would rather play on —
  a leading offence takes the whistle, a level or trailing one plays on. The same goes
  for an excess timeout for an injured defensive player. `[2025 · 4-7-3]`
- A replay reversal or a nullified foul after the two-minute warning that leaves the clock
  where a correct ruling would not have stopped it also runs ten seconds off; neither team
  may decline that one, but either may spend a timeout to stop it. `[2025 · 4-7-4]` Not
  modelled: there is no replay system, and `test:noRunoffFollowsAReplay` pins the
  exclusion.
- An excess timeout for injury against the team in possession — after the two-minute
  warning, when its team has no timeout left to be charged — carries a runoff at the
  defence's choice, and the clock then starts on the ready with the play clock at 30.
  `[2025 · 4-5-4]` Note 3

## Scoring

| Play | Points | Cite · checked by |
| --- | --- | --- |
| Touchdown | 6 | `[2025 · 11-1-2-a]` · `test:touchdown` |
| Field goal | 3 | `[2025 · 11-1-2-b]` · `test:fieldGoal` |
| Safety | 2 | `[2025 · 11-1-2-c]` · `test:safetyPaysTheDefence` |
| Try by kick | 1 | `[2025 · 11-1-2-d]` · `test:extraPointIsOnePoint` |
| Try by pass or run | 2 | `[2025 · 11-1-2-d]` · `test:twoPointIsTwoPoints` |

A field goal has to be place-kicked or drop-kicked, struck at or behind the line, and it
must reach the goal without grazing the turf or one of the kicker's own men.
`[2025 · 11-4-1]`

Field goal distance = yards to goal line + 10 (end zone) + 7 (snap depth). Ball on the
opponent's 30 is a 47-yard attempt. Get this formula right once, in one place. The snap
depth is a modelling constant, not a rule.

**A miss is a field-position event.** When a missed kick crosses the line and the
receivers never touch it, the ball comes back to where it was struck — or to their own 20,
if it was struck from nearer than that. `[2025 · 11-4-2]`

**After a safety, the team that was scored upon puts the ball in play with a free kick
from its own 20**, and that kick alone may be a punt as well as a drop kick or place kick.
`[2025 · 11-5-2]`, `[2025 · 6-1-1-b]`

## The try

- After a touchdown the scoring team gets one untimed scrimmage down. The game clock does
  not run during it. `[2025 · 11-3-1]`
- The snap is 15 yards from the defence's goal line for a kick, two yards from it for a
  pass or run — the offence's choice, changeable after a penalty or a timeout.
  `[2025 · 11-3-1]`
- **Either team can score on a try.** A try that ends in a touchdown is two points whoever
  scores it; what would be a safety on a try is one point to the opponent.
  `[2025 · 11-3-2-b]`, `[2025 · 11-3-2-c]`
- **A touchdown on the last play of a period still gets its try.** It is waived only
  during sudden-death overtime, or when time in the fourth period has expired and a
  successful try could not affect the outcome. `[2025 · 4-8-2-c]`
- **The period is extended for that try.** A period may be extended by one untimed down
  when something in the down that expired it calls for one, and the try is that down: it
  belongs to the period the touchdown ended, at 0:00, not to the next one.
  `[2025 · 4-8-2]`, `[2025 · 4-8-2-c]`
- After the try, the team that was on defence for it receives the kickoff.
  `[2025 · 11-3-4]` The same is true after a successful field goal. `[2025 · 11-4-6]`

## Overtime

**Regular season** — a single 10-minute period, after a break of three minutes at most.
`[2025 · 16-1-3]`

- **Each side is owed a turn with the ball**, whatever the first turn produced. The
  article names one exception: a team that kicks off and then scores a safety against the
  receivers' opening drive has won on the spot. `[2025 · 16-1-3-a]`
- Once both have had that opportunity, whoever has more points has won. `[2025 · 16-1-3-b]`
- If the side that had it first came away with nothing, or the two are still level once
  both have had their turn, **the next points of any kind win it**. `[2025 · 16-1-3-c]`
- A defence that takes the ball away has thereby had its possession — possession is gained
  by catching, intercepting or recovering a loose ball — so a first-possession turnover
  puts the game into sudden death, and a defensive touchdown on the first possession ends
  it under (b). `[2025 · 16-1-5-b]`
- **The period is never extended**, not even for a second team that has not possessed or a
  possession still running. Level at the end is a tie. `[2025 · 16-1-3-d]`
- Two timeouts each; fourth-quarter timing rules otherwise apply — the two-minute warning,
  the five-minute out-of-bounds window and the runoff among them. `[2025 · 16-1-3-e]`

**Postseason** — 15-minute periods, as many as it takes. `[2025 · 16-1-4]`

- The possession rules are the same. `[2025 · 16-1-4-a]` to `[2025 · 16-1-4-c]`
- Level at the end of a period, or a second team's initial possession unfinished, means
  another period. `[2025 · 16-1-4-d]`
- Three timeouts per half, two-minute intermissions between periods, and a fresh coin toss
  after the fourth. A half is two periods: the captain who lost the toss before overtime
  has the first choice of 4-2-2's privileges at the start of the **third** period, so a
  third period — and a fifth, after the new toss — is put back in play with a free kick,
  and the three timeouts are renewed with it. `[2025 · 16-1-4-e]`, `[2025 · 16-1-4-g]`,
  `[2025 · 16-1-4-i]`
- **Timing pairs the periods into halves.** At the end of a second overtime period the
  timing rules are the first half's, and at the end of a fourth the fourth period's — so
  the two-minute warning, the out-of-bounds window and the runoff belong to a second and a
  fourth overtime period, and a first or a third has none of them. `[2025 · 16-1-4-h]`
  What happens past a fourth is not in the book; the engine reads the new toss there as
  restarting the pairing, and says so as a modelling reading.

On kicking plays the opportunity to possess is defined for you: a kickoff is the receiving
team's opportunity, and if the kicking team legally recovers it the receiving team is
still deemed to have had it. `[2025 · 16-1-5-c]` So after a field goal on the opening
possession, a kickoff the kicking team recovers ends the game `[2025 · A.R. 16.2]`, and
one returned for a touchdown ends it too, with no try `[2025 · A.R. 16.4]`; the return
touchdown on the *opening* kickoff, by contrast, gets its try, because the kicking team is
still owed its turn. `[2025 · A.R. 16.1]`

## Penalties

Common ones, with what the book says they cost.

| Penalty | Yards | Notes | Cite · checked by |
| --- | --- | --- | --- |
| False start | 5 | Enforced before the snap | `7-4-2` · `test:falseStartAtTheOwnThreeIsHalfTheDistance`, `row:penalty.falseStart` |
| Encroachment | 5 | Pre-snap, defense | `7-4-3` · `test:everyFoulIsCalled` |
| Offside | 5 | The offense may get a free play | `7-4-5` · `test:offsideOnTheConversionMovesItIn`, `row:penalty.offside` |
| Delay of game | 5 | Play clock expired, and the other listed delays; the engine produces the first kind only | `4-6` · `test:delayOfGameWhenThePlayClockExpires`, `row:penalty.delayOfGame` |
| Illegal formation (offense) | 5 | | `7-5-1` · `row:penalty.illegalFormation` |
| Illegal motion | 5 | | `7-4-8` · `test:everyFoulIsCalled` |
| Holding (offense) | 10 | Replay the down | `12-1-3-c` · `test:holdingOnAGain`, `row:penalty.offensiveHolding` |
| Illegal use of hands (offense) | 10 | | `12-1-3-a` · `test:everyFoulIsCalled` |
| Illegal block in the back | 10 | | `12-1-3-b` · `test:blockInTheBackDuringARun` |
| Holding (defense) | 5 | Automatic first down | `8-4-6`, `12-1-6` · `test:defensiveHoldingAtTheThreeIsHalfTheDistance`, `row:penalty.defensiveHolding` |
| Illegal contact | 5 | Automatic first down | `8-4-4` · `test:everyFoulIsCalled` |
| Pass interference (defense) | Spot foul | First down at the spot of the foul. In the end zone it is first down at the 1, or half the distance to the goal when the previous spot was inside the 2 | `8-5-4` · `test:interferenceInTheEndZoneSpotsAtTheOne`, `test:interferenceInTheEndZoneFromInsideTheTwo`, `row:penalty.defensivePassInterference` |
| Pass interference (offense) | 10 from the previous spot | Replay the down | `8-5-4` · `test:offensiveInterference` |
| Roughing the passer | 15 | Automatic first down | `12-2-11` · `test:roughingOnACompletion`, `row:penalty.roughingThePasser` |
| Unnecessary roughness | 15 | Automatic first down if by the defense | `12-2-8` · `row:penalty.unnecessaryRoughness` |
| Facemask | 15 | Automatic first down if by the defense | `12-2-15` · `test:facemaskAtTheEndOfARun` |

All cites are the 2025 book.

**Accept/decline:** simulate the play outcome and the penalty outcome, then let the
non-penalized team take whichever is better. Offsetting penalties replay the down.

**Where a foul is enforced from** is its own rule, and the next section carries it.

The 10–14 penalties per game the harness aims at is a calibration band, not a rule, and
its season and source belong to issue #2.

### Where a foul is enforced from

- The spots a penalty can be enforced from are the previous spot (where the ball was last
  put in play), the spot of the foul, the spot of a backward pass or fumble, the dead-ball
  spot, the succeeding spot (where the next down will start), the other try spot, and the
  spot of a change of possession. `[2025 · 14-3-4]`
- **Half the distance to the goal is measured from the spot of enforcement**, whichever
  spot that is. `[2025 · 14-2-1]`
- A foul before the snap is enforced from the succeeding spot and the down stays; a foul
  at the snap from the previous spot, and the down is repeated. `[2025 · 14-4-1]`
- **The basic spot.** A run with no change of possession in it takes the dead-ball spot;
  a run that ends in one takes the spot where possession went; a backward pass or a fumble
  takes the spot of the pass or the fumble. `[2025 · 14-3-5]`
- **The three-and-one method.** A foul during a run, a backward pass or a fumble is
  enforced from the basic spot when the defence fouls anywhere, or the offence fouls in
  advance of it; when the offence fouls behind the basic spot, from the spot of the foul.
  Exceptions: the offence's fouls behind the line of scrimmage are enforced from the
  previous spot, and so are the defence's when the basic spot is behind the line.
  `[2025 · 14-3-6]`
- When a run with a foul in it is followed by a change of possession: a defensive foul
  gives the ball back to the offence before enforcement; an offensive foul must be
  declined by the defence to keep the ball, unless it was a personal or unsportsmanlike
  foul, in which case the defence keeps the ball and the foul is enforced from the
  dead-ball spot. `[2025 · 14-4-3]`
- A personal or unsportsmanlike foul by a team whose opponent has the ball at the end of
  the down may be enforced from the dead-ball spot. `[2025 · 14-2-4]`
- **A foul during a score.** A personal or unsportsmanlike foul during a down in which
  the opponent kicks a field goal or scores a safety is enforced on the free kick; during
  a touchdown, any foul is enforced on the try; the offended team may instead take the
  penalty with customary enforcement and give up the points. `[2025 · 14-2-3]` The
  engine does not enforce on the try or the kickoff yet (#48, C9): the score stands and
  the flag is recorded declined.
- **The passing game.** Between the snap and the moment a forward pass from behind the
  line is over, a foul by either team is enforced from the previous spot; the catch is the
  boundary, and with the ball in a receiver's hands the down has become a run.
  `[2025 · 8-6-1]` Interference by the defence is enforced from the spot of the foul; in
  the end zone it is first down at the 1, or half the distance from the previous spot when
  that was inside the 2. `[2025 · 8-6-1-b]` A personal foul by the defence before a
  completion is enforced from the dead-ball spot or the previous spot, whichever favours
  the offence; if the play scores, on the try. `[2025 · 8-6-1-d]`
- Unsportsmanlike conduct after the play is fifteen yards from the succeeding spot, and an
  automatic first down when it is the defence's. `[2025 · 12-3-1]`
- Horse-collar tackle: fifteen yards and an automatic first down. `[2025 · 12-2-16]`
  Impermissible use of the helmet: fifteen, an automatic first down if by the defence.
  `[2025 · 12-2-10]` Blindside block: fifteen. `[2025 · 12-2-7]` Illegal use of hands by
  the offence: ten. `[2025 · 12-1-3-a]` An ineligible player downfield on a pass: five
  from the previous spot. `[2025 · 8-3-1]`

## Kickoffs

The dynamic kickoff, made permanent for 2025. The two units line up five yards apart and
nobody moves until the ball comes down.

- **The kick is from the kicking team's 35** — its 20 for a safety kick — and the other
  ten of the kicking team line up on the **receiving team's 40**. `[2025 · 6-1-2-a]`,
  `[2025 · 6-1-2-b]`
- The receiving team's restraining line is its own 35, and the **setup zone** is the five
  yards between its 35 and its 30. `[2025 · 6-1-2-c]`, `[2025 · 6-1-2-d]`
- The **landing zone** is the receiving team's 20 out to its goal line. `[2025 · 6-1-2-e]`
- **At least nine receiving players must be in the setup zone**, at least six of them with
  a foot on the restraining line — seven if the team puts more than nine in the zone. That
  leaves at most two returners deep. `[2025 · 6-1-3-b]`
- **Three of them at most may stand off that line, and only one to a lane**: the sidelines
  and the inbounds lines cut the zone into three lanes across the field, and no lane may
  hold two of the three. This is the 2025 modification to the formation.
  `[2025 · 6-1-3-b]` Item 2
- The kicking team's ten put a front foot on their restraining line and keep both feet
  down, and nobody but the kicker and the men deep may move until the kick has come down —
  in the end zone, or in the landing zone — or been touched there. `[2025 · 6-1-3-a]`,
  `[2025 · 6-1-3-c]`
- **A kick that comes down in the landing zone is live and gets returned.** No fair catch
  is available on it, and the reason is the ground: a free kick may be fair caught only
  while it is still in the air, and this one has already landed. `[2025 · 6-1-4]`,
  `[2025 · 10-2-1]`
- **Short, or out of bounds:** a kick that crosses a sideline before reaching a goal line,
  or that first hits the turf or a man in front of the landing zone, hands the receiving
  team its choice of three spots — the ball **25 yards on from where it was kicked**, at
  the inbounds line on that side of the field, which is its own 40 from a kick at the 35;
  or the spot where it left the field; or wherever it came down, but that one only when it
  is nearer than 25 yards on. A safety kick pays 30 rather than 25. `[2025 · 6-2-4]`
- **Landing zone, then the end zone:** the ball is live; downed there or out of bounds
  behind the goal line, it is a touchback at the **20**. `[2025 · 6-1-5-a]`
- **Into the end zone without touching down in the landing zone first** — downed there,
  out of bounds behind the goal line, or off the goal post — it is a touchback at the
  **35**. This is the 2025 change; it was the 30 in 2024. `[2025 · 6-1-5]`
- A kickoff or safety kick that reaches the end zone and stays inbounds is still alive:
  the receiving team either brings it out or kills it where it is. `[2025 · 6-1-5]`
- Once the kick has reached the end zone or the landing zone — landing there, or touched
  there by a receiving-team player — the kicking team may take it, and a legal recovery is
  its ball where the play died. `[2025 · 6-1-4-c]`, `[2025 · 6-1-4-d]`

The two touchback spots are the point of the rule: a kicker who will not put the ball in
the landing zone hands over the 35, so leg strength is a decision rather than a formality.

## Onside kicks

- **Only a trailing team may attempt one, and it must declare it** to the Referee before
  the play clock starts; the Referee then tells the receiving team. There is no surprise
  onside kick. `[2025 · 6-1-1-c]`, `[2025 · 6-1-6]`
- **It may be declared at any point in the game.** Fourth quarter only was the 2024 rule.
  `[2025 · 6-1-6]`
- The kicking team's restraining line is still its **35** (its 20 on a safety kick), with
  the rest of the unit's front feet on that line and no more than five players either side
  of the ball. `[2025 · 6-1-6-b]`, `[2025 · 6-1-6-c]`
- The kicking team may recover only once the ball has **got to the receiving team's
  restraining line**, ten yards on from its own, or a receiver has put a hand on it first.
  `[2025 · 6-1-6-e]`, `[2025 · 6-1-6-g]`
- The receiving team puts eight or nine players between its restraining line and 15 yards
  behind it, the onside kick setup zone. A kick that goes untouched beyond that zone is
  dead and the receiving team's, and costs the kicking team 15 yards.
  `[2025 · 6-1-6-h]`, `[2025 · 6-1-6-k]`

**Not this book:** reporting that puts the onside kick at the 34, or lets a team that is
*not* trailing declare one, is describing later rule-making. In the 2025 book the
restraining line is the 35 and only a trailing team may declare. Rule 6 has three 2025
modifications and only three — the setup-zone alignment, the touchback spot, and
declaring at any point when trailing.

## Punts

- A punt that reaches the end zone untouched by the receivers is a touchback, and the
  receiving team snaps at its own 20. `[2025 · 11-6-2-c]`, `[2025 · 11-6-3]`
- A fair catch is what a returner gets for a valid signal and then an unmolested take. It
  is available on a scrimmage kick past the line — a field goal attempt is one of those —
  and on a free kick, but either way only while the kick is still airborne: once it has
  hit the ground it cannot be fair caught. His team snaps where he caught it, or may ask
  for a fair catch kick instead. `[2025 · 10-2-1]`, `[2025 · 10-2-4]`
- A ball downed inside the 10 is a significant field-position win and the AI should value
  it. Modelling, not a rule.
- Blocks and muffs are low-probability branches worth modeling — they're memorable and
  their absence is noticeable over a long career.

## Changes since 2024

The book's own list of what changed for 2025, with what it touches here.

| Rule | What changed | Touches |
| --- | --- | --- |
| `6` | The 2024 form of the kickoff is made permanent | The kicking game — #46 |
| `6-1-3` | Where the receiving team stands on a kickoff or a safety kick, inside its setup zone: three men at most off the restraining line, and only one to a lane across the field | #46 |
| `6-1-5` | **Touchback spot moves to the 35** when the kick reaches the end zone without touching down in the landing zone first — downed there, out of bounds behind the goal line, or off the goal post | `Rules.kickoffTouchbackOwnYard` — #41, #46 |
| `6-1-6` | Where the kicking team stands for an onside kick, **and a trailing team may now call for one in any quarter** | `PlayCaller.kicksOnside` — #41, #46 |
| `15-9` | Replay assist may advise the on-field crew on more objective aspects of a play | Officiating; not modelled |
| `16-1-3` | **Regular-season overtime gives both teams a possession** whatever the first one produced, within one 10-minute period | `GameState`, `Rules` — #15, and the wave 1 review for the kickoff cases |

The landing-zone touchback (the 20) did not move, and neither did the onside kick's
restraining line: it is still the 35.

## What the code carries today

The gap between this doc and the tree, as of the September 2026 audit. Each line is
somebody's issue; none of them are decided questions. The first three were read out of the
tree while this doc was written; the rest are the audit's findings, taken on its word.

- `Rules.kickoffTouchbackOwnYard` is the 35 and `Rules.rulebookSeason` is 2025, so the
  defaults are one book. `Rules.swift`.
- The onside declaration is `Rules.mayDeclareOnsideKick` — any period, trailing — and the
  simulator asks it before it asks the caller, so no caller can declare one the book does
  not allow. Whether a coach *wants* one is still the `PlayCaller` extension's default,
  inherited by every caller. `Rules.swift`, `GameSimulator.swift`, `PlayCaller.swift`.

The dynamic kickoff is in the engine as far as the *aiming points* go and no further.
`Rules` carries the landing zone, the touchback at the 35 and 6-2-4's twenty-five yards;
the resolver calls one of two kicks — through the end zone, or into the zone to be
returned — and reads the spot the kick is taken from, so a distance penalty changes the
kick. What is absent is everything about *lining up*: no setup zone, no restraining lines,
no alignment fouls, and therefore no second touchback spot, since that one needs a kick to
come down in the landing zone and then reach the end zone.

## Injured reserve and game-day rules

Roster rules rather than playing rules; they are in the league's bylaws, not the rulebook,
and the money side of them is in [`salary-cap.md`](salary-cap.md).

- A player placed on IR misses a minimum number of games; teams have a limited number
  of return-from-IR designations per season.
- 53 on the active roster, 48 active on game day.
- Practice squad players can be elevated a limited number of times per season before
  they must be signed to the active roster.

*None of the three carries a rule number because none of them is in the playing rules
(unverified: cite on next pass).* They live in the constitution and bylaws — the 2025
amendments to Article XVII, Section 17.16 are the return-from-IR designations above — and
those want a reference of their own.
