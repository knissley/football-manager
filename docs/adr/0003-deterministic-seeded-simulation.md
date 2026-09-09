# 0003. Deterministic seeded simulation

**Status:** Accepted
**Date:** 2026-09-08

## Context

The simulation is the product. It's also the hardest thing to test: outcomes are
random by design, so "is this right?" and "did my change break it?" are not obviously
answerable questions.

Meanwhile players will absolutely notice non-determinism. If backgrounding the app
mid-game and returning produces a different result, or if a bug report can't be
reproduced from a save, trust in the sim collapses — and trust in the sim is the
whole relationship.

## Decision

The simulation and world generation are **fully deterministic functions of their
inputs and an explicit seed**. Same world, same gameplans, same seed ⇒ identical
result, on every device and every OS version, forever.

A game is reproducible from the tuple `(initialState, seed, sliderConfig, decisionLog)`.
The decision log is required because play calling can be toggled at will: a game where
the player took over some snaps is not a pure function of its seed alone. Every player
decision is recorded in order.

**That tuple is also the storage format.** Games we don't retain in full — fifteen of
sixteen every week — keep a box score and their replay tuple, and re-simulate
identically on demand. Determinism is therefore a player-facing feature, not only a
testing tool.

Concretely:

- All randomness comes from `FMRandom`'s `SplittableRandom`, seeded explicitly.
- Per-play generators are split from `(gameSeed, playIndex)`, so play *N* resolves
  identically regardless of what ran before it.
- The following are banned in `FMSimulation` and `FMGeneration`, enforced by a CI
  lint: `Int.random`, `Double.random`, `SystemRandomNumberGenerator`, `.shuffled()`,
  `.randomElement()`, `UUID()`, `Date()`, and any environment or clock read.
- Iteration order over unordered collections is never observable in output — sort by
  a stable ID before iterating.
- Concurrent simulation of a week merges results in game-ID order, so parallelism
  cannot change outcomes.
- Golden-seed tests check in the full box score of known seeds. They fail on any
  behavior change; when the change is intentional, the golden file is regenerated in
  the same commit and the diff is reviewed as part of the change.

## Consequences

- Bug reports become reproducible from a seed and a play index. This is the single
  biggest debugging win available to us.
- Storage stays bounded across a decade-long career without discarding the ability to
  watch any game that ever happened. Replay-from-tuple is what makes full-fidelity
  league simulation affordable to keep.
- **The bar is now higher than it was.** When determinism was only a testing
  convenience, a rare divergence was an annoyance. Now it corrupts saved history: a
  game replays differently than it was reported. Slider config and decision logs must
  be captured faithfully, and float discipline in the spatial engine
  ([ADR-0006](0006-spatial-simulation.md)) is load-bearing rather than tidy.
- Balance work becomes measurable: change a constant, re-run 10,000 seasons, diff the
  distributions.
- Golden tests catch unintended behavior drift, which is otherwise nearly invisible in
  a stochastic system.
- Every contributor must internalize the banned list. `.shuffled()` is a natural thing
  to reach for and will silently break the guarantee — hence the lint rather than a
  convention.
- Floating-point determinism across architectures needs real care, and more of it now
  that the engine is spatial and errors compound over thousands of ticks. We avoid transcendental
  functions in hot paths where a cheaper formulation exists, and golden tests run on
  both arm64 and x86_64 in CI to catch divergence.
- Refactors that change iteration order or split order break golden tests even when
  behavior is "the same." That noise is the cost of the guarantee.

## Alternatives considered

**Statistical testing only** (assert stats fall in a range, no golden files). Cheap
and robust to refactors, but it can't catch a change that shifts behavior within the
range — which is most regressions.

**Determinism only in generation, not in games.** Would give reproducible worlds
without constraining the engine. Rejected: the engine is where the bugs are, and it's
where players notice inconsistency.

## Amendment 2026-09-09 — what it took to break it, in practice

Recorded after the guarantee was broken and fixed, because the shape of the failure is
not the shape the banned list guards against. The decision above is unchanged; this
section is an amendment under the rule in [README.md](README.md), and the body it amends
was not edited to match.

`SchemeFit.effectiveOverall` blends a position's rating weights with a scheme's
adjustments, and it summed them **while iterating a dictionary**. No banned call, no
unseeded randomness, no clock read. But floating-point addition is not associative, so the
sum's last bits depended on Swift's hash seed — which is randomised **per process** — and
the result was divided and rounded to a whole overall point. A player sitting near a
rounding boundary was a point better in one process and a point worse in the next. His
scheme fit moved with him, that fed his effective rating, and the same seed produced a
different season.

Two lessons worth more than the fix:

**"Never let iteration order reach the output" includes arithmetic.** The rule reads as
though it is about *which* element you pick — a `first`, a `max`, an allocation order. It
is also about the order you *add doubles in*. Any float sum over an unordered collection
is a determinism bug whether or not anything downstream looks order-sensitive.

**Every determinism test we had was blind to it.** They all compared two runs *inside one
process*, which share a hash seed, so they agreed with each other and disagreed with
yesterday's run. The bug surfaced only as intermittent flakiness that looked like
infrastructure noise. A determinism test has to be a **checked-in golden constant**, and
its checksum must not use `Hasher` — that is per-process seeded too, and a golden test
built on it cannot detect the thing it exists to detect. `FMSimulation`'s
`GoldenSeedTests` and `FMGeneration`'s `GoldenWorldTests` are that check; both use FNV-1a
over the values that matter.
