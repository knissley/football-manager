# Architecture

## The one rule

**The simulation never imports SwiftData, SwiftUI, or UIKit.**

The domain model and the match engine are plain Swift value types in a local Swift
package. They are pure functions over state: given a world and a seed, they produce
a season. That makes them deterministic, trivially testable, fast to iterate on
(a headless harness can sim 10,000 seasons without launching a simulator), and
buildable on any Swift toolchain — including Linux CI.

Persistence and UI are adapters *around* that core, not something it knows about.
Rationale in [ADR-0004](adr/0004-pure-swift-domain-core.md).

## Module map

```
FootballManager.xcodeproj          App target — SwiftUI entry point, composition root
│
└── Packages/
    ├── FMCore            Domain types. No dependencies.
    │                     Player, Team, League, Contract, Ratings, Season,
    │                     DepthChart, Scheme. All Sendable value types.
    │
    ├── FMRandom          Seeded, splittable PRNG. No dependencies.
    │                     The only source of randomness anywhere in the sim.
    │
    ├── FMGeneration      World generation. → FMCore, FMRandom
    │                     Names, leagues, franchises, initial rosters, draft classes.
    │
    ├── FMSimulation      Match engine + season engine. → FMCore, FMRandom
    │                     Play resolution, drives, games, schedules, playoffs,
    │                     progression, injuries.
    │
    ├── FMPersistence     SwiftData models + mapping. → FMCore
    │                     @Model classes and translation to/from FMCore types.
    │                     The ONLY module that knows SwiftData exists.
    │
    └── FMUI             Shared SwiftUI components. → FMCore
                          Design system, rating bars, position badges, field views.
```

Dependency arrows point one way. `FMCore` and `FMRandom` depend on nothing.
Nothing depends on the app target.

### Why `FMRandom` is its own module

Determinism is a promise we make to players and a tool we use for testing, and it
only holds if there is exactly one way to get a random number. A separate module
makes the rule enforceable: a lint check fails the build if `Int.random`,
`SystemRandomNumberGenerator`, `shuffled()`, or `UUID()` appears anywhere under
`FMSimulation` or `FMGeneration`.

## Layering

```
┌───────────────────────────────────────────────┐
│  Views (SwiftUI)                              │  Dumb. Render state, send intent.
├───────────────────────────────────────────────┤
│  Stores (@Observable, @MainActor)             │  Own view state, orchestrate.
├───────────────────────────────────────────────┤
│  Services                                     │  GameService, SimulationService,
│                                               │  RosterService. Bridge async work
│                                               │  to the sim, own the save cadence.
├───────────────────────────────────────────────┤
│  FMSimulation / FMGeneration                  │  Pure. Synchronous. No I/O.
├───────────────────────────────────────────────┤
│  FMPersistence (SwiftData)  ·  FMCore         │
└───────────────────────────────────────────────┘
```

- **Views** hold no business logic. If a view has an `if` that decides a game rule,
  it belongs in the sim.
- **Stores** are `@Observable` and `@MainActor`. One per screen or feature area.
  They expose read-only state and `func` intents.
- **Services** are `actor`s or plain `Sendable` types. They run simulation work off
  the main actor and hand back value types.
- **Simulation** is synchronous and pure. It never awaits, never touches disk, never
  logs. If it needs to report something, it returns it.

## Concurrency

Swift 6 language mode, strict concurrency on, everywhere.

- All `FMCore` types are `Sendable` (they're value types; this should be free).
- Simulating a week runs on a background executor. A full week of games is
  independent per game — sim them concurrently, then merge results deterministically
  by sorting on game ID before applying, so parallelism can't change the outcome.
- The main actor only ever sees finished value types.

## Persistence

SwiftData, one store, on-device. See [ADR-0002](adr/0002-swiftdata-offline-first.md).

The mapping between `FMCore` structs and `@Model` classes is explicit and lives in
`FMPersistence`. This is deliberate boilerplate: it keeps schema-migration concerns
out of the domain model and lets the sim's types change freely between milestones
without a migration each time.

Save cadence: after every week advance, and on scene phase change to background.
A career is one `SaveGame` root object; multiple careers can coexist.

**Careful with size.** A 10-season career with full play-by-play retained is large.
Play-by-play is retained for the current season only; older seasons keep box scores
and aggregated stats. Revisit if profiling says otherwise.

## Testing strategy

| Layer | How it's tested |
| --- | --- |
| `FMCore` | Unit tests on value semantics, cap math, depth chart validity |
| `FMRandom` | Known-answer tests — a fixed seed produces a fixed sequence, forever |
| `FMSimulation` | Golden-seed tests (a seeded season's box score is checked in and must not drift) + statistical tests over many seeds |
| `FMGeneration` | Distribution tests — generated leagues have plausible talent spread |
| `FMPersistence` | Round-trip tests: `FMCore` → `@Model` → `FMCore` is identity |
| UI | Snapshot tests on the design system; XCUITest for the week-advance happy path only |

Golden-seed tests are the tripwire for accidental behavior changes. When the engine
changes on purpose, the golden file is regenerated in the same commit and the diff
is reviewed as part of the change — never regenerated to make a red test go away.

## Tooling

- `Tools/simharness` — a Swift CLI that sims N seasons headless and emits stats as
  JSON. This is how balance work gets done; do not tune the engine by playing the app.
- `swift-format` with the config in `.swift-format`, enforced in CI.
- CI runs on macOS for the app target; package tests also run on Linux to keep the
  core honest about its dependencies.
