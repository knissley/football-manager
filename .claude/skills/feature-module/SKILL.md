---
name: feature-module
description: Scaffold a new feature area in the iOS app following this repo's layering — view, store, service, and tests in the right modules. Use when adding a new screen or feature (roster screen, draft board, contract negotiation, trade UI) and you need it wired up to the project's architecture rather than improvised.
---

# Adding a feature module

Feature work in this app cuts across layers, and the whole value of the architecture
is that each piece lands in the right one. Read `docs/architecture.md` first if you
haven't this session.

## Decide what the feature actually needs

Not every feature needs every layer. Work out which of these are in play before
writing anything:

| Layer | Needed when | Where it goes |
| --- | --- | --- |
| Domain types | The feature introduces a new concept (a `TradeOffer`, a `ScoutingReport`) | `Packages/FMCore` |
| Game logic | There's a rule, a calculation, or an outcome (trade validity, cap impact, AI response) | `Packages/FMCore` or `Packages/FMSimulation` |
| Persistence | The new state must survive app launch | `Packages/FMPersistence` |
| Service | The feature runs work off the main actor, or coordinates the sim | App target `Services/` |
| Store | The screen has state (selection, filters, in-progress edits) | App target `Features/<Name>/` |
| View | There's a screen | App target `Features/<Name>/` |
| Shared components | A control other screens will reuse | `Packages/FMUI` |

**Build bottom-up.** Domain and logic first, with tests, before any SwiftUI. A feature
whose rules are tested in `FMCore` is a feature whose UI is thin and obvious.

## Layout

```
Packages/FMCore/Sources/FMCore/<Concept>/         Types + rules + invariants
Packages/FMCore/Tests/FMCoreTests/<Concept>Tests.swift

FootballManager/Features/<Name>/
    <Name>View.swift          Screen. Renders store state, sends intents.
    <Name>Store.swift         @Observable @MainActor. State + intents.
    Components/               Views used only by this feature.

FootballManager/Services/<Name>Service.swift      Only if async work is involved.
```

## The rules to hold to

- **No game rules in the view.** An `if` in a SwiftUI body that decides something
  about football belongs in `FMCore`. This is the single most common way this
  architecture erodes.
- **Stores expose read-only state and intent methods.** Views never mutate store
  properties directly.
- **Views take what they render, not the world.** A view signature taking `World` or
  the whole store is a smell; pass the slice.
- **Sim work goes off the main actor** through a service, and comes back as value
  types. Never call into `FMSimulation` from a view body.
- **New domain types are `Sendable` value types** with typed IDs, no `UUID`.
- **Accessibility from the start** — Dynamic Type, VoiceOver labels on anything
  conveying a rating or a number. Retrofitting this onto a dense table is far worse
  than doing it now.

## Checklist before calling it done

- [ ] Rules live in `FMCore`/`FMSimulation` and have unit tests
- [ ] New domain types are `Sendable`, use typed IDs, and no `UUID`/`Date()`
- [ ] Persisted types have a round-trip test (`FMCore` → `@Model` → `FMCore` is identity)
- [ ] The view compiles without importing `FMSimulation` or `SwiftData`
- [ ] Dynamic Type and VoiceOver handled
- [ ] `swift-format` run
- [ ] Any design change is reflected in `docs/`

## What you cannot verify in a Linux session

Claude Code web sessions have no Xcode. Package code (`FMCore`, `FMRandom`,
`FMSimulation`, `FMGeneration`) builds and tests here. Anything touching the app
target, SwiftUI, or SwiftData does not — write it carefully and say plainly that it
is unverified rather than implying it was tested.
