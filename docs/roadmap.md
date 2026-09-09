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
- World generation: ✅ names, colleges, players with hidden ceilings and development
  traits, and 53-man rosters with a league talent spread; ✅ franchises — fictional
  cities with regions, nicknames, legible colours, and stadiums whose roof, climate,
  altitude and noise are real simulation input; ✅ draft classes — a three-year college
  pipeline with hidden ceilings, production carrying independent error, red flags, early
  declarations and mean-reverting class strength; ✅ seeded rivalry history — a
  fabricated event log in the same shape lived history will use, folded to intensity with
  decay (`Packages/FMGeneration`).
- ✅ `Tools/worldgen` — inspect any of it from a terminal, no app required.
- ✅ `League`, `Conference`, `Division` assembled to a validated `LeagueShape`, with a
  second validator for a legal shape filled in wrongly.
- ✅ Team identity event-sourced, so a replay shows the name and the building of the
  time rather than the ones a rebrand has since given the team.
- The `GameSimulator` game-state machine — clock, downs, possession, scoring, penalties,
  overtime — written once and shared with M5's spatial resolver
  ([ADR-0012](adr/0012-play-resolver-seam.md)).
- `DepthChart` with real rotation by position group, so every snap credits a real player
  and backups accumulate genuine statistics.
- ✅ A crude matchup-lite `PlayResolver` emitting real participants and decision points,
  with the internal-consistency constraints from ADR-0012 asserted as tests.
- ✅ `GameSimulator`, the shared game-state machine, and a baseline caller on both sides.
- Injury availability — a player can go down and miss weeks. Severity stays in M3.
- ✅ `Tools/simharness` running headless and reporting the calibration table.
- ✅ Configurable, validated league shape with 8- and 12-team test presets.
- ✅ `SituationClass` — the shared situational vocabulary both callers, the gameplan
  layer and analysis key off ([play-calling.md](play-calling.md#situational-football)).
- ✅ `DefensiveCall` — the defensive call as composed data, so defense is first-class in
  the model before either caller is written.

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

## Designed but not yet in the engine

An audit of the crude resolver found it reads `runFit` and the weather on a kick, and
nothing else. These are systems that exist, are designed and in several cases fully
tested, and that the engine has never consulted. Recorded here so they are deferred
deliberately rather than forgotten.

**Landing before M2**, because M2's analysis and narrative are built on this stream and
would otherwise be built against a league missing them:

- Endgame clock — spikes, kneels and timeouts. The clock rules underneath are already
  correct and tested; the caller has never learned to use them, so a two-minute drill
  cannot currently be played properly.
- Penalties. Enforcement and accept/decline are built and tested; **zero are ever drawn**.
  Unlocks a calibration row, the `discipline` rating, crowd noise as the home-field
  mechanism [penalties.md](penalties.md) describes, and a category of news.
- Injury availability, already agreed for M1.
- Kick and punt returns. Every kickoff is a touchback and every punt a fair catch.
- Traits, as engine hooks rather than cosmetic modifiers.
- Crowd noise and stadium; weather beyond the kicking game.

**Deferred to M5, and still needed** — these want the spatial engine to be meaningful, not
merely to be wired up:

- `CallVulnerability`. Every defensive call is designed to give something up, and the
  resolver never asks what. Without geometry there is no honest way to make a soft spot
  actually soft.
- `SchemeExperience`. Coordinator familiarity decaying and rebuilding is a season-scale
  mechanic that needs a season loop to mean anything.
- Coordinator quality. Both callers are currently the same hardcoded pair of identifiers,
  so every team in the league calls plays identically. The real caller and its
  benchmark are [play-calling.md](play-calling.md)'s work.
- Personnel groups and defensive packages. The resolver fields the same eleven regardless
  of what the situation says is on the field.
- Stamina and fatigue within a game.

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

- The play format: formations, assignments, routes, blocking rules, coverages. The
  offensive playbook entry — the `PlayDesign` — lands here; it should read like
  `DefensiveCall` already does, and until then `OffensiveCall.design` points at a
  playbook that does not exist.
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
