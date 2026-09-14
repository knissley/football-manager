# Lessons — the stories behind the rules

Every rule in [`CLAUDE.md`](../CLAUDE.md) and in the `/orchestrator` skill was written
because something went wrong. Those stories are the institutional memory and none of them
is deleted; they live here. **A rule without its story is a rule someone will argue with.
A story in front of every agent on every task is a cost** — an implementer was told to
read about 61,000 words before starting (measured 2026-09-14,
[`docs/proposals/2026-09-14-agent-throughput.md`](proposals/2026-09-14-agent-throughput.md)
§1). So the rule stays where the agent reads it, and the story moved here, under the rule
it defends, with its date and the issue or PR it came from where the source names one.

Nothing here is a rule. If this page and CLAUDE.md disagree about what to do, CLAUDE.md
wins and this page is stale — fix it in the same commit.

---

## Part A — the stories behind CLAUDE.md

### Project status: the audit of September 2026

An external audit in September 2026 found that the rules layer did not finish a game
correctly: regular-season games ended tied with no overtime, a touchdown on the last play
of a half got no try, the wrong team kicked off after a safety, the clock ran through a
change of possession, and contact fouls were enforced from the wrong spot — while five
hundred sixty-two tests were green, three of them asserting wrong football.

**Wave 1 of the backlog fixed those** (S9–S13 and S15 in the audit doc): overtime, the
try, the safety kickoff, the clock with its runoff, and the enforcement spot each have
scenario tests written from the 2025 rulebook, and the three wrong tests were rewritten;
#74 then gave overtime its two-minute warning and postseason overtime its timing. Wave 2's
record track closed S14 (B2 #22) and the two record gaps wave 1 left — the spot where
possession was lost, and a kicking-team kickoff touchdown (#58). Wave 3's D track then
made `Rules` the 2025 book, gave the kickoff its landing zone and its aiming points, and
put a foul on a scoring play on the try or the free kick where the rules put it.

The audit doc, [`audit-is-this-football.md`](audit-is-this-football.md), is current as of
wave 1: it carries all fifteen findings with a status table and links every open one to
its issue.

### Rule 2 — randomness comes from one place

A game is reproducible from `(initialState, seed, sliderConfig, decisionLog)` — and **that
tuple is how most games are *stored***. So a determinism bug corrupts saved history; it
does not merely fail a test. That is why the banned list is a list of primitives rather
than a style preference, and why iteration order over an unordered collection counts as a
random draw.

### Rule 4 — everything downstream reads the event stream

Queries over the stream, rather than totals accumulated beside the simulation, are what
lets the engine be replaced without touching anything above it. The moment a box score is
summed during the sim, the engine and its consumers are one component.

### Rule 5 — the tick loop never allocates

The budget is a season in ~60s, about 1.1µs per entity-tick. It is architectural:
retrofitting it onto a design that allocates per tick is a rewrite, not an optimisation
pass. ([ADR-0006](adr/0006-spatial-simulation.md))

### Rule 10 — football is asserted from a reference, never from memory

**The reference the engine was first written from was memory, and the code carried its
errors for weeks** while a table in the `football-domain` skill said the opposite and
nothing connected the two. That is the whole reason [`reference/`](reference/) exists and
the reason a football claim must cite an article number and a season rather than sound
right.

The same failure has a documentation half. Measured 2026-09-14 (proposal §1): of the 75
articles the football-domain skill's `game-rules.md` cites, 74 are also in
`reference/playing-rules.md`, and `invariants.md` cites 83 — **every rule has three
homes**. The D-track branch fixed article 6-2-3 in the reference and shipped it wrong in
the skill in one commit set, through review. Real-article-but-wrong citations have shipped
at least five times, twice into permanent commit messages.

### Rule 11 — football tests come first

A test derived from the code afterwards asserts what the code does, which is what a
regression pin is for; it cannot tell you the code is wrong. That is why a football test
is committed red from the reference before the code exists, and why a `.pin` is a separate
tag rather than a lesser `.football`.

### Conventions → Naming: fluent vocabulary is not correct rules

The code sounded like a broadcast while the wrong team kicked off after a safety. Using
the sport's real vocabulary is necessary and nowhere near sufficient; it is a naming rule,
not a correctness one, and the audit above is what happens when it is mistaken for one.

### Conventions → SwiftUI: accessibility from the start

Retrofitting Dynamic Type and VoiceOver onto a dense roster table is much worse than
building it in, which is why it is a convention rather than a milestone task.

### Conventions → Tests: the suite's own budget

FMSimulation's debug suite was 170–200s before the game samples were shared across tests
and 85–111s over five runs after (measured on a four-core container). Measured again
2026-09-14 on the same class of container: **173 s warm, 216 s cold, and 15 s under
`-c release`** — 165 of those 173 seconds are spent building the forty-game corpus in a
debug binary, which is why `preflight --iterate` runs release and why one `#if DEBUG` test
in `FormAndFitTests` is the only thing the release run misses. Machines differ by a factor
of two; measure yours rather than trusting the number.

### Working style — watch a game

**Aggregates hid every rules bug the audit found.** The per-play numbers landed while the
wrong team kicked off after a safety. Reading one full `gamelog` game before and after an
engine change is the cheapest check that has ever caught anything the aggregates could
not.

### Working style — every number printed gets a target

**The harness printed eighteen ties in four hundred games on every run for a week. Nobody
had written down that the real number is two.** A number with no target beside it is
decoration: it cannot be read as a pass or a failure, so nobody reads it.

### Working style — say plainly what you did not check

"All fifteen calibration rows land" and "it builds" are different claims, and so are "the
test passes" and "I ran it four times and it passed four times". Every significant error
in this project has been a claim that was true of something narrower than what it said.

### Current work — the labels are the live backlog

#1's wave tables are a filing-time record, not an index: **39 of the 115 backlog issues do
not appear in them at all** (measured 2026-09-12; re-derive by diffing the issue numbers
in those tables against the `audit-backlog` label query). The tracker body said 38 until
that count was taken — an off-by-one in the very sentence warning you the tables are
unreliable, which is the re-quoting trap below in miniature.

### Current work — waves merge, they never rebase

Pushed history is never rewritten here; a branch that `main` has moved under merges
`origin/main` in. Measured 2026-09-12: the last forty commits on `main`'s first-parent
chain are all merges (`log -40 --first-parent`; a plain `log -40` shows six, the rest
being the branches' own commits).

### Current work — the measured noise floor

A before-and-after at one seed and a comparison across two seeds have different noise
floors, which is why a move must say which floor it was read against.
**Roughly half of the graded rows — fifty-five of them — print a different verdict at
different seeds with nothing changed at all.** The floors are in
[`reference/calibration-sources.md`](reference/calibration-sources.md#the-measured-noise-floor);
they are measured, not assumed, and re-taken in the same commit as a change that moves
engine behaviour.

### Current work — the PR body is the report, and it is capped

The last twelve merged PR bodies averaged about 2,200 words, one of them for a single
visibility change (measured 2026-09-14, proposal §1); #185's was 2,267 and its commit
messages ran to 400. Hence the 500-word cap outside the report block: evidence is a line —
the command and what it printed — not the story of running it.

---

## Part B — the stories behind the orchestrator skill

### The state machine

**A `status:review` label exists and is carried by nothing** — measured across all 115
backlog issues, open and closed. It is not part of the flow; do not start using it without
deciding what it would mean.

**The practice drifted once and an orchestrator did the drifting:** two issues carried
`needs-owner` with **no** `status:` at all, which made them invisible to a query for
either ready or blocked work. Both are fixed, and all four `needs-owner` issues now carry
a status. That is why the invariant is "exactly one `status:` on every open issue" — it is
what makes "what can I dispatch" a total query rather than one with a hole in it, and why
the fix is to run the query rather than trust the paragraph asserting it holds.

**One issue sat `blocked` for a day after every dependency had closed**, because nobody
re-checked. It was genuinely not dispatchable, but the reason had become a scope question
and no `needs-owner` said so, so it read as waiting for work that had already landed. A
flag without a written question is as stuck as a stale label.

### Maintaining the tracker

The Current state section **reached about 2,000 words and was rewritten at that length on
every merge**, which is both the cost and the reason it goes stale: a section nobody can
re-read in a minute is one nobody re-derives. That is the 400-word cap.

**Three status comments were posted in twenty-four hours, each superseding the last, and a
fresh session reading the thread top-to-bottom met the stale one first.** That is the
failure the body-is-state convention exists to prevent, and posting one more is how it
comes back.

A count quoted from the previous version of the section is exactly the failure mode below.

### Scope, and the wave summary

Two standing rules, agreed with the owner at the re-audit of **2026-09-11** and until then
recorded only in a comment on #1, which by the skill's own convention is history.

**The A track grew from nine issues to nineteen on correctness alone** — correct and cited
is not sufficient; a rules-layer or resolver issue must move a graded harness row or be
something a fan would notice in the printed `gamelog` game.

Re-reading each closed issue's plan against the current harness output, rather than
against the PR's claims, found **two plan items that did not land — C10's chip-shot share
and C11's net-punt separation**. Both are now inputs to the retune.

### Dispatching

**Agents sharing one checkout have produced a commit landing on the wrong branch carrying
two other agents' work, and a reset that took an agent's only copy of its red tests.**
Recovery worked only because the contaminated commit was pinned to a ref *before anything
else was attempted*. Hence: every dispatch gets its own worktree.

**A container restart has killed an agent an hour into its work**; it survived only
because its worktree happened to persist. Hence: push early, even a WIP commit. Untidy and
safe beats clean and gone.

**Throughput is not the constraint; attention is.** The findings that mattered came from
reading a result carefully, not from having more in flight. Hence: hold a slot free.

### Review, before you merge

Per round the suites ran six times — implementer, a reviewer told to run everything
itself, and CI twice per push (`push` and `pull_request` both fire) on two architectures,
a CI run being about six minutes (measured 2026-09-14, proposal §1). A reviewer's run is
the fourth agreeing green of the same trees. **What the reviewer adds is reading, not
repetition.**

**Two of eight findings on one branch were mis-classified as pre-existing from reports**,
which is why a reference finding is checked against `origin/main`'s copy of the file
before it is called pre-existing.

A two-dot diff of `origin/main..branch` **showed a landed PR's work as if it had been
reverted** once `main` had moved, which is why the merge base is resolved first.

### Cost discipline for a dispatch round

The five rules were agreed with the owner **2026-09-13, after PR #185** took about two and
a half hours and a large share of a session's budget to land 309 added lines of which one
was an engine change. Rounds two and three were roughly 1.5 of those hours, touched no
engine source, and ran the full pre-push checklist each time over wording. Of the four
findings that triggered #185's round 2, only one plausibly met the bar for a fix round;
the other three should have been filed on #93 — whose own taxonomy says doc-duplication,
process-history and snapshot findings "batch without loss".

The checklist itself was measured and it is not the cost: cold, from a clean tree, the
entire mandated list is about nine minutes (proposal §1). **The expensive part was never
rigour; it was re-running a full checklist three times over wording.** Nothing in the cost
rules changes anything about the football: articles are still read as printed rather than
trusted from a lint, `.football` tests are still mutation-verified, `Targets.swift` is
still checked numerically against the base, and a report's numbers are still re-derived
rather than re-quoted.

### Verifying before you merge

Three ways a diff has lied, each found the hard way:

- **A pathspec of `Packages/*/Sources` silently matches nothing.** The diff comes back
  empty even when those files changed.
- **A two-dot diff lies once `main` has moved** — see above.
- **`--stat` shows nothing for *staged* changes.** Only the first column of
  `status --porcelain` revealed a staged deletion of a file a live agent had just created.

**Never `add -A` and commit in a dead agent's worktree.** Its index holds the pre-death
state while the branch ref moves under it, so a commit there silently reverts live work
and deletes files the live agent added. Two worktrees on one branch is the hazard.

**A green run on the push event does not satisfy branch protection.** The gate wants the
required check in the PR context, and has refused a merge with *"2 of 2 required status
checks are in progress"* while the push run on the identical sha was fully green. Both the
check-runs API and `mergeable_state` lag, in both directions — which is why the rule is to
attempt the merge and read the 405's refusal, since it comes from the thing that actually
decides. The expected-head parameter needs the full 40 characters.

A "49-minute queue stall" was the round-two CI run sitting queued from 04:20 until the
round-three push cancelled it at 05:09 (inferred from run timestamps; the runner log was
not read).

### After a container restart

Salvaging every agent worktree's uncommitted work to the scratchpad *before* anything else
is **the only reason a multi-seed sweep survived once**.

### The failure mode to watch for in yourself

Every significant error — the orchestrator's and the agents' — has had one shape: **a
number or claim taken from an intermediate artefact instead of from the source.**

A closed-issue count quoted forward without re-counting. "197 lines identical" that were
197 grep *matches* across 131 lines. A share computed over a denominator that included
rows carrying no grade. A healthy CI run cancelled because a report said "stalled for two
hours" and nobody ran `date -u` — it was four minutes old. An arithmetic slip travelling
doc → report → issue body → brief, each step citing the last. An issue citing the wrong
article number, which would have shipped into the project's own football reference. And an
issue filed claiming a defect that was **correct football all along** — implementing its
plan would have put a bug in, *and it would have looked like an improvement* because the
rate it moved would have gone toward the league's.

**Re-derive, do not re-quote — including your own numbers, and including anything in an
issue body you wrote.** CLAUDE.md rule 10 binds an issue body and a dispatch brief, not
just a test.

---

## Part C — the stories behind the standing brief (the skill's Part 2)

### Timings an agent budgets against

**The brief said a harness seed was two to three minutes. It is 16 seconds** (measured
2026-09-14). Agents budget turns and chunk work against the stated figure, so a stale
timing in the brief is not a cosmetic error. Every FMSimulation run also puts about 800
lines and 100 KB of green checkmarks into the agent's context, carried in every turn after
it; twelve runs is over a megabyte, which is what the forbidden-variant rule cost on #185.

### A `.football` test must be able to fail

**A test has been tagged `.football` while asserting a modelling substitution, and another
stayed green under mutation because a *different* defect kept its assertion true.** That
is why the mutation is run rather than the sentence believed: if it cannot be made to
fail, it is a `.pin`.

### Never paste rulebook text into a commit message

**Branches have put verbatim rulebook text into commit messages that are now unfixable** —
a pushed message cannot be corrected after a merge. That is why `lint-reference.sh
--messages` is run immediately before the push and not after it.

### Terms of art in the reference

Entries in `reference/playing-rules.md` have shipped wrong by swapping one term: "the free
*kick* ends" is not "the free-kick *down* is over", and "outside the inbounds lines" (the
hash marks) is not "at the sideline". The lint validates that a cited article *exists*,
not that it says what the citation claims — reading the article is the check, and
`lint-reference.sh --show` is how.

### The two editions differ in four articles

The readily available rulebook edition is **2026**; this project targets **2025**, and
they differ in **exactly four articles — 6-1-3, 6-1-5, 6-1-6 and 19-2**. The likeliest
concrete trap is **6-1-6**: both editions let the declaration be made at any point in the
game, and the 2026 change is that it drops the condition that the declaring team be
behind. Under 2025 it is available throughout **but only to a team that is trailing** — an
unconditional onside declaration is the 2026 book, which is a different game.
[`reference/rulebook-acquisition.md`](reference/rulebook-acquisition.md) is the page.

### Assumed and Not checked

A PR body missing its Assumed and Not-checked lists goes back before it is reviewed:
**those two lists are where the real findings have come from.** A body without them reads
as certainty nobody has.

### The shingle is the lint's job

The brief once told every agent to write its own shingle scanner.
`scripts/lint-reference.sh` already scans per line and joined, prints a firing control cut
from the corpus at runtime, takes `--n 8` and `--messages`, and has a self-test in CI. A
hand-rolled scanner is a second implementation of a check that already has one.

### Green on your head is not green on `main`

Checks ran on a head containing the `main` you cut from. If another branch merges first
and it touched `Packages/*/Sources` or `Tools/*/Sources`, your corpus counts, goldens and
harness rows were measured against an engine `main` no longer has. **Green on two heads is
not green on their union** — which is also why two ready PRs touching sources
forward-merge rather than both merging on their own green.
