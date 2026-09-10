# 0006. Spatial simulation over an abstract outcome model

**Status:** Accepted
**Date:** 2026-09-08

## Context

The original design was an abstract outcome engine: a play resolved as a chain of
matchups, each drawing from a probability distribution — "time to win" for a pass
rusher, "separation at a timing window" for a receiver. It never knew where anyone was
standing.

Two product decisions made that untenable. The match view is a 2D field, and the hook
is a simulation you can interrogate. An abstract engine can satisfy neither honestly:
the dots would be an animator's reconstruction of what a number meant, and any "why"
the app offered would be narration over a dice roll rather than a readout of what
happened. When the UI says "your right tackle lost his rep," the dots showing it would
be a coincidence.

## Decision

The engine is genuinely spatial. Twenty-two players have positions and velocities on a
field, updated on a fixed tick. Outcomes emerge from geometry: separation is real
distance, pressure is a rusher reaching the quarterback, a catch depends on where the
ball arrives relative to the receiver.

Ratings and traits are inputs to the physics rather than modifiers on an outcome roll.
The 2D view renders engine state directly.

We adopt a hard performance budget of **~60 seconds per simulated season** — roughly
220ms per game, 1.5ms per play, 1.1µs per entity-tick — and treat it as architectural:
flat arrays of `struct`, no allocation in the tick loop, no string construction during
simulation, opt-in trajectory capture.

## Consequences

- The interrogation layer becomes a readout rather than a fiction. This is the whole
  product thesis, and nothing else delivers it.
- Traits get to be mechanically true. "Swim master" selects a different pass-rush
  resolution with different timing; "sticky hands" changes an actual catch radius. The
  flavor and the physics are the same system.
- The play designer becomes coherent: a drawn play is spatial data the engine already
  reads, so the editor is a document editor over the engine's input format.
- **This is 5–10× the engine work** of the abstract model, and it is the project's
  dominant technical risk. Accepted because the scope is a hobby project with no
  deadline, and because the alternatives don't deliver the hook.
- Performance stops being a later concern. A naive implementation — classes, per-tick
  object churn, dictionaries, logging strings — is roughly 100× too slow, and fixing it
  is a rewrite rather than a tuning pass. The budget is enforced by a CI benchmark —
  *not yet true: the Linux workflow runs the suites and the lints and has no benchmark
  step. Since #9 it does **report** the budget: `simharness` times its simulate loop and
  the job summary carries the `Budget` block, so drift is visible even though nothing
  fails on it.*
- Floating-point determinism across architectures becomes a real risk rather than a
  theoretical one, because errors compound over thousands of ticks. Golden tests run on
  both arm64 and x86_64.
- Plays now require an assignment format and a validator before the engine can run them,
  which is work the abstract model didn't need.

## Alternatives considered

**Abstract engine with an animated view.** Far cheaper and playable much sooner. The
view would interpolate plausible movement to match a decided outcome. Rejected because
it makes the interrogation layer dishonest — the explanation and the animation would
both be reconstructions, and the one thing this game is supposed to offer is that they
aren't.

**Hybrid — spatial for the pass rush and coverage, abstract elsewhere.** Superficially
a sensible compromise. Rejected because hybrid engines tend to get the worst of both,
and the seam would be visible exactly where players look hardest. It also wouldn't
reduce the hard part: once you have a tick loop and entities, the remaining play types
are incremental.
