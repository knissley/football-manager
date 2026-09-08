# 0011. Derive identity for regenerable event streams

**Status:** Accepted
**Date:** 2026-09-08

## Context

[ADR-0009](0009-event-sourcing-by-default.md) states that events "carry a monotonic
sequence number." That is right for the world streams — `ContractEvent`,
`TransactionEvent`, `DevelopmentEvent` and the rest. Each is world-level, ordered once,
never discarded, and is the source of truth for what it records. An allocated sequence
number is the natural identity.

`PlayRecord` differs on two axes, and both matter:

- It is scoped to a **game**, not the world. Games in a week are concurrent, so a global
  ordering across them describes nothing real.
- It is the only stream that is **discarded and rebuilt**. The retention policy is
  *retain your own games in full; replay everything else from its seed*
  ([ADR-0003](0003-deterministic-seeded-simulation.md), sized in
  [play-record.md](../play-record.md)). Most plays that ever exist are never stored.

An allocated identifier cannot survive that. Replaying a game and recovering the same
identifiers would require the allocator's counter as it stood at that game, stored per
game — a snapshot whose only justification is the identifier itself, and precisely the
replay cascade that ADR-0009's fourth point exists to prevent.

The identifier also turned out to earn very little. Nothing queries a play by opaque
identifier; the real queries are *this game's plays*, *every third-and-long this season*,
*this player's snaps*, which key off `game`, `SituationClass` and participant slots.
Ordering is already `index`, which must exist regardless as the per-play seed-split
label. Only outward references — a highlight, a news item, a bookmark — need a handle.

## Decision

**Allocated identity for streams that are the source of truth; derived identity for
streams that are a cache over a seed.** This extends ADR-0009 rather than replacing it:
its rule stands for the world streams, and this names the exception and why.

`PlayRecord.id` is removed. A play is addressed by `PlayRef` — a `Hashable`, `Comparable`
value of `(GameID, index)` — exposed as a computed property over fields the record
already carries. Nothing is stored for it, no allocator exists, and a link to a play in a
game that was never retained resolves by replaying that game and indexing into it.

`PlayRef` is a struct, not a packed `UInt64`.

## Consequences

- One identity per play instead of two that could disagree.
- The engine needs no identifier allocator, so a game replays independently with no
  counter state to carry — consistent with the opponent-model snapshot already in
  `GameSetup`.
- References survive the retention tier. A highlight recorded against a game you later
  stop retaining still resolves.
- The cost lands on `FMPersistence` and on links: a composite key is more awkward than a
  flat column, and it synthesizes a storage key from the pair. This is real friction and
  it recurs wherever a play is addressed from outside the sim.
- `play-record.md`'s "append-only, ordered by `PlayID`" was wrong and is corrected.
  Ordering is `index` within a game; across games it comes from the schedule.
- New streams must now answer a question before they are designed: is this the source of
  truth, or a cache over a seed? Getting it wrong is expensive in the same way it was
  here.

## Alternatives considered

**Keep an allocated `PlayID` and store the per-game starting counter.** Opaque flat
identifiers are the most pleasant thing to hold downstream — one column, one URL
component, no composite keys anywhere. Rejected because the stored counter is a snapshot
with no justification beyond preserving the identifier, and it reintroduces exactly the
cross-game dependency the replay design removes everywhere else.

**Pack `(game, index)` into a `UInt64`.** Flat, eight bytes, a trivial dictionary key,
and it keeps the pleasant properties above while staying derived. Rejected because it
bakes a ceiling on games per career into the event contract to save two bytes and a
little syntax — a bad trade in the one place in the codebase that is hardest to change
later.

**Address plays only by `(game, index)` with no named type.** Nothing to define, nothing
to keep in sync. Rejected because the pair then gets passed as two loose arguments
through every layer that references a play, and the ordering of two integers is exactly
the thing that gets swapped silently.
