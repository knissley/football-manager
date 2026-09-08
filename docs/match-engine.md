# Match engine

Lives in `FMSimulation`. Pure, synchronous, deterministic. Given a `GameSetup`
(two teams, gameplans, weather, seed) it returns a `GameResult` containing the full
play-by-play, the box score, and per-player grades.

## Shape of the loop

Discrete event simulation, one play at a time.

```
while !gameOver {
    let situation  = Situation(state)                 // down, distance, clock, score
    let offCall    = offense.selectPlay(situation)    // AI or user gameplan
    let defCall    = defense.selectCall(situation)
    let pre        = resolvePrePlayPenalty(...)       // false start, encroachment
    let outcome    = resolve(offCall, defCall, ...)   // the interesting part
    let post       = resolvePostPlayPenalty(...)      // holding, PI, facemask
    state.apply(outcome, penalties: [pre, post])
    state.runClock(for: outcome)
    log.append(PlayRecord(situation, offCall, defCall, outcome))
}
```

`GameState` is the whole world: quarter, clock, down, distance, ball position,
possession, score, timeouts remaining per team, weather, and per-player fatigue and
in-game injury status.

## Play resolution

The core idea: **resolve a play as a sequence of matchups, not as a single roll.**
A dice roll against team ratings gives you a number; a chain of matchups gives you a
*story* — which lineman lost, which receiver won, who missed the tackle — and that
story is what pillar 2 of the [vision](vision.md#design-pillars) is built on.

### Pass play

1. **Protection.** Each pass rusher is matched against a blocker (per the protection
   scheme and the defense's call). Each matchup resolves to a time-to-win drawn from
   a distribution shaped by `powerMove`/`finesseMove` vs `passBlock`/`blockAnchor`.
   The earliest win is the pressure clock.
2. **Route progression.** Each receiver's separation at each timing window is drawn
   from `routeRunning` + `acceleration` + release vs the assigned defender's
   `manCoverage`/`zoneCoverage` + `agility`, adjusted for the coverage shell.
3. **Decision.** The QB reads the progression, gated by `awareness` and `underPressure`
   against the pressure clock: throw to the best available window, check down, scramble,
   throw it away, or take the sack.
4. **Accuracy.** Ball placement drawn from the depth-appropriate accuracy rating,
   degraded by pressure and weather.
5. **Catch.** `catching`/`catchInTraffic` vs placement, separation, and the defender's
   `ballHawk`. Resolves to catch, incompletion, drop, contested catch, or interception.
6. **YAC.** If caught in space: `elusiveness`/`breakTackle` vs pursuit angles and
   `tackling` from the nearest defenders, drawn from a heavy-tailed distribution so
   the occasional 70-yard catch-and-run exists.
7. **Turnover checks.** Strip-sack on a sack; fumble on a completed catch.

### Run play

1. **Point of attack.** The blocking scheme (zone/gap) assigns matchups; each
   resolves to a win, stalemate, or loss, producing a *hole quality* score.
2. **Yards before contact** drawn from a distribution scaled by hole quality and the
   defense's box count vs the offense's personnel.
3. **Tackle attempts.** Sequential: each pursuing defender gets a chance, `tackling` +
   `pursuit` vs `breakTackle` + `elusiveness`. Broken tackles chain into more yards
   and re-roll against the next level.
4. **Fumble check**, weighted by `carrying`, hit power, and weather.

### Special teams

- **Field goal** — probability from distance, `kickPower` (max range), `kickAccuracy`,
  wind, precipitation, and a small snap/hold failure rate.
- **Punt** — distance and hang time from `puntPower`/`puntAccuracy`, then a returner
  matchup for the return, with coffin-corner and touchback handling.
- **Kickoff** — touchback rate from `kickPower`; returns resolve like punt returns.
- Blocks and muffs are low-probability branches, not ignored — they're memorable.

## Clock model

Getting the clock wrong makes late-game situations feel fake, which is exactly where
players pay the most attention.

- Incompletion and out-of-bounds (in the last two minutes of a half) stop the clock.
- In-bounds plays run 4–7s of live action, then 25–40s of play clock depending on the
  offense's tempo setting and situation.
- Two-minute warning, timeouts, spikes, kneel-downs, and the ten-second runoff are
  explicit states, not approximations.
- The AI's clock management is coach-rated: a bad coordinator burns timeouts early
  and lets the clock run when trailing. This is intentional and observable.

## Penalties

A layer around resolution rather than an outcome type, because penalties can negate
a play. Pre-snap (false start, encroachment, delay) modify the situation and re-run.
Post-snap (holding, pass interference, facemask, roughing) are drawn per matchup with
rates influenced by player `discipline` and coach ratings, then applied with correct
accept/decline logic — the sim evaluates both branches and takes the better one for
the non-penalized team.

## AI play calling

A situational policy, not a neural net.

Inputs: down, distance, field position, score differential, time remaining, timeouts,
opponent tendencies, and the team's gameplan. Output: a play family and personnel.

Baseline behavior comes from a situation table (a run/pass/deep/screen distribution
per down-distance-field-position bucket), then gets modulated by the coach's
aggression, scheme identity, and their read of the matchup. Fourth-down decisions run
an expected-points calculation, with the coach's aggression rating shifting the
threshold — a conservative coach punts from the 38 on 4th-and-2 and you get to be mad
about it.

## Determinism

The engine takes a single `seed: UInt64` and constructs a `SplittableRandom` from it.
Every random draw in the game comes from that generator or a child split off it.

Splitting is per-play, derived from `(gameSeed, playIndex)`. This means play *N*
resolves identically regardless of what was simulated before it in the same process,
which makes debugging a specific play possible without replaying the whole game.

**Banned in `FMSimulation` and `FMGeneration`** (enforced by a CI lint):
`Int.random`, `Double.random`, `SystemRandomNumberGenerator`, `.shuffled()`,
`.randomElement()`, `UUID()`, `Date()`, and anything reading the clock or environment.

## Quick sim

Watching drive-by-drive is the headline experience; simming the other 15 games of the
week is not. But **quick sim runs the same engine** — it just skips the per-play
narration and event emission and retains only the box score.

We do *not* write a second, statistical fast path. Two engines means two sets of
balance and two sets of bugs, and players notice when the game they watched behaves
differently from the games they didn't. If full-fidelity week simulation turns out to
be too slow on target hardware, the fix is to profile and optimize the one engine, and
that decision gets its own ADR.

Performance budget: a full week of 16 games in **under 2 seconds** on an iPhone 13,
simulated concurrently, merged deterministically by game ID.

## Calibration

The engine is tuned against a headless harness (`Tools/simharness`), never by playing
the app. The harness sims N seasons and emits aggregate distributions as JSON;
a checked-in target file defines acceptable ranges and CI fails if the engine drifts
out of them.

Targets to hit at the league level (per team per season unless noted):

| Metric | Target range |
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
| Games lost to injury per team | 40–90 |
| Spread of team win totals (σ) | 2.6–3.2 |

The last row matters most and is the easiest to get wrong: if the standard deviation
of win totals is too low, the league feels random and roster building doesn't matter;
too high and every season is decided in August.

Also checked: the best players lead the league (a top-5 QB should finish top-10 in
passing yards most seasons), and no single strategy dominates — a run-heavy roster and
a pass-heavy roster of equal talent should win the same number of games within noise.

## Build order

Match the [roadmap](roadmap.md). Get an end-to-end skeleton producing plausible
scorelines before deepening any single subsystem — a crude complete engine can be
calibrated and played; a beautiful pass-rush model attached to nothing cannot.

1. Game loop, clock, downs, scoring. Play outcomes from a placeholder distribution.
2. Run and pass resolution from real matchups.
3. Special teams.
4. Penalties, injuries, fatigue.
5. AI play calling and fourth-down logic.
6. Calibration pass against the table above.
