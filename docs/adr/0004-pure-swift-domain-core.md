# 0004. Pure Swift domain core, isolated from frameworks

**Status:** Accepted
**Date:** 2026-09-08

## Context

The obvious way to build a SwiftData app is to make the `@Model` classes the domain
model: `Player` is a `@Model`, the sim mutates it, the UI observes it. It's less code
and the framework is designed for it.

It's also a trap for this particular app. `@Model` classes are reference types managed
by a `ModelContext`, which means simulation code would carry an implicit dependency on
a live persistence container. That makes the sim impossible to run headless, hard to
run concurrently, subject to hidden mutation through shared references, and unable to
build anywhere but Apple platforms. Every one of those is directly load-bearing for
how we intend to build and calibrate the engine.

## Decision

`FMCore` contains the domain model as **plain Swift value types with no framework
dependencies** — no SwiftData, SwiftUI, UIKit, or Foundation types that carry platform
behavior. `FMSimulation` and `FMGeneration` operate only on those types.

`FMPersistence` owns the `@Model` classes and the explicit mapping in both directions.
It is the only module that imports SwiftData.

## Consequences

- The sim runs headless in a CLI harness, so 10,000 seasons can be simulated in CI
  without a simulator. This is what makes [calibration](../match-engine.md#calibration)
  practical.
- Value semantics remove a whole category of bug: nothing can mutate a player from
  under you mid-play.
- `Sendable` conformance is essentially free, so concurrent week simulation is safe by
  construction under Swift 6 strict concurrency.
- Packages test on Linux, which mechanically enforces the no-framework rule — a stray
  `import SwiftData` in `FMCore` fails CI rather than passing quietly.
- The persistence model can change on its own schedule; a mid-milestone domain change
  doesn't force a migration.
- **The cost is the mapping layer.** Every domain type needs a `@Model` counterpart and
  two translation functions, kept in sync by hand. This is the main ongoing tax of the
  decision and it will feel tedious. Round-trip tests (`FMCore` → `@Model` → `FMCore`
  is identity) catch the drift.
- Loading a full career means materializing a lot of value types. If that becomes a
  performance problem, the fix is partial loading at the `FMPersistence` boundary, not
  abandoning the split.

## Alternatives considered

**`@Model` classes as the domain model.** Less code, no mapping layer, and SwiftData's
observation drives the UI for free. Rejected for the headless-testing and concurrency
reasons above — those aren't nice-to-haves for a simulation game, they're how it gets
built at all.

**Protocol abstraction over persistence, with the sim generic over it.** Avoids
duplicate types. Rejected as strictly worse than the mapping layer: the abstraction
leaks (lazy loading, contexts, identity) and generic code over a persistence protocol
is harder to read than two structs and a function.

## Amendment 2026-09-10 — what the headless harness actually runs in CI

The first consequence says "10,000 seasons can be simulated in CI without a simulator."
The decision it draws that from holds — the packages build and test on Linux with no
Xcode, which is what makes headless calibration possible at all — but the number
overstates today by a wide margin, and this is an amendment under the rule in
[README.md](README.md) rather than an edit to the body.

`Tools/simharness` sims **games, not seasons**: there is no schedule, no standings and no
season loop until M3, so "a season" is not a unit the tree can run. What
[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) runs is 400 games at seed 7,
on x86_64 and arm64, in a job that uploads its output and writes the calibration table
into the job summary and **does not gate a merge**. Calibration is practical, exactly as
the decision predicted; the scale in that sentence is aspirational and the job is
reporting.

