# Tools

**Status: built.** Every tool and script on this page exists and runs today: `worldgen`,
`playsize`, `simharness`, `gamelog`, `scripts/lint-sim.sh`, `scripts/harness-reach.sh`
and `scripts/test-census.sh`. Nothing here is a plan.

Command-line tools for inspecting the engine without an app, an Xcode, or a Mac.
Everything here runs in a Claude Code web session, so it works from a phone: ask
for a command and read the output.

**Everything is reproducible from a seed.** The same seed prints the same world
every time, so anything surprising can be re-run exactly.

**Every tool builds its world the same way.**
`WorldGenerator.generate(seed:shape:franchises:season:)` in `FMGeneration` is the single
entry point, so `worldgen --seed 7` and
`simharness --seed 7` are looking at the same league, and so are the engine's tests. Since
[decision 215](design-decisions.md#world-generation) that league's thirty-two clubs are
curated rather than drawn, so two seeds are two sets of players in one set of buildings.

## worldgen — look at generated content

```bash
cd Tools/worldgen && swift run worldgen --help
```

| Command | Shows |
| --- | --- |
| `swift run worldgen --show roster --team 3` | A full 53-man roster |
| `swift run worldgen --show starters --team 7` | Projected starting lineup |
| `swift run worldgen --show league --teams 32` | Talent summary and strength offset for every team |
| `swift run worldgen --show teams --teams 32` | Cities, colours, stadiums, divisions |
| `swift run worldgen --show class` | This year's draft class, top prospects and shape |
| `swift run worldgen --show pipeline` | All three visible classes at a glance |
| `swift run worldgen --show rivalries` | Seeded grudges, their history and heat |
| `swift run worldgen --show colleges` | The generated college pool |

Options: `--seed <n>` `--teams <n>` `--team <n>` `--season <n>` `--show <mode>`
`--franchises curated|random`

**The clubs are the same every time.** A world starts from the curated thirty-two in
`FMGeneration.FranchiseSet` ([decision 215](design-decisions.md#world-generation)), so
`--show teams` prints the same league at every seed — the same cities, nicknames,
colours and grounds, down to which of them have roofs. The league's own name is curated
with them, so the header line of `--show teams` reads the same at every seed too
([#82](https://github.com/knissley/football-manager/issues/82)); under
`--franchises random` it is drawn from the pools with everything else. What the seed
still moves is everything a career is played with: rosters, strengths, schemes, the
draft pipeline and the rivalries. `--franchises random` is the old pool draw, kept as a
last resort behind the flag and deliberately not refined before M8; it is the only way
to see two seeds name two different leagues. A league larger than thirty-two —
`--teams 64` — is the curated set finished from the pools.

`--teams` is rounded down to the nearest legal shape — two conferences of divisions of
four — so it is really a multiple of eight, and the header prints what was built. The
`STR` column in `--show league` is the strength offset the team was drawn at, in overall
points either side of the league's middle; it sums to zero across the league by
construction, so a run whose column is flat is a bug and not a quiet season.

Useful invocations:

```bash
# A contender and a rebuilding team from the same world, side by side
swift run worldgen --seed 42 --show starters --team 0
swift run worldgen --seed 42 --show starters --team 31

# Does the league's talent spread look right?
swift run worldgen --seed 7 --show league --teams 32

# The same team from a different world
swift run worldgen --seed 99 --show roster --team 3

# Does the roster have a past? The DRAFT column carries round, pick and season, or
# UDFA and the season he signed. Watch for: nobody undrafted, a team of first-round
# picks, a history only one draft deep, a starter who went in the seventh with a
# ninety ceiling on every roster. The footer counts how many were drafted — about
# three quarters league-wide, higher on a contender — and how many are in their first
# season, which is about a sixth of the league, eight or nine of fifty-three
# (docs/reference/calibration-sources.md).
swift run worldgen --seed 7 --show roster --team 3

# The league a career starts in. Two seeds, one league: this is the check that
# the curated set is what a world is built from.
swift run worldgen --seed 7 --show teams
swift run worldgen --seed 11 --show teams

# Does a drawn world read as a league someone drew, or as output? Watch for:
# repeated city stems, colliding abbreviations, a "South" division full of
# cold-weather cities, every stadium a temperate dome.
swift run worldgen --seed 42 --show teams --franchises random

# Is the class a distribution or a ranking? Watch for: the same positions at the
# top every year, a flat ceiling histogram, production that never disagrees with
# ability, nobody declaring early.
swift run worldgen --seed 7 --season 2030 --show class

# Does the invented past hold together? Watch for: two championship games in one
# season, every rivalry the same origin, a league that opens as all blood feuds
# or all indifference.
swift run worldgen --seed 42 --season 2030 --show rivalries
```

Reading this output has now caught four classes of bug that the tests did not:
athletic profiles decoupled from position, dead scheme modifiers, a roster built for
the wrong scheme, and — here — duplicate stadium names, colliding abbreviations, four
cities sharing a stem, and divisions named for regions they did not contain. It is
worth doing every time the generator changes.

## playsize — footprint, and a link guard

```bash
swift run --package-path Tools/playsize
```

Reports the in-memory size of a play record and what it implies at league scale.

It has a second job: it is a plain executable depending only on the `FM*`
modules, so it fails to build if one of them picks up a framework dependency.
That has already caught `Double.rounded()` — which resolves to libm's `round` —
twice. Test targets hide the problem because the testing library links
Foundation.

## simharness — calibration

```bash
swift run --package-path Tools/simharness -- --games 60
```

Simulates games headless and prints the [calibration table](match-engine.md#calibration)
with each row marked `ok` or `OFF`, and beside every row the real-league season and the
source its band came from and the rule areas it depends on. **Tuning is done against this
and never by playing the app.**

The bands are `Tools/simharness/Sources/simharness/Targets.swift`, and the doc table is
generated from them: `swift run simharness --targets-markdown` prints it, and the
package's test fails if the doc and the array disagree. A row marked `stale` was sourced
under a different rulebook than the run and is never `ok`; one marked `unsourced` keeps a
band nobody has cited and is never `ok` either.

```bash
cd Tools/simharness && swift run simharness --games 400 --seed 7 --rulebook 2024
```

`--rulebook 2024` plays today's `Rules.standard` and compares the kickoff rows against
the bands sourced from the 2024 season; `--rulebook 2025` plays with the touchback at the
35 and compares against 2025. If the kickoff rows land under both, the mechanism is right
rather than tuned. The default run plays `Rules.standard` against the 2025 targets, so
the 2024-sourced rows warn at startup until D2 lands.

Games are played between teams of drawn strength, from the same generator `worldgen`
prints — the header names the spread the league was drawn at. Before that, every
calibration game was between two clubs of exactly league-average strength, which is not a
matchup that occurs in the sport and made every row that depends on one team being better
than the other meaningless. Because it is the shipping world, the harness also inherits
the roughly one-in-eight clubs whose roster was assembled for a scheme they no longer
play ([decision 214](design-decisions.md#world-generation)), which it did not before: a
few points of scheme fit come off those teams, so the calibration table is measured over
a league with badly-fitted rosters in it rather than a league of perfectly-fitted ones.

The crude resolver owns the parametric rows — completion percentage, sack rate,
interception rate — because at matchup-lite fidelity those are inputs rather than
emergent properties.

It measures far more than the parametric rows: where the points come from, how drives
end and start, the shape of the carry and dropback distributions rather than their means,
field goals by distance, red zone conversion, personnel and package shares, fourth-down
behaviour, penalties by foul, injuries, the endgame, and the weather and home-road
splits. One row in [the calibration table](match-engine.md#calibration) has no value at
all — the spread of team win totals, which needs a season with a schedule and arrives
with M3; it prints under **Not measured here** so the row cannot be quietly forgotten.

The weather and rare-event rows need `--games 1000`; at 400 there are only twenty-odd
heavy-rain games and the row is noise.

The output is byte-identical across processes for a given seed and game count, so the
before-and-after comparison every engine fix depends on is a plain `diff`. A line that
moves between two runs of the same binary at the same seed is a bug in the harness's
read-out, not noise (#52) — with one deliberate exception, the `Budget` block below.

CI checks that on every push, as a hard-failing step of the `test` job: two
`--games 50 --no-timing --seed 7` runs and a `cmp`, with the difference printed if there
is one (#72). It was a local duty before that, done twice per seed by whoever remembered.

### The world checksum

The header names the league the run was played in, as one number:

```text
simharness — 400 games, seed 7
  32 teams, strength offset -8.4 to 7.5
  world checksum bb034c43d9254a63  (no target: it names the league, it does not grade it)
```

It is `WorldChecksum` in `FMGeneration` — the same function `GoldenWorldTests` pins to a
checked-in constant, covering every part a generated world stores that can reach a snap:
every team and stadium, every roster and depth chart, the map of players the engine is
handed, the schemes, the strength offsets, and the draft pipeline and rivalries when a
world has them. Every variable-length group carries its length, so a depth chart
repartitioned over the same men is a different number. The doc comment on the type lists
what it reads and what it does not — the college pool by its size alone, a team's colours
not at all, and its name only as city-and-nickname joined, none of which is handed to
`GameSetup`. The number here is not
the golden's constant, because the harness generates a smaller world without the optional
parts, but it is the same function over it — which is what makes two *branches'* numbers
comparable.

It follows from the seed alone, so it does not disturb the byte-identical property above,
and it prints in `--no-timing` output too.

```bash
swift run --package-path Tools/simharness simharness --world-checksum-only --seed 7
# world checksum bb034c43d9254a63
```

`--world-checksum-only` generates the world, prints that one line and exits without
simulating — it takes a second, and it is how `scripts/harness-reach.sh` below asks two
builds whether they would play the same league.

### The Budget block

The run ends with a `Budget` block: the wall clock of the simulate calls alone, as ms per
game, the seconds that rate makes of a 272-game season, and the ~220 ms per game the
[60-second season budget](match-engine.md#performance-budget) allows, with the ratio
between them.

```text
  Budget
    Wall clock of the simulate calls alone — world generation, the weather draws
    and this report are outside it. Reporting only: no gate, and not a calibration
    target. It is the one block that moves between two runs of the same binary at
    the same seed, which is what --no-timing exists for.
    simulate calls                400 games in 5.90 s
    ms per game                   14.75
    seconds per 272-game season   4.01
    budget                        220.00 ms per game, 60 s a season (match-engine.md#performance-budget)
    ratio to budget               0.07x
```

**Reporting only.** Nothing gates on it, and timing is not a `CalibrationTarget`: a
wall-clock reading measures the machine that took it as much as the engine, so a band
would mean one thing on a laptop and another on a CI runner. What it is for is drift — the
budget is architectural ([ADR-0006](adr/0006-spatial-simulation.md)) and until this block
existed nothing measured it at all (#9).

It is printed **last**, after the verdicts, and it is the only part of the output that
moves between runs. `--no-timing` omits it, so the byte-identical check still works:

```bash
cd Tools/simharness
swift run -c release simharness --games 400 --seed 7 --no-timing | md5sum
```

Read the ratio, not the milliseconds. What one machine's milliseconds are worth is
unknown; what a doubling between two commits on the same machine means is not.

## gamelog — watch a game

```bash
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11
```

Simulates one game out of the same world `simharness` plays and prints it as a broadcast
log. One line per play: quarter and clock, the offence, down and distance, field position
in own or opponent terms, the concept, what happened and who did it, the personnel
matchup, any flag and how it was enforced, and the score after anything that scored. A
drive summary at each change of possession and a scoreboard at the end of each period.

Options: `--seed <n>` `--home <i>` `--away <i>` `--week <n>` `--season <n>`
`--scenario <name>`

`--home` and `--away` are indices into the league at that seed, in identifier order, and
the header names the two teams it picked. They agree with `worldgen` and `simharness`:
all three call `WorldGenerator.generate(seed:shape:franchises:season:)`, and every stage of
it draws from its own labelled substream, so `worldgen`'s larger college pool no longer
shifts the
league behind it. At seed 7, `--home 3` and `worldgen --seed 7 --show roster --team 3` are
the same club.

`--week` is what the weather is drawn from: week 1 in a warm city is not the same game as
week 17 in a cold one.

Everything printed is a **query over the `PlayRecord` stream** — the score, the drive
boundaries and the period boundaries are folded out of the emitted plays using the same
`Rules` arithmetic the state machine used. The tool ends by comparing its own total
against the score the engine reported, and says so loudly if they disagree.

A drive summary reads `── NRW drive: 4 plays, 34 yards, 1:52 — touchdown`: snaps from
scrimmage, net yards, the clock the drive had the ball, and how it ended. A drive that ran
out of period rather than out of downs is named by the break it ran into — `end of half`,
`end of regulation`, or `end of game`. Overtime is where that is easy to get wrong, and
#87 is where it was: the end of a first or a third postseason overtime period is **not** a
break, because the next one begins with the ball where it was and the same side in
possession (16-1-4-f, 4-2-3), so a drive runs straight through it and is printed once,
when it really ends. The end of a second or a fourth is one — the third and the fifth
period open a new half with a kickoff (16-1-4-e, 16-1-4-i) — and the drive chart ends a
drive there as it does at halftime, because both read `Rules.periodResumesWithKickoff`.
The last
drive of a game runs to 0:00, because in regulation the clock is the only thing that ends
a game — a kick that wins it at 0:03 does not, the horn does. The exception is again
overtime, where a score ends the game where it stands: a walk-off drive is charged to the
play that won it, and since no `PlayRecord` carries the interval before a snap, that one
line is short by that interval and by nothing else.

**Read one game end to end before and after any engine change.** This is the recipe:

```bash
# Before the change, and again after it. Read both; diff them if the change was meant
# to be behaviour-preserving.
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11 > /tmp/before.txt

# The same game in bad weather, which is a different game.
swift run gamelog --seed 7 --home 3 --away 11 --week 17

# A different matchup out of the same world, for a second opinion.
swift run gamelog --seed 7 --home 12 --away 5
```

Watch for the things a table of means cannot show: who kicks off after a safety, whether
a touchdown gets its try, whether a tie plays overtime, how much clock burns between the
last snap of one possession and the first of the next, whether the same quarterback takes
every snap of a drive, and whether a penalty leaves the ball where the rule puts it.

Aggregates hid every rules bug the September audit found. Each of them is obvious in
thirty seconds of this output, which is why it exists.

### --scenario — watch a conformance scenario

```bash
cd Tools/gamelog && swift run gamelog --scenario list
cd Tools/gamelog && swift run gamelog --scenario safety-free-kick
```

The rules-conformance scenarios are the acceptance language for the rules layer: each one
is a game whose plays are dictated, so that what is left to watch is the clock, the downs,
possession, scoring, enforcement and overtime. The suite in
`Packages/FMSimulation/Tests/FMSimulationTests/RulesConformanceTests.swift` asserts on
them and prints a verdict; `--scenario` prints the game, so a rule can be *shown* to a
person rather than described to him.

It is the same game and the same printer. The scenario, its world, its caller and its seed
all come from `FMSimulationScenarios`, the library the suite runs, so what a reader watches
is what the suite asserts on, and the play-by-play is `printPlayByPlay` — the one a seeded
game goes through.

`--scenario list` names them all. The name is a slug (`safety-free-kick`) because a shell
argument cannot be the test's own sentence; under each name the list prints what the suite
asserts about it, verbatim — the football sentence and the rule it comes from — and the
same lines head the game itself, so a reader knows what he is looking for before the first
play goes by. Most scenarios play a *whole* game, and the moment the citation points at is
usually a handful of plays: read the header, then find them.

```bash
# The rule the audit's S11 was about: the side scored upon free-kicks from its own 20.
swift run gamelog --scenario safety-free-kick | head -20

# S10: a touchdown as the fourth quarter expires gets its try, at 0:00 of that period.
# Down six, the kick wins it and the game ends on the try, so the tail is short.
swift run gamelog --scenario last-play-touchdown-down-six | tail -10

# The same rule down seven, where the try levels it: the try is at 0:00 of the fourth
# and a ten-minute overtime period follows, so the play-by-play runs on past it.
swift run gamelog --scenario last-play-touchdown-down-seven | tail -40

# And the other half of the same rule: a try that could not change the outcome is waived.
swift run gamelog --scenario last-play-touchdown-down-two | tail -10

# A11 (#74): the overtime period has a two-minute warning. A play ends at OT 2:01 with
# the clock running, and the next snap comes at 2:00 rather than a huddle later.
swift run gamelog --scenario play-ending-just-before-the-two-minute-warning-of-overtime | tail -30

# Postseason overtime pairs its periods into halves: a first period has no warning, a
# second has the first half's. The period label counts them — OT, 2OT, 3OT.
swift run gamelog --scenario play-ending-just-before-the-two-minute-warning-of-a-second-postseason-overtime-period | tail -30

# A13 (#85): the late out-of-bounds window is judged where the runner stepped out. A
# play snapped outside 5:00 of the fourth quarter carries him out inside it, and the
# next snap comes with the clock stopped rather than a huddle later.
swift run gamelog --scenario runner-out-of-bounds-across-five-minutes-of-the-fourth-quarter | tail -30

# A14 (#86): a third postseason overtime period opens a new half — a kickoff at 3OT
# 15:00, kicked to the side that lost the toss before overtime, and three timeouts each
# again; the 2OT boundary before it is played straight through.
swift run gamelog --scenario third-postseason-overtime-period | tail -60
```

The men are not named in a scenario — a scripted outcome credits nobody, so the log says
"the back" and "the kicker" — and the header says so. Everything else reads exactly as a
seeded game does.

## Tests

```bash
swift test --package-path Packages/FMRandom
swift test --package-path Packages/FMCore
swift test --package-path Packages/FMGeneration
swift test --package-path Packages/FMSimulation      # ~45s; the engine's own suite
swift test --package-path Tools/simharness          # the calibration table cannot drift from its doc
swift test --package-path Tools/gamelog             # what a drive summary says about the clock

# Integer maths must agree between debug and release
swift test -c release --package-path Packages/FMRandom
```

Every one of these is a hard-failing step of the `test` job in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml), on both architectures —
`Tools/simharness` since #9 and `Tools/gamelog` since #87, because nothing else compiles
either tool's tests, or in gamelog's case the tool itself.

Every `@Test` in all six targets carries a kind tag, and
[`test-census`](#test-census--what-the-suite-asserts) below fails on one that does not.
What the kinds mean and what the suite currently looks like when you count it are in
[testing.md](testing.md).

### The conformance scenarios are a library, not test support

`FMSimulation` ships a second library, **`FMSimulationScenarios`**: the scripted games the
rules-conformance suite runs — `Snap` and the outcome vocabulary, `ScriptedCaller`,
`ScriptedGame`, the `Trace` a game produces, `ScenarioWorld`, and the scenarios themselves.
It is a plain `FM*` module: no Swift Testing, no Foundation, and `scripts/lint-sim.sh`
scans it like any other.

It is a library rather than a test target so that a tool can link it, which is what
`gamelog --scenario` does. What stays in `Packages/FMSimulation/Tests/` is the half only a
test can hold: the assertions over a `Trace` (`expectPlay` and the rest, in
`Scenarios/TraceAssertions.swift`) and the conformance suite itself.

Every scenario the suite runs is a case of `RulesScenario`, and that enum is the only way
to reach one — the scripts are internal to the library. So the list `--scenario list`
prints is the list the suite runs, by construction rather than by upkeep, and
`Scenarios/ScenarioLibraryTests.swift` pins the rest: that the listing names every
scenario with the football it is there to show, that the printed name is the name the tool
parses back, and that every scenario still runs.

## lint-sim — the determinism and purity lint

```bash
./scripts/lint-sim.sh
```

Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree; exits 2 when
it would otherwise have passed by scanning nothing — a `Sources/` directory that is gone,
or that is there and holds no Swift files. It takes two to five seconds depending on what
else the machine is doing — run it before committing. CI runs it as a hard-failing step,
on both architectures, in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml),
next to the self-test below.

It enforces two rules that were conventions with nothing behind them:

- The primitives [ADR-0003](adr/0003-deterministic-seeded-simulation.md) bans in the
  `Sources/` trees of `FMCore`, `FMRandom`, `FMGeneration` and `FMSimulation` —
  `.random(`, `SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement(`, `UUID(`,
  `Date(`, `Hasher(`, a clock or environment read — plus the framework imports
  [ADR-0004](adr/0004-pure-swift-domain-core.md) bans: `Foundation`,
  `FoundationEssentials`, `Dispatch`, `SwiftData`, `SwiftUI`, `UIKit` and the rest.
  `playsize` already catches a framework dependency at link time; this catches it at the
  import, with a line number.
- `Hasher` in a `*Golden*Tests.swift`. Swift randomises its hash seed per process, so a
  golden checksum built on `Hasher` agrees with itself inside one run and disagrees with
  yesterday's — it cannot detect the drift it exists to detect. Both goldens use FNV-1a.
  The world golden's checksum now lives in `FMGeneration` as `WorldChecksum`, so that
  `simharness` can print the same number; `Hasher(` is banned there by the rule above,
  which scans every `FM*` `Sources/` tree.

Comments are stripped before matching, so prose *about* the ban — the doc comment on
`SplittableRandom` naming `Int.random(in:using:)`, the one on each golden `Checksum`
saying it is deliberately not `Hasher` — does not trip the lint. String literals are
not stripped: interpolation can hold real code.

The stripper is not airtight, and a clean run is not proof. It walks a line at a time and
never rejoins what a comment split, so `Date/* x */()` matches no rule; the script header
says so at length. The golden tests, the replay contract tests and review are what catch
the rest.

That list of four packages is written out in the script rather than globbed.
`FMPersistence` is an `FM*` package that must *not* be scanned — SwiftData lives there by
design — so `Packages/FM*` would be the wrong check, not a shorter one. When `FMAnalysis`
or `FMNarrative` lands, add it to the `packages` array; nothing else will.

A file that genuinely needs an exemption goes in the `allowlist` array at the top of the
script as a `"<path> <rule-id>"` pair. It is empty today. Widening it to turn a red lint
green is the one thing it must not be used for.

### The self-test

```bash
./scripts/lint-sim.sh --self-test
```

The comment stripper is the subtle part of the script, and for a while nothing checked
it. `--self-test` lints
[`scripts/lint-sim-fixtures/`](../scripts/lint-sim-fixtures) instead of the packages.
That tree holds a Swift file per rule — never compiled, never part of a package, never
scanned by the real lint, because they carry banned tokens on purpose — each with a plain
hit plus the same token behind a line comment and inside a block comment. Alongside them
sit a negative control naming every banned token in comments, the golden `Hasher`
doc-comment case, and the shapes the stripper has to get right: a string literal holding
`//`, an escaped quote, a multi-line string, and a block comment that opens or closes
mid-line.

Every hit the tree must produce is listed in `scripts/lint-sim-fixtures/expected.txt` as
`path:line: rule-id`, and a difference in either direction fails — a hit that quietly
stops firing is caught as loudly as a new false positive. So a new rule needs a fixture
and an expectation line. It runs in under a second, and CI runs it as its own
hard-failing step.

## harness-reach — can this change reach the harness?

```bash
./scripts/harness-reach.sh origin/main
```

Prints exactly one line — `skip` or `run`, and why — and exits 0 for `skip`, 1 for `run`,
2 when it could not decide. Everything else it says goes to stderr, so the line is safe
to paste into a PR body.

```text
run  the engine's own sources moved against origin/main — 1 file(s): Packages/FMSimulation/Sources/FMSimulation/Fumbles.swift — run the harness
skip  no engine source moved against origin/main and the world is identical at seeds 7 11 (bb034c43d9254a63 85c82634e3d87e7e) — the harness cannot see this change
```

Every fix in the backlog runs `simharness --games 400` at two seeds, before and after, and
again in each review round. For a change the harness genuinely cannot see — the hundred
lines of rivalry generation in #64, which the calibration world never draws — that is four
sweeps to prove a negative. The rule was unconditional because "the harness cannot see
this" was an *argument a reviewer wrote*, and an argument holds only until somebody adds
rivalries to the harness world. This is the same claim, made by the tooling instead
(#72): CLAUDE.md takes this one line in place of the sweep, and the double run at a seed
is now CI's job rather than the implementer's.

It says `skip` only when both of these hold:

1. `git diff <base-ref>` is empty over the engine's own sources — `FMSimulation`,
   `FMCore` and `FMRandom`'s `Sources`, `Tools/simharness/Sources`, each package's
   `Package.swift`, and `FMGeneration`'s `WeatherGenerator.swift`, which the harness calls
   directly for every game. Files that are new and uncommitted count as changes; without
   that, an uncommitted file in `FMSimulation/Sources` would be invisible and the answer
   confidently wrong.
2. The world checksum at seeds 7 and 11 is the same on the working tree and on the base.
   It builds the base in a scratch directory extracted with `git archive` — nothing
   touches your index or working tree — and asks both with `--world-checksum-only`.

`FMGeneration`'s sources are deliberately absent from that first list. Generation reaches
the harness only through the world it builds, and the checksum covers every part a
`GeneratedWorld` stores that can reach a snap — including `world.players`, the map the
engine is handed, and the length of every variable-length group — so a generator change
that moves nothing the harness plays is exactly the case this tool exists to wave through.
The parts it leaves out are the ones no snap reads: the college pool beyond its size, a
club's colours, and the boundary between its city and its nickname. What it cannot speak
for is anything the world does not store: the weather drawn per game is why
`WeatherGenerator.swift` and that package's manifest are watched by name. Nor can it speak
for the toolchain — it compares two builds made minutes apart on one machine, which is the
case it is for.

### Its self-test

```bash
./scripts/harness-reach.sh --self-test
```

The test for the script, in the shape [`lint-sim.sh --self-test`](#the-self-test) uses. It
copies the working tree into a scratch repository, commits it as a base, and applies six
scripted changes whose answers are known:

| Scripted change | Expected | Which arm decides |
| --- | --- | --- |
| An engine constant in `Fumbles.swift` | `run` | the file list |
| A line appended to `docs/tools.md` | `skip` | both, having found nothing |
| `WorldGenerator.strengthSpread` | `run` | the checksum — no watched file moved |
| `RivalryGenerator`'s events per season | `skip` | the checksum — the harness draws no rivalries |
| `world.players` given five points of speed the rosters do not have | `run` | the checksum |
| A depth chart repartitioned over the same men | `run` | the checksum |

A scenario that answers wrongly, or answers rightly for the wrong reason — every case but
the first two is decided by the checksum with no watched file moved — fails the run and
prints what it got. If a fixture edit stops applying because the constant it names has
moved, that fails too, loudly, rather than turning into a scenario that tests nothing.

The last two are the first review round's findings on #72, kept as scenarios rather than
as a reviewer's memory: both moved the harness by hundreds of lines while the checksum
called the two leagues identical.

It builds a harness per scenario that reaches one — a few minutes on a warm Linux
container, longer from cold — so run it when you change the script. CI does not run it, deliberately: the determinism step in the `test` job is the cheap guard
that runs on every push.

## test-census — what the suite asserts

```bash
./scripts/test-census.sh
```

Counts the kind tag on every `@Test` in every test target, per target and per suite, and
prints the shares. Exits 1 on a test that carries no kind or carries two, naming it as
`file:line: what is wrong`; exits 2 when it would otherwise have passed by counting
nothing. It takes under a second — it is a text scan, not a build.

```text
test census — 717 @Test declarations in 5 targets

  target           football   contract       unit        pin   untagged   total
  FMRandom          0   0.0%    3   9.1%   30  90.9%    0   0.0%    0   0.0%      33
  FMCore           28   8.6%   27   8.3%  268  82.7%    1   0.3%    0   0.0%     324
  FMGeneration      0   0.0%   66  38.2%  107  61.8%    0   0.0%    0   0.0%     173
  FMSimulation     59  33.7%   50  28.6%   63  36.0%    3   1.7%    0   0.0%     175
  simharness        0   0.0%    9  75.0%    3  25.0%    0   0.0%    0   0.0%      12
  all              87  12.1%  155  21.6%  471  65.7%    4   0.6%    0   0.0%     717
```

The kinds are `.football`, `.contract`, `.unit` and `.pin`, defined in CLAUDE.md under
*Conventions → Tests* and declared per test target in `TestTags.swift`. What the shares
mean, and what the first census found, are in [testing.md](testing.md) — that page is
where a number from this table gets argued with, not this one.

`--list` prints one line per test, `file:line: kind`, which is how you find out what a
suite is made of without reading it:

```bash
./scripts/test-census.sh --list | grep FMSimulation | grep football | wc -l
```

CI runs the census as a hard-failing step of the `test` job on both architectures and
writes the table into the job summary, so the shares are in front of whoever opens the
run. It is architecture-independent — it reads source, not behaviour — so the two legs
print the same table, and that is the cost of not having a third job.

The scan is deliberately literal. A line that *begins* with `@Test` opens an attribute,
which is then accumulated until its parentheses balance: that is what makes a multi-line
attribute and a parameterised test count once each. Lines inside a `"""` string and
inside a `/* */` block are skipped, so prose about a `@Test` does not become one. A
`@Test` written any other way is meant to be missed here and caught in review — and the
per-target totals printed above are the check on that, because they have to agree with
what `swift test` reports it ran.

### Its self-test

```bash
./scripts/test-census.sh --self-test
```

The test for the script, in the shape [`lint-sim.sh --self-test`](#the-self-test) uses.
It censuses [`scripts/test-census-fixtures/`](../scripts/test-census-fixtures) instead of
the packages: two Swift files that are never compiled and never part of a package, one
carrying a test of each kind plus every shape the scan has to get right — a multi-line
attribute, a parameterised test, a tag on the `@Suite` rather than on the test, a struct
with no `@Suite` at all, and `@Test` written inside a doc comment, inside a block comment
and inside a multi-line string — and one carrying the four ways a test can fail to say
what kind it is.

Every test the fixture tree must produce is listed in
`scripts/test-census-fixtures/expected.txt` as `path:line: kind`, and a difference in
either direction fails: a shape that quietly stops being counted is caught as loudly as
one counted twice. So a new shape needs a fixture and an expectation line. It runs in
under a second, and CI runs it as its own hard-failing step.

## Formatting

```bash
swift format lint --strict --recursive --parallel Packages/ Tools/   # before committing
swift format --in-place --recursive --parallel Packages/ Tools/
```

`--strict` is not optional: without it `swift format lint` prints its findings and still
exits 0, so a script that trusts the exit code passes while CI fails.

## Getting a toolchain

Containers start without Swift. Web sessions need it installed once per session:

```bash
command -v swift || ./scripts/install-swift.sh
```

This requires the environment's network policy to allow `download.swift.org`.
