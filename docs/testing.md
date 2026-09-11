# Testing

**Status: built.** The tags, the script and the census on this page all exist and run
today. The working agreement is [`CLAUDE.md`](../CLAUDE.md) — rule 11 and
*Conventions → Tests*; this page is what the suite actually looks like when you count it.

## The taxonomy

Every `@Test` in every test target carries exactly one kind tag. A test with none fails
`scripts/test-census.sh`, and CI fails with it.

| Tag | Asserts | The test is one of these only if |
| --- | --- | --- |
| `.football` | Something true of the sport | its name or its doc comment **cites** a rule article and rulebook season, or a real-league season and the source the number came from |
| `.contract` | A promise the engine makes about itself | breaking it breaks replay, the stream, a projection, a golden, or the traceability between the docs and the tests |
| `.unit` | A unit computes or validates what it should | it is arithmetic or a table's own well-formedness — cap maths, RNG known answers |
| `.pin` | Current behaviour, pinned | its name says what it pins and why |

The citation is the whole point of the first row. A test can read like the sport,
be named like the sport, and still be a claim somebody made from memory — which is
exactly how the engine carried five rules bugs for weeks. **An uncited test is not a
football test**, however football it sounds, and it is tagged `.unit` until somebody goes
and reads the rule.

The tags are declared per test target, in `TestTags.swift` beside the tests — Swift
Testing tags are ordinary Swift declarations and each test target is its own module:

```
Packages/FMRandom/Tests/FMRandomTests/TestTags.swift
Packages/FMCore/Tests/FMCoreTests/TestTags.swift
Packages/FMGeneration/Tests/FMGenerationTests/TestTags.swift
Packages/FMSimulation/Tests/FMSimulationTests/TestTags.swift
Tools/simharness/Tests/simharnessTests/TestTags.swift
Tools/gamelog/Tests/gamelogTests/TestTags.swift
```

A tag rather than a naming convention because a tag is a value the toolchain knows about:
`@Tag` declarations are checked by the compiler, so a misspelt kind fails to build, where
a misspelt prefix in a display name is just a string that counts as something else.
Selecting a run by tag is a Swift Testing feature; SwiftPM on the 6.2 toolchain does not
expose a flag for it, so the census reads the tags out of the source instead.

## Counting it

```bash
./scripts/test-census.sh              # the table below, and a non-zero exit on an untagged test
./scripts/test-census.sh --list       # one line per test: file:line: kind
./scripts/test-census.sh --self-test  # the scanner's own fixture test
```

CI runs the census as a hard-failing step of the `test` job and writes the table into the
job summary, so the shares are in front of whoever opens the run rather than in a script
nobody remembers to call. See [tools.md](tools.md#test-census--what-the-suite-asserts).

The census reads the tags out of the source, so it counts a test that exists only in a
debug build. Two do: the exit tests that check an assertion fires —
`PositionWeightsTests.incompleteSetIsCaught` in FMCore and
`SchemeFitInEngineTests.missingKeyIsCaught` in FMSimulation — sit under `#if DEBUG`, are
in the table, and are absent from a `-c release` run. That costs nothing, because a
release run is required only of FMRandom (CI runs it both ways; its integer maths must
agree with optimisation on), and is run for FMGeneration when its goldens change so the
constants agree between builds. FMCore and FMSimulation run in debug, which is where
those two tests live.

## The first census

Taken on the merge of wave 1, at 717 tests.

| target | football | contract | unit | pin | total |
| --- | ---: | ---: | ---: | ---: | ---: |
| FMRandom | 0 — 0.0% | 3 — 9.1% | 30 — 90.9% | 0 | 33 |
| FMCore | 28 — 8.6% | 27 — 8.3% | 268 — 82.7% | 1 | 324 |
| FMGeneration | 0 — 0.0% | 66 — 38.2% | 107 — 61.8% | 0 | 173 |
| FMSimulation | 59 — 33.7% | 50 — 28.6% | 63 — 36.0% | 3 | 175 |
| simharness | 0 — 0.0% | 9 — 75.0% | 3 — 25.0% | 0 | 12 |
| **all** | **87 — 12.1%** | **155 — 21.6%** | **471 — 65.7%** | **4** | **717** |

A sixth target has joined the census since: `gamelog`, which was not in the table above,
and the table is left as it was taken.

The estimate this rule was written from was "roughly 85% checking that the code does what
the code does, about 10% the engine's own contracts, perhaps 5% the sport" — read off the
suite by hand, because nothing measured it. Measured, and after wave 1 added the
fifty-five-scenario rules-conformance suite, it was 65.7%, 21.6% and 12.1%. How much of
that move is wave 1 and how much is the estimate being an estimate has not been measured:
the tags do not exist on the pre-wave-1 tree, so the census cannot be taken there.

## The census as it stands

Taken on the merge of wave 2's record and ratings tracks with the whole of wave 3, plus
the two tests that came with a receiver training ball security, at 917 tests. `./scripts/test-census.sh` reprints it; if this table and that output disagree,
the output is right and this table is stale.

| target | football | contract | unit | pin | total |
| --- | ---: | ---: | ---: | ---: | ---: |
| FMRandom | 0 — 0.0% | 3 — 9.1% | 30 — 90.9% | 0 | 33 |
| FMCore | 54 — 14.4% | 33 — 8.8% | 286 — 76.1% | 3 | 376 |
| FMGeneration | 1 — 0.5% | 95 — 46.1% | 110 — 53.4% | 0 | 206 |
| FMSimulation | 115 — 40.5% | 91 — 32.0% | 70 — 24.6% | 8 | 284 |
| simharness | 0 — 0.0% | 11 — 78.6% | 3 — 21.4% | 0 | 14 |
| gamelog | 0 — 0.0% | 4 — 100.0% | 0 — 0.0% | 0 | 4 |
| **all** | **170 — 18.5%** | **237 — 25.8%** | **499 — 54.4%** | **11** | **917** |

Nothing is untagged, in any target, which is the census's hard-failing condition.

### Where the football is, and is not

The share that matters is not the tree's. It is the share **in the rules layer and in the
resolver**, which is what CLAUDE.md asks to watch between milestones.

The areas are sums over named suites of the census above, so the grouping can be checked
against `./scripts/test-census.sh` rather than taken on trust. The rules layer is *Down
and possession advancement*, *Rules*, *Clock stoppage*, *The ten-second runoff*, *The last
forty seconds*, *The play clock*, *Running the clock*, *Penalty enforcement*, *Tries and
touchbacks*, *A foul during a score*, *Free kick spots* and *The rulebook the defaults come
from* — the last three joined when wave 3's D track put a foul on a scoring play where the
rules put it, gave the free kick its spots, and made `Rules` say which book it is. The
resolver is *Crude resolver*, *Contest curve*, *Out of bounds*, *Punting* and *The dynamic
kickoff* — the last three are the resolver's own suites, split out when wave 3 gave it the
sideline, the aimed punt and the two kickoffs.

| Area | football | contract | unit | pin | total |
| --- | ---: | ---: | ---: | ---: | ---: |
| The rules layer — `Rules.advance`, `enforce`, the clock, the try (FMCore) | 51 — 44.7% | 6 | 54 | 3 | 114 |
| Rules conformance — the scripted games (FMSimulation) | 98 — 98.0% | 0 | 0 | 2 | 100 |
| The resolver — `CrudeResolver`, the contest curve, out of bounds, punting and the kickoff (FMSimulation) | 6 — 20.7% | 11 | 10 | 2 | 29 |
| Generation (FMGeneration) | 1 — 0.5% | 95 | 110 | 0 | 206 |

Three findings come straight off that table.

**The resolver asserts little football, and what it does assert is shape rather than
rate.** Six of its twenty-nine tests do, every one of them added by wave 3. Two came with
the sideline and the aimed punt: where a play ends laterally is a clock decision (4-3-2-a)
and a punt from plus territory beats the touchback (11-6-2-c, 9-5-1 Note a). Each of those
two asserts only what its articles actually say — the *direction* of the sideline lever,
and that a placed punt leaves the receivers short of the 20 a touchback would give them.
The magnitudes that shipped inside them (a trailing offence reaching the sideline twice as
often as a leading one, above a fifth of its tackles; fewer than 15% of plus-territory
punts reaching the end zone) came from the issues that built those levers rather than from
an article or a sourced season, so they are pinned beside the football tests instead of
inside them, and are the two `.pin` in that row. Its parametric rates — completion
percentage, sack rate, interception rate — are asserted by the harness's sourced bands
and by nothing in the suite. CLAUDE.md says a harness band with a sourced season counts
as a football test for a rate, and it does; but the census cannot see it, because
`simharness`'s own tests check that the table matches
[the doc](match-engine.md#calibration) and that a sourced band names its season, never
that a run lands inside one. A row going `OFF` in CI is reporting, not a failure. So the
`0.0%` in that row is honest about the suite and unfair to the harness, and both halves
of that sentence are worth remembering.

The other four came with the dynamic kickoff (#46): a kick into the landing zone is
returned, a penalty on the free kick changes what the kick can do, a kick that misses the
zone hands over 6-2-4's spot, and an onside kick dies where the rules let it be recovered.
They too assert the *shape* the articles require of the play rather than a rate, which is
what a suite can do about a resolver and a harness cannot. The finding stands for
everything the resolver draws that is only a rate.

**Fifty-four of the rules layer's one hundred and fourteen tests are `.unit`, and many of
them are football claims with no citation.** Three suites are the clearest:
`Tries and touchbacks`
(11 of 11 — what an extra point is worth, where a kickoff touchback is spotted), the
uncited fourteen of `Down and possession advancement`, and five of `Clock stoppage`.
Every one asserts something true of the sport; not one cites where it came from, so none
of them is tagged `.football`. That is the backlog rule 11 creates, and it is bigger than
the untagged-test problem this issue set out to fix.

**Generation makes almost no claim about the sport, and mostly should not.** A generated
league is fiction ([ADR-0005](adr/0005-generated-fictional-content.md)); what it owes is
determinism, structure, and a plausible spread — which is why `.contract` is
FMGeneration's largest share after `.unit`, and the highest of the four packages: 38.2% in
the first census, and 45.9% — 94 of 205 — now. Nearly `0.0%` football is the right answer
there, not a gap.

The exception, and the shape of any other: **a league of fictional people still has to be
made up like a real one.** [#67](https://github.com/knissley/football-manager/issues/67)
found a quarter of every roster in its first season, and no test in that `.contract` share
could have said so, because a fence written from the output said `< 0.30` and passed. What
replaced it is a `.football` band — the share of a roster in its first season, from three
seasons of week-1 rosters, with the derivation in
[`reference/calibration-sources.md`](reference/calibration-sources.md#bands-the-harness-cannot-measure).
An aggregate about a *roster* is exactly as sourceable as one about a game, and the harness
cannot see it, so it is the test that has to. Nobody's name, club or number is in the repo
for it — a count is not a likeness.

## Why the rule exists

Five hundred and sixty-two tests were green when the September 2026 audit read the
engine, and three of them asserted wrong football:

| Test | What it asserted | The rule |
| --- | --- | --- |
| `GameSimulatorTests.ties` | a level regular-season game ends after four periods | it plays one ten-minute overtime period first (4-1-1, 16-1-3) |
| `AdvancementTests.safety` | possession changes on a safety | the team scored upon keeps the ball to free-kick from its own 20 (11-5-2) |
| `ClockStoppageTests.liveBallRuns`, suite "Clock stoppage" in `GameClockTests.swift` | a downed punt keeps the clock running | a downed kick has changed hands, and that stops the clock (4-4-i) |

None of them was a slip in the code the test was reading. Each was a sentence about
football that somebody wrote down from memory, and then made the engine agree with. A
green suite is not evidence about the sport unless the tests in it cite something, which
is what rule 11 says and what the `.football` tag now records — and all three were
rewritten in wave 1 from the 2025 rulebook, with the article numbers in their names.

The other half of the same failure is that nobody had to look. The 85% was an impression,
and an impression can be disagreed with over a coffee and left alone. A number on every
CI run cannot: it has a target, which is that the rules layer and the resolver do not
lose football share between milestones, and a fall in either is a finding rather than a
matter of opinion.
