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
with each row marked `ok` or `OFF`. **Tuning is done against this and never by playing
the app.**

The crude resolver owns the parametric rows — completion percentage, sack rate,
interception rate — because at matchup-lite fidelity those are inputs rather than
emergent properties. Rows that depend on the *shape* of the yardage distribution rather
than its mean are harder, and the spread of team win totals is not measurable at all
until a schedule exists in M3.

## Tests

```bash
swift test --package-path Packages/FMRandom
swift test --package-path Packages/FMCore
swift test --package-path Packages/FMGeneration

# Integer maths must agree between debug and release
swift test -c release --package-path Packages/FMRandom
```

## lint-sim — the determinism and purity lint

```bash
./scripts/lint-sim.sh
```

Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree. It takes
about two seconds — run it before committing. CI runs it as a hard failure once the
Linux workflow lands (issue H1); the script is the half that does the work.

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
