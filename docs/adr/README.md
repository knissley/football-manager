# Architecture Decision Records

Short documents capturing decisions that are expensive to reverse, and *why* we made
them — so that six months from now nobody re-litigates a settled question from scratch,
and when we do reverse one, we know what we're giving up.

## When to write one

Write an ADR when a decision:

- is hard to undo later (persistence layer, module boundaries, determinism guarantees),
- will confuse someone who wasn't in the room,
- was made after considering a real alternative, or
- overturns a previous ADR.

Don't write one for a naming choice, a library version bump, or anything you'd happily
change on a whim.

## How

Copy [`TEMPLATE.md`](TEMPLATE.md) to `NNNN-short-title.md` with the next number.
Or ask Claude: `/adr <the decision>`.

ADRs are immutable once accepted. To change a decision, write a new ADR that supersedes
the old one and update the old one's status line to point at it.

**One exception, already spent:** ADRs 0002–0005 were drafted on 2026-09-08 as a
strawman, before the game's design existed. They were revised once later the same day
to reflect the decisions actually made in scoping (see
[design-decisions.md](../design-decisions.md)). From that point they are immutable like
any other.

## Index

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-swiftdata-offline-first.md) | SwiftData, offline-first, no backend | Accepted |
| [0003](0003-deterministic-seeded-simulation.md) | Deterministic seeded simulation | Accepted |
| [0004](0004-pure-swift-domain-core.md) | Pure Swift domain core, isolated from frameworks | Accepted |
| [0005](0005-generated-fictional-content.md) | Generated fictional players and teams | Accepted |
| [0006](0006-spatial-simulation.md) | Spatial simulation over an abstract outcome model | Accepted |
| [0007](0007-event-stream-contract.md) | The play event stream is the engine's public contract | Accepted |
| [0008](0008-win-probability-keystone.md) | Win probability as shared infrastructure | Accepted |
| [0009](0009-event-sourcing-by-default.md) | Event sourcing as the default state model | Accepted |
| [0010](0010-plays-designs-and-calls.md) | Distinguish play designs, calls, and plays | Accepted |
| [0011](0011-derived-identity-for-regenerable-streams.md) | Derive identity for regenerable event streams | Accepted |
| [0012](0012-play-resolver-seam.md) | Separate the play resolver from the game-state machine | Accepted |
