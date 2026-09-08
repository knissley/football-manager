# Football Manager (working title)

An offline-first American football management sim for iOS. You run a franchise:
draft and develop players, manage the salary cap, set your scheme and gameplan,
and watch games play out drive by drive over a multi-season career.

Everything — leagues, teams, players — is fictional and procedurally generated
from a seed. No real names, no licensing entanglements, infinite worlds.

## Status

Pre-alpha. The repo currently holds design docs and tooling config; no Swift
code has landed yet. See [`docs/roadmap.md`](docs/roadmap.md) for what ships when.

## Docs

| Doc | What's in it |
| --- | --- |
| [Vision](docs/vision.md) | What the game is, who it's for, the design pillars, what it deliberately isn't |
| [Architecture](docs/architecture.md) | Module map, layering rules, why the sim is pure Swift |
| [Domain model](docs/domain-model.md) | Entities, ratings, contracts, the season calendar |
| [Match engine](docs/match-engine.md) | Play-by-play simulation design, resolution model, calibration |
| [Roadmap](docs/roadmap.md) | Milestones M0–M9 with exit criteria |
| [ADRs](docs/adr/) | Architecture decision records |

## Working on this repo

Read [`CLAUDE.md`](CLAUDE.md) first — it covers conventions, the layering rules
that matter most, and how to run things.

## Requirements

- Xcode 16+ / iOS 18+ (SwiftData, Swift 6 concurrency)
- macOS for building the app target; the domain and simulation packages build
  and test on any Swift 6 toolchain
