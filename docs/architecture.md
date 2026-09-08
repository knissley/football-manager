# Architecture

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

```
FootballManager.xcodeproj          App target — SwiftUI, composition root
│
└── Packages/
    ├── FMCore            Domain types + the event stream types. No dependencies.
    │                     Player, Team, League, Contract, Ratings, Trait, Play,
    │                     PlayRecord, GameResult. All Sendable value types.
    │
    ├── FMRandom          Seeded splittable PRNG. No dependencies.
    │                     The only source of randomness in the sim.
    │
    ├── FMGeneration      World generation. → FMCore, FMRandom
    │                     Names, franchises, rosters, draft classes, seeded rivalries.
    │
    ├── FMSimulation      Spatial match engine + season engine. → FMCore, FMRandom
    │                     Tick loop, play resolution, schedules, playoffs, progression.
    │
    ├── FMAnalysis        The interrogation layer. → FMCore
    │                     Win probability, leverage, player grades, situational splits,
    │                     tendencies, causal summaries. Pure functions over the stream.
    │
    ├── FMNarrative       The whimsy layer. → FMCore, FMAnalysis
    │                     News generation, highlight selection, rivalry state,
    │                     storylines, awards, Hall of Fame. Turns data into voice.
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

## Win probability is shared infrastructure

One model, four consumers ([ADR-0008](adr/0008-win-probability-keystone.md)):

- **Interrogation** — aggregate WP swings by unit and situation to answer "why are we losing"
- **Highlights** — leverage is `|ΔWP|`; the league highlight reel is a sort over it
- **Drama detection** — "playoff spot on the line" is computable by simming the
  remaining schedule and measuring how much a game moves playoff odds
- **AI decisions** — fourth down, two-point conversions, clock management

Build it early. Four of the product's asks collapse into it.

## Layering

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

Swift 6 language mode, strict concurrency throughout. A week's games are independent —
simulate them concurrently, then merge in game-ID order so parallelism cannot change
outcomes.

## Performance discipline

The 60-second season budget ([match engine](match-engine.md#performance-budget)) is
architectural. In `FMSimulation`'s hot loop:

- Flat arrays of `struct`, indexed by slot. No dictionaries, no per-tick allocation.
- No string construction during simulation. Events carry IDs and enums; `FMNarrative`
  renders text later.
- Buffers sized once and reused. No `Array` growth inside a play.
- Trajectory capture is opt-in per game.

A benchmark test guards the budget and fails CI on regression.

## Persistence

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

A 4-team, 4-game league sims a season instantly — use it for tests
([configurable league shape](design-decisions.md#simulation)).

## Tooling

- `Tools/simharness` — headless CLI, sims N seasons, emits calibration JSON.
- `swift-format` with the repo config, enforced in CI.
- CI runs packages on Linux (which mechanically enforces rule 1) and the app on macOS.
