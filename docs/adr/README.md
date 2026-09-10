# Architecture Decision Records

**Status: built** — the practice is in use and thirteen records exist.

An ADR records a **decision**, not a build state. Its `**Status:**` line is the
decision's status — `Accepted`, or superseded by a later record — and it stays accepted
whether or not a line of code has been written. Because an ADR's body is immutable (see
below), the build state cannot live inside it, so the index at the end of this file
carries an **In the tree** column instead. That column is the one thing here that is
allowed to go stale, so it is checked against `Packages/` and `Tools/` rather than
against another doc.

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

## Amending, and reversing

The **body** of an accepted ADR is immutable. Context, decision, consequences and
alternatives record what was decided and what it was weighed against; rewriting them to
match what we now know destroys the only record of the reasoning.

Two edits are permitted:

- **A dated `Amendment` section, appended at the end**, one per amendment. Use it when
  practice taught something the original could not have known — a way the decision got
  broken, a case it did not cover, a consequence that landed differently. Head each one
  `## Amendment YYYY-MM-DD`, optionally with a short title after an em dash, and say what
  it adds. Never edit the body to match it.
  [ADR-0003](0003-deterministic-seeded-simulation.md) is the worked example, and
  [ADR-0001](0001-record-architecture-decisions.md) is amended by this rule itself.
- **The status line**, to point at a superseding ADR.

**A reversal is a new ADR, not an amendment.** If the decision itself changes, write a new
ADR whose context explains what changed, set the old one's status to
`Superseded by [ADR-NNNN](NNNN-....md)`, and update both rows in the index.

**One exception, already spent:** ADRs 0002–0005 were drafted on 2026-09-08 as a
strawman, before the game's design existed. They were revised once later the same day
to reflect the decisions actually made in scoping (see
[design-decisions.md](../design-decisions.md)). From that point their bodies are
immutable like any other's.

## Index

| # | Title | Status | In the tree |
| --- | --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted | Built — this directory |
| [0002](0002-swiftdata-offline-first.md) | SwiftData, offline-first, no backend | Accepted | Not built — M4 |
| [0003](0003-deterministic-seeded-simulation.md) | Deterministic seeded simulation | Accepted | Built — `FMRandom`, `scripts/lint-sim.sh`, the two golden suites |
| [0004](0004-pure-swift-domain-core.md) | Pure Swift domain core, isolated from frameworks | Accepted | Built — no framework import in any `FM*` package; `playsize` guards the link |
| [0005](0005-generated-fictional-content.md) | Generated fictional players and teams | Accepted | Built — `FMGeneration` |
| [0006](0006-spatial-simulation.md) | Spatial simulation over an abstract outcome model | Accepted | Not built — M5. The seam it needs is built (0012) |
| [0007](0007-event-stream-contract.md) | The play event stream is the engine's public contract | Accepted | Partly — the engine emits the stream; no downstream consumer exists yet |
| [0008](0008-win-probability-keystone.md) | Win probability as shared infrastructure | Accepted | Not built — M2 |
| [0009](0009-event-sourcing-by-default.md) | Event sourcing as the default state model | Accepted | Partly — `TeamIdentityEvent`, `InjuryEvent` and the rivalry log; no world fold yet |
| [0010](0010-plays-designs-and-calls.md) | Distinguish play designs, calls, and plays | Accepted | Partly — calls are held by value; `PlayDesign` and the playbook are M6 |
| [0011](0011-derived-identity-for-regenerable-streams.md) | Derive identity for regenerable event streams | Accepted | Built — `PlayRef` |
| [0012](0012-play-resolver-seam.md) | Separate the play resolver from the game-state machine | Accepted | Built — `GameSimulator` and `CrudeResolver` |
| [0013](0013-fluid-positions.md) | Separate a player's personnel position from where he lines up | Accepted | Not built — [roadmap M3.5](../roadmap.md) |
