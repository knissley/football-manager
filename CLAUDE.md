# Football Manager — working agreement

An offline-first American football management sim for iOS. SwiftUI + SwiftData,
single-player GM-and-head-coach career, spatial match engine, fully generated fictional
content.

The hook is **a simulation you can interrogate**: the engine explains what actually
happened rather than narrating a dice roll.

**Read first:** [`docs/vision.md`](docs/vision.md) for what we're building,
[`docs/design-decisions.md`](docs/design-decisions.md) for what's settled and what's
still open, [`docs/architecture.md`](docs/architecture.md) for where code goes.
Rationale lives in [`docs/adr/`](docs/adr/).

## Project status

Pre-alpha, late in milestone M1. Four packages exist and are green: `FMRandom`,
`FMCore`, `FMGeneration` and `FMSimulation`, with four tools — `playsize`, `worldgen`,
`simharness` and `gamelog`. **No app target, no SwiftUI, no SwiftData yet**; that is M4. Don't
assume a file exists because a doc describes it; check first, because several docs still
describe intent rather than what is built.

What works today: world and roster generation, a crude game engine behind the real
`PlayRecord` contract, and a calibration harness. The per-play numbers land. An external
audit in September 2026 found that the rules layer did not finish a game correctly:
regular-season games ended tied with no overtime, a touchdown on the last play of a half
got no try, the wrong team kicked off after a safety, the clock ran through a change of
possession, and contact fouls were enforced from the wrong spot — while five hundred
sixty-two tests were green, three of them asserting wrong football. **Wave 1 of the
backlog fixed those** (S9–S13 and S15 in the audit doc): overtime, the try, the safety
kickoff, the clock with its runoff, and the enforcement spot each have scenario tests
written from the 2025 rulebook, and the three wrong tests were rewritten; #74 then gave
overtime its two-minute warning and postseason overtime its timing. Still open are S14
(B2 #22, E2 #42), two record gaps — the spot where possession was lost, and a
kicking-team kickoff touchdown — (#58), and the re-try after a foul on a try (#48).

The fixes are an issue backlog, tracked in **#1**. Read that issue and
[`docs/audit-is-this-football.md`](docs/audit-is-this-football.md) before touching the
engine. The audit doc is current as of wave 1: it carries all fifteen findings with a
status table and links every open one to its issue.

The target rulebook is the **2025 season**. Some defaults in `Rules` still carry 2024
values until issue D1 lands.

## The rules that matter

These are the ones where a mistake is expensive to unwind. Everything else is taste.

**1. The simulation is pure.** `FMCore`, `FMRandom`, `FMSimulation`, `FMGeneration`,
`FMAnalysis`, and `FMNarrative` never import SwiftData, SwiftUI, UIKit, or anything
platform-specific.
No I/O, no logging, no clock reads. If the sim needs to report something, it returns
it. ([ADR-0004](docs/adr/0004-pure-swift-domain-core.md))

**2. Randomness comes from one place, and replay depends on it.** Every random draw
comes from `FMRandom`, seeded explicitly. A game is reproducible from
`(initialState, seed, sliderConfig, decisionLog)` — and that tuple is how most games
are *stored*, so a determinism bug corrupts saved history, it doesn't just fail a test. Never use `Int.random`, `Double.random`,
`SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`, `UUID()`, or
`Date()` inside `FMSimulation` or `FMGeneration`. Never let iteration order over an
unordered collection reach the output — sort by a stable ID first.
([ADR-0003](docs/adr/0003-deterministic-seeded-simulation.md))

**3. The world is a fold over an event log.** Event sourcing is the default for domain
state, not a simulation technique. Anything whose past value could ever be asked for is
event-sourced; current state is a *projection* — derived, cached, rebuildable, never the
source of truth. Snapshot only at boundaries that must reproduce independently, and
justify each one. ([ADR-0009](docs/adr/0009-event-sourcing-by-default.md))

**4. Everything downstream reads the event stream.** The engine emits typed
`PlayRecord`s. Box scores, grades, news, highlights and tendencies are *queries* over
that stream — never accumulated in parallel with the simulation. This is what lets the
engine be replaced without touching anything above it.
([ADR-0007](docs/adr/0007-event-stream-contract.md))

**5. The tick loop never allocates.** The engine has a hard budget — a season in ~60s,
about 1.1µs per entity-tick. Flat arrays of `struct`, no dictionaries, no per-tick
object churn, no string building during simulation. This is architectural; retrofitting
it is a rewrite. ([ADR-0006](docs/adr/0006-spatial-simulation.md))

**6. Game rules live in the sim, never in a view.** If a SwiftUI view contains an `if`
that decides something about football, it's in the wrong layer.

**7. Only `FMPersistence` knows SwiftData exists.**

**8. Never ship real names or marks.** No real players, teams, leagues, logos, or
likenesses — not in code, not in test fixtures, not in placeholder data. Generated
fiction only. Citing a rulebook by rule number and season is fine; pasting its text into
the repo is not. ([ADR-0005](docs/adr/0005-generated-fictional-content.md))

**9. Never regenerate a golden test file to make a red test pass.** If the engine
changed on purpose, regenerate it in the same commit and describe the behavior change
in the commit message. If you didn't mean to change behavior, you found a bug. And never
retune a calibration constant to keep a harness row green inside a fix: report the row
that moved and why, and leave tuning to a dedicated retune.

**10. Football is asserted from a reference, never from memory.** A claim about the
sport — in a doc, a test name, a PR — cites a rule number and rulebook season, or a
real-league season and the source the number came from. A claim about the engine's
behaviour cites a harness row or a scenario test. The reference the engine was first
written from was memory, and the code carried its errors for weeks while a table in the
football-domain skill said the opposite and nothing connected the two. The reference is
[`docs/reference/`](docs/reference/) — the rules by article number, and where every
calibration band came from — and what must be true of a game is
[`docs/invariants.md`](docs/invariants.md), where each line names the test that checks it.

**11. Football tests come first, and every test says what kind it is.** A change to the
rules layer, the resolver, or a caller lands with at least one football test it turned
green: a scenario or a sourced statistical band, written from the reference *before* the
code, committed red, then made green. A test derived from the code afterwards is a
regression pin, not a football test, and is tagged as one. Nobody asserts a football
outcome they cannot cite. Details under Conventions → Tests.

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
  the `football-domain` skill has the reference. Fluent vocabulary is not correct rules;
  the code sounded like a broadcast while the wrong team kicked off after a safety.

**SwiftUI**
- Views are small and take exactly what they render. A view that takes the whole
  `World` is a smell.
- One `@Observable` `@MainActor` store per feature area. Views hold no logic.
- Everything supports Dynamic Type and VoiceOver from the start; retrofitting
  accessibility onto a dense roster table is much worse than building it in.

**Tests**
- Swift Testing (`@Test`), not XCTest, for new code.
- Every test is one of three kinds, and carries the tag:
  - `.football` asserts something true of the sport: a scenario from the rules reference,
    or a band from a sourced season. Named as the football sentence plus its citation.
    Written from the reference before the code, committed red, then made green.
  - `.contract` asserts a promise the engine makes about itself: the same seed replays
    identically, decisions agree with the outcome, twenty-two men are on every play, the
    scoreboard is the stream summed.
  - `.unit` asserts a unit does its arithmetic: cap math, RNG known answers.
  - A test that pins current behaviour because changing it would be surprising is
    `.pin`, and its name says what it pins and why.
- A harness band with a sourced season counts as a football test for a rate. A scenario
  is the only acceptable test for a rules change; a unit test on the helper alone is not.
- Balance is measured, not hoped for. `scripts/test-census.sh` counts tags per package
  and CI prints it; what the kinds mean and what the suite currently looks like when you
  count it are in [`docs/testing.md`](docs/testing.md). A football share that falls in the
  rules layer or the resolver between milestones is a finding.
- Cap math, clock rules, and schedule generation get exhaustive unit tests. They're
  rule-based, player-visible, and easy to get subtly wrong.
- Engine changes need both a golden-seed test and a statistical check.
- A test that needs a `ModelContext` to test a game rule means the rule is in the
  wrong layer.
- A test that encodes a bug is rewritten, not deleted, and the PR says so.

**Docs**
- A change that alters the design updates the doc in the same commit.
- A decision that was hard to make, or that rejected a real alternative, gets an ADR.
  Use `/adr`.
- A doc describes intent; the tree describes reality. Where they disagree, the doc says
  so at the top rather than describing the intent in the present tense.

## Working style here

- **Check the docs before proposing a design.** Most architectural questions are
  already answered in `docs/`. If a doc is wrong, say so and fix it — don't silently
  work around it.
- **Prefer breadth before depth.** Per the [roadmap](docs/roadmap.md), a crude complete
  system beats one beautiful subsystem attached to nothing. Get it end-to-end, then
  deepen.
- **Balance the engine with the harness, not by playing.** Tuning constants is done
  against `Tools/simharness` output and the
  [calibration table](docs/match-engine.md#calibration), and only in a retune issue.
- **Watch a game.** Aggregates hid every rules bug the audit found. Read one full game
  of `Tools/gamelog` output before and after any engine change — the recipe is in
  [tools.md](docs/tools.md#gamelog--watch-a-game).
- **The whimsy goes in the world, not the engine.** Trait names, news voice, and draft
  storylines are playful. The physics never winks and no outcome is authored.
- **Check `design-decisions.md` before assuming.** Most decisions are settled; the ones
  that are not are listed under *Open questions* at the end. If your work depends on an
  open one, ask. Decisions the audit reopened are marked there with the issue that
  reopens them.
- **Grill before you build.** Anything substantial starts with the questions, not the
  code. Surface the design choices, name what each one trades away, give a
  recommendation on every one, and *wait*. "Anything else we should settle before we
  begin?" is the expected opening for a new system, not a courtesy — and it is wanted
  even when the request sounds like a straightforward instruction. Small judgment calls
  inside work already agreed: just make them. **When you are executing a backlog issue,
  the questions were asked when the issue was written**: do not reopen them, but stop and
  report the moment the plan proves wrong rather than guessing past it.
- **A recommendation, not a survey.** Lay out the real alternatives with the one you
  would pick and why. An exhaustive list with no opinion is not help; neither is a
  decision made silently because the options seemed obvious.
- **Say plainly what you did not check.** Distinguish measured from assumed, every
  time. "All fifteen calibration rows land" and "it builds" are different claims, and
  so are "the test passes" and "I ran it four times and it passed four times".
- **Every number printed gets a target or a reason it has none.** The harness printed
  eighteen ties in four hundred games on every run for a week. Nobody had written down
  that the real number is two.

## Current work: the audit backlog

The tracker is **#1**. Issues carry `track:` and `wave:` labels and a `status:`
label that is the state machine. Wave 0 runs in parallel; every wave after it changes
engine behaviour and therefore the golden constants, so those issues run one at a time in
wave order and rebase.

- Integration branch: `main`. Work branches: `fix/<issue>-<slug>`, cut from `main`.
- Before you push: all four suites green, `swift test -c release` for FMRandom,
  `swift format lint --strict` clean, `playsize` builds.
- Goldens regenerated in the same commit as the behaviour change, with the change
  described. Never to make a red test pass.
- No retuning in a fix. Run `simharness --games 400` at seeds 7 and 11 before and after,
  once per seed, or paste the output of `scripts/harness-reach.sh` showing the change
  cannot reach it; paste the rows that moved into the PR body with one line on why.
- The PR body names the issue it closes, what was measured versus assumed, and the
  harness rows before and after. No model identifiers in commit or PR text beyond the
  attribution trailer the tooling appends.
- A test that encodes a bug is rewritten, not deleted, and the PR says so.
- If the issue's plan is wrong or something is unknown, stop and report on the issue.
  Do not guess.

## Commands

```
# Available now
swift build --package-path Packages/FMRandom
swift test  --package-path Packages/FMRandom
swift test  -c release --package-path Packages/FMRandom   # integer maths must agree with debug
swift test  --package-path Packages/FMCore
swift test  --package-path Packages/FMGeneration
swift test  --package-path Packages/FMSimulation          # ~45s; the engine's own suite
swift run   --package-path Tools/playsize                 # play record footprint; also
                                                          # proves FM* modules link standalone
cd Tools/worldgen && swift run worldgen --help            # inspect generated content
                                                          # see docs/tools.md for recipes
cd Tools/simharness && swift run simharness --games 400 --seed 7
                                                          # the calibration harness. Weather
                                                          # and rare-event rows need --games 1000
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11
                                                          # one game, play by play. Read one
                                                          # before and after an engine change
swift format lint --strict --recursive --parallel Packages/ Tools/
                                                          # run before committing. Without
                                                          # --strict the linter prints its
                                                          # findings and still exits 0, so a
                                                          # script that trusts the exit code
                                                          # passes while CI fails
swift format --in-place --recursive --parallel Packages/ Tools/
scripts/lint-sim.sh                                       # banned primitives, no Foundation;
                                                          # see docs/tools.md
scripts/lint-sim.sh --self-test                           # the lint's own fixture test; run it
                                                          # when you change it or add a rule
scripts/test-census.sh                                    # test kinds per target and per suite;
                                                          # fails on a @Test with no kind tag.
                                                          # docs/testing.md reads the shares
scripts/test-census.sh --self-test                        # the census's own fixture test

# Planned — land with the backlog
xcodebuild -scheme FootballManager -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Note on this environment:** Claude Code web sessions run on Linux with no Xcode. The
`FM*` packages are framework-free by design and build on any Swift 6 toolchain, so
package work *can* be verified here — but only once a toolchain is installed. Containers
start without one.

Run `./scripts/install-swift.sh` to install it. This needs the environment's network
policy to allow `download.swift.org`; without that the script fails with a proxy 403 and
**no Swift can be compiled or tested in the session at all**.

Check before claiming anything is verified:

```
command -v swift || ./scripts/install-swift.sh
```

Anything touching the app target, SwiftData, or SwiftUI can only be checked on a Mac
regardless. Never describe untested code as working — say plainly that it is unverified.

## Skills

- `/adr` — write an architecture decision record
- `/feature-module` — scaffold a new feature module to the repo's layering
- `/football-domain` — reference for football rules, terminology, roster and cap
  structure. Load it before writing sim logic or naming domain types.
