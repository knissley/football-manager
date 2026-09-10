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
| `.pin` | Current behaviour, pinned | its name says what it pins, why, and which issue owns changing it |

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

The estimate this rule was written from was "roughly 85% checking that the code does what
the code does, about 10% the engine's own contracts, perhaps 5% the sport" — read off the
suite by hand, because nothing measured it. Measured, and after wave 1 added the
fifty-five-scenario rules-conformance suite, it is 65.7%, 21.6% and 12.1%. How much of
that move is wave 1 and how much is the estimate being an estimate has not been measured:
the tags do not exist on the pre-wave-1 tree, so the census cannot be taken there.

### Where the football is, and is not

The share that matters is not the tree's. It is the share **in the rules layer and in the
resolver**, which is what CLAUDE.md asks to watch between milestones.

| Area | football | contract | unit | pin | total |
| --- | ---: | ---: | ---: | ---: | ---: |
| The rules layer — `Rules.advance`, `enforce`, the clock, the try (FMCore) | 25 — 30.5% | 4 | 52 | 1 | 82 |
| Rules conformance — the scripted games (FMSimulation) | 54 — 98.2% | 0 | 0 | 1 | 55 |
| The resolver — `CrudeResolver` and the contest curve (FMSimulation) | 0 — 0.0% | 10 | 6 | 0 | 16 |
| Generation (FMGeneration) | 0 — 0.0% | 66 | 107 | 0 | 173 |

Three findings come straight off that table.

**The resolver asserts no football at all.** Its parametric rates — completion
percentage, sack rate, interception rate — are asserted by the harness's sourced bands
and by nothing in the suite. CLAUDE.md says a harness band with a sourced season counts
as a football test for a rate, and it does; but the census cannot see it, because
`simharness`'s own tests check that the table matches
[the doc](match-engine.md#calibration) and that a sourced band names its season, never
that a run lands inside one. A row going `OFF` in CI is reporting, not a failure. So the
`0.0%` in that row is honest about the suite and unfair to the harness, and both halves
of that sentence are worth remembering.

**Fifty-two of the rules layer's eighty-two tests are `.unit`, and many of them are
football claims with no citation.** Three suites are the clearest: `Tries and touchbacks`
(11 of 11 — what an extra point is worth, where a kickoff touchback is spotted), the
uncited fourteen of `Down and possession advancement`, and five of `Clock stoppage`.
Every one asserts something true of the sport; not one cites where it came from, so none
of them is tagged `.football`. That is the backlog rule 11 creates, and it is bigger than
the untagged-test problem this issue set out to fix.

**Generation makes no claim about the sport, and should not.** A generated league is
fiction ([ADR-0005](adr/0005-generated-fictional-content.md)); what it owes is
determinism, structure, and a plausible spread — which is why 38% of FMGeneration is
`.contract`, the highest share anywhere. `0.0%` football is the right answer there, not a
gap.

## Why the rule exists

Five hundred and sixty-two tests were green when the September 2026 audit read the
engine, and three of them asserted wrong football:

| Test | What it asserted | The rule |
| --- | --- | --- |
| `GameSimulatorTests.ties` | a level regular-season game ends after four periods | it plays one ten-minute overtime period first (4-1-1, 16-1-3) |
| `AdvancementTests.safety` | possession changes on a safety | the team scored upon keeps the ball to free-kick from its own 20 (11-5-2) |
| `ClockStoppageTests.liveBallRuns` | a downed punt keeps the clock running | a downed kick has changed hands, and that stops the clock (4-4-i) |

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
