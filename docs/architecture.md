# Architecture

**Status: partly built, sections marked.** Four of the nine modules in the map below
exist — `FMCore`, `FMRandom`, `FMGeneration`, `FMSimulation`, the last of them shipping
`FMSimulationScenarios` alongside it — and the two rules are enforced today. There is no
app target, no SwiftUI, no SwiftData, and no `FMAnalysis`, `FMNarrative`,
`FMPersistence` or `FMUI`. Sections describing those carry a
`Designed, not built` label.

## Two rules

**1. The simulation never imports SwiftData, SwiftUI, or UIKit.**
The domain model and engine are plain Swift value types. Pure, deterministic, testable,
and buildable on any Swift 6 toolchain — which is what makes headless calibration
possible. ([ADR-0004](adr/0004-pure-swift-domain-core.md))

**2. Everything downstream reads the event stream.**
The engine emits typed play events. Box scores, grades, news, highlights, tendencies
and the causal breakdown are all *queries* over that stream. Nothing accumulates
statistics in parallel with it. ([ADR-0007](adr/0007-event-stream-contract.md))

Rule 2 is what makes the engine safe to deepen. A crude engine and the eventual spatial
one emit the same events, so everything above them is written once, early, against a
contract that doesn't move.

## Module map

**Four of these exist**, and `FMSimulationScenarios` with them. `FMCore`, `FMRandom`,
`FMGeneration` and `FMSimulation` are built and green. The app target, `FMUI` and
`FMPersistence` are M4; `FMAnalysis` and `FMNarrative` are M2. The rest of this map is
the shape they get built to, not a description of the tree — check `Packages/` before
assuming a module is there.

```
FootballManager.xcodeproj          App target — SwiftUI, composition root
│
└── Packages/
    ├── FMCore            Domain types + the event stream types. No dependencies.
    │                     Player, Team, League, Contract, Ratings, PlayRecord,
    │                     OffensiveCall, DefensiveCall. All Sendable value types.
    │                     (`GameResult` is FMSimulation's; a trait is a `TraitID`
    │                     and a play design is M6 — neither is a type yet.)
    │
    ├── FMRandom          Seeded splittable PRNG. No dependencies.
    │                     The only source of randomness in the sim.
    │
    ├── FMGeneration      World generation. → FMCore, FMRandom
    │                     Names, rosters, draft classes, seeded rivalries — and the
    │                     thirty-two curated franchises a world starts from, which
    │                     are a table rather than a draw (FranchiseSet).
    │                     One entry point:
    │                     WorldGenerator.generate(seed:shape:franchises:season:).
    │
    ├── FMSimulation      Match engine + season engine. → FMCore, FMRandom
    │                     `GameSimulator` drives the sport's rules and asks a
    │                     `PlayResolver` what happened on each snap (ADR-0012).
    │                     Schedules, playoffs, progression, and the AI play-caller
    │                     on both sides (see docs/play-calling.md).
    │                     Built: the match engine and both callers. The season
    │                     half — schedules, playoffs, progression — is M3.
    │
    ├── FMSimulationScenarios
    │                     The rules-conformance scenarios, as scripted games.
    │                     → FMSimulation, FMCore, FMGeneration, FMRandom
    │                     A second library of the FMSimulation package: `Snap`,
    │                     `ScriptedGame`, `Trace`, `ScenarioWorld` and the scenarios
    │                     themselves, with `RulesScenario` naming each one. The
    │                     conformance suite asserts over them and `gamelog --scenario`
    │                     prints them — same game, same printer. A plain FM* module:
    │                     the assertions stay in the test target, which is the only
    │                     place that may import Swift Testing.
    │
    ├── FMAnalysis        The interrogation layer. → FMCore
    │                     Win probability, leverage, player grades, situational splits,
    │                     tendencies, causal summaries. Pure functions over the stream.
    │
    ├── FMNarrative       The whimsy layer. → FMCore, FMAnalysis
    │                     Writers, news rendering, storylines, ceremonies.
    │                     Turns Findings into voice. A pure leaf: nothing depends on it.
    │
    ├── FMPersistence     SwiftData models + mapping. → FMCore
    │                     The ONLY module that knows SwiftData exists.
    │
    └── FMUI              Shared SwiftUI components. → FMCore
                          Design system, field view, rating displays.
```

Dependencies point one way. `FMCore` and `FMRandom` depend on nothing.

`FMAnalysis` and `FMNarrative` are separate modules because the hook demands it: the
interrogation layer is product, not a reporting afterthought, and keeping narrative
downstream of analysis means the news is generated *from* measured facts rather than
invented alongside them.

The split is load-bearing in one specific place. Media coverage feeds owner patience and
so the coaching carousel — but the signal the owner reads is `MediaPressure`, a *metric
computed in `FMAnalysis`*, never something `FMNarrative` produces. Otherwise
`FMSimulation` would depend on prose generation to decide whether you get fired.
`FMNarrative` renders and nothing depends on it. See
[news-and-narrative.md](news-and-narrative.md#media-pressure-feeds-owner-expectations-carefully).

## Generation describes the world; simulation changes it

`FMGeneration` runs **once, at world creation**. It answers "what does this league
look like on day one" — franchises, rosters, staff, a draft class, plausible
history. Nothing it contains is a rule about how the world should behave
afterwards. Not all of it is generated: the franchises are curated data
([decision 215](design-decisions.md#world-generation)) and only what a career is
played *with* is drawn from the seed.

Everything after day one is `FMSimulation`: games, development, and every roster
transaction, including the ones AI teams make.

The boundary is worth stating explicitly because the two will look temptingly
similar. Both want a roster with good starters and useful depth. But generation
gets there by *assigning* — it knows every hidden value and simply writes them
down — while an AI team has to get there the hard way, under a cap, from noisy
estimates, through choices it can get wrong. An AI that reused generation's
heuristics would be handing itself outcomes instead of earning them, and every
trade and draft it made would be theatre.

There is exactly one way in: `WorldGenerator.generate(seed:shape:franchises:season:)`
returns the league, its teams, their rosters and depth charts, the colleges, the draft
pipeline and
the rivalries. Every tool and every game-building test calls it, so the league the harness
calibrates against is the league the tool prints and the league the tests play in.

So they share a *target* — `RosterShape`, which lives in `FMCore` — and no
mechanism at all. If AI roster management ever needs a function from
`FMGeneration`, that is the signal something has gone wrong.

## Win probability is shared infrastructure

**Designed, not built.** M2. Nothing computes win probability today.

One model, four consumers ([ADR-0008](adr/0008-win-probability-keystone.md)):

- **Interrogation** — aggregate WP swings by unit and situation to answer "why are we losing"
- **Highlights** — leverage is `|ΔWP|`; the league highlight reel is a sort over it
- **Drama detection** — "playoff spot on the line" is computable by simming the
  remaining schedule and measuring how much a game moves playoff odds
- **AI decisions** — fourth down, two-point conversions, clock management

Build it early. Four of the product's asks collapse into it.

## Layering

**Designed, not built above the sim.** The bottom two rows exist; there are no views,
no stores and no services, and there will not be until M4. The rules are here so the
first screen is written to them.

```
Views (SwiftUI)                  Render state, send intent. No football logic.
Stores (@Observable @MainActor)  Own screen state, orchestrate.
Services                         Bridge async work to the sim; own save cadence.
FMSimulation / FMAnalysis /      Pure. Synchronous. No I/O.
  FMNarrative / FMGeneration
FMPersistence · FMCore
```

- If a SwiftUI view has an `if` that decides something about football, it's in the
  wrong layer.
- Simulation is synchronous and pure. If it needs to report something, it returns it.
- The main actor only ever sees finished value types.

## Concurrency

Swift 6 language mode, strict concurrency throughout — that part is enforced today.

*Designed, not built:* a week's games are independent, so they will be simulated
concurrently and merged in game-ID order, which is what stops parallelism changing
outcomes. Nothing sims a week yet; the season loop is M3.

## Performance discipline

The 60-second season budget ([match engine](match-engine.md#performance-budget)) is
architectural. In `FMSimulation`'s hot loop:

- Flat arrays of `struct`, indexed by slot. No dictionaries, no per-tick allocation.
- No string construction during simulation. Events carry IDs and enums; `FMNarrative`
  renders text later.
- Buffers sized once and reused. No `Array` growth inside a play.
- Trajectory capture is opt-in per game.

**Designed, not built.** The hot loop the rules above describe is the M5 tick loop, and
nothing in the tree runs one. There is no benchmark target and no CI step that fails on a
timing regression — CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) runs
the suites, the two lints and the harness — and nothing gates on the budget. Since H3
(#9), `simharness` times its simulate loop and prints a `Budget` block that the job
summary carries: a number to read, not a gate.

## Persistence

**Designed, not built.** M4. No `FMPersistence`, no `@Model` class and no store exists;
nothing is written to disk today.

SwiftData, one on-device store ([ADR-0002](adr/0002-swiftdata-offline-first.md)), with
explicit mapping between `FMCore` structs and `@Model` classes in `FMPersistence`.

**What gets stored:**

| Data | Retention |
| --- | --- |
| Your games | Full event stream, current season |
| Other teams' games | Box score + replay tuple `(state, seed, sliders, decisions)` |
| Past seasons | Box scores and aggregates; games replayable from tuple |
| Career/season/player stats | Forever — records and the Hall of Fame depend on it |

Replay-from-tuple is why determinism is load-bearing rather than merely convenient.

## Testing

**Partly built.** The `FMCore`, `FMRandom`, `FMGeneration` and `FMSimulation` rows exist
today, minus the perf benchmark. The `FMAnalysis`, `FMPersistence` and UI rows describe
suites for modules that do not exist yet.

| Layer | How |
| --- | --- |
| `FMCore` | Value semantics, cap math, depth chart and play validity |
| `FMRandom` | Known-answer tests — a fixed seed's sequence never changes |
| `FMSimulation` | Golden-seed box scores + statistical tests + a perf benchmark |
| `FMAnalysis` | Known-input tests on WP and grades; monotonicity properties |
| `FMGeneration` | Distribution tests on generated talent |
| `FMPersistence` | Round-trip: `FMCore` → `@Model` → `FMCore` is identity |
| UI | Snapshot tests on the design system; XCUITest on week-advance only |

Golden-seed tests are the tripwire for accidental behavior drift. Regenerate them only
when behavior changed on purpose, in the same commit, with the diff reviewed.

Use the smallest league shape that still exercises what a test is about
([`LeagueShape`](../Packages/FMCore/Sources/FMCore/LeagueShape.swift)):
`.minimal` (8 teams) for scheduling and brackets, `.compact` (12 teams) for
anything touching standings — with only two teams in a division, most tiebreaker
rules never fire.

## Tooling

- `Tools/simharness` — headless CLI, sims N games and prints the calibration table.
- `Tools/worldgen` — inspect generated content from a terminal; `Tools/playsize` —
  play-record footprint, and the proof the `FM*` modules link without a framework.
- [`scripts/lint-sim.sh`](../scripts/lint-sim.sh) — the banned primitives from ADR-0003
  and the framework ban from ADR-0004, enforced as a script.
- [`scripts/lint-reference.sh`](../scripts/lint-reference.sh) — rule 8 and half of rule 10,
  enforced as a script: ten-word runs the tree shares with the rulebook, and article
  numbers in the reference documents that name no article. It needs a corpus from outside
  the tree and skips without one; its self-test ships an invented one and runs in CI.
- `swift-format` with the repo config, enforced in CI as `swift format lint --strict`
  (without `--strict` the linter reports findings and exits 0).
- CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) runs the packages on
  Linux — which mechanically enforces rule 1 — on both x86_64 and arm64. The macOS leg
  for the app target lands with the app target.
