# Football Manager — working agreement

An offline-first American football management sim for iOS. SwiftUI + SwiftData,
single-player career, fully generated fictional content.

**Read first:** [`docs/vision.md`](docs/vision.md) for what we're building,
[`docs/architecture.md`](docs/architecture.md) for where code goes. Decisions with a
rationale live in [`docs/adr/`](docs/adr/).

## Project status

Pre-alpha, milestone M0. **No Swift code exists yet** — the repo is docs and tooling
config. Don't assume a file exists because a doc describes it; check first. The docs
describe the intended design, not the current state.

## The rules that matter

These are the ones where a mistake is expensive to unwind. Everything else is taste.

**1. The simulation is pure.** `FMCore`, `FMRandom`, `FMSimulation`, and
`FMGeneration` never import SwiftData, SwiftUI, UIKit, or anything platform-specific.
No I/O, no logging, no clock reads. If the sim needs to report something, it returns
it. ([ADR-0004](docs/adr/0004-pure-swift-domain-core.md))

**2. Randomness comes from one place.** Every random draw in the sim comes from
`FMRandom`, seeded explicitly. Never use `Int.random`, `Double.random`,
`SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`, `UUID()`, or
`Date()` inside `FMSimulation` or `FMGeneration`. Never let iteration order over an
unordered collection reach the output — sort by a stable ID first.
([ADR-0003](docs/adr/0003-deterministic-seeded-simulation.md))

**3. Game rules live in the sim, never in a view.** If a SwiftUI view contains an `if`
that decides something about football, it's in the wrong layer.

**4. Only `FMPersistence` knows SwiftData exists.**

**5. Never ship real names or marks.** No real players, teams, leagues, logos, or
likenesses — not in code, not in test fixtures, not in placeholder data. Generated
fiction only. ([ADR-0005](docs/adr/0005-generated-fictional-content.md))

**6. Never regenerate a golden test file to make a red test pass.** If the engine
changed on purpose, regenerate it in the same commit and describe the behavior change
in the commit message. If you didn't mean to change behavior, you found a bug.

## Conventions

**Swift**
- Swift 6 language mode, strict concurrency, throughout.
- Value types by default. Reference types need a reason (identity or shared mutable
  state), and `@Model` classes in `FMPersistence` are the main legitimate case.
- Typed IDs (`PlayerID`, `TeamID`) over raw integers. Never `UUID` in the sim.
- No force unwrapping outside of tests. Model impossible states out of existence
  rather than asserting they don't happen.
- `swift-format` with the repo config; run it before committing.

**Naming**
- Modules are `FM`-prefixed. Types inside them are not (`FMCore.Player`, not
  `FMPlayer`).
- Use the sport's real vocabulary — `downAndDistance`, `redZone`, `deadMoney`,
  `proration`. Don't invent generic synonyms for terms of art. When unsure of a term,
  the `football-domain` skill has the reference.

**SwiftUI**
- Views are small and take exactly what they render. A view that takes the whole
  `World` is a smell.
- One `@Observable` `@MainActor` store per feature area. Views hold no logic.
- Everything supports Dynamic Type and VoiceOver from the start; retrofitting
  accessibility onto a dense roster table is much worse than building it in.

**Tests**
- Swift Testing (`@Test`), not XCTest, for new code.
- Cap math, clock rules, and schedule generation get exhaustive unit tests. They're
  rule-based, player-visible, and easy to get subtly wrong.
- Engine changes need both a golden-seed test and a statistical check.
- A test that needs a `ModelContext` to test a game rule means the rule is in the
  wrong layer.

**Docs**
- A change that alters the design updates the doc in the same commit.
- A decision that was hard to make, or that rejected a real alternative, gets an ADR.
  Use `/adr`.

## Working style here

- **Check the docs before proposing a design.** Most architectural questions are
  already answered in `docs/`. If a doc is wrong, say so and fix it — don't silently
  work around it.
- **Prefer breadth before depth.** Per the [roadmap](docs/roadmap.md), a crude complete
  system beats one beautiful subsystem attached to nothing. Get it end-to-end, then
  deepen.
- **Balance the engine with the harness, not by playing.** Tuning constants is done
  against `Tools/simharness` output and the
  [calibration table](docs/match-engine.md#calibration).
- **Ask when a decision is load-bearing.** Small judgment calls: just make them.
  Anything that would earn an ADR: ask first.

## Commands

Nothing to build yet. As modules land, this section gets the real commands.

```
# Planned — not yet available
swift build --package-path Packages/FMCore
swift test  --package-path Packages/FMSimulation
swift run   --package-path Tools/simharness -- --seasons 1000 --out calibration.json
xcodebuild -scheme FootballManager -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Note on this environment:** Claude Code web sessions run on Linux with no Xcode.
The `FM*` packages are designed to build and test on any Swift 6 toolchain, so package
work is verifiable here; anything touching the app target, SwiftData, or SwiftUI can
only be checked on a Mac. Say so plainly rather than claiming untested code works.

## Skills

- `/adr` — write an architecture decision record
- `/feature-module` — scaffold a new feature module to the repo's layering
- `/football-domain` — reference for football rules, terminology, roster and cap
  structure. Load it before writing sim logic or naming domain types.
