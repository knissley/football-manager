# Tools

Command-line tools for inspecting the engine without an app, an Xcode, or a Mac.
Everything here runs in a Claude Code web session, so it works from a phone: ask
for a command and read the output.

**Everything is reproducible from a seed.** The same seed prints the same world
every time, so anything surprising can be re-run exactly.

## worldgen — look at generated content

```bash
cd Tools/worldgen && swift run worldgen --help
```

| Command | Shows |
| --- | --- |
| `swift run worldgen --show roster --team 3` | A full 53-man roster |
| `swift run worldgen --show starters --team 7` | Projected starting lineup |
| `swift run worldgen --show league --teams 32` | Talent summary for every team |
| `swift run worldgen --show teams --teams 32` | Cities, colours, stadiums, divisions |
| `swift run worldgen --show class` | This year's draft class, top prospects and shape |
| `swift run worldgen --show pipeline` | All three visible classes at a glance |
| `swift run worldgen --show rivalries` | Seeded grudges, their history and heat |
| `swift run worldgen --show colleges` | The generated college pool |

Options: `--seed <n>` `--teams <n>` `--team <n>` `--season <n>` `--show <mode>`

Useful invocations:

```bash
# A contender and a rebuilding team from the same world, side by side
swift run worldgen --seed 42 --show starters --team 0
swift run worldgen --seed 42 --show starters --team 31

# Does the league's talent spread look right?
swift run worldgen --seed 7 --show league --teams 32

# The same team from a different world
swift run worldgen --seed 99 --show roster --team 3

# Does the world read as a league someone drew, or as output?
# Watch for: repeated city stems, colliding abbreviations, a "South" division
# full of cold-weather cities, every stadium a temperate dome.
swift run worldgen --seed 42 --show teams

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

The crude resolver owns the parametric rows — completion percentage, sack rate,
interception rate — because at matchup-lite fidelity those are inputs rather than
emergent properties. Rows that depend on the *shape* of the yardage distribution rather
than its mean are harder, and the spread of team win totals is not measurable at all
until a schedule exists in M3.

The output is byte-identical across processes for a given seed and game count, so the
before-and-after comparison every engine fix depends on is a plain `diff`. A line that
moves between two runs of the same binary at the same seed is a bug in the harness's
read-out, not noise (#52).

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

`--home` and `--away` are indices into `gamelog`'s own league, and the header names the
two teams it picked. **They do not agree with `worldgen`**, which draws a larger college
pool before its league and so builds a different world from the same seed; the indices
mean something across `gamelog` and `simharness` and nothing outside them. G1 (#3) is the
one world generator that makes all three agree.

`--week` is what the weather is drawn from: week 1 in a warm city is not the same game as
week 17 in a cold one.

Everything printed is a **query over the `PlayRecord` stream** — the score, the drive
boundaries and the period boundaries are folded out of the emitted plays using the same
`Rules` arithmetic the state machine used. The tool ends by comparing its own total
against the score the engine reported, and says so loudly if they disagree.

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

## Tests

```bash
swift test --package-path Packages/FMRandom
swift test --package-path Packages/FMCore
swift test --package-path Packages/FMGeneration
swift test --package-path Tools/simharness          # the calibration table cannot drift from its doc

# Integer maths must agree between debug and release
swift test -c release --package-path Packages/FMRandom
```

## lint-sim — the determinism and purity lint

```bash
./scripts/lint-sim.sh
```

Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree. It takes
about two seconds — run it before committing. CI runs it as a hard-failing step, on both
architectures, in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

It enforces two rules that were conventions with nothing behind them:

- The primitives [ADR-0003](adr/0003-deterministic-seeded-simulation.md) bans in the
  `Sources/` tree of every `FM*` package — `.random(`, `SystemRandomNumberGenerator`,
  `.shuffled()`, `.randomElement(`, `UUID(`, `Date(`, `Hasher(`, a clock or environment
  read — plus the framework imports
  [ADR-0004](adr/0004-pure-swift-domain-core.md) bans: `Foundation`, `Dispatch`,
  `SwiftData`, `SwiftUI`, `UIKit` and the rest. `playsize` already catches a framework
  dependency at link time; this catches it at the import, with a line number.
- `Hasher` in a `*Golden*Tests.swift`. Swift randomises its hash seed per process, so a
  golden checksum built on `Hasher` agrees with itself inside one run and disagrees with
  yesterday's — it cannot detect the drift it exists to detect. Both goldens use FNV-1a.

Comments are stripped before matching, so prose *about* the ban — the doc comment on
`SplittableRandom` naming `Int.random(in:using:)`, the one on each golden `Checksum`
saying it is deliberately not `Hasher` — does not trip the lint. String literals are
not stripped: interpolation can hold real code.

A file that genuinely needs an exemption goes in the `allowlist` array at the top of the
script as a `"<path> <rule-id>"` pair. It is empty today. Widening it to turn a red lint
green is the one thing it must not be used for.

## Formatting

```bash
swift format lint --recursive --parallel Packages/ Tools/     # before committing
swift format --in-place --recursive --parallel Packages/ Tools/
```

## Getting a toolchain

Containers start without Swift. Web sessions need it installed once per session:

```bash
command -v swift || ./scripts/install-swift.sh
```

This requires the environment's network policy to allow `download.swift.org`.
