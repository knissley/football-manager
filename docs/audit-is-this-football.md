# Audit: is this football?

**Status: built** — this is a record of an audit of code that exists, not a design doc.
Every finding and every number in it is measured. S1 through S8 are fixed, and so are
S9 through S13 and S15 as of wave 1 of the backlog; S14, the completion-percentage row,
is the one still open. The backlog tracker (#1) is the live state of each; the table at
the end is a snapshot.

A deliberate pass over the engine asking one question — *does this behave like the sport?*
— rather than *do the units work?* Separate from the end-of-M1 systems inventory, which
asks whether designed systems are wired in. This one assumes they are and asks whether
what comes out is a football game.

S1 through S8 are that pass, in severity order, and every number in them is from
`simharness --games 400 --seed 7`, whose output now carries the rows that produced them.
S9 through S15 were added by the September 2026 external audit and are appended after S8,
in the backlog's order rather than severity order; their numbers come from the issue that
closes each unless the text says they were measured here.

**Nothing below is fixed unless its heading says so**, and
[Where this leaves the engine](#where-this-leaves-the-engine) carries the status of all
fifteen. The live state of each is the backlog in
[#1](https://github.com/knissley/football-manager/issues/1).

## Why the audit found so much

The calibration table measures the passing and running game — yards, completion rate,
sack rate, third-down rate — and **almost nothing about a game of football**. There was no
row for where drives start, how they end, what fraction of points come from kicks, or what
a final score looks like. The engine was tuned against the rows that existed, and
everything the rows did not cover drifted unchecked.

Every finding below is visible in one page of harness output. Nobody had printed that
page.

## S1 — The scoreboard does not play football — **fixed**

`Rules.advance(from:outcome:)` switches on `PlayEnding` alone and never looks at
`PlayKind`. A try is therefore not modelled as a try:

- **A made extra point scores 3 points**, and is recorded as a `.fieldGoal`.
- **A successful two-point conversion scores 6 points**, and is recorded as a
  `.touchdown`.
- **The two-point try is snapped from the 15**, not the two. `Rules.twoPointSnapYard = 2`
  is defined and read by nothing, so a conversion needs fifteen yards. Across 800
  team-games: 44 attempts, **zero successes**.

The evidence is on the scoreboard. Summing scores at their correct values gives 19.3
points per team-game; the engine's own total is 23.0. The 3.7-point gap is exactly
1.8 extra points × 2 points too many. And the most common finals are 24-21, 24-12, 30-24,
21-18, 30-21 and 18-15 — every one a multiple of three, because a touchdown with the kick
is worth nine and a field goal is worth three.

**The `points 20.0–26.0` calibration row is a false pass.** Corrected, the engine scores
19.3 and is under target. Every tuning decision made to keep that row green was made
against a broken number.

**Fixed.** `Rules.advance` now asks what kind of play it was before deciding what it was
worth, and the two-point decision is made before the situation is built so the try is
snapped from the two. The same root cause was behind the kickoff touchback spot in S2,
which is fixed with it. Scores now look like the sport's: 20-10, 24-20, 23-20, 24-17.

## S2 — Field position is a dead variable — **fixed**

Field position is one of the two or three things a football game is *about*. Here it
barely moves.

- **94.6% of drives start in the offence's own half** (real: 75–80%). Average start is the
  own 24 (real: own 28–29).
- **Every kickoff is a touchback, 100% of the time.** No returns, no squibs, and no onside
  kick — so a trailing team can never get the ball back after scoring, which removes a
  whole phase of endgame football.
- **Kickoff touchbacks use the punt spot.** `Advancement` routes both through
  `puntTouchbackSpot`, the own 20. A kickoff touchback is the 30 under current rules (the
  25 before 2024), so every possession after a score starts five to ten yards too deep.
  (Fixed with S1 — same root cause.)
- **No punt returns.** A punt is a fair catch or a touchback. Net punting reads 44.5 yards
  against a real 41–42 — flattering, because nothing is ever returned.
- **No fumbles at all**, and an interception is spotted where it was caught with no return,
  so a pick six is arithmetically impossible.

Turnovers end 8.2% of drives against a real 11–12%, and the short field that makes a
turnover worth more than its count does not exist.

**Fixed.** The kicking game is a phase now rather than a way of ending a drive:

- `Rules.advance` gained an `advanceKick` branch beside `advanceTry`, for the same reason
  — a kick is its own rules problem and asking only how the play *ended* cannot tell a
  returned punt from a fourth-down stop.
- Kickoffs are returned or not depending on the kicker's leg and the weather; touchbacks
  run about 62%. Punts are fair caught, downed, run out of bounds or returned, and net
  punting fell from a flattering 44.5 to a realistic 40.4 now that returns come off it.
- **Onside kicks exist**, so a trailing team can get the ball back. About one in nine is
  recovered, and the decision to try one belongs to the caller.
- **Fumbles exist**, in `Fumbles`, driven by `carrying` against `hitPower` — ratings that
  nothing had ever read. Strip sacks come loose at five times the rate of a hit on a
  runner who saw it coming. Fumbles lost run 0.6 per team-game against a real 0.5–0.8, and
  turnovers overall 1.4 against 1.1–1.6.
- **Interceptions are returned**, so a pick six is possible. It was not merely rare
  before: the spot was clamped one yard short of the only value that scores.

Touchdowns the offence did not score now run 0.15 per team-game — 0.08 from interception
returns, 0.04 from fumbles, 0.02 from punt returns, 0.01 from kickoffs — against a real
figure near 0.18 that also includes the blocked kicks this engine still does not model.

What remains: **90.2% of drives still start in the offence's own half** against a real
75–82%, down from 95.6%. Average start is the own 30, which is right. The distribution is
still too tight, and the rest of it is the fourth-down conservatism in S4 and the blocked
kicks in S6 rather than anything left in the return game.

## S3 — One personnel grouping, one defensive package, all game — **fixed**

Every snap of every game is `11` personnel against `base` defence. `PersonnelGroup` and
`DefensivePackage` are complete, tested `FMCore` types that the engine never sets: nothing
in `FMSimulation` writes `Situation.offensePersonnel` or `.defensePackage`.

- On third and fifteen the defence has four defensive backs. **Nickel — the most-played
  defence in the modern game — never appears**, nor dime, goal-line or prevent.
- `DefensiveCall` carries a `package` the resolver never reads. Of its six dimensions
  three are read (`coverage`, `rush`, `runFit`) and three ignored (`frontAlignment`,
  `package`, `disguised`). `OffensiveCall.usedMotion` is ignored too.
- The kicking units field **eight men, not eleven**.
- `DepthChart.unmannedPositions`, written to report a group with nobody left to play it,
  is called by nothing. A depleted group silently plays a man short.

**Fixed.** Substitution happens in the order the sport does it: the offence picks a play,
sends out the grouping that runs it — which is public information — and the defence
answers what it sees. Both land on the situation the snap is recorded with, so the stream
can now be asked what a team runs from twelve personnel against nickel.

The slot layout became a function of the grouping rather than a table. Slots stay stable
and the *positions* filling them vary, which is what lets the rest of the engine go on
talking about "the receivers" and "the blockers" while the personnel underneath changes.
Note what the old fixed defensive layout actually was: two edges, two tackles, **two**
linebackers and **three** corners. That is nickel. The engine played nickel on every snap
of every game and called it base.

It is a real matchup rather than a label. An extra tight end is an extra blocker; an empty
set has five men running routes and nobody helping the line. Corners cover receivers now,
where the old fixed list put whoever sat in slot 17 on the number one — a linebacker, in a
base defence. And the run is a count: a defender nobody can block is a free hitter, a
blocker with nobody left to take is a double team. On first and ten it is worth **5.0
yards a carry with an even count against 3.4 when the offence is outnumbered**.

Usage lands where the sport does: 11 personnel 69%, 12 at 13%, 21 and 22 around 4% each;
nickel 54%, base 30%, dime 12%. The defence deliberately does *not* match personnel every
time — it stays in its base front against eleven personnel about a quarter of the time,
betting on the run, because a defence that always matches is one nobody can ever catch
out.

Two smaller things fell out. `RotationProfile` had said all along that the third
linebacker plays "a little under half the time, about a third base and two thirds nickel"
— a rotation curve written for a substitution system that did not exist, so that
linebacker had never played a snap. And `Player.secondaryPositions` was generated for
every player and read by nothing; it is now the fallback when a package asks for a body a
depleted group cannot supply, which is what stops a team silently fielding ten men.

The kicking units field eleven rather than eight. Every position a team carries now takes
a snap, and the coverage suite's register of unreachable positions is empty.

## S4 — Fourth down and the endgame are too tame — **fixed**

- **Drives end on downs 1.5% of the time**; real is 5–6%. `BaselineCaller` punts or kicks
  in nearly every fourth-down situation, so the most-discussed decision in the modern game
  barely occurs.
- Two-point tries happen 0.1 times per team-game and have never succeeded (see S1).
- **9.8 drives per team-game** against a real 11.3–11.7.

**Fixed.** `fourthDown` took any kick inside the maximum *before* asking whether to go, so
a fifty-five yarder from the opponent's thirty-eight beat a fourth-and-one attempt, and
going for it at all required fourth and three or less in a six-yard strip of the field.
It is a chart now — distance first, then field position and the scoreboard — and a long
kick is an endgame option rather than a routine one. Fourth-and-one attempts run 70%
against a real two-thirds; drives end on downs 4.4% of the time against a real 5–6%.

The two-point chart gained the deficits where the second point changes what you need next
(down two, five, ten) and the leads where it makes a one-score game unanswerable. And a
conversion is no longer an ordinary four-yard route that happens to start closer: from the
two there is no grass behind the defence, so it is a one-yard throw into a contested end
zone. Attempts run 0.19 per team-game and convert at 48%, against a real 0.22 and 48%.

### What chasing the drive count actually found

The drive shortfall turned out not to be a fourth-down problem at all. Plays per game,
first downs per game, third-down rate and yards per carry were all correct; the difference
was that the same first downs were packed into fewer, longer drives — series taking 2.18
plays against a real 1.99.

Raising offensive efficiency made it *worse*, which is the tell: a more reliable offence
has fewer three-and-outs and therefore fewer drives. Real football has both a higher yards
per play **and** more three-and-outs, which is only possible with a wider distribution.

Measuring the dropback the way the carry rows measure a carry found it immediately:
**forty-yard pass plays were 0.0% of dropbacks, against a real 1.5–3%.** Two causes, both
structural rather than a wrong constant:

- **Route depth had no variance at all.** A `mediumPass` was ten yards, always. Completions
  piled into the ten-to-fourteen band and nothing could reach forty. A concept has a
  depth; a route run against a particular coverage does not.
- **The only path to a long gain was breaking three tackles in a row** at nine percent
  each — a one-in-fifteen-hundred event. A long completion in the sport comes from a blown
  coverage or a receiver faster than the man on him, which is an independent draw, not the
  tail of three coin flips.

With both fixed the dropback distribution lands in full — incompletions, ten-plus,
twenty-plus and forty-plus — and yards after the catch rose from about three to a realistic
five, with `elusiveness` finally deciding some of it. Drives went from 9.6 to 10.3 per
team-game and three-and-outs from 17.8% to 18.9%.

Both are still short of the target band (10.5–12.0 and 20–27%), along with plays per drive
at 6.1 and first downs at 18.3. All four are the same remaining fact and they are close;
the rest of it is variance the crude resolver does not have and the spatial engine will.

## S5 — The kicking curve is wrong in the middle — **fixed**

| distance | engine | real |
| --- | --- | --- |
| 0–29 | 99.0% | ~98% |
| 30–39 | 88.6% | ~91% |
| 40–49 | **69.4%** | ~82% |
| 50–55 | 60.1% | ~62% |

The ends land and the middle sags by thirteen points. The extra point runs through the
same curve as a 32-yard field goal, which is why it is made 85% of the time against a real
94–96%.

**Fixed.** The curve is two segments centred on an average leg rather than one line from
twenty-five, and a try carries a small bonus over a field goal of the same length — it is
kicked from the middle of the field against a rush nobody means. Now 93.1% / 83.0% /
64.3% by bucket, against a real 91 / 82 / 66.

Nothing about a kickoff depends on the kicker: the outcome is a constant, so leg strength
is irrelevant on the one play it most obviously matters.

## S6 — 21 of 33 fouls never occur — **fixed**

Never produced: encroachment, illegal formation, illegal motion, illegal shift, illegal
substitution, illegal use of hands, illegal block in the back, blindside block, chop
block, tripping, ineligible receiver downfield, illegal man downfield, **offensive pass
interference**, horse-collar, illegal use of the helmet, low block, **roughing the
kicker**, running into the kicker, illegal touching, unsportsmanlike conduct, taunting.

Special teams draw no flags at all: `Penalties.preSnap` runs only on run and pass
families, so there is no false start on a field goal and no offside on a punt.

**Fixed. All thirty-three are called now**, and the shape of the gap is worth naming:
every one of those fouls already had its yardage, its side and its automatic-first-down
rule settled in `FMCore`. The rules layer was complete; the engine reached twelve of it.

The families that were missing, and where they now come from:

- **Procedural offence** — illegal formation, motion, shift and substitution, drawn off
  discipline and tempo. This is also what finally reads `OffensiveCall.usedMotion`, a
  field the resolver had never looked at: shifting people before the snap is how you find
  out what the defence is in, and it is also how you get flagged.
- **Blocking** — a beaten blocker holds, or gets his hands outside, or gets his feet
  wrong. Only the first of those had ever been thrown.
- **Offensive pass interference**, drawn from the same moment as the defensive kind: the
  separation was real but it was made with a hand in the chest.
- **Downfield blocking** — a block in the back, a blindside block, a low block, on runs
  that reach space and on punt returns. This is what brings a return back, and without it
  a return could not be wiped out.
- **Ineligible man downfield**, on screens and play-action, which is when linemen release.
- **Kicker protection** — running into him is five, roughing him is fifteen and a first
  down, and the difference between them is the rule.
- **Illegal touching**, when a cover man gets to a punt before the returner does.
- **Conduct** — and this one needed a rules capability that did not exist. A dead-ball
  foul is neither a pre-snap foul (which cancels the snap) nor a live-ball one (which the
  other team may decline in favour of the play): the play *stands* and the yardage is
  walked off from where it ended. `Rules.enforce` now has that path.

Two structural fixes came with it. **A pre-snap flag no longer cancels a try or a
kickoff** — the rules loop used to consume the pending state on any play, including one
that never happened, so a false start on a field goal simply erased the kick, which is why
those two were excluded from flags entirely. And `Penalties` now picks its offender from
the actual `Lineup` rather than the stale static slot lists, so the man charged is one who
was on the field.

Penalties run 12.3 per game against a real 12.8, with a distribution that matches the
sport's rather than twelve fouls carrying all of it.

**And it cost something, which is the honest part.** A realistic penalty load is a real
tax on an offence: third-down conversion fell to 35.9 and yards per carry to 3.9–4.0, both
at or just under their floors on two seeds. Those bands were set when the engine threw ten
fouls a game and had never called offensive interference, illegal formation or a hold in
the back. Combined with S3 giving the defence real sub packages, third down got harder
twice over. Both rows are the first item for the engine-wide retune rather than something
to paper over here.

## S7 — Calibration runs in conditions no game is played in — **fixed**

The harness passes no stadium and no weather, so every calibration game is at "Neutral
Field" with crowd noise 50 and clear skies. **Home-field advantage and weather are
mechanisms with no evidence behind them** — they have never been measured, because the
measurement has never included a home field or a forecast.

**Fixed, and it was worse than the finding said.** There was no weather *generator* at
all: `WeatherState` and `Climate` had existed since the world was first generated and
nothing had ever produced one. `WeatherGenerator` now builds a day from the stadium's
climate, the week and the seed — colder and wetter as the season turns, snow late in cold
cities, still and seventy under a roof — and the harness plays each game at the home
team's real ground.

Measuring it immediately showed the second half of the problem: **only the kicking game
read the weather**, so a game in driving snow threw and caught the ball exactly like a
game in a dome, and the first run that included weather at all found scoring *higher* in
the rain than in the dry. `Conditions` now turns the forecast into three scalars — how
hard the ball is to handle, how much accuracy a throw loses (scaled by how far it has to
travel, because that is how wind behaves), and how many yards a kick gains or loses — and
those reach catching, ball security, throwing and kicking. Scoring now falls a couple of
points in the wet, which is the sport's number.

`Stadium.altitudeFeet` was generated for every ground and read by nothing; a kick a mile up
now carries.

**Home-field advantage is the honest part.** It measures about half a point and a hair
over 50%, against a real two points and 56% — and that gap should not be closed by turning
up the crowd. Most of real home advantage is travel, rest and short weeks, none of which
can exist before there is a schedule to travel on (M3). What this engine models is the
crowd, and the crowd alone is worth roughly what the research attributes to it. So the
harness now targets the **mechanism** — a road offence commits 1.15–1.35× the pre-snap
fouls of a home one — and prints the aggregate without a target and with a note saying
why.

Two things had to be corrected to get there. The noise coefficient was tuned against a
neutral field with nobody in it, and against real crowds it made road teams commit
*twice* the pre-snap fouls rather than about a fifth more. And a second mechanism was
missing: a silent count costs a road line a fraction of a beat, which is why hostile
grounds show up in sack rates and not only in false starts.

Worth recording separately: **the harness had been counting home and road pre-snap fouls
for a long time and never printing them.** Computed and dropped — the same bug shape as the
sack credit, the scheme fit and the run-play holding. The measurement that would have
caught all of this existed; its answer was thrown away.

## The retune that followed S1

Correcting the try dropped scoring from a false 23.0 to a true 19.3, so the table had to
be re-established against honest numbers. Three things came out of it.

**One row was never an engine problem at all.** "Yards gained on first down" had sat at 4.2
against a 4.6–5.8 target, and the metric was counting every kickoff and every extra point
as a zero-yard first-down snap — about six of them per team-game against twenty-four real
ones. Filtered to plays from scrimmage the same engine reads 5.1. The row was measuring
the wrong thing, which is the audit's own thesis arriving on schedule.

**Yards per carry was genuinely 15% high, and the mean said nothing about why.** The new
carry-shape rows located it exactly: the stuff rate (19.8%), the short carries (44.3%) and
the 20+ tail (3.2%) were all correct, and the whole excess sat in ten-to-nineteen-yard
runs, at 19.4% against a real 11%. The cause was a big-hole bonus that fired on ~19% of
carries — the same 19% — and reliably paid ten yards. Scaling it down killed the 20+ tail
with it, because the same clause was producing that too. What works is making it rarer and
larger: a hole that opens gets the back to the second level, and beating the man waiting
there is what makes it a long run, which the tackle sequence already decides. All four
carry-shape rows now land, at 4.3 a carry.

**What remains is structural, and should not be tuned away.** Scoring sits at 19.8 against
a 20.0 floor and a real 22.5. Real football takes roughly 1.7 points per team-game from
touchdowns the offence did not score — pick sixes, fumble returns, kick and punt returns —
and this engine produces exactly zero of them, because S2 is unfixed. It also plays 10.1
drives per team-game against a real 11.4, and the missing possessions are mostly the
missing fumbles. The honest position is that **the points row cannot legitimately close
until S2 lands**, and closing it by making the offence more efficient would be the exact
failure this audit exists to name. (S2 has since landed and the row closed on its own:
points read 22.5 at `--games 400 --seed 7`.)

## What this changes about how we calibrate

The calibration table needs rows for the game and not only the play: where drives start,
how they end, the split of points by source, kick accuracy by distance, and the shape of a
final score. Those rows are now in the harness under **Is this football?** and should move
into [`match-engine.md`](match-engine.md#calibration) as targets rather than observations.


## S8 — The simulation is not deterministic — **fixed**

Found while finishing S3, and **pre-existing**: it reproduces on the engine as it was
before any of this audit's work.

Two calls to `simulate` with the same setup and seed, in the same process, on the same
thread, intermittently produce different games. Roughly one full-suite run in three or
four goes red on either `The same seed resolves identically` or `The same seed produces
the same injuries`.

This is the most expensive rule in the project to have broken.
[ADR-0003](adr/0003-deterministic-seeded-simulation.md) makes replay depend on it, and the
tuple `(initialState, seed, sliderConfig, decisionLog)` is how most games are *stored* —
so this does not merely fail a test, it means a saved season cannot be trusted to replay
as the season that was played.

What the divergence looks like: identical players in identical slots, identical outcome,
and one recorded `separation` value differing by exactly one — 158 against 159. A
one-in-the-last-place difference in a `Double`, truncated by `Int(...)` into an integer
that differs, which later flips a threshold and changes the game. In the injury case the
two runs agree for five injuries and then one run has a sixth at play 158.

Ruled out so far:

- **Generation.** Rosters, colleges and depth charts from the same seed compare equal.
- **Forbidden primitives.** No `Int.random`, `Double.random`, `.shuffled()`,
  `.randomElement()`, `UUID()`, `Date()` or `SystemRandomNumberGenerator` anywhere in
  `FMCore`, `FMGeneration` or `FMSimulation`.
- **Shared mutable state.** No `static var`, no reference types, no `@unchecked Sendable`
  in any of the three modules' sources.
- **Concurrency in the engine.** No `async`, `Task`, `DispatchQueue` or task groups.
- **Unordered iteration.** `Ratings` is a flat array with a bitset, `DepthChart.positions`
  sorts by raw value, `Form.table` sorts its keys.
- **Test parallelism.** It fails with `--no-parallel` too, so it is not tests interfering.

**Found and fixed.** `SchemeFit.effectiveOverall` summed its rating weights **while
iterating a dictionary**. Floating-point addition is not associative, so the sum's last
bits depended on Swift's hash seed — randomised per process — and the result was divided
and rounded to a whole overall point. A player near a rounding boundary came out a point
better in one process and a point worse in the next; his scheme fit moved with him, that
fed his effective rating, and the same seed produced a different season.

The clue that cracked it was magnitude. The divergence showed a recorded `separation` of
158 against 159 — not a last-place difference in a `Double` but a whole unit, which needed
a rating to move by about a quarter of a point. `schemeFit` is scaled by 0.35 in
`PlayContext.effective`, so a `schemeFit` off by one is worth 0.35: the right size.
Everything before that had been chasing a one-in-the-last-place difference that could
never have been large enough.

Proved by controlled experiment rather than argument. With the fix, three golden seeds
match across eight separate processes. With the bug put back, three of those eight
processes disagree.

Two things this says about how the guarantee was being tested, now written into
[ADR-0003](adr/0003-deterministic-seeded-simulation.md):

- **"Never let iteration order reach the output" includes arithmetic.** The rule reads as
  though it is about which element you pick. It is also about the order you add doubles
  in.
- **Every determinism test we had was blind to it**, because they all compared two runs
  inside one process — which share a hash seed, so they agree with each other and disagree
  with yesterday. A determinism test has to be a checked-in constant, and its checksum must
  not use `Hasher`, which is per-process seeded as well. `GoldenSeedTests` and
  `GoldenWorldTests` are that check.

A sweep of the rest of `FMCore`, `FMGeneration` and `FMSimulation` found no other place
where an unordered collection's iteration order reaches an output: the generators' loops
are over arrays or explicitly sorted, and `SchemeFit.combined` accumulates each key in
array order. This was the only one.

## S9 — There is no overtime in the regular season — **fixed**

`GameSimulator.State.checkForEnd` — the state machine in `GameState.swift` — ends any
tied regulation game when ties are allowed (`Rules.mayEndInATie`, called from there), so
overtime exists only in the postseason and
`Rules.regularSeasonOvertimeLength` is dead. The harness prints **25 ties in 400 games, at
seed 7 and at seed 11 alike**, with no target beside the row; the real rate is about 0.4%.

A test asserts the bug: `A tied game ends level in the regular season and goes on in the
postseason`, in `GameSimulatorTests.swift`, is green and wrong.

The tie counts above are measured, at `--games 400` on seeds 7 and 11. The rest
reproduces as [A1 · #15](https://github.com/knissley/football-manager/issues/15)
describes, which is the issue that closed it.

**Fixed by A1 (#15), in the wave 1 PR.** A level game always plays overtime: one
ten-minute period in the regular season, each side owed an opportunity to possess and
sudden death once both have had one, a tie only if still level at the end of it
(2025 rulebook, 16-1-3); fifteen-minute periods until decided in the postseason
(16-1-4). The `ties` test is rewritten to assert that. The wave 1 review added the
kickoff cases: a kickoff that scores, or that the kicking team recovers, ends the
receivers' opportunity, so after an opening-possession field goal either one ends the
game (16-1-5-c, A.R. 16.2, A.R. 16.4), and each side has two timeouts in a
regular-season overtime period (16-1-3-e). The engine's overtime scenarios are in
`RulesConformanceTests`, eleven of them, one per clause. The two-minute warning in
overtime, which the fourth quarter's timing (16-1-3-e) implies and `Rules.isEndOfHalf`
did not give, landed with [A11 · #74](https://github.com/knissley/football-manager/issues/74).

## S10 — A touchdown at the end of a half gets no try — **fixed**

The half restart in `GameSimulator.State.checkForEnd` sets `pendingTry = false` along
with the fresh timeouts, so a touchdown as the second quarter expires never gets its
extra point. The end
of regulation checks the score *before* the try exists, so a team down seven that scores on
the final play loses by one having never been allowed to kick.

Reproduces as the issue describes: a scripted resolver, final 6–7 in each case. Closed by
[A2 · #31](https://github.com/knissley/football-manager/issues/31).

**Fixed by A2 (#31), in the wave 1 PR.** The try is an untimed down of the period the
touchdown ended — the period is extended for it (2025 rulebook, 4-8-2) — so nothing ends
while one is owed. It is waived only where 4-8-2-c says: in sudden-death overtime once the
touchdown has decided it, and at the end of the game when no successful try could change
who won. The end-of-regulation matrix (down seven, six, eight, two, one, level, up one)
and the second- and first-quarter cases are scenarios in `RulesConformanceTests`, each
asserting the try's period and clock.

## S11 — The team that scored the safety kicks off — **fixed**

`Rules.advance` returns `possessionChanged: true` for a safety at `Advancement.swift:158`.
Under the engine's convention the possessing team kicks, so the team that just *scored*
free-kicks from its own 20 and the team that conceded receives at its 30 — both halves of
it backwards. What the issue asks for is `possessionChanged: false`: the team scored upon
keeps the ball to free-kick with, and the kick flips possession as every kickoff does.

Two tests cover it and neither catches it: `AdvancementTests.safety` asserts
`possessionChanged` with a comment warning against exactly this outcome, and
`GameSimulatorTests.safetyPaysTheDefence` checks only the points.

Reproduces as the issue describes. Closed by
[A3 · #16](https://github.com/knissley/football-manager/issues/16).

**Fixed by A3 (#16), in the wave 1 PR.** The safety branch of `Rules.advance` no longer
flips possession: the team scored upon keeps the ball to free-kick from its own 20
(2025 rulebook, 11-5-2, 6-1-1-b) and the kick changes hands as every kickoff does. Both
tests are rewritten to assert the kicker and the spot.

## S12 — The clock runs through a change of possession, and there is no runoff — **fixed**

`Rules.clockBehavior(after:)` reads only the ending. A fourth-down stop and a returned punt
both end `.tackled`, which `GameClock.swift:39` treats as a live ball, so the team taking
over burns its huddle off the game clock. Reproduced in the issue: **37 seconds elapse
after a turnover on downs, against 6 for the play itself.**

The ten-second runoff does not exist at all. Both
[`match-engine.md`](match-engine.md) and
[ADR-0012](adr/0012-play-resolver-seam.md) name it as a rule the shared layer has to get
right — it is the example both use — and nothing implements it. A pre-snap foul also
charges a phantom 6 seconds of play time, because `runClock` substitutes 6 for a zero
`clockRunoff`.

Closed by [A4 · #17](https://github.com/knissley/football-manager/issues/17) and
[A5 · #32](https://github.com/knissley/football-manager/issues/32).

**Fixed by A4 (#17), A5 (#32) and A10 (#56), in the wave 1 PR.** Any change of
possession stops the clock until the snap, whatever the ending (2025 rulebook, 4-4-i,
4-3-2-a-1); a kickoff return costs its seconds and a touchback none (4-3-1); the
two-minute warning is a stoppage between downs, so a down under way at 2:00 finishes
(3-41). A flag before the snap charges no play time, and the clock then restarts as
4-3-2-e says: as though the flag had never flown, except on the snap after the
two-minute warning of the first half, inside the last five minutes of the second half,
or after an offensive foul that stops the clock before the snap anywhere in the fourth
period or regular-season overtime (`Rules.clockStartsOnTheSnapAfterFoul`, from the wave
1 review, which found the fourth-quarter case asserted the wrong way). The kick's
clock does not start on a touchback, on a kick the kicking team recovers first, or on a
fair catch (4-3-1-a to 4-3-1-c). The ten-second runoff exists: `Rules.tenSecondRunoff`,
with the window in `Rules.carriesRunoff` (4-7-1 Item 1, 4-7-2; regular-season overtime
included, 16-1-3-e), the offence's timeout and the defence's decline as `PlayCaller`
decisions with baseline defaults, and a half that can end on it (4-5-4 Note 4). The
postseason overtime clock cases (16-1-4-h) landed with the overtime two-minute warning
in [A11 · #74](https://github.com/knissley/football-manager/issues/74): every clock case
reads `Rules.periodTiming`, which pairs postseason overtime periods into halves. Twenty
clock scenarios in `RulesConformanceTests` cover the three, and nine more the overtime
clock. The four timing rules the invariants list found unenforced landed with
[A12 · #76](https://github.com/knissley/football-manager/issues/76): the play clock is
counted in the rules layer — forty from the end of a play, twenty-five from the whistle
after an administrative stoppage, thirty after a runoff (4-6-1, 4-6-2, 4-6-3) — and a
delay of game is that clock expiring rather than a flat rate, with the clock in force
written into every play's record; a defensive act that conserves time in the last forty
seconds ends the half at the offence's election (4-7-3); and an injury timeout after the
two-minute warning is charged as a team timeout or, with none left, is an excess timeout
whose runoff is the defence's to take (4-5-4 Note 3). Eight more scenarios cover them,
and every election a side makes about the clock is in the play's decision log. Article
4, the runoff after a replay reversal, stays a labelled exclusion until there is a
replay system to reverse anything.

## S13 — Live-ball fouls are enforced from the previous spot — **fixed**

`Rules.enforcedAdvancement` measures every foul from `situation.ballOn`, the previous spot.
A facemask at the end of a 20-yard run therefore offers the offence 15 yards from the old
line against a 20-yard gain, so the engine declines it; the sport gives 35 yards and a
first down. Roughing the passer on a completion loses the completion. Horse collar and
illegal use of the helmet, added in `35e12ce`, inherit the same path.

Decision 119's claim that every foul has real enforcement is therefore false for the whole
contact family, and `defensivePassInterference` smuggles its spot through the `yards` field
because there is nowhere else to put it.

This is S6's sequel. S6 made all thirty-three fouls *occur*; whether the yardage that
follows is football is a separate question, and for the contact fouls the answer is no.
Reproduces as the issue describes. Closed by
[A6 · #18](https://github.com/knissley/football-manager/issues/18).

**Fixed by A6 (#18), in the wave 1 PR.** Every foul carries its enforcement family
(`Foul.enforcement`: the previous spot, the spot of the foul, or the succeeding spot,
2025 rulebook 14-3-4), a spot foul carries its measured spot in
`PenaltyRecord.enforcementSpot` rather than in `yards`, and `Rules.enforce` is one
routine that computes the accepted branch in the frame of the team that snaps next. The
contact family is walked off from the dead-ball spot with the gain counting (14-3-5-a,
14-3-6, 8-6-1-d), so a facemask at the end of a twenty-yard run is thirty-five yards and
a first down; interference in the end zone is the 1 (8-6-1-b); half the distance is
measured from the enforcement spot (14-2-1). The case table is in
`PenaltyEnforcementTests`, and the harness prints how often the contact family is
declined. A live-ball contact foul by the scorer wipes its own score and is enforced
from the previous spot, which stands in for the spot of the foul the record does not
carry (14-3-6; the wave 1 review). The record also lacks the spot where possession was
lost, and cannot express a kicking-team kickoff touchdown —
[B7 · #58](https://github.com/knissley/football-manager/issues/58). A foul by the team
scored upon, or a dead-ball conduct foul by the scorer, is still recorded declined with
the score standing, until [C9 · #48](https://github.com/knissley/football-manager/issues/48)
enforces it on the try or the kickoff (14-2-3) and re-tries after a live-ball foul on a
try.

## S14 — The completion-percentage row is a false pass — **fixed**

`PlayEnding` cannot express a completed pass: a catch for a loss ends `.tackled`, exactly
like a run. The harness therefore counts a completion as `yards > 0 || touchdown`, so every
ball caught for no gain or a loss is scored an incompletion.

Measured at `--games 400`: the row reads **62.8 against a 61.0–68.0 band on seed 7 and
64.5 on seed 11, marked `ok` both times**. The rate the catch decisions actually describe
is **68.4**, from the issue below. The row is not imprecise, it is several points low and
green — the same shape as S1's points row, and the reason that row was believed for as
long as it was.

`Outcome.pointsScored` is the other half of it: the field is on every record and nothing
ever assigns it, so it is always zero, the scoreboard cannot be a sum over the stream, and
anything that wants the score has to re-run the rules. Checked here rather than taken from
the issue: across every package, test suite and tool the only occurrences of
`pointsScored` are its declaration, its default of `0`, and the assignment of that
default.

Closed by [B2 · #22](https://github.com/knissley/football-manager/issues/22): a
completion is a fact in the record (`Outcome.passResult`) and the row reads it, and the
points are written onto the play by the game so the scoreboard is the stream summed. The
rows still on the older inference — yards per completion's denominator and the catch
leaders — are [E2 · #42](https://github.com/knissley/football-manager/issues/42)'s.

## S15 — A flag on a try is recorded and never enforced — **fixed**

`GameSimulator.step` calls `moveToTrySpot` on every step while a try is pending, so the
enforcement spot from a pre-snap flag is overwritten with the standard 15 or 2 before the
replay. In 40 games: **13 flags before a try, and 13 tries re-snapped from the standard
spot.**

This is the far side of S6's second structural fix. S6 stopped a pre-snap flag cancelling
the try, which is what allowed flags on tries at all; nothing then applies them. A false
start on an extra point should make it a 37-yard kick, and does not.

Reproduces as the issue describes. Closed by
[A7 · #19](https://github.com/knissley/football-manager/issues/19).

**Fixed by A7 (#19), in the wave 1 PR.** The try is chosen once, when it is first
owed, and a replayed try keeps its enforced spot; the other try option's yard line
follows the same walk-off (2025 rulebook, 11-3-3), and a defensive foul that leaves the
ball inside the two puts the two-point question to the caller again. A false start on an
extra point is now a 37-yard kick from the 20, and `TryTests` asserts it.

## Where this leaves the engine

**Fifteen findings: fifteen fixed.** S1 through S8 are the original pass and are fixed.
S9 through S15 were added by the September 2026 external audit; the seven rules-layer
findings among them were fixed by wave 1 of the backlog, and S14 — the harness row, not
the engine — by wave 2's record track. The backlog in
[#1](https://github.com/knissley/football-manager/issues/1) is the live state of each; this
table is a snapshot. The wave 1 fixes deferred three gaps to their own issues:
[A11 · #74](https://github.com/knissley/football-manager/issues/74) (the overtime
two-minute warning and postseason overtime timing), since landed, as has
[A12 · #76](https://github.com/knissley/football-manager/issues/76) (the play clock, the
last forty seconds and the injury timeout, which the invariants list had found unenforced);
[B7 · #58](https://github.com/knissley/football-manager/issues/58) (the spot where
possession was lost, and a kicking-team kickoff touchdown, neither in the record) and
[C9 · #48](https://github.com/knissley/football-manager/issues/48) (the re-try after a
foul on a try), both open.

| finding | status | closed by |
| --- | --- | --- |
| S1 The scoreboard does not play football | fixed | — |
| S2 Field position is a dead variable | fixed | — |
| S3 One personnel grouping, one defensive package, all game | fixed | — |
| S4 Fourth down and the endgame are too tame | fixed | — |
| S5 The kicking curve is wrong in the middle | fixed | — |
| S6 21 of 33 fouls never occur | fixed | — |
| S7 Calibration runs in conditions no game is played in | fixed | — |
| S8 The simulation is not deterministic | fixed | — |
| S9 There is no overtime in the regular season | fixed | [A1 · #15](https://github.com/knissley/football-manager/issues/15) |
| S10 A touchdown at the end of a half gets no try | fixed | [A2 · #31](https://github.com/knissley/football-manager/issues/31) |
| S11 The team that scored the safety kicks off | fixed | [A3 · #16](https://github.com/knissley/football-manager/issues/16) |
| S12 The clock runs through a change of possession, and there is no runoff | fixed | [A4 · #17](https://github.com/knissley/football-manager/issues/17), [A5 · #32](https://github.com/knissley/football-manager/issues/32), [A10 · #56](https://github.com/knissley/football-manager/issues/56) |
| S13 Live-ball fouls are enforced from the previous spot | fixed | [A6 · #18](https://github.com/knissley/football-manager/issues/18) |
| S14 The completion-percentage row is a false pass | fixed | [B2 · #22](https://github.com/knissley/football-manager/issues/22) |
| S15 A flag on a try is recorded and never enforced | fixed | [A7 · #19](https://github.com/knissley/football-manager/issues/19) |

These fifteen are not the whole backlog. The engine findings that did not earn a section of
their own are one line each under *What to trust* below, with the issue that closes them.
What follows is what a fresh pair of eyes needs to know before picking the work up.

### Rows that are out of band, and why

These are not regressions to hunt. They are the price of two fixes that were both correct,
and the bands they miss were set before either landed.

Measured at `--games 400`, seeds 7 and 11. Where the two seeds disagree, both are given —
that disagreement is itself the point: these rows sit *on* their limits rather than
comfortably outside them.

| row | seed 7 | seed 11 | band | why |
| --- | --- | --- | --- | --- |
| third-down conversion | 35.9 **OFF** | 36.0 ok | 36–43 | S3 gave the defence real sub packages and S6 a realistic penalty load. Third down got harder twice, independently. |
| yards per carry | 4.5 ok | 3.9 **OFF** | 4.0–4.8 | Same cause, plus a box count that now decides runs. Swings a whole band-width between seeds, which says the run is noisier than the band assumes. |
| fourth-down conversion | 58.9% | — | 45–58 | Correcting the first-half desperation bug removed a pool of low-percentage fourth-and-longs from the offence's own end, so what remains converts better. |
| first downs per team-game | 17.9 | — | 18.5–22 | Follows from the first two. |
| three-and-out rate | 18.8% | — | 20–27 | Partly definitional: 32% of drives are three plays or fewer, but only the ones that *punt* count here. |

Fourteen of the fifteen headline calibration rows landed on seed 7 when this was written
and third-down conversion was the one that did not — but one of the fourteen was not a
pass at all. Completion percentage sat inside its band only because the harness could not
see a completion that gained nothing (S14); it reads the record's pass result now.

**The engine-wide retune is the next piece of work**, and its brief is that one sentence:
the calibration bands were established against a defence that never substituted and a
league that threw ten fouls a game, and neither is true any more. Re-baseline rather than
chase individual rows.

### What to trust, and what to be careful of

- **The harness is the instrument, and it has been wrong more often than the engine.** Four
  separate findings in this audit were measurement bugs, not engine bugs: the first-down
  row counted kickoffs, the drive chart called returned punts turnovers on downs, the
  home-field counter was computed and never printed, and a pre-snap foul filter excluded
  the only plays that carry pre-snap fouls. Check the row before believing what it says
  about the engine.
- **A mean is not a distribution.** The carry, dropback and drive-length rows exist because
  yards per carry was correct while the shape underneath it was not. Any new row that
  reports an average should probably report a shape instead.
- **Watch for a value computed and then dropped.** It has happened five times now — the
  sack credit, the scheme fit, the run-play holding, the home-field counter, and the
  fourth-down decision that never reached the situation. It is the most common bug shape
  in this codebase by some distance.
- **Golden tests are checked-in constants, and they must stay that way.** Regenerating one
  to make a red test pass is forbidden; regenerating it in the same commit as a deliberate
  behaviour change, with the change described, is the intended workflow. `Hasher` must
  never appear in one — see [ADR-0003](adr/0003-deterministic-seeded-simulation.md).
- **Weather rows need `--games 1000`.** At 400 there are twenty-odd heavy-rain games and the
  row is noise. This nearly caused a mis-tune.
- **`pressureAllowed` does not mean pressure.** It is emitted whenever a rusher wins his
  rep, whether or not he arrives before the ball is out, so it fires on 74% of dropbacks
  against a real rate near a third. Anything that reads it as pressure will explain three
  of every four stalled drives the same way.
  ([C1 · #36](https://github.com/knissley/football-manager/issues/36))
- **Interference is drawn before the throw.** Both kinds are drawn per read in the coverage
  loop, so in 40 games 4 of 58 defensive interference flags were on sacks and 26 on
  receivers nobody threw to. Interference requires a pass toward that receiver.
  ([C2 · #38](https://github.com/knissley/football-manager/issues/38))
- **A blitz rushes four.** Rushers come from `Lineup.front`, which holds four men in
  nickel, so five- and six-man calls rush four on 93% of snaps and protection is always the
  five linemen. A blitz in this engine changes the label and not the count.
  ([C5 · #45](https://github.com/knissley/football-manager/issues/45))
- **The backup quarterback takes about 4% of dropbacks, at random.** `Lineup.fill` draws
  every slot per snap against rotation shares, so the quarterback changed 125 times between
  consecutive dropbacks in 40 games with nobody hurt. Any per-player number off this engine
  is measured on a team that substitutes mid-drive for no reason.
  ([C6 · #27](https://github.com/knissley/football-manager/issues/27))
- **ADR-0013's rating premise is inverted.** It assumes `overall(at:)` penalises a player
  for the ratings he lacks; `PositionWeights.overall` drops the missing weight and
  renormalises, so absence is a bonus. The issue's measurement at seed 7: receivers average
  59.7 at receiver and 64.8 at quarterback, and a kicker rates a 67 quarterback. Do not
  trust an out-of-position overall until this lands.
  ([F1 · #25](https://github.com/knissley/football-manager/issues/25), with
  [F3 · #35](https://github.com/knissley/football-manager/issues/35) amending the ADR to
  say so)

#### The open engine findings that have no section above

One line each, with the issue that closes it. None was re-measured here; each is as its
issue describes. C12 below was found by the play-by-play printer's author reading one game
end to end rather than by any aggregate, and so were two findings that stood on this list
until wave 1 fixed them: A9, the kickoff return that got no try
([#55](https://github.com/knissley/football-manager/issues/55)), and A10, the pre-snap foul
that ran the clock ([#56](https://github.com/knissley/football-manager/issues/56)), which
the S12 row above credits. Three findings out of one game read end to end is the whole
argument for watching a game.

- **A8** — half and overtime boundaries are hardcoded quarter literals, and
  `Situation.isValid` rejects a sixth period, which a postseason game can reach.
  ([#20](https://github.com/knissley/football-manager/issues/20))
- **B1**, **B3**, **B4** and **B5** landed with wave 2's record track: who was on the
  field is twenty-two roster indices on every play
  ([#21](https://github.com/knissley/football-manager/issues/21)); the record carries a
  schema version and the concept called is on it by value, with the design reference
  `nil` until a playbook exists rather than pointing into a stand-in identifier space
  that would have dangled ([#33](https://github.com/knissley/football-manager/issues/33));
  the weather is on the game's result and no longer on a hundred and fifty situations
  ([#23](https://github.com/knissley/football-manager/issues/23)); and the enums behind
  `DecisionPoint.detail` have a two-directional coverage register — the twelve cases the
  engine cannot reach are named with the issue that closes each, and the suite fails the
  moment one is reached ([#24](https://github.com/knissley/football-manager/issues/24)).
- **B6** landed with B1: a flag names a slot, and every slot resolves through `onField`
  whether or not the play credited the man, so the eight fouls on uncredited slots — 29 of
  1104 flags over eighty games — name a player a reader can identify. The pin that listed
  the eight is the contract again, with no register.
  ([#54](https://github.com/knissley/football-manager/issues/54))
- **B7** — the record does not carry where a kick was fielded, so gross punt distance, net
  punt distance and return yardage cannot be recovered from a returned kick; nor does it
  carry timeouts or the two-minute warning, which are inferences from two consecutive
  situations. ([#58](https://github.com/knissley/football-manager/issues/58))
- **C3** — the quarterback always throws to the best-separated receiver on the field. He
  never locks onto his first read, never checks down, never throws it away, and never
  attempts a throw he cannot make.
  ([#44](https://github.com/knissley/football-manager/issues/44))
- **C4** — `tackleAttempt` emits only `madeTackle` and `broken`, `blockResult` only `won`
  and `lost`, `coverageAssignment` only `offMan` and `zoneDeep`. `forcedFumble` is never
  emitted even on a play where a fumble was forced.
  ([#39](https://github.com/knissley/football-manager/issues/39))
- **C7** — every two-point try is a pass, and the defensive call's package disagrees with
  the situation's on 49% of scrimmage snaps, an invariant ADR-0010 says is testable.
  ([#40](https://github.com/knissley/football-manager/issues/40))
- **C8** — a tackle ends out of bounds 14% of the time, flat, whatever the play and
  whatever the clock is doing.
  ([#28](https://github.com/knissley/football-manager/issues/28))
- **C9** — a dead-ball foul after a score is dropped because there is nowhere to enforce
  it, `afterThePlay` is called from the run path only, and roughing the kicker on a made
  field goal erases the three points.
  ([#48](https://github.com/knissley/football-manager/issues/48))
- **C10** — the baseline caller reads `DownAndDistanceClass` as law rather than
  description: `isPassingDown` includes second and 8 and third and 4, and the caller never
  runs on them. ([#37](https://github.com/knissley/football-manager/issues/37))
- **C11** — a punt is always hit at full distance, so from inside the opponent's 45 it is a
  touchback 78 to 86% of the time and no punter's touch decides anything.
  ([#26](https://github.com/knissley/football-manager/issues/26))
- **C12** — a team up eight kneels once at 1:52 with the defence holding timeouts, then
  runs two ordinary plays and kicks a field goal. Too early to kneel, and a team that has
  decided the game is over does not go back to playing. Found in the same game.
  ([#57](https://github.com/knissley/football-manager/issues/57))
- **D1** — `Rules` still carries 2024 values. `kickoffTouchbackOwnYard` is 30 and onside
  kicks are fourth quarter only, and nothing records which season the defaults describe.
  ([#41](https://github.com/knissley/football-manager/issues/41))
- **D2** — the kickoff is a touchback coin flip that ignores where the kick is taken from,
  so a penalty on the kicking team changes nothing about the kick.
  ([#46](https://github.com/knissley/football-manager/issues/46))
- **F2** — `PlayContext.effective` substitutes `player.overall` for any rating the player
  lacks, so a running back's route running is his overall.
  ([#34](https://github.com/knissley/football-manager/issues/34))

### Still deferred, deliberately

Home-field advantage measures about a point against a real two, because the engine models
the crowd and the rest of it is travel and rest — which cannot exist before there is a
schedule, at M3. `CallVulnerability`, `SchemeExperience`, coordinator quality and stamina
are registered in [the roadmap](roadmap.md) as designed and not yet consulted.
