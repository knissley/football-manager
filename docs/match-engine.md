# Match engine

**Status: partly built, sections marked.** `FMSimulation` exists and sims a game behind
the real `PlayRecord` contract, using the crude resolver. The spatial engine, the play
format, sliders and grades are M5 and M6 work; every section describing them is labelled
`Designed, not built`. The rules layer has known gaps that are open issues on the audit
backlog (#1) and are labelled where they appear.

Lives in `FMSimulation`. Pure, synchronous, deterministic — and spatial at M5. Today a
crude, matchup-lite resolver sits behind the same contract ([the resolver
seam](#the-resolver-seam)).

Given a `GameSetup` — two teams, gameplans, sliders, weather, seed — it returns a
`GameResult`.

*Designed, not built:* today `GameResult` carries the event stream, the injuries, the
score and the winner. The box score and the per-player grades are queries over the stream
that nothing computes yet — they arrive with `FMAnalysis` at M2. `GameSetup` carries no
gameplan and no sliders yet either; both are types that do not exist.

## The engine is spatial

**Designed, not built.** This is M5. No tick loop, no field geometry and no entity
positions exist in `FMSimulation` today; the crude resolver named below is what runs.
Everything in this section is written in the present tense because it is the contract M5
is built to, not a description of the tree.

Twenty-two players exist as positions and velocities on a field, updated on a fixed
tick. Outcomes are not drawn from outcome distributions; they **emerge from geometry**.

- Separation is the actual distance between a receiver and a defender.
- Pressure is a rusher actually reaching the quarterback's position.
- A tackle happens when bodies converge and a tackle attempt resolves.
- A catch depends on where the ball arrives relative to where the receiver is.

This is the expensive choice and the reason the rest of the product works
([ADR-0006](adr/0006-spatial-simulation.md)). The 2D field view is a direct render of
engine state — the dots are the simulation, not an animator's guess at what a dice roll
meant. And the causal breakdown is a *readout* of what happened rather than a story
told about a number.

Player ratings and traits are **inputs to the physics**: `speed` sets a top velocity,
`routeRunning` sets how sharply a cut can be made without losing ground, "swim master"
selects a different pass-rush move resolution with different timing. Traits are engine
hooks, not cosmetic modifiers.

## The event stream is the contract

The engine's public output is an ordered stream of typed events
([ADR-0007](adr/0007-event-stream-contract.md)), specified in
[play-record.md](play-record.md). Everything downstream — box scores,
grades, news, highlights, tendencies, the causal breakdown — is a **query over that
stream**, never a parallel accumulation.

```
PlayRecord
  situation      down, distance, ball position, clock, score, personnel
  calls          the offensive and defensive calls, held by value, and who chose
                 each (AI or player) — a design edited later cannot rewrite history
                 ([ADR-0010](adr/0010-plays-designs-and-calls.md))
  decisions      the engine's own branch points, recorded as data
                 ("pressure at 2.1s", "progression read 2 of 3", "checkdown covered")
  outcome        yards, result, participants, penalty
  trajectory     per-tick positions — retained only where the game is retained
```

This is what makes the engine safe to deepen. A crude engine and a full spatial engine
emit the same event shapes, so the analysis layer, the UI, and the news system are
written once, against a stable contract, before the engine is any good.

## Determinism and replay

A game is a pure function of `(initialState, seed, sliderConfig, decisionLog)`.

The `decisionLog` matters because of toggle-at-will play calling: a game where the
player took over some snaps is not reproducible from a seed alone. Every player
decision is recorded in order, so the game replays exactly.

That tuple *is* the storage format for games we don't retain in full. Fifteen of
sixteen games each week keep a box score and their replay tuple; ask to watch one and
it re-simulates identically. Storage stays bounded across a decade-long career, and
determinism stops being a testing convenience and becomes a player-facing feature.

*Designed, not built:* the storage half of that paragraph is M4. There is no persistence
layer, no `SliderConfig` and no `decisionLog` type today. What is built and enforced is
the determinism itself — the banned list below, `scripts/lint-sim.sh`, and the golden
constants in `GoldenSeedTests` and `GoldenWorldTests`.

**Banned in `FMSimulation` and `FMGeneration`**: `Int.random`, `Double.random`,
`SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`, `UUID()`, `Date()`, and
any clock or environment read. Iteration order over unordered collections must never
reach output — sort by a stable ID first.

The list is enforced by [`scripts/lint-sim.sh`](../scripts/lint-sim.sh), across the
`Sources/` tree of every `FM*` package, and CI runs it as a hard-failing step — "Banned
primitives in the sim" in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — on
every push and pull request. The iteration-order rule is the one part no lint checks:
nothing mechanically catches a dictionary walk reaching output.

Floating-point determinism across architectures is a real risk here in a way it wasn't
for an abstract engine. Golden tests run on both arm64 and x86_64 in CI, and hot paths
avoid transcendental functions where a cheaper formulation exists.

## Performance budget

**Designed, not built.** The budget describes the M5 tick loop, and there is no tick loop
and no season loop to time. There is no benchmark target and no CI step that fails on a
timing regression, and nothing gates on the budget. Since H3 (#9), `simharness` times
its simulate loop and prints a `Budget` block that the job summary carries: a number to
read, not a gate. The rules below are what M5 is written to.

**A season simulates in about 60 seconds.** That is the constraint, and it is
architectural rather than a tuning target.

```
272 games / 60s          ≈  220 ms per game
220ms / ~150 plays       ≈  1.5 ms per play
1.5ms / (60 ticks × 22)  ≈  1.1 µs per entity-tick
```

A tight entity update — integrate velocity, steer toward a target, test a few
proximities — should run in 50–200ns, which leaves 5–20× headroom for a richer per-tick
model. That headroom exists **only if the hot loop never allocates**:

- Flat arrays of `struct`, indexed by slot. No per-tick object churn, no dictionaries.
- No string construction during simulation. Events carry IDs and enums; text is
  rendered later, by the narrative layer.
- No `Array` growth inside a play. Buffers are sized once and reused.
- Trajectory capture is opt-in per game, not always-on.

Build this in from the first line. Retrofitting it is a rewrite, not an optimization
pass.

## The resolver seam

The engine splits in two ([ADR-0012](adr/0012-play-resolver-seam.md)):

```
GameSimulator     the sport's rules — clock, downs, possession, scoring,
                  penalties, timeouts, overtime. Written once, never rewritten.
   ↓ asks, per snap
PlayResolver      what happened on this snap.
   ├── CrudeResolver     M1. Named matchups, no geometry. Deleted at M5.
   └── SpatialResolver   M5. Twenty-two entities on a tick clock.
```

Most of what an engine does is not physics. A wrong ten-second runoff is wrong in both
resolvers, and it is wrong exactly where players are paying the most attention. Writing
those rules once means M5 replaces one component into a harness that already sims a
season, rather than rewriting the clock and its tests along with everything else.

### The crude resolver

Matchup-lite: no positions and no tick loop, but **real named matchups** — this rusher
beat this tackle at this time, this corner was covering this receiver. It emits genuine
`Participation` and `DecisionPoint` data, because a resolver that returned empty
`decisions` would leave the interrogation layer unbuildable until M5, which is the exact
risk [ADR-0007](adr/0007-event-stream-contract.md) exists to remove.

Its decision points must be **consistent with its own outcome**. If it reports pressure
at 2.1 seconds and a sack, the sack is by that rusher. A fabricated causal chain that
merely looks plausible would let the analysis layer appear to work while reading noise —
the real risk of building M2 against scaffolding.

What it does *not* do: geometry, trajectories, or anything requiring a position. It hits
the parametric calibration rows because they are inputs at this fidelity, and it takes
the spread of team win totals seriously because that one is emergent.

It is scaffolding, and it is deleted at M5 rather than kept as a fast-sim path. Career
fast-forward runs at the spatial engine's speed; unwatched games are already stored as
replay tuples and reproduce exactly.

## Play resolution

### Plays are data

**Designed, not built.** The play format, the concept library and the validator are M6.
`OffensiveCall.design` points at a playbook that does not exist.

A play is a formation plus a per-player assignment: a route with landmarks and timing,
a blocking rule, a coverage responsibility. The engine reads that format; the play
designer edits it; the premade concept library is authored in it.

Because assignments are data, a designed play needs **validation** — eleven players,
legal formation, every assignment executable — before it reaches the engine. That's a
constraint checker, not a drawing tool, and it's the real cost of the play designer.

### Pass play

**Designed, not built.** M5. The crude resolver draws a pass from named matchups and
emits decision points consistent with its own outcome; it has no ball flight, no route
geometry and no pocket.

Pressure, routes, and the read happen concurrently on the tick clock rather than as
sequential dice rolls:

1. Rushers and blockers engage; each matchup resolves as a physical contest whose
   result is *when* and *where* the rusher gets past, not a binary win.
2. Receivers run their assigned routes; defenders play their assigned technique.
   Separation is measured, not drawn.
3. The quarterback progresses through his reads on a timing schedule, gated by
   `awareness` and by what the pocket is actually doing around him. He throws, checks
   down, scrambles, throws it away, or takes the sack.
4. Ball flight has a duration. The catch resolves on arrival, against the defender's
   actual position and the receiver's `catching` and hands traits.
5. Yards after catch is pursuit geometry and tackle attempts.

Each of those steps writes a decision record. That's where "your right tackle lost his
rep in 2.1 seconds and the checkdown was covered" comes from — it's logged, not inferred.

### Run play

**Designed, not built.** M5. The crude resolver has no gaps and no pursuit angles.

Blocking assignments resolve into actual displacement; the hole is a real gap between
bodies. The back's vision trait affects which gap he attacks and how quickly he commits.
Tacklers pursue on real angles. Broken tackles chain.

**What the crude resolver does today** is a hole-quality score and then *three* outcomes,
which is the part worth keeping when the spatial engine replaces it. The score pays twelve
a block — twelve for a block won or lost at the point of attack, twelve for a defender the
offence had no blocker for, six for a blocker with nobody left to take — so it carries the
count and the blocking in one signed number, and the record publishes it as the play's
`holeQuality` point. Below a block's worth above an even fight the defence won the point of
attack and the carry dies at or behind the line. Four blocks clear the play side is washed
and he is through into the second level. In between is the **ordinary carry**, three to nine
yards, decided by the back's vision and contact balance against the tackling of the men who
have to come downhill and meet him — and that is the plurality of carries, as it is in the
sport.

One line through the score instead of three outcomes is what the run game used to be, and it
had no middle: a stuff-or-break contest that satisfied all four of the cumulative shape rows
while putting half the carries at two yards or fewer and paying for the mean out of a flat
lottery on the tail. The harness prints the whole carry-length histogram now, because four
cumulative shares cannot see that and a reader can.

### Special teams

**Partly built.** Kick distance and accuracy from ratings, wind and precipitation are in
the crude resolver today, and so are kickoff and punt returns, fair catches, touchbacks
and muffs — the harness prints the return rates. *Designed, not built:* returns as
pursuit geometry (M5), and blocked kicks.

A punt separates **intent** from **execution**. `PuntPlan` is the call: hit it as far as
it goes from outside the opponent's 45, aim a pooch between the 5 and the 10 from inside
it, or aim the corner inside the 5 when the punter has the touch to be trusted with it.
The punter's `puntPower` bounds what he can reach and his `puntAccuracy` is the scatter
around the target, with the long half of that scatter growing with his leg — so a strong
leg with poor hands overkicks a pooch into the end zone and a modest leg with good hands
drops it on the 8. A touchback (11-6-2-c, spotted on the 20 by 9-5-1 Note a) is what a
miss looks like rather than what happens whenever a team punts from plus territory.

Kick distance and accuracy from ratings, wind, and precipitation; returns resolve as
pursuit geometry like any other play. Blocks and muffs are low-probability branches and
worth keeping — they're memorable.

## Injuries

Availability in M1; severity, rehabilitation and reaggravation in M3.

Injuries are drawn from a play's **participants** rather than inside the resolver,
because an injury is about who was involved and not about how the contact was modelled —
so the model survives the spatial resolver replacing the crude one, at which point real
contact severity can feed it instead of the play kind.

Two causes, and they are genuinely different events rather than two sizes of the same
one:

**Contact.** Somebody was hit. Weighted toward the ball carrier and the men who brought
him down, scaled by how much contact the play involved.

**Non-contact.** A cut, a plant, a landing. Drawn from who was *moving hard* rather than
who was hit, so it is uncorrelated with how the play went and can happen on a snap where
nobody was touched at all. It has no walk-it-off branch: an achilles is most of a season
and a hamstring is still weeks. About a sixth of injuries and well over a third of the
games lost, which is the relationship the sport actually has.

A linemen in a phone booth does not tear a knee coming out of a break, so only explosive
roles are exposed — and a quarterback is exposed when he scrambles and not when he stands
in the pocket.

## Clock, penalties, and AI

**Partly built, and the gaps are open issues.** Penalties and the AI caller are in the
engine. The clock rules below are built as of wave 1 of the audit backlog: the clock
stops on every change of possession (#17), a foul before the snap charges no play time
and the clock restarts as 4-3-2-e says (#56, and the wave 1 review), a kick the kicking
team recovers or the receivers fair catch starts no clock (4-3-1), and the ten-second
runoff exists with its timeout and decline as caller decisions (#32), in regular-season
overtime too (16-1-3-e). The two-minute warning is in overtime as well, and postseason
overtime is timed as 16-1-4-h pairs its periods into halves (#74). The play clock is
counted in the rules layer — forty from the end of a play, twenty-five from the whistle
after an administrative stoppage, thirty after a runoff — and a delay of game is that
clock expiring rather than a rate drawn beside it (4-6). A two-minute warning taken
between downs is one of those stoppages, so it is taken before the snap it precedes is
prepared and that snap is played against the twenty-five (#128); the last forty seconds of a
half (4-7-3) and the injury timeout after the two-minute warning (4-5-4) are modelled
with their elections as caller decisions, and every choice a side makes about the clock
between downs is written into the play's decision log (#76). The runoff after a replay
reversal (4-7-4) stays excluded until there is a replay system. Read the tracker (#1)
before trusting anything else in this section.

- **Clock** rules are explicit states, not approximations. Two-minute warning, spikes,
  kneels, the out-of-bounds rule, and the ten-second runoff all matter most exactly
  where players pay the most attention.
- **Penalties** are drawn per matchup from player `discipline` and coaching, then
  applied with correct accept/decline logic — the engine evaluates both branches and
  takes the better one for the non-penalized team.
- **AI play calling**, on both sides of the ball, keys off `SituationClass` and the
  opponent's tendencies, modulated by coach ratings and gameplan. Fourth-down decisions
  run on expected points, with coach aggression shifting the threshold.

Because play calling can be toggled at will, the AI caller is a **headline system** and
has its own design doc: [play-calling.md](play-calling.md). In short — your offensive
coordinator makes the calls inside guardrails your gameplan sets, both sides carry noisy
tendency models of each other built from `PlayRecord` history, the defense never sees
the call, and caller quality is benchmarked against an oracle and against human play
rather than assessed by feel.

## Variance, and why records have to be reachable

Means are the easy part. A league tuned only to its averages produces a distribution that
is *narrower than chance*, and in one a record is not merely unlikely — it is impossible.
An early crude resolver managed a maximum of three passing touchdowns in four hundred
team-games and could never have produced four. A Poisson process with the same mean would
have produced four in one game in twenty-five.

Two mechanisms fix that, and neither is "more randomness":

**Form.** A rating is a central tendency, not a constant. Each player draws a day once per
game, seeded from the game and his identifier, applied to every rep he takes. This is what
*correlates* a player's plays within a game — and correlation, not magnitude, is what
gives a distribution tails. Independent per-play noise averages out over a hundred snaps;
a day does not. Ordinary days stay within a few rating points so talent still decides a
season; a rare day well outside that is what lets a generational player in the right
situation chase a number nobody should reach.

Form sits on a different timescale from everything else that moves a player, and the
three should never be confused:

| | Timescale | Reverts | Answers |
| --- | --- | --- | --- |
| **Trait** | A career | No | What kind of player is he |
| **Development** | Season to season | No | Who is he becoming |
| **Form** | One game | Completely | Who was he on Sunday |

Two things it deliberately is not. It is **not a hot hand**: form is drawn before kickoff
and never reacts to what happens in the game, because a model that noticed a player was
having a good day and made him better would be the engine authoring a narrative. And it is
variance in *capability*, not in *outcomes* — every play still resolves through identical
physics, and form only changes what a player brings to it.

*Designed, not built:* `Form` draws a **per-player** day from the game's seed and the
player's identifier, and that is all it draws. There is no team-wide component and none
of the reasons behind one — travel, a short week, a hostile crowd, the game before —
because none of those exists before there is a schedule to travel on (M3). The team-days
paragraph below is the design for that half.

**Form is visible after the fact, never before.** The analysis layer can say *he was off
all day* as an observation drawn from the stream, the same way it reports pressure or
separation, because a performance nobody can account for is exactly what the interrogation
hook promises not to produce. It is not visible before kickoff, where it would become a
lineup cheat and tell the player the answer before asking the question.

**Teams have days too, and they have reasons.** *Designed, not built — M3.* Part of each
player's day comes from a team-wide component, so a squad can be collectively flat or
collectively electric — which is real, and is a direct lever on the spread of team win
totals, the row the calibration table calls the most important number. That component is
driven by things with causes: travel, a short week, a hostile crowd, the game before. A
shared draw with no reason behind it would be indistinguishable from an excuse.

**Explosive plays.** A receiver who beats every defender with an angle on him is in open
field, not three yards further on. The run game had a burst through the hole from the
start and the passing game had no equivalent, which is precisely why one had a tail and
the other did not. Both are the same mechanism now: a long run is a tackle **missed in
space**, not a hole that measured well, so the carrier's contact balance is what earns it
and the blocking only decides whether he gets to the man who has to make that tackle. A
tackle attempted in space is missed far more often than one made at the line, which is
what makes a tail possible at all — at the line's rate a carrier would have to beat three
men in a row, which happens about once in fourteen hundred carries.

The test of this is not the mean. It is whether, over a long enough career, somebody
breaks a record that looked unattainable — and `Tools/simharness` reports the tails
alongside the means for exactly that reason.

## Sliders

**Designed, not built.** No `SliderConfig` type exists; the replay tuple's slider slot is
a promise, not a field. The calibration targets below are read at the engine's own
defaults.

Sliders are **league-wide world tuning**, not a personal difficulty dial. Pass
difficulty, injury frequency, pass rush intensity and the rest apply to every team, so
stat leaders, records and the Hall of Fame stay comparable within a career.

Sliders are part of the replay tuple. Calibration targets below are valid **at default
settings only**.

*Open:* whether sliders lock at career creation or records carry their config. See
[design-decisions.md](design-decisions.md#open-questions).

## Calibration

Tuned against `Tools/simharness` — never by playing the app. The harness sims N games
headless and prints every row below with its measured value, its band, and a verdict.
The bands are `Tools/simharness/Sources/simharness/Targets.swift`; this table is
generated from that array (`swift run simharness --targets-markdown`) and the package's
test fails if the two disagree, so the doc cannot describe a target the harness does not
check.

CI runs it at 400 games on seed 7 on both architectures, uploads the output as an
artifact and puts the table in the job summary — but the job **reports, it does not
gate**: an `OFF` row is a finding to read, not a red build. The `Gate` column below is
what a gating step would read when one exists; making a row gating is a per-row decision,
taken in a retune issue, and no row fails CI yet.

**Every band names the real-league season it was derived from and the source it came
from.** Nothing in the table is remembered. The sourced rows were computed by
`scripts/calibration-sources.py` from the nflverse play-by-play data set (built from the
league's official play-by-play feed) and, for personnel, box counts and pressure, the
nflverse participation data from Next Gen Stats; the script prints each row's value in
every season alongside the band, so a number that cannot be reproduced from it is wrong.
A row nobody has cited keeps its old band, prints `unsourced`, and is never `ok`.

The band policy is the script's and is stated once, there: a row's band spans the sourced
seasons' values, widened on each side by the larger of 5% of the mean and twice the
standard error of a 400-game harness run, measured by resampling whole games — so rare
events (ties, return touchdowns) get the width their rarity demands. Regular-season games
only. Sliders at default.

**A target measured under one rulebook can be wrong under another.** Per-play and
per-drive rates move slowly and come from 2023 and 2024. A row that depends on a rule the
2025 rulebook changed — the kickoff (touchback to the 35), the onside kick (permitted
whenever trailing), overtime (both teams possess in the regular season) — is sourced from
2025 alone, and its 2024 row is kept beside it so `simharness --rulebook 2024` can check
the mechanism against the season it was played in. The harness compares each row's season
against the rulebook of the run and prints, at startup, every row that is `stale`: sourced
under rules the run is not playing. A stale row is never `ok`. Until D1 (#41) lands,
`Rules.standard` still carries 2024 kickoff values while the target rulebook is 2025, so
the default run lists the 2024-sourced kickoff rows as stale by design; D2 (#46) is what
makes the 2025 rows land.

Columns: **Season** is the real-league season(s) the band was derived from; **Sensitive
to** lists the rule areas the row depends on, which is what decides staleness when the
rulebook moves; **Gate** is whether a miss counts as a failure — `no` for rows the harness
cannot measure yet or whose sample is too thin to fail on.

<!-- calibration-targets:begin -->
| Row | Target | Season | Sensitive to | Source | Gate | Definition and notes |
| --- | --- | --- | --- | --- | --- | --- |
| points | 20.6-24.1 | 2023-24 | — | S1 | yes | — |
| passing yards | 221.7-248.1 | 2023-24 | — | S1 | yes | Gross: yards on completions, sacks not deducted, which is what the harness sums. |
| rushing yards | 94.7-110.4 | 2023-24 | — | S1 | yes | Designed runs only, as the harness counts them; the league's figure adds scrambles and kneels. |
| yards per carry | 3.9-4.6 | 2023-24 | — | S1 | yes | Designed runs only. |
| completion percentage | 61.2-68.6 | 2023-24 | — | S1 | yes | Completions over attempts, read from the record's pass result. Counted as a gain of a yard or more it read about three points low (2023–24 positive-only rate: 61.1–62.4); the zero-or-fewer row is the gap. |
| sack rate per dropback | 6.1-7.2 | 2023-24 | — | S1 | yes | — |
| interception rate | 1.9-2.6 | 2023-24 | — | S1 | yes | Per pass attempt. |
| third down conversion | 36.7-41.7 | 2023-24 | — | S1 | yes | — |
| plays from scrimmage | 59.0-66.3 | 2023-24 | — | S1 | yes | Rushes, passes, sacks, scrambles, kneels and spikes. |
| penalties (both teams) | 10.8-13.5 | 2023-24 | — | S1 | yes | Accepted fouls per game. |
| average third down distance | 6.6-7.4 | 2023-24 | — | S1 | yes | — |
| yards gained on first down | 5.1-5.8 | 2023-24 | — | S1 | yes | Scrimmage plays on first down. |
| yards per pass attempt | 6.6-7.5 | 2023-24 | — | S1 | yes | Gross. |
| yards per play | 5.0-5.8 | 2023-24 | — | S1 | yes | The harness's definition: gross pass, designed-run and sack yards over every scrimmage play, scramble yards excluded. The league's net figure was 5.5–5.7. |
| yards per completion | 10.3-11.5 | 2023-24 | — | S1 | yes | — |
| drops per target | none | unsourced | — | — | no | Catch attempts the record calls a drop, over catch attempts. Every throw the engine resolves to a receiver has exactly one target, so this is the charting convention's denominator. Unsourced: the play-by-play does not chart a drop. |
| passes defensed per game | none | unsourced | — | — | no | Both teams, break-ups only: a ball the defender knocked away or fouled away, which is what the stat counts. Interceptions are row:interceptionRate's. Unsourced: the play-by-play does not name the defender on a break-up. |
| plays per game | 152-170 | 2023-24 | — | S1 | yes | Every play including kicks, tries and flag-only snaps; not timeouts. |
| ties per game | 0.000-0.010 | 2025 | overtime | S1 | yes | One tie in 272 games in 2025; the band is that rate widened by twice the resampled standard error of a 400-game run, per the policy. |
| games reaching overtime | 3.0-7.3% | 2025 | overtime | S1 | yes | Fourteen of 272 games in 2025. |
| seconds played per overtime | 355-463 | 2025 | overtime | S1 | yes | Game clock used by the last snap of the period. Both teams possessing lengthened it from about 345 in 2023–24. |
| player-games lost per season | 40.0-90.0 | unsourced | — | — | no | Nobody has cited this band; it is not in the play-by-play. |
| scrambles per game | 3.5-4.2 | 2023-24 | — | S1 | yes | — |
| kneels per game | 1.3-1.8 | 2023-24 | — | S1 | yes | — |
| spikes per game | 0.1-0.4 | 2023-24 | — | S1 | yes | — |
| timeouts spent per game | 7.1-8.2 | 2023-24 | — | S1 | yes | Team timeouts, both teams. |
| spread of team win totals (σ) | 2.5-3.8 | 2023-24 | — | S1 | no | Standard deviation of regular-season wins across the 32 teams, ties as a half. Not measurable before a schedule exists (M3). |
| share of points from touchdowns | 62.6-70.1% | 2023-24 | — | S1 | yes | Six per touchdown; tries counted separately. |
| share of points from field goals | 21.1-24.6% | 2023-24 | — | S1 | yes | — |
| snaps in 11 personnel | 62.3-71.9% | 2023-24 | — | S2 | yes | — |
| snaps against nickel | 61.6-69.2% | 2023-24 | — | S2 | yes | Five defensive backs on the field. |
| snaps against base | 20.2-25.0% | 2023-24 | — | S2 | yes | Four defensive backs on the field. |
| yards per carry, even count | 4.3-5.0 | 2023-24 | — | S2 | yes | First and ten, designed runs; blockers are five linemen plus tight ends plus extra backs, the box is eleven less the defensive backs, as the harness counts it. By defenders actually in the box the figure was 4.5–4.7. |
| yards per carry, outnumbered by one | 3.9-5.1 | 2023-24 | — | S2 | yes | Same construction, one more in the box than blockers. The sport's gap between even and outnumbered is small: 4.3–4.6 against 4.5–4.7. |
| quarterback snaps per team-game | 58.9-66.8 | 2023-24 | — | S2 | yes | Player-snaps on plays from scrimmage by roster position group, the source's participation feed scaled to plays from scrimmage. One a snap by construction on both sides. |
| backfield snaps per team-game | 64.2-72.4 | 2023-24 | — | S2 | yes | Running backs and fullbacks. |
| receiver snaps per team-game | 150.3-171.0 | 2023-24 | — | S2 | yes | — |
| tight end snaps per team-game | 77.1-87.2 | 2023-24 | — | S2 | yes | — |
| offensive line snaps per team-game | 296.7-332.9 | 2023-24 | — | S2 | yes | Five a snap by construction in the engine; the source has a sixth now and then. |
| front seven snaps per team-game | 363.7-405.1 | 2023-24 | — | S2 | yes | Edge, interior and linebacker together: the source lists a four-man front's edge rushers as ends and a three-man front's as outside linebackers, so a narrower split would follow the scheme rather than the job. |
| defensive back snaps per team-game | 285.5-323.9 | 2023-24 | — | S2 | yes | Cornerbacks and safeties. |
| carries stuffed (0 or fewer) | 17.5-19.9% | 2023-24 | — | S1 | yes | — |
| carries of 2 or fewer | 40.6-46.5% | 2023-24 | — | S1 | yes | — |
| carries of 10 or more | 9.6-11.2% | 2023-24 | — | S1 | yes | — |
| carries of 20 or more | 2.0-2.5% | 2023-24 | — | S1 | yes | — |
| dropbacks losing yards | 7.2-8.6% | 2023-24 | — | S1 | yes | Sacks and completions or scrambles behind the line. |
| dropbacks with no gain | 30.3-34.6% | 2023-24 | — | S1 | yes | Almost all incompletions. |
| dropbacks of 10 or more | 23.8-27.8% | 2023-24 | — | S1 | yes | — |
| dropbacks of 20 or more | 7.7-8.6% | 2023-24 | — | S1 | yes | — |
| dropbacks of 40 or more | 1.0-1.5% | 2023-24 | — | S1 | yes | — |
| pressure rate per dropback | 27.8-32.3% | 2023-24 | — | S2 | yes | Next Gen Stats' pressure flag over attempts, sacks and scrambles. The harness counts a dropback whose record says a rusher reached the quarterback before the ball was out; a rep lost after the throw is a lost rep and not a pressure. |
| completions for 0 or fewer yards | 4.0-5.6% | 2023-24 | — | S1 | yes | Share of all completions. |
| drives ending in a punt | 32.8-39.0% | 2023-24 | — | S1 | yes | — |
| drives ending in a touchdown | 19.2-23.8% | 2023-24 | — | S1 | yes | — |
| drives ending on downs | 4.7-6.3% | 2023-24 | — | S1 | yes | — |
| drives per team-game | 10.2-11.7 | 2023-24 | — | S1 | yes | — |
| plays per drive | 5.3-6.1 | 2023-24 | — | S1 | yes | Offensive plays; the punt or kick that ends a drive is not one. |
| first downs per team-game | 16.6-18.9 | 2023-24 | — | S1 | yes | By rush or pass, as the harness counts; with penalty first downs the league had 17.8–18.3. |
| drives of 3 plays or fewer | 33.3-39.0% | 2023-24 | — | S1 | yes | — |
| drives of 4 to 7 | 33.7-38.4% | 2023-24 | — | S1 | yes | — |
| drives of 8 or more | 25.9-29.7% | 2023-24 | — | S1 | yes | — |
| three and out | 19.1-22.5% | 2023-24 | — | S1 | yes | Drives of three offensive plays or fewer that end in a punt, over all drives. |
| red zone touchdown rate | 51.1-59.1% | 2023-24 | — | S1 | yes | Drives with a snap inside the 20 that end in the offence's touchdown. |
| average start (own yard) | 29.1-32.3 | 2025 | kickoff | S1 | yes | First snap of each drive. The 2025 touchback at the 35 moved this half a yard from 2024. |
| average start (own yard) | 28.6-31.7 | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| drives starting in own half | 85.2-94.2% | 2025 | kickoff | S1 | yes | Strictly inside the drive's own half; midfield is not. |
| drives starting in own half | 85.6-94.7% | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| punts per team-game | 3.5-4.4 | 2023-24 | — | S1 | yes | — |
| net punt (yards) | 39.4-43.8 | 2023-24 | — | S1 | yes | Distance less return yards, a touchback counted as a punt to the 20 — read off the record, which carries where the punt was fielded. |
| gross punt (yards) | 45.0-50.0 | 2023-24 | — | S1 | yes | Line to where the punt was fielded, downed or went out. Blocked punts excluded. ASSUMED, not read from the source: that the source measured a touchback's gross to the goal line. The band is what the source publishes; how it treated a touchback is our reading of it, and if that reading is wrong this row is biased by the touchback share. |
| yards per punt return | 8.8-10.6 | 2023-24 | — | S1 | yes | Over punts that were fielded and run back; a fair catch is not a return. |
| two-point tries per team-game | 0.19-0.29 | 2023-24 | tryAttempt | S1 | yes | — |
| two-point conversion rate | 33.6-62.3% | 2023-24 | tryAttempt | S1 | yes | Wide because the sport itself swung from 55% to 41% on about 130 tries a season. |
| kickoff touchbacks | 18.9-22.4% | 2025 | kickoff | S1 | yes | Share of all kickoffs, onside kicks included in the denominator. |
| kickoff touchbacks | 61.1-67.6% | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| field goals per team-game | 1.8-2.2 | 2023-24 | — | S1 | yes | Attempts. |
| field goals made, under 30 | 92.1-100.0% | 2023-24 | — | S1 | yes | — |
| field goals made, 30-39 | 89.5-99.3% | 2023-24 | — | S1 | yes | — |
| field goals made, 40-49 | 72.4-84.0% | 2023-24 | — | S1 | yes | — |
| field goals made, 50+ | 63.7-74.9% | 2023-24 | — | S1 | yes | — |
| attempts under 30, share | 19.1-25.3% | 2023-24 | — | S1 | yes | Share of field goal attempts by distance. |
| attempts 30-39, share | 24.1-31.9% | 2023-24 | — | S1 | yes | — |
| attempts 40-49, share | 23.8-29.1% | 2023-24 | — | S1 | yes | — |
| attempts 50+, share | 19.2-27.6% | 2023-24 | — | S1 | yes | — |
| extra points made | 91.0-100.0% | 2023-24 | tryAttempt | S1 | yes | — |
| fourth downs punted | 50.7-58.6% | 2023-24 | — | S1 | yes | Of fourth downs that ended in a punt, a field goal or a play. |
| fourth downs kicked | 23.1-27.9% | 2023-24 | — | S1 | yes | — |
| fourth downs gone for | 18.4-21.3% | 2023-24 | — | S1 | yes | Rising: 23.3% in 2025. |
| fourth down attempts per team-game | 1.3-1.6 | 2023-24 | — | S1 | yes | — |
| fourth down conversion rate | 48.3-60.0% | 2023-24 | — | S1 | yes | — |
| 4th and 1: went for it | 62.8-74.2% | 2023-24 | — | S1 | yes | Rising: 76.3% in 2025. |
| fumbles lost per team-game | 0.38-0.55 | 2023-24 | — | S1 | yes | On any play, kicks included. |
| fumbles kept per team-game | 0.46-0.63 | 2023-24 | — | S1 | yes | Fumbles the fumbling team recovered. |
| turnovers per team-game | 1.06-1.37 | 2023-24 | — | S1 | yes | Interceptions and fumbles lost; not downs. |
| touchdowns not by the offence | 0.09-0.15 | 2025 | kickoff | S1 | yes | Every return touchdown per team-game. |
| touchdowns not by the offence | 0.08-0.14 | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| interception and fumble return TDs | 0.05-0.14 | 2023-24 | — | S1 | yes | Per team-game. |
| kickoff and punt return TDs | 0.02-0.06 | 2025 | kickoff | S1 | yes | Per team-game; 21 in 2025 against 14 in 2024. |
| kickoff and punt return TDs | 0.01-0.04 | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| onside kicks per game | 0.15-0.24 | 2025 | onsideKick | S1 | yes | Kicks described as onside in the official play description. |
| onside kicks per game | 0.13-0.23 | 2024 | onsideKick | S1 | yes | Kept for --rulebook 2024. |
| onside kicks recovered | 2.8-16.4% | 2025 | onsideKick | S1 | no | Five of 52 in 2025; too few kicks a season to fail on. |
| onside kicks recovered | 0.5-11.5% | 2024 | onsideKick | S1 | no | Kept for --rulebook 2024. |
| kickoffs returned | 72.3-80.0% | 2025 | kickoff | S1 | yes | Share of all kickoffs. |
| kickoffs returned | 30.9-35.9% | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| yards per kickoff return | 24.1-26.7 | 2025 | kickoff | S1 | yes | From where the kick was fielded, end-zone depth included, to where the return ended; onside kicks excluded. |
| yards per kickoff return | 25.6-28.4 | 2024 | kickoff | S1 | yes | Kept for --rulebook 2024. |
| punts returned | 40.5-45.3% | 2023-24 | — | S1 | yes | Share of punts fielded and run back; fair catches, downed and touchbacks are not. |
| snaps inside own 10 | 1.55-1.84 | 2023-24 | — | S1 | yes | Scrimmage plays per team-game. |
| safeties per team-game | 0.01-0.05 | 2023-24 | — | S1 | yes | — |
| pre-snap fouls, road vs home | 0.94-1.19x | 2023-24 | — | S1 | yes | The offence's pre-snap fouls per snap, road over home. The sport's edge is about 6%, not the fifth the band once claimed; the home side won 53–56% of decided games and outscored by 2–3 points, most of which is not the crowd. |
| combined points, heavy rain vs dry | 2.0-4.0 | unsourced | — | — | no | Points lower in heavy rain. The play-by-play does not grade rain, so nobody has cited this; needs --games 1000. |
| games within 3 | 19.6-29.3% | 2023-24 | — | S1 | yes | — |
| games within 7 | 44.5-57.0% | 2023-24 | — | S1 | yes | — |
| offensive holding per game | 1.89-2.68 | 2023-24 | — | S1 | yes | — |
| false start per game | 2.10-2.66 | 2023-24 | — | S1 | yes | — |
| defensive pass interference per game | 0.88-1.24 | 2023-24 | passInterference | S1 | yes | — |
| defensive holding per game | 0.55-0.74 | 2023-24 | — | S1 | yes | — |
| unnecessary roughness per game | 0.51-0.73 | 2023-24 | — | S1 | yes | — |
| delay of game per game | 0.48-0.71 | 2023-24 | — | S1 | yes | — |
| defensive offside per game | 0.46-0.66 | 2023-24 | — | S1 | yes | — |
| illegal formation per game | 0.13-0.55 | 2023-24 | — | S1 | yes | Wide because 2024 called it twice as often as 2023. |
| roughing the passer per game | 0.27-0.43 | 2023-24 | — | S1 | yes | — |
| neutral zone infraction per game | 0.27-0.41 | 2023-24 | — | S1 | yes | — |
| interference drawn per game | none | unsourced | passInterference | — | no | Defensive interference flags thrown, accepted or declined, both teams. The accepted half is row:penalty.defensivePassInterference, which is the graded one. Unsourced: a band for flags thrown rather than enforced has not been computed. |
| interference on completions | 0.0-0.0% | unsourced | passInterference | — | no | Defensive interference flags on a pass that was then completed, as a share of them. Not a league rate and not sourced: the band is the engine's own promise from 8-5-1, where the foul is contact that spoiled the receiver's chance at the ball and so is the reason it was not caught. The offence's push-off is excluded and printed beside it, because a catch it brings back is the sport working normally. |

- **S1** — nflverse play-by-play data, regular-season games
- **S2** — nflverse participation data from Next Gen Stats, regular-season games
<!-- calibration-targets:end -->

### Reading the table

The spread of team win totals is the row that encodes "upsets happen and dominant teams
dominate." Too low and the league feels random; too high and every season is decided in
August. It is the single most important number in this table and the harness cannot
measure it until there is a schedule (M3), which is why it carries no gate.

Everything in the first block measures the passing and running game. None of it measures
*football*, and the [is-this-football audit](audit-is-this-football.md) is what that
omission cost: the engine hit "points per game" for months while paying three points for
an extra point, because no row asked where the points came from. The rest of the table is
what a game is made of — where points come from, how drives end, where they start, the
shape of a carry and a dropback rather than their means — and it is checked in the harness
under **Is this football?**.

Some rows the sport itself corrected. Drives start in their own half about 90% of the time,
not 75–82%; dropbacks of forty or more are 1.2–1.3% of dropbacks, not 1.5–3%; a road
offence commits about 6% more pre-snap fouls than a home one, not a fifth more; teams go
for it on a fifth of fourth downs, not an eighth. Every one of those was a band written
from memory, and every one of them read `ok` against an engine that was wrong.

Two harness measurements do not yet match the source's definition, and the notes column
says so rather than bending the band to the measurement: net punt spots a touchback at
the goal line, and yards per play leaves scramble yards out of the numerator. Those are
harness fixes, not retunes, and they move measured values, so they are not made here. A
third was fixed the same way: completion percentage counted only completions that gained
until the record could say a pass was caught, and it reads `Outcome.passResult` now.

Home win rate and the home scoring edge are printed **without** a target. In 2023–24 the
home side won 53–56% of decided games and outscored the visitor by two to three points,
and most of that is travel, rest and short weeks — none of which exists before there is a
schedule to travel on (M3). What the engine models is the crowd, so the mechanism (the
pre-snap foul ratio) gets the target and the aggregate gets a note.

The weather rows need a large sample: at 400 games there are only twenty-odd heavy-rain
games and the row is noise. Run `--games 1000` before reading them.

Also checked: the best players lead the league most seasons, and no scheme dominates —
equal-talent rosters built differently should win the same number of games within noise.

## Build order

Deepen behind the event contract rather than building depth first. See the
[roadmap](roadmap.md).

1. Event stream shape and a deliberately crude outcome engine behind it.
2. The analysis and narrative layers, proving the contract carries what they need.
3. Spatial engine: dropback passing with real geometry, same events out.
4. Run game, special teams, penalties, injuries, fatigue.
5. Play format and designer.
6. AI play calling benchmarked against the player.
7. Calibration.
