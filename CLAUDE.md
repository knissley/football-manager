# Football Manager — working agreement

Offline-first American football management sim for iOS: SwiftUI + SwiftData, single-player
GM-and-head-coach career, spatial match engine, generated fiction. The hook is **a simulation
you can interrogate**, not a narrated dice roll. **Read first:** [`vision.md`](docs/vision.md),
[`design-decisions.md`](docs/design-decisions.md), [`architecture.md`](docs/architecture.md),
[`docs/adr/`](docs/adr/). **Every rule here exists because something went wrong; the stories
are in [`docs/lessons.md`](docs/lessons.md).**

## Project status

Pre-alpha, late in M1: four packages and four tools are green, with **no app target, no
SwiftUI and no SwiftData yet** — don't assume a file exists because a doc describes it. The
target rulebook is the **2025 season**, a later book's rule is a defect, and how the engine got
here is [the audit story](docs/lessons.md#project-status-the-audit-of-september-2026).

## The rules that matter

Where a mistake is expensive to unwind. Everything else is taste.

**1. The simulation is pure.** `FMCore`, `FMRandom`, `FMSimulation`, `FMGeneration`,
`FMAnalysis` and `FMNarrative` import no SwiftData, SwiftUI, UIKit or platform API and do no
I/O, logging or clock reads: what the sim reports, it returns.
([ADR-0004](docs/adr/0004-pure-swift-domain-core.md))

**2. Randomness comes from one place, and replay depends on it.** Every draw comes from
`FMRandom`, seeded; a game replays from `(initialState, seed, sliderConfig, decisionLog)`. In
`FMSimulation` and `FMGeneration` never `Int.random`, `Double.random`,
`SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`, `UUID()` or `Date()`, and
never let iteration order over an unordered collection reach the output — sort by a stable ID.
([ADR-0003](docs/adr/0003-deterministic-seeded-simulation.md) ·
[why](docs/lessons.md#rule-2--randomness-comes-from-one-place))

**3. The world is a fold over an event log.** Anything whose past value could be asked for is
event-sourced; current state is a *projection*, never the source of truth, and snapshots happen
only where something must reproduce independently.
([ADR-0009](docs/adr/0009-event-sourcing-by-default.md))

**4. Everything downstream reads the event stream.** The engine emits typed `PlayRecord`s; box
scores, grades, news, highlights and tendencies are *queries* over it, never accumulated beside
the sim. ([ADR-0007](docs/adr/0007-event-stream-contract.md) ·
[why](docs/lessons.md#rule-4--everything-downstream-reads-the-event-stream))

**5. The tick loop never allocates.** A season in ~60s, about 1.1µs per entity-tick: flat
arrays of `struct`, no dictionaries, no per-tick churn, no string building in the sim.
([ADR-0006](docs/adr/0006-spatial-simulation.md) ·
[why](docs/lessons.md#rule-5--the-tick-loop-never-allocates))

**6. Game rules live in the sim, never in a view.** A SwiftUI view with an `if` that decides
something about football is in the wrong layer.

**7. Only `FMPersistence` knows SwiftData exists.**

**8. Never ship real names or marks** — no real players, teams, leagues, logos or likenesses,
fixtures included. Cite a rulebook by number and season; never paste its text.
([ADR-0005](docs/adr/0005-generated-fictional-content.md))

**9. Never regenerate a golden to make a red test pass.** Regenerate it in the same commit as
a deliberate behaviour change, described; otherwise you found a bug. Never retune a constant to
keep a row green inside a fix — report the row and leave tuning to a retune.

**10. Football is asserted from a reference, never from memory.** A claim about the sport cites
a rule number and rulebook season, or a real-league season and its source; a claim about the
engine cites a harness row or a scenario test. [`docs/reference/`](docs/reference/) is the
reference, [`invariants.md`](docs/invariants.md) what must be true of a game.
([why](docs/lessons.md#rule-10--football-is-asserted-from-a-reference-never-from-memory))

**11. Football tests come first, and every test says what kind it is.** A change to the rules
layer, the resolver or a caller lands with a football test it turned green — a scenario or a
sourced band, written from the reference *before* the code and committed red. A test written
from the code afterwards is a regression pin, tagged as one.
([why](docs/lessons.md#rule-11--football-tests-come-first))

## Conventions

**Swift** — Swift 6 mode, strict concurrency. Value types by default; a reference type needs a
reason (`@Model` in `FMPersistence` is the main one). Typed IDs, never `UUID` in the sim, no
force unwrapping outside tests, `swift-format` before committing.

**Naming** — modules are `FM`-prefixed, types inside them are not (`FMCore.Player`). Use the
sport's vocabulary — `downAndDistance`, `redZone`, `deadMoney`, `proration` — never a synonym
for a term of art; `/football-domain` is the reference. Fluent vocabulary is not correct rules
([why](docs/lessons.md#conventions--naming-fluent-vocabulary-is-not-correct-rules)).

**SwiftUI** — views are small and take exactly what they render; one taking the whole `World`
is a smell. One `@Observable` `@MainActor` store per feature area, no logic in views, Dynamic
Type and VoiceOver from the start.

**Tests** — Swift Testing (`@Test`), exactly one kind tag each — **`.football`**,
**`.contract`**, **`.unit`**, **`.pin`** — defined in [`testing.md`](docs/testing.md) and
counted by `scripts/test-census.sh`; a football share that falls in the rules layer or the
resolver between milestones is a finding. Cap math, clock rules and schedule generation get
exhaustive unit tests; an engine change needs a golden-seed test *and* a statistical check. A
rule needing a `ModelContext` to test is in the wrong layer; a test encoding a bug is
rewritten, not deleted.

**Docs** — a design change updates its doc in the same commit; a decision that rejected a real
alternative gets an ADR (`/adr`). A doc describes intent and the tree reality, so where they
disagree the doc says so.

## Working style here

- **Check the docs first**; if one is wrong, say so and fix it.
- **Breadth before depth** ([roadmap](docs/roadmap.md)): a crude complete system beats a
  beautiful subsystem attached to nothing.
- **The whimsy goes in the world, not the engine.** No outcome is authored.
- **Balance with the harness, not by playing**, and only in a retune issue
  ([table](docs/match-engine.md#calibration)).
- **Watch a game**: one full `gamelog` before and after any engine change
  ([why](docs/lessons.md#working-style--watch-a-game)).
- **Grill before you build** — the choices, what each trades away, a recommendation on each,
  then *wait*; `design-decisions.md` lists the open questions. **A backlog issue is the
  exception**: report when its plan proves wrong instead of reopening it.
- **A recommendation, not a survey**, and **say plainly what you did not check**: give every
  number a target or a reason it has none
  ([why](docs/lessons.md#working-style--every-number-printed-gets-a-target)).

## How work flows: design, then orchestrate

`/game-designer` owns what the game is for; `/orchestrator` owns how and when work lands;
`/design-grill` turns one idea into a brief and edits nothing; a fresh-session audit gates each
milestone's exit. The process is [`docs/design/README.md`](docs/design/README.md), the design
tracker is **#183**, and `/next` says which step you are at. Three rules keep the halves apart:
design reaches implementation **as issues the owner has read**, never as a doc edit an agent
must notice; **two writers never edit one file at once**; **every milestone has a stream list**,
checked against `docs/play-record.md` before it opens.

## Current work: the audit backlog

The tracker is **#1** and **its body is the state**; its comments are history. Read Current
state, and [`audit-is-this-football.md`](docs/audit-is-this-football.md), before touching the
engine. Issues carry `track:`, `wave:` and exactly one `status:`; `status:blocked` does not say
why — a dependency, or a decision, which **`needs-owner`** marks. **Labels are the live
backlog**, not the wave tables
([count](docs/lessons.md#current-work--the-labels-are-the-live-backlog)); later waves move the
goldens, so they run one at a time, each cut from the `main` before it and merging rather than
rebasing ([why](docs/lessons.md#current-work--waves-merge-they-never-rebase)).

Branches are `fix/<issue>-<slug>` from `main`; **`preflight.sh` green before you push**;
goldens regenerate in the commit that changed behaviour; **nothing is retuned inside a fix** —
paste each moved harness row with its mechanism against its **measured** noise floor, naming
the floor ([why](docs/lessons.md#current-work--the-measured-noise-floor)). **The PR body is
the report**, shaped by [`.github/pull_request_template.md`](.github/pull_request_template.md),
capped at 500 words outside the `--report` block
([why](docs/lessons.md#current-work--the-pr-body-is-the-report-and-it-is-capped)), with no
model identifiers beyond the tooling's trailer. If the plan is wrong or something is unknown,
stop and report. Dispatch and verification are `/orchestrator`.

## Commands

```
# Available now
./scripts/preflight.sh                                    # the pre-push command: picks a lane
                                                          # from the diff and runs it
swift build --package-path Packages/FMRandom
swift test  --package-path Packages/FMRandom
swift test  -c release --package-path Packages/FMRandom   # integer maths must agree with debug
swift test  --package-path Packages/FMCore
swift test  --package-path Packages/FMGeneration
swift test  --package-path Packages/FMSimulation
swift run   --package-path Tools/playsize
cd Tools/worldgen && swift run worldgen --help
cd Tools/simharness && swift run simharness --games 400 --seed 7
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11
swift format lint --strict --recursive --parallel Packages/ Tools/
                                                          # without --strict it exits 0 on
                                                          # findings and CI fails where you pass
swift format --in-place --recursive --parallel Packages/ Tools/
scripts/lint-sim.sh
scripts/lint-sim.sh --self-test
scripts/fetch-rulebook.sh <dir-outside-the-repo>          # check WHICH EDITION it got
scripts/lint-reference.sh --self-test
FM_RULEBOOK_TEXT=<path> scripts/lint-reference.sh
FM_RULEBOOK_TEXT=<path> scripts/lint-reference.sh --messages
                                                          # RUN IT BEFORE YOU PUSH
scripts/test-census.sh
scripts/test-census.sh --self-test
python3 scripts/calibration-sources.py --self-test
python3 scripts/harness-noise.py --self-test

# Planned — land with the backlog
xcodebuild -scheme FootballManager -destination 'platform=iOS Simulator,name=iPhone 16' test
```

[`docs/tools.md`](docs/tools.md) is what each is for and its recipes;
[`docs/lessons.md`](docs/lessons.md) has the measured timings.

**This environment:** Linux, no Xcode, no toolchain. `./scripts/install-swift.sh` installs one
and needs `download.swift.org` allowed; without it **nothing compiles**, so check
`command -v swift` before claiming anything is verified. The app target, SwiftData and SwiftUI
need a Mac, and untested code is never described as working.

## Skills

- `/adr` — write an architecture decision record
- `/feature-module` — scaffold a feature module to the repo's layering
- `/football-domain` — rules, terminology, roster and cap structure
- `/orchestrator` — run a filed backlog from its tracker; its second half is the standing brief
- `/game-designer` — review the design, judge a brief, deepen or open a milestone
- `/design-grill` — one idea into a brief, in a fresh session; edits nothing
- `/next` — where the loop stands and what to do now
