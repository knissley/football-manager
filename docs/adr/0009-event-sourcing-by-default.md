# 0009. Event sourcing as the default state model

**Status:** Accepted
**Date:** 2026-09-08

## Context

Three independent event logs had already arrived in the design, each for its own local
reason: `PlayRecord` because everything downstream needed to query the engine's output
([ADR-0007](0007-event-stream-contract.md)), `DevelopmentEvent` so a deferred
development currency could bolt on without a retrofit, and the per-game decision log
because toggleable play calling breaks replay-from-seed
([ADR-0003](0003-deterministic-seeded-simulation.md)).

The boundary between "this deserves history" and "this is just current state" was drawn
ad hoc, and it was wrong. A concrete case made it obvious: a player's gear and
appearance change over a career, and replaying a game from three seasons ago should show
him as he looked *then*, not as he looks now. Current-state models cannot answer that,
and the same argument applies to contracts, scouting grades, staff, and injuries — the
product is full of questions of the form *what was true at time T*.

## Decision

**The world is a fold over an ordered event log.** Event sourcing is the default for
domain state, not a technique reserved for the simulation.

1. Anything whose past value could ever be asked for is event-sourced.
2. **Current state is a projection** — derived, cached, and rebuildable from the log at
   any time. It is never the source of truth.
3. Events are immutable, carry a monotonic sequence number, and are stamped with the
   world time (season, phase, week) at which they occurred.
4. **Snapshot at boundaries that must reproduce independently; fold everywhere else.**
   A game's `GameSetup` carries the opponent-model snapshot so replaying one game does
   not cascade into replaying every game before it. Such boundaries are deliberate, and
   each is justified where it appears.
5. Old events compact into period snapshots to bound storage; a snapshot plus subsequent
   events must remain sufficient to reconstruct any later state.
6. State nobody will ever ask about historically — UI preferences, sort orders, the tab
   you had open — stays plain state. The test is whether its value at a past moment
   could ever matter.

Streams this implies: `PlayRecord`, `DevelopmentEvent`, `AppearanceEvent`,
`ContractEvent`, `TransactionEvent`, `EvaluationEvent`, `StaffEvent`, `InjuryEvent`,
`AwardEvent`.

## Consequences

- **Temporal reconstruction is free everywhere.** Replays, Hall of Fame retrospectives,
  draft post-mortems and franchise history all show the world as it was, without
  bespoke snapshotting per feature.
- **The interrogation hook extends past the field to the whole franchise.** "How did our
  cap get like this?" and "what did we think of him at the time?" become ordinary
  queries. Those two in particular were not achievable under current-state models and
  are among the most interesting things the game can offer.
- One architectural idea instead of several, applied consistently. New systems inherit
  history rather than each deciding whether to keep it.
- Rebuild-from-log is a strong test — projections are provably faithful — and a recovery
  path if a projection is ever corrupted.
- **Read performance now depends on projections.** Folding a twenty-season log to render
  a roster row is unusable, so every read path needs a maintained projection. This is the
  main ongoing cost and the thing most likely to be got wrong under time pressure.
- **Projection drift is a new class of bug**: the cached view disagreeing with the log.
  Mitigated by a rebuild-and-compare test, which must actually be run.
- **Storage grows with history**, so compaction is mandatory rather than an optimization.
  1,700 players across twenty seasons produce a lot of events.
- Every mutation site becomes "append an event, update the projection" — more ceremony
  than assigning to a property, and a discipline that has to hold everywhere to be worth
  anything.
- Changing an event's shape is a migration problem, because old events must still fold
  correctly. Event types need to be versioned from the start.

## Alternatives considered

**Current state, with an audit log for selected things.** Much cheaper, and standard.
Rejected because it requires predicting in advance which values will be asked about
historically — and the gear case proves that prediction fails. Retrofitting history onto
a value that was never logged is impossible, not merely expensive.

**Full snapshots at each season boundary.** Simple, and answers year-granularity
questions. Rejected: it cannot answer anything sub-season ("what did his contract look
like at the trade deadline"), and snapshotting an entire world twenty times is larger
than the event log that produced it.

**Event-source the simulation only, plain state elsewhere.** The position this ADR
replaces. Rejected because the boundary is arbitrary — the same temporal questions arise
about contracts, appearance, staff and scouting grades as about plays, and drawing the
line at the sim's edge was an artifact of the order things were designed in.
