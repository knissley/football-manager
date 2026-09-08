# Match engine

Lives in `FMSimulation`. Pure, synchronous, deterministic, spatial.

Given a `GameSetup` — two teams, gameplans, sliders, weather, seed — it returns a
`GameResult`: the event stream, the box score derived from it, and per-player grades.

## The engine is spatial

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
  calls          offensive play, defensive call, who chose them (AI or player)
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

**Banned in `FMSimulation` and `FMGeneration`** (CI-enforced): `Int.random`,
`Double.random`, `SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`,
`UUID()`, `Date()`, and any clock or environment read. Iteration order over unordered
collections must never reach output — sort by a stable ID first.

Floating-point determinism across architectures is a real risk here in a way it wasn't
for an abstract engine. Golden tests run on both arm64 and x86_64 in CI, and hot paths
avoid transcendental functions where a cheaper formulation exists.

## Performance budget

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

## Play resolution

### Plays are data

A play is a formation plus a per-player assignment: a route with landmarks and timing,
a blocking rule, a coverage responsibility. The engine reads that format; the play
designer edits it; the premade concept library is authored in it.

Because assignments are data, a designed play needs **validation** — eleven players,
legal formation, every assignment executable — before it reaches the engine. That's a
constraint checker, not a drawing tool, and it's the real cost of the play designer.

### Pass play

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

Blocking assignments resolve into actual displacement; the hole is a real gap between
bodies. The back's vision trait affects which gap he attacks and how quickly he commits.
Tacklers pursue on real angles. Broken tackles chain.

### Special teams

Kick distance and accuracy from ratings, wind, and precipitation; returns resolve as
pursuit geometry like any other play. Blocks and muffs are low-probability branches and
worth keeping — they're memorable.

## Clock, penalties, and AI

- **Clock** rules are explicit states, not approximations. Two-minute warning, spikes,
  kneels, the out-of-bounds rule, and the ten-second runoff all matter most exactly
  where players pay the most attention.
- **Penalties** are drawn per matchup from player `discipline` and coaching, then
  applied with correct accept/decline logic — the engine evaluates both branches and
  takes the better one for the non-penalized team.
- **AI play calling** is a situational policy over down, distance, field position,
  score, time, and opponent tendencies, modulated by coach ratings and gameplan.
  Fourth-down decisions run on expected points, with coach aggression shifting the
  threshold.

Because play calling can be toggled at will, the AI caller is a **headline system** and
has its own design doc: [play-calling.md](play-calling.md). In short — your offensive
coordinator makes the calls inside guardrails your gameplan sets, both sides carry noisy
tendency models of each other built from `PlayRecord` history, the defense never sees
the call, and caller quality is benchmarked against an oracle and against human play
rather than assessed by feel.

## Sliders

Sliders are **league-wide world tuning**, not a personal difficulty dial. Pass
difficulty, injury frequency, pass rush intensity and the rest apply to every team, so
stat leaders, records and the Hall of Fame stay comparable within a career.

Sliders are part of the replay tuple. Calibration targets below are valid **at default
settings only**.

*Open:* whether sliders lock at career creation or records carry their config. See
[design-decisions.md](design-decisions.md#open-questions).

## Calibration

Tuned against `Tools/simharness` — never by playing the app. The harness sims N seasons
headless and emits distributions as JSON; a checked-in target file defines acceptable
ranges and CI fails on drift.

| Metric (per team per season) | Target range |
| --- | --- |
| Points per game | 20–26 |
| Passing yards per game | 200–260 |
| Rushing yards per game | 95–140 |
| Yards per carry | 4.0–4.8 |
| Completion percentage | 61–68% |
| Sack rate (per dropback) | 5.5–8.0% |
| Interception rate (per attempt) | 1.8–2.8% |
| Third-down conversion rate | 36–43% |
| Red zone TD rate | 52–62% |
| Penalties per game (both teams) | 10–14 |
| Turnovers per game (both teams) | 2.2–3.2 |
| Player-games lost to injury | 40–90 |
| **Spread of team win totals (σ)** | **2.6–3.2** |

The last row is the one that encodes "upsets happen and dominant teams dominate." Too
low and the league feels random; too high and every season is decided in August. It is
the single most important number in this table.

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
