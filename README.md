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

Pre-alpha. The repo currently holds design docs and tooling config; no Swift
code has landed yet. See [`docs/roadmap.md`](docs/roadmap.md) for what ships when.

## Docs

| Doc | What's in it |
| --- | --- |
| [Vision](docs/vision.md) | What the game is, the hook, the design pillars, what it isn't |
| [Design decisions](docs/design-decisions.md) | Every settled decision, and what's still open |
| [Architecture](docs/architecture.md) | Module map, layering rules, why the sim is pure Swift |
| [Domain model](docs/domain-model.md) | Entities, ratings, contracts, the season calendar |
| [Match engine](docs/match-engine.md) | Spatial simulation, the event stream, performance budget, calibration |
| [Play calling](docs/play-calling.md) | Coordinators, gameplan constraints, opponent models, benchmarking |
| [Gameplan](docs/gameplan.md) | The weekly decision surface, rule sets, directives, hypothesis grading |
| [News and narrative](docs/news-and-narrative.md) | Story detection, writers, whimsy, media pressure |
| [Draft and scouting](docs/draft-and-scouting.md) | Biased scouts, the fog, consensus boards, draft day |
| [Contracts](docs/contracts.md) | Structures over numbers, agents, negotiation, failure modes |
| [Traits](docs/traits.md) | The four hook kinds, discovery, and the starter catalogue |
| [Roadmap](docs/roadmap.md) | Milestones M0–M9 with exit criteria |
| [ADRs](docs/adr/) | Architecture decision records |

## Working on this repo

Read [`CLAUDE.md`](CLAUDE.md) first — it covers conventions, the layering rules
that matter most, and how to run things.

## Requirements

- Xcode 16+ / iOS 18+ (SwiftData, Swift 6 concurrency)
- macOS for building the app target; the domain and simulation packages build
  and test on any Swift 6 toolchain
