# Audit: is this football?

A deliberate pass over the engine asking one question — *does this behave like the sport?*
— rather than *do the units work?* Separate from the end-of-M1 systems inventory, which
asks whether designed systems are wired in. This one assumes they are and asks whether
what comes out is a football game.

Findings in severity order. Every number is from `simharness --games 400 --seed 7`, whose
output now carries the rows that produced them.

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

## S6 — 21 of 33 fouls never occur

Never produced: encroachment, illegal formation, illegal motion, illegal shift, illegal
substitution, illegal use of hands, illegal block in the back, blindside block, chop
block, tripping, ineligible receiver downfield, illegal man downfield, **offensive pass
interference**, horse-collar, illegal use of the helmet, low block, **roughing the
kicker**, running into the kicker, illegal touching, unsportsmanlike conduct, taunting.

Special teams draw no flags at all: `Penalties.preSnap` runs only on run and pass
families, so there is no false start on a field goal and no offside on a punt.

## S7 — Calibration runs in conditions no game is played in

The harness passes no stadium and no weather, so every calibration game is at "Neutral
Field" with crowd noise 50 and clear skies. **Home-field advantage and weather are
mechanisms with no evidence behind them** — they have never been measured, because the
measurement has never included a home field or a forecast.

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
failure this audit exists to name.

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