# 0012. Separate the play resolver from the game-state machine

**Status:** Accepted
**Date:** 2026-09-08

## Context

M1 needs a working engine so that M2's analysis and narrative layers can be built
against a real event stream rather than a hypothesis
([ADR-0007](0007-event-stream-contract.md)). The engine M1 needs is not the engine the
game ships: the spatial simulation is M5's work and the largest technical risk in the
project ([ADR-0006](0006-spatial-simulation.md)).

So a deliberately crude engine gets built first and thrown away. The question is what
"thrown away" costs, and the answer depends entirely on where the line is drawn.

Much of what a game engine does is not physics. The clock, the down and distance state
machine, possession, scoring, penalty accept/decline, timeouts and overtime are **rules
of the sport**. They do not change when outcomes stop being drawn and start emerging
from geometry. A wrong ten-second runoff is wrong in both engines, and it is wrong in
exactly the place players pay the most attention.

Written as one engine, all of that is rewritten at M5 — including the parts that were
already correct, and including their tests.

## Decision

**The play resolver is a seam.** `PlayResolver` takes a situation and the two calls and
returns a `PlayRecord`. Everything else lives outside it and is written once:

```
GameSimulator            the sport's rules — clock, downs, possession, scoring,
                         penalties, timeouts, overtime. Written once.
   ↓ asks, per snap
PlayResolver             what happened on this snap.
   ├── CrudeResolver     M1. Named matchups, no geometry. Deleted at M5.
   └── SpatialResolver    M5. Twenty-two entities on a tick clock.
```

The crude resolver is **matchup-lite**: no positions and no tick loop, but real named
matchups — this rusher beat this tackle at this time, this corner was covering this
receiver — so it emits genuine `Participation` and `DecisionPoint` data rather than
empty arrays.

It is scaffolding and will be deleted at M5, not kept as a fast-sim path.

## Consequences

- What M5 deletes is one resolver, not an engine. The clock rules and their tests, which
  are fiddly and player-visible, are written once and survive.
- The spatial resolver arrives into a harness that already works: a season already sims,
  standings already compute, and the failure is isolated to the one component that
  changed.
- **The crude resolver must emit decision points that are consistent with its own
  outcome**, or M2 gets built against fiction. If it reports pressure at 2.1 seconds and
  a sack, the sack must be by that rusher. This is the real risk of the decision — a
  fabricated causal chain that looks plausible lets the analysis layer appear to work
  while reading noise.
- Two resolvers exist only briefly, so the protocol is free to be shaped by the spatial
  one's needs rather than being a negotiated compromise between them.
- Rejecting a permanent fast-sim path means fast-forwarding a career runs at the spatial
  engine's speed. At the budgeted 60 seconds a season, a decade is ten minutes. If that
  proves intolerable the answer is a faster spatial engine or a resumable background sim,
  not a second set of football behaviour to keep calibrated.
- The crude resolver hits the **parametric** calibration rows (completion percentage,
  sack rate, penalties) because they are inputs at this fidelity, and takes the spread of
  team win totals seriously because it is emergent and is the number the whole league's
  credibility rests on. Rows that depend on geometry are M5's.

## Alternatives considered

**One engine, deepened in place.** No protocol, no second implementation, no seam to
maintain — start crude and make it spatial incrementally. Genuinely appealing, and it is
how most engines actually evolve. Rejected because the two resolve plays in
fundamentally different shapes: one draws a result and attributes it, the other
integrates positions over a tick clock. "Deepening" is a rewrite of the resolver either
way, and doing it in place drags the clock and scoring rules through the rewrite with it.

**Keep the crude resolver as a permanent fast-sim path.** Makes career fast-forward
instant, and matches the quick-sim/deep-dive split the product wants. Rejected because
two resolvers must then agree forever: every calibration change lands twice, and "the
fast sim gave me a different season" becomes a permanent and legitimate complaint. The
quick-sim experience is better served by the replay tuple, which already stores unwatched
games and reproduces them exactly.

**Outcome tables for M1.** Far less work: draw yards from a distribution by play type.
Rejected because `decisions` comes back empty, and the interrogation layer — the actual
product — could then not be built or validated until M5, which is precisely the risk
ADR-0007 exists to remove.
