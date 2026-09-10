# Football Manager (working title)

An offline-first American football management sim for iOS. You're the GM and the head
coach: draft and develop players, manage the cap, set the scheme, and call the shots —
or sim a rebuilding season in about a minute.

The hook is **a simulation you can interrogate**. A spatial match engine puts twenty-two
players on a field and lets outcomes emerge from geometry, so when a drive stalls the
game can show you which matchup lost rather than narrating a dice roll.

Everything — leagues, teams, players — is fictional and generated from a seed. No real
names, no licensing entanglements, infinite worlds.

## Status

Pre-alpha, late in milestone M1. Four packages build and test — `FMRandom`, `FMCore`,
`FMGeneration`, `FMSimulation` — with three command-line tools: `playsize`, `worldgen`
and `simharness`. There is no app target, no SwiftUI and no SwiftData yet; that is M4.
World generation and a crude game engine work behind the real `PlayRecord` contract, and
the per-play numbers land, but the rules layer does not yet finish a game correctly — the
fixes are an issue backlog. See [`CLAUDE.md`](CLAUDE.md) for the current state and
[`docs/roadmap.md`](docs/roadmap.md) for what ships when.

## Docs

**Every doc opens with a status line** — `built`, `partly built, sections marked`, or
`designed` — because most of this repository is still design. Inside a partly-built doc,
a section describing work that does not exist yet is labelled `Designed, not built`. The
ADR index carries the same information in an [In the tree](docs/adr/README.md#index)
column, since an ADR's own status is the decision's, not the code's.

| Doc | What's in it |
| --- | --- |
| [Vision](docs/vision.md) | What the game is, the hook, the design pillars, what it isn't |
| [Design decisions](docs/design-decisions.md) | Every settled decision, and what's still open |
| [Architecture](docs/architecture.md) | Module map, layering rules, why the sim is pure Swift |
| [Domain model](docs/domain-model.md) | Entities, ratings, contracts, the season calendar |
| [Match engine](docs/match-engine.md) | Spatial simulation, the event stream, performance budget, calibration |
| [PlayRecord](docs/play-record.md) | The event stream shape — the contract everything downstream reads |
| [Play calling](docs/play-calling.md) | Coordinators, gameplan constraints, opponent models, benchmarking |
| [Gameplan](docs/gameplan.md) | The weekly decision surface, rule sets, directives, hypothesis grading |
| [News and narrative](docs/news-and-narrative.md) | Story detection, writers, whimsy, media pressure |
| [Draft and scouting](docs/draft-and-scouting.md) | Biased scouts, the fog, consensus boards, draft day |
| [Contracts](docs/contracts.md) | Structures over numbers, agents, negotiation, failure modes |
| [Schemes](docs/schemes.md) | Team identity, scheme fit, and the cost of changing |
| [Penalties](docs/penalties.md) | Why flags happen, officiating, accept/decline |
| [Development](docs/development.md) | Breakouts, ceilings, the conservation law, calibration |
| [Traits](docs/traits.md) | The four hook kinds, discovery, and the starter catalogue |
| [Weekly loop](docs/weekly-loop.md) | *Provisional* — a UI probe run against the systems design |
| [Roadmap](docs/roadmap.md) | Milestones M0–M9 with exit criteria |
| [Tools](docs/tools.md) | Command-line tools for inspecting the engine, with example invocations |
| [ADRs](docs/adr/) | Architecture decision records |

## Working on this repo

Read [`CLAUDE.md`](CLAUDE.md) first — it covers conventions, the layering rules
that matter most, and how to run things.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and every pull
request, inside the official `swift:6.2` image, on **x86_64 and arm64** — the golden
tests have to agree on both, because a stored game is re-simulated from its seed and
floating-point drift between architectures would corrupt saved history
([ADR-0003](docs/adr/0003-deterministic-seeded-simulation.md)).

The `test` job gates a merge. It runs everything the *before you push* list in
[`CLAUDE.md`](CLAUDE.md) asks for, and two checks beyond it — the sim lint and a
`worldgen` build, both marked below:

```
swift format lint --strict --recursive --parallel Packages/ Tools/
./scripts/lint-sim.sh                        # beyond the push list
swift test --package-path Packages/FMRandom
swift test -c release --package-path Packages/FMRandom
swift test --package-path Packages/FMCore
swift test --package-path Packages/FMGeneration
swift test --package-path Packages/FMSimulation
swift run --package-path Tools/playsize
swift build --package-path Tools/worldgen    # beyond the push list
```

Note the `--strict` on the format step: without it `swift format lint` reports findings
and still exits 0, so the check could never fail.

The `harness` job is **reporting, not gating**. It runs `simharness --games 400 --seed 7`
on each architecture, uploads the full output as a job artifact, and writes the
calibration table into the job summary. Rows marked `OFF` do not fail the job; making a
row gating is a per-row decision taken in a retune issue.

Branch protection is a repo setting the owner has to enable. The checks to require are
named at the top of the workflow file:

```
test (ubuntu-24.04)
test (ubuntu-24.04-arm)
```

## Requirements

- Xcode 16+ / iOS 18+ (SwiftData, Swift 6 concurrency)
- macOS for building the app target; the domain and simulation packages build
  and test on any Swift 6 toolchain

On Linux, CI uses the official `swift:6.2` image. In a Claude Code web container, or on
a runner that cannot pull that image, install a toolchain with
`./scripts/install-swift.sh` — it picks the x86_64 or aarch64 build to match the machine,
and needs network access to `download.swift.org`.
