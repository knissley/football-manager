# Roadmap

Ordered by dependency and by risk, not by calendar. The shape follows one idea: **fix
the event stream contract early, then deepen the engine behind it.** Everything above
the engine — analysis, news, UI — is written once against a contract that doesn't move.

## M0 — Design foundation ✅

Docs, CLAUDE.md, project skills, ADR practice, twenty scoping decisions recorded in
[design-decisions.md](design-decisions.md).

*Exit:* a contributor can read the docs and know what the game is and where code goes.

## M1 — The stream and a living world

`FMCore`, `FMRandom`, `FMGeneration`, and a deliberately crude `FMSimulation`.

- ✅ Typed IDs, positions, ratings; contracts and cap arithmetic.
- ✅ `SplittableRandom` with known-answer tests (`Packages/FMRandom`).
- ✅ **The `PlayRecord` event stream shape** — the most important design work in the
  project (`Packages/FMCore`, specified in [play-record.md](play-record.md)).
- World generation: ✅ names and colleges (`Packages/FMGeneration`); franchises,
  rosters, draft classes and seeded rivalry history still to come.
- A crude outcome engine that emits real event shapes and plausible scorelines.
- `Tools/simharness` running headless.
- Configurable league shape, with a 4-team league for fast tests.

*Exit:* `generateWorld(seed:)` is reproducible byte-for-byte, a season sims headless,
and the event stream carries everything M2 needs without changes.

## M2 — Analysis and narrative

`FMAnalysis` and `FMNarrative`. This is where the hook becomes real, and it validates
the contract before the expensive engine work starts.

- **Win probability** — the keystone ([ADR-0008](adr/0008-win-probability-keystone.md)).
- Leverage, player grades, situational splits, team tendencies.
- Causal summaries: why a drive stalled, why a unit is underperforming.
- League news, highlight selection, rivalry intensity that grows from results.

*Exit:* over a simulated season, the highlight reel surfaces genuinely notable plays,
the news reads like a league is happening, and "why is my run defense bad" has an
answer derived entirely from the stream.

## M3 — Season and career

- Schedule generation, standings with correct tiebreakers, playoff seeding and bracket.
- Injuries, fatigue, rest across a season.
- Offseason skeleton: retirements, camp progression.
- Coaching carousel: reputation, firing, AI hiring, applying elsewhere.

*Exit:* a ten-season career runs headless with no invariant violations, and win-total
spread lands in the calibration range.

## M4 — First playable

App target, `FMUI`, `FMPersistence`. The first build that is a game.

- Team hub, roster, player detail, depth chart, schedule, standings, news feed.
- Watch a game as an event feed with the analysis layer attached.
- Week advance; SwiftData save/load with round-trip tests.

*Exit:* install on a phone, start a career, play a season, background and resume without
loss.

## M5 — The spatial engine

The big technical risk, taken once the contract and everything above it are proven.

- Tick loop, field geometry, 22 entities, assignment execution.
- Dropback passing with real pressure, separation, and reads — same events out.
- Run game, special teams, penalties.
- 2D field view rendering engine state directly.
- Replay from `(state, seed, sliders, decisionLog)`, with scrubbing.
- **Performance budget enforced by benchmark**: a season in ~60s.

*Exit:* the spatial engine passes the same golden and statistical tests as the crude
one, hits the budget, and a replayed game is identical to its original.

## M6 — Plays as data

- The play format: formations, assignments, routes, blocking rules, coverages.
- Validation — eleven players, legal formation, executable assignments.
- The premade concept library, authored in the format.
- The play designer.

*Exit:* a play drawn in the designer runs in a game, and its results are indistinguishable
in kind from an authored concept.

## M7 — The GM half

- Contracts: extensions, restructures, cuts with dead-money preview.
- Salary cap enforcement everywhere.
- Free agency with AI bidding; real negotiation with agent reservation values.
- Draft: scouting with genuine fog, a draft board, AI teams that pick sensibly.
- Trades with a valuation model that can refuse, and can beat you.

*Exit:* three AI-only offseasons produce cap-legal rosters, teams that draft well get
better, and a human tester cannot reliably fleece the trade AI.

## M8 — Texture

- Traits with real engine hooks, good and bad, with personality.
- Development: role, playing time, mentorship as nudges.
- Awards, records, league leaders, Hall of Fame ceremonies.
- Draft storylines, random league events, franchise history.
- Sliders UI.

*Exit:* a ten-season career review reads like a history worth screenshotting.

## M9 — Polish and beta

Onboarding, VoiceOver and Dynamic Type, haptics, performance pass, save-size audit,
TestFlight.

## Why this order

- **The contract comes before the engine** so nothing above it gets rewritten.
- **Analysis before the spatial engine** proves the hook is achievable and makes the
  crude engine's output immediately interesting.
- **A playable app at M4**, before the hardest work, so there's something to react to.
- **The spatial engine at M5** is the biggest risk; by then it's the only unknown left
  and it slots in behind a proven contract.
- **The GM half after the engine** because the engine is the hook and the thing that
  makes roster decisions legible.

## Deferred

Online leagues, iPad and Mac layouts, custom league import, 3D visualization.
