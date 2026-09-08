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
- Balance work becomes measurable: change a constant, re-run 10,000 seasons, diff the
  distributions.
- Golden tests catch unintended behavior drift, which is otherwise nearly invisible in
  a stochastic system.
- Every contributor must internalize the banned list. `.shuffled()` is a natural thing
  to reach for and will silently break the guarantee — hence the lint rather than a
  convention.
- Floating-point determinism across architectures needs care. We avoid transcendental
  functions in hot resolution paths where a cheaper formulation exists, and the golden
  tests run on both arm64 and x86_64 in CI to catch divergence.
- Refactors that change iteration order or split order break golden tests even when
  behavior is "the same." That noise is the cost of the guarantee.

## Alternatives considered

**Statistical testing only** (assert stats fall in a range, no golden files). Cheap
and robust to refactors, but it can't catch a change that shifts behavior within the
range — which is most regressions.

**Determinism only in generation, not in games.** Would give reproducible worlds
without constraining the engine. Rejected: the engine is where the bugs are, and it's
where players notice inconsistency.
