# Agent throughput: the proposal

**Status: proposed, not dispatched.** Nothing below is built. Measured on `main` at
`cf885fb`, 2026-09-14, on a four-core Linux container with Swift 6.2, unless a line says
*assumed*. The owner reviews this page, then the orchestrator files each item as an issue
in the standard body and dispatches in the order in section 4.

## 1. The finding

PR #185 landed one line of engine change in about two and a half hours and a large share
of a session's budget. The report on #1 attributed the cost to the pre-push checklist
running three times. The checklist was measured here and it is not the cost. Cold, from a
clean tree, the entire mandated list is about nine minutes:

| step | seconds |
|---|---:|
| FMRandom, debug and release | 33 |
| FMCore | 34 |
| FMGeneration | 67 |
| FMSimulation, debug | 216 cold, 173 warm |
| simharness release build, then 400 games at one seed | 63, then 16 |
| simharness and gamelog suites, playsize, format lint | 85 |
| the nine shell and Python lints with their self-tests | 4 |

What the cost actually is:

- **FMSimulation spends 165 of its 173 seconds building the forty-game corpus in a debug
  binary.** Every suite reports the same 165 seconds because all of them wait on it. The
  same suite under `-c release` runs in 15 seconds; `--filter ForwardProgressTests` runs
  in 3. One test, behind `#if DEBUG`, is the only difference between the two runs. The
  brief forbids both variants, so the implementer ran the 173-second version twelve times.
- **The brief says a harness seed is two to three minutes. It is 16 seconds.** Agents
  budget turns and chunk work against the stated figure.
- **Every FMSimulation run puts about 800 lines and 100 KB of green checkmarks into the
  agent's context**, carried in every turn after it. Twelve runs is over a megabyte.
- **Per round the suites run six times**: implementer, a reviewer told to run everything
  itself, and CI twice per push (`push` and `pull_request` both fire) on two
  architectures. A CI run is six minutes. The 49-minute "queue stall" was the round-two run
  sitting queued from 04:20 until the round-three push cancelled it at 05:09 (inferred from
  run timestamps; the runner log was not read).
- **The prose is the largest output.** The last twelve merged PR bodies average about
  2,200 words. #185's was 2,267 for one visibility change; its commit messages run to 400
  words; the implementer's report has six mandated sections; the tracker's Current state
  is about 2,000 words rewritten on every merge. Before starting, an implementer is told
  to read about 61,000 words (CLAUDE.md 3,700; the orchestrator skill 4,100; the docs they
  point at the rest).

Why the documentation corrections keep coming, which is the other half of the ask:

- Since 2026-09-10, **39 of 254 non-merge commits are review or correction rounds**, and
  the two most-edited files in the repository are `docs/reference/playing-rules.md` and
  `docs/invariants.md` at 56 commits each, ahead of every Swift file.
- **Every rule has three homes.** Of the 75 articles the football-domain skill's
  `game-rules.md` cites, 74 are also in `playing-rules.md`; `invariants.md` cites 83. The
  D-track branch fixed 6-2-3 in the reference and shipped it wrong in the skill in one
  commit set, through review. #93 item 1 is this fix and is blocked behind four record
  issues it does not share files with.
- **Hand-maintained numbers with no machine check.** `invariants.md` has 130 hand-numbered
  entries and a header sentence stating their ranges; the traceability test checks only
  that there are more than 100. A 29-entry hand renumber went through CI green with a
  broken header and cost a third round. `testing.md`'s census table and `play-record.md`'s
  footprint are the same class. The pattern that works is already in the tree:
  `match-engine.md`'s calibration table is asserted equal to `Targets.swift` by
  `documentTableMatchesTargets`.
- **`lint-reference.sh` checks that an article exists, not what it says.** Real-article
  wrong citations have shipped at least five times, twice into permanent commit messages.
  The check is reading the article, and today each agent scrapes the book and searches a
  text file by hand to do it.
- **The brief tells every agent to write its own shingle scanner.** `lint-reference.sh`
  already scans per line and joined, prints a firing control, takes `--n 8` and
  `--messages`, and has a self-test in CI.

## 2. The ordering principle

Tooling first, because every rule change after it cites a command the tooling provides.
Then the machine checks, so the doc sweep that follows is held by a test rather than by
care. Then the rule and brief edits, sequentially, because two writers never edit one file
at once and CLAUDE.md and the orchestrator skill are the files every item wants. Deferred
items each carry the trigger that brings them back.

## 3. The items

Each item is issue-shaped: the orchestrator files it in the standard body with a `Where
it fits` line. Sizes are in agent-sessions on the measured timings above.

### Phase 0 — tooling everything else cites

**T1 — `scripts/preflight.sh`: one command, scoped to the blast radius.** Size: medium.
Depends on: T3 merged (both edit `ci.yml`).

Reads `git diff --name-only $(git merge-base origin/main HEAD)` plus the working tree and
picks a lane: `docs` (lints, census, `lint-reference` over tree and `--messages`, the
traceability tests by `--filter`); `tests` (the touched package's suite plus the docs
lane); `tools` (the touched tool's build and suite, playsize, plus the docs lane);
`engine` (everything in CLAUDE.md's Commands block, `harness-reach.sh` deciding the
harness, and the harness at seeds 7 and 11 when it says `run`). `--full` forces the engine
lane; `--lane <name>` overrides. Prints one line per step with its seconds, what it skipped
and why, the `harness-reach` verdict, and the sha256 of `Targets.swift` against the merge
base. Full output goes to a directory outside the tree and only summary lines reach the
terminal, so a run costs an agent a dozen lines of context rather than a thousand.
`--report` prints the same block in the shape the PR body needs. `--self-test` runs it
against scripted diffs with known lanes, in the shape `harness-reach.sh --self-test` uses,
and CI runs the self-test.

Done when: the four lanes exist and the self-test covers each with a diff that must select
it; a docs-lane run on this tree finishes in under 90 seconds and an engine-lane run in
under 10 minutes; a failing step exits non-zero naming the step and the log path;
`docs/tools.md` has a section; CI runs `--self-test`.

**T2 — `lint-reference.sh --show`: the article beside the citation.** Size: small.
Depends on: nothing.

For every article the branch diff adds a citation to (and `--show <article>` for one, or
`--show-all <file>` for a document), print the article's text from `FM_RULEBOOK_TEXT` to
stdout. Reading the article as printed becomes one command for implementer and reviewer.
Reuses `fetch-rulebook.sh`'s refusal to write inside any checkout; stdout only. With no
corpus it says so and exits 0, as the lint does.

Done when: the self-test fixture corpus exercises it; it refuses a path inside a worktree;
`docs/tools.md` documents it and the brief (B1) tells both roles to run it before writing
or judging an entry.

**T3 — CI fires once per push.** Size: trivial. Depends on: nothing. First to land.

`on.push.branches: [main]`; `pull_request` unchanged. Halves the jobs per push from eight
to four and removes the queue exposure. The header's cost note is rewritten to say so. The
required checks are the `pull_request`-context ones already, so branch protection is
unaffected; confirm by attempting the next merge and reading the result rather than the
check-runs API, per the skill.

Done when: one push to a branch produces one run; the header says why.

### Phase 1 — machine checks, then the sweep they hold

**M1 — every hand-maintained number has a check.** Size: small to medium. Depends on:
nothing; start beside T1.

Three checks, each in CI. (a) `InvariantsTraceabilityTests` asserts the numbered entries
are contiguous from 1, in order, with no duplicate, and that the header's stated ranges
match the entries as parsed. (b) `scripts/test-census.sh --markdown` prints the table
`docs/testing.md` carries, and a CI step diffs the two; the doc keeps the commit stamp
beside it because the step regenerates it in the same commit as any test change. (c)
`play-record.md`'s footprint numbers are diffed against `playsize` output the same way.
The numbers on `main` are corrected in the same PR, and the stale figures are named in the
body.

Done when: all three checks exist, the tree passes them, and each failure message names
the command that regenerates the number.

**M2 — the process-history lint, with a baseline.** Size: small. Depends on: nothing;
runs after M1 to avoid two agents in `lint-sim.sh`'s fixtures at once. This is #93 item 3
brought forward.

`lint-sim.sh` fails on `#\d+`, `wave \d`, "audit", "the review" or "orchestrator" in a
comment under `Sources/` or `Tests/`, with the two exceptions #93 names (a `.pin` test's
doc comment; a register of unreachable cases). A baseline file in the shape of
`lint-reference-baseline.txt` carries the hits on `main` so the lint lands green today
and new ones cannot enter; M3 burns the baseline down.

Done when: fixtures for both directions; the baseline lists every current hit; CI runs it.

**M3 — #93, the half that has no dependency.** Size: medium. Depends on: M1, M2, T2
merged. Requires the orchestrator to split #93 on the issue.

Items 1, 4, and item 2 outside the files in flight. One home per rule: the skill's
`game-rules.md` tables cite `playing-rules.md` by article and keep only the vocabulary and
roster material with no home elsewhere, so a citation can be wrong in one place. Snapshots
either carry their commit or point at the script (M1 covers three; sweep the rest). The
comment sweep covers `Packages/` and `Tools/` except `PlayRecord.swift` and the record
docs, which wait for #177 and #97 (D3). `harness-reach.sh` decides whether the harness
runs; comment-only edits under FMSimulation should print `skip`.

Done when: #93's Done-when items 1, 2 (scoped) and 3 are met; M2's baseline is empty
except the in-flight files; the citation count in the skill's references is the count of
pointers, not paraphrases.

### Phase 2 — the brief and the rules, one writer at a time

**B1 — the brief, first pass: the measured numbers and the commands.** Size: small.
Depends on: T1, T2 merged.

Edits Part 2 of the orchestrator skill and CLAUDE.md's Commands block and *Before you
push* bullet. Timings replaced with the measured ones. The twelve pre-push commands become
`scripts/preflight.sh`, and its `--report` block is what the PR body pastes. Iteration is
`swift test -c release` and `--filter`, with one full debug run before the push, and the
one `#if DEBUG` test named as the reason the debug run stays. `--show` is the step before
writing or judging a reference entry. "Shingling is untrusted, verify your own" is
deleted; the lint's `--n 8` and `--messages` are the two flags. Agents open a draft PR
with their first push, which is how a bare branch gets its CI signal once T3 lands.

Done when: no timing in the brief differs from `preflight`'s own printed seconds by more
than a factor of two on the container it names; the brief names no command the tree does
not have.

**B2 — the brief, second pass: the reviewer reads, and the prose is capped.** Size:
medium. Depends on: B1 merged (same files), T3 merged.

The reviewer does not re-run the suites: CI runs them twice on two architectures per push.
The reviewer reads the diff, runs `--show` on every citation added, checks the
`preflight --report` block against the tree (Targets checksum, harness-reach verdict),
and reads the articles. A PR body template at `.github/pull_request_template.md`: the
Done-when checklist with evidence, measured / assumed / not checked as three bullet lists,
the `--report` block, moved harness rows with a mechanism each. Cap: 500 words outside the
report block. The implementer's report to the orchestrator is the same body. Commit
messages: one paragraph and the mechanism. The tracker's Current state: the state, capped
at 400 words, with the reasoning in comments where the skill already puts history. The
four cost rules agreed 2026-09-13 move from a comment on #1 (history, by the skill's own
convention) into Part 1, with one addition: a PASS with prose findings gets a follow-up
commit from the same implementer and no second review, and only for a doc that contradicts
its own numbers.

Done when: the template exists and the skill's report section points at it; the review
section says what the reviewer runs and what it does not; the cost rules are in Part 1.

**B3 — CLAUDE.md and the skill, slimmed: rules stay, stories move.** Size: medium.
Depends on: B1, B2 merged (same files), M3 merged (so the skill's references are settled).

The narrative of past failures is the institutional memory and it is not deleted; it
moves to one `docs/lessons.md`, each story under the rule it defends, and each rule links
its stories. CLAUDE.md keeps the eleven rules, the conventions, the commands and the
pointers; target under 1,500 words from 3,700. The orchestrator skill's Part 1 keeps the
state machine, the dispatch rules and the verification rules and links its stories; Part 2
keeps what an implementer must do, target under 1,200 words from about 1,800. Before-start
reading for an implementer falls from about 61,000 words to under 12,000, measured with
`wc -w` over the files the brief names.

Done when: the word counts above hold; every deleted paragraph is findable in `lessons.md`
by its rule; `/next`, `/orchestrator` and `/game-designer` still resolve every file they
name.

## 4. Dispatch order

| order | item | can run beside | touches |
|---|---|---|---|
| 1 | T3 | T2, M1 | `ci.yml` |
| 2 | T1 | T2, M1 | `scripts/preflight.sh`, fixtures, `docs/tools.md`, `ci.yml` |
| 2 | T2 | T1, M1 | `scripts/lint-reference.sh`, fixtures, `docs/tools.md` (its own section) |
| 2 | M1 | T1, T2 | `InvariantsTraceabilityTests.swift`, `test-census.sh`, `ci.yml` (after T1), three docs |
| 3 | M2 | B1 | `lint-sim.sh`, fixtures, baseline |
| 3 | B1 | M2 | orchestrator `SKILL.md` Part 2, `CLAUDE.md` |
| 4 | M3 | B2 | skill references, comments across `Packages/` and `Tools/` |
| 4 | B2 | M3 | orchestrator `SKILL.md`, `CLAUDE.md`, PR template |
| 5 | B3 | nothing | `CLAUDE.md`, orchestrator `SKILL.md`, `docs/lessons.md` |

Two agents editing `docs/tools.md` at once (T1, T2) is a merge, not a conflict, if each
adds its own section and neither reflows the file. `ci.yml` is touched by T3, T1 and M1 in
that order; each merges `origin/main` in before pushing.

Every item runs under the current brief until B1 lands; from B1 on, the new one. Every
item is a docs-or-tooling change, so under T1's own lanes none of them runs the harness
except M3's comment sweep, and `harness-reach.sh` decides that.

## 5. Deferred, each with the trigger that reopens it

- **D1 — a semantic citation check.** No design exists for checking that an article says
  what the entry beside it claims; T2 makes the reading cheap instead. Reopen if a
  wrong-article citation ships after T2 is in the brief.
- **D2 — the debug corpus.** 165 seconds of the FMSimulation suite is forty games in a
  debug binary. Release iteration sidesteps it; making debug fast is engine work under
  ADR-0006's budget. Reopen if a debug-only failure slips past a release iteration loop.
- **D3 — #93's comment sweep of `PlayRecord.swift` and the record docs.** Reopen when
  #177 and #97 merge; M2's baseline names the lines.
- **D4 — stable slugs instead of hand numbers in `invariants.md`.** M1's contiguity check
  stops the regression; slugs stop the renumber. Reopen at the next insertion that
  renumbers more than ten entries.
- **D5 — regenerating the tracker body from the labels.** The skill already says the
  labels are the backlog. Reopen if the Current state section is found stale twice more.
- **D6 — the arm runner queue.** T3 halves the exposure. Reopen if a run queues past
  twenty minutes again; the fix then is the arm leg on `main` only.

## 6. What done looks like, measured

Baselines are from this analysis; targets are what the items above should produce. The
orchestrator re-measures after B2 lands and again two weeks later, and posts both on #1.

| measure | baseline | target |
|---|---|---|
| wall clock, a docs-and-tests issue like #167, dispatch to merge | ~2.4 h (#185, reported) | under 45 min |
| suite runs per review round | 6 | 3 (implementer once, CI twice) |
| pre-push check, docs lane | ~9 min (full list) | under 90 s |
| PR body, words outside the report block | ~2,200 average | under 500 |
| words an implementer reads before starting | ~61,000 | under 12,000 |
| correction commits as a share of branch commits | 39 of 254 since 2026-09-10 | measured again; the direction is the claim |
| rule paraphrases with more than one home | 74 articles | 0 |

## 7. Measured, assumed, not checked

**Measured:** every timing in section 1, on this container, one run each (the FMSimulation
warm run twice, at 173 and 175 seconds; the release run twice, at 15 seconds both);
the word counts; the commit and file-churn counts; CI run durations from the Actions API;
the citation overlap between the three documents; the traceability test's assertions.

**Assumed:** that the 49 minutes was runner queueing, from run timestamps alone. That
release-mode testing changes no outcome beyond the one `#if DEBUG` test: all 347 passed
here once, and the debug run stays in the loop for that reason. That the cost split of
#185's session was dominated by output and context rather than inference: the session's
token totals were reported without a breakdown.

**Not checked:** whether branch protection names the `pull_request`-context checks
specifically (T3 confirms it on its first merge). Whether the skill's file references
survive B3 (its Done-when checks).
