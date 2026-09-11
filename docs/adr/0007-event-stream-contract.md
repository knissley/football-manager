# 0007. The play event stream is the engine's public contract

**Status:** Accepted
**Date:** 2026-09-08

## Context

The product wants a great deal from every simulated play: a box score, per-player
grades, situational splits, season tendencies, league highlights, news, and a causal
explanation of what happened and why. The engine that produces those plays is also the
most expensive and most uncertain part of the project — it will start crude and be
rewritten as a spatial simulation ([ADR-0006](0006-spatial-simulation.md)).

If the analysis, narrative, and UI layers each reach into the engine for what they need,
every engine change breaks all of them, and the expensive work has to come first before
anything above it can be built at all.

## Decision

The engine's only public output is an ordered stream of typed play events. A
`PlayRecord` carries the situation, the calls and who made them, the engine's own
decision points as structured data, the outcome, and optionally per-tick trajectory.

Everything downstream is a **query over that stream**. Box scores, grades, tendencies,
highlight selection, and causal summaries are derived — never accumulated in parallel
with the simulation.

The stream shape is designed in M1, before the real engine exists, and is treated as a
stable interface thereafter.

## Consequences

- The engine can start deliberately crude and be replaced wholesale without touching
  the analysis layer, the news system, or any screen. This is the main reason the
  roadmap can put a living league before the hard engine work.
- One source of truth for statistics. The box score cannot drift from the play log,
  because it *is* the play log, summed.
- New analysis is additive. A metric nobody thought of is a new query, not an engine
  change and a migration.
- Recording the engine's internal decision points as first-class data is what makes
  "the checkdown was covered" possible. Those records have to be designed in from the
  start; an engine that only reports outcomes cannot be interrogated afterward.
- **Designing the stream shape before the real engine exists means guessing.** Some
  fields will turn out to be wrong or missing, and changing the shape late is expensive
  precisely because everything depends on it. Mitigated by building the analysis layer
  in M2, early enough that the guesses get tested while they're still cheap to fix.
- Event data is larger than aggregates. Retention is tiered, and games we don't keep
  are replayed from their seed rather than stored
  ([ADR-0003](0003-deterministic-seeded-simulation.md)).

## Alternatives considered

**Engine returns a rich result object; consumers read its fields.** Simpler, no stream
to design. Rejected: it couples every consumer to the engine's internal shape, which is
exactly the thing scheduled to be rewritten.

**Accumulate statistics during simulation alongside the play log.** Faster to query and
avoids a derivation pass. Rejected because two sources of truth diverge — and the bug
where the box score disagrees with the play-by-play is both inevitable and corrosive to
a game whose selling point is that you can trust its explanations.

## Amendment 2026-09-10 — every slot a record names is a player the record identifies

The decision says the stream is the engine's entire public output, and the consequence
it did not spell out is that a record has to be able to name everybody it points at. For
a while it could not. A `PenaltyRecord` names the offender by `PlayerSlot`, and the only
way a reader could resolve a slot to a player was `outcome.participants` — the sparse
credits of [decision 97](../design-decisions.md#foundational). A foul by a man the play
never credited — a decoy route runner, a rusher who never reached the kicker, a blocker
on a return — therefore named somebody nobody downstream could identify: 29 of 1104 flags
over eighty games, on eight fouls. The test that asserted otherwise passed by luck over
six seeds, and was made a pin on the gap with the eight fouls registered.

The gap closed when presence went on the record: `PlayRecord.onField` carries the
twenty-two men on every play, and `player(at:rosters:)` resolves any slot through it
([play-record.md](../play-record.md#who-was-on-the-field)). So the contract is now the
stronger sentence this ADR always meant: **every slot a record names — an offender, a
decision point's subject, a credit — is a player the record identifies**, and
`PenaltyTests.offendersAreReal` asserts it for flags, register gone.
