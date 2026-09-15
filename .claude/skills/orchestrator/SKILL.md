---
name: orchestrator
description: Run a filed backlog from its tracker issue — dispatch implementers, verify, merge. Load when driving a tracker's issues to merged; its second half is the standing brief.
disable-model-invocation: true
---

# Orchestrating a backlog

**Argument: the tracker issue number**; with none, the open issue labelled `tracker` — today
**#1**, whose body names its issues' label. **Part 1 is yours; Part 2 is the implementer's
brief.** Every rule's story is in [`docs/lessons.md`](../../../docs/lessons.md), Part B: read it,
never paste it into a brief.

---

# Part 1 — The orchestrator's job

You dispatch subagents; **you never implement an issue yourself.** You read every report
critically, **verify the hard constraints in the tree rather than trusting it**, merge, and
correct the record when something turns out wrong. An issue you file carries a `Where it fits`
line, and its body is Finding, Plan, Done-when and Not-in-scope — **never a Conventions or check
list**: the checks live in `CLAUDE.md` and Part 2. **You are not the designer**: an idea that is
not a defect a fan would notice goes to the owner and the design tracker.

## The state machine

Issues carry the backlog's label (`audit-backlog` today), a `track:` and usually a `wave:`.
**`status:` is the state and every open issue has exactly one:** `ready` → `in-progress`, plus
**`blocked`** — **not dispatchable**. `done` lands on an issue already closed; `status:review` is
carried by nothing and is not in the flow.

**`blocked` does not say why**: either an open dependency, named in *Depends on*, or a pending
decision, which the separate **`needs-owner`** flag marks — so a decision-blocked issue carries
**both**. **Run the query rather than trusting this paragraph**: list open `needs-owner` issues
and give a `status:` to any that lacks one. **On meeting a `blocked` issue, establish which
reason it is**; if its dependencies have cleared it is a decision, so add `needs-owner` and
**write the question down**.

Issues auto-close via `Closes #N`; **flip the label to `status:done` yourself.** A PR satisfying
only part of an issue says **`Refs #N`**, and the issue stays open with a comment naming which
*Done when* items are met.

## Maintaining the tracker

**The body is the state. The comments are history.**

- **Current state is rewritten in place** when `main` moves, an issue lands, something becomes
  owner-gated, or the queue changes. **Never append state as a comment.**
- **Cap it at 400 words**, five things: the `main` sha; the counts; what is in flight, one entry
  per branch; what waits on the owner, with the question; the queue.
- **An in-flight entry is the handoff**: branch, head sha, issues closed, what has been verified
  on that head, the next action. A session that pauses rewrites these before deleting its
  triggers; one that resumes continues from the body, not memory.
- **Reasoning, findings, residuals, rule changes, wave summaries and corrections are comments.**
  Counts and shas are **measured, not carried forward**.

**#1 has no wave tables**: a filing-time record nobody maintained, deleted 2026-09-12. **The
live backlog is the labels** — query them. #1's *Why certain issues exist* section stays. Do not
rebuild a table.

## Scope, and the wave summary

Two standing rules, agreed with the owner 2026-09-11:

- **No new rules-layer or resolver issue is dispatched unless it moves a graded harness row or a
  fan would notice it in the printed `gamelog` game.** Correct and cited is not sufficient.
- **Every wave summary re-reads each closed issue's plan and Done-when against the current
  harness output**, not the PR's claims, and lists any plan item that did not land.

The summary is one comment: what merged with shas, every moved harness row with its mechanism,
plan changes, what waits on the owner, the re-read.

## Dispatching

1. **Every dispatch gets its own worktree.**
2. **Batch issues that touch the same file onto one branch**; where that would blur what each
   decided, run them **one at a time**, the second inheriting the first's convention.
3. **Agents open their own PR. They never merge and never enable auto-merge.**
4. **Tell agents to push early**, even a WIP commit.
5. **Hold a slot free.** Throughput is not the constraint; attention is.
6. **Keep a check-in scheduled while any agent runs**; delete the triggers when you pause.

### The dispatch prompt

Paste this, filling `<N>` and the slug:

```text
Implement issue #<N> in knissley/football-manager. Read CLAUDE.md, Part 2 of
.claude/skills/orchestrator/SKILL.md and .github/pull_request_template.md; read issue #<N>
and every comment on it — its Plan and Done-when are the spec.

git fetch origin main && git checkout -b fix/<N>-<slug> origin/main

Push with your first commit and open a draft PR. Swift is on PATH or at /opt/swift/usr/bin;
run every check in the foreground with the Bash tool's timeout, capturing output to files.
Iterate with ./scripts/preflight.sh --iterate <SuiteName>, run ./scripts/preflight.sh once
before the final push, and paste ./scripts/preflight.sh --report into the PR body. Never
merge and never enable auto-merge. Do not wait on CI: mark the PR ready, report, and end
your turn. Report in under 250 words, in the template's shape. If the plan is wrong or
something you need is missing, stop and report on the issue.
```

Add per issue what only you know: the convention to inherit from a sibling PR, the files not to
touch, and any measurement to record.

## Review, before you merge

When an implementer reports done and its PR is open, dispatch **one reviewer with a fresh
context**: it gets the PR body, the diff, every *Done when* line the PR closes, `CLAUDE.md`, and
Part 2. **It does not re-run the suites** — the implementer's `preflight` is the first pass, CI
the second and third. What it adds is reading.

**It reads:** the diff against a merge base it resolves itself (a two-dot `origin/main..branch`
lies once `main` has moved); **every article the branch cites**, as `lint-reference.sh --show`
prints it, quoting the header before judging the entry; the **`--report` block against the
tree**, where a mismatched checksum, verdict or lane is a finding; and **each *Done when* line
against its evidence**, with the Assumed and Not-checked lists.

**It runs** `lint-reference.sh --show`; `preflight.sh --lane docs`, which catches the lints, the
census and `--messages` on the head as pushed; and **any mutation the implementer claims**.
Nothing else, unless a claim cannot be judged another way, and then it names that claim.

**It returns `pass`, or concrete failures, each with the command that shows it**; a finding with
no reproducing command is an opinion. Before calling a reference finding pre-existing it checks
`origin/main`'s copy. **A second round is for behaviour, football, or rule 8 to 11 failures only;
after two failed rounds the issue stops**, and a narrow third is only for prose the first fix
introduced, written on the issue first. The review adds no status, and its pass is not your
verification.

## Cost discipline for a dispatch round

Agreed with the owner 2026-09-13
([why](../../../docs/lessons.md#cost-discipline-for-a-dispatch-round)). **The four rules are the
owner's, verbatim:**

1. **Merge on a reviewer's PASS.** A PASS with non-blocking findings is a merge, not a fix
   round.
2. **Route non-blocking prose findings to #93**, which exists for exactly this and whose own
   taxonomy says doc-duplication, process-history and snapshot findings "batch without loss".
   The **one** exception is #93's kind 1 — a doc whose own numbers contradict it — which stays
   in the PR that introduced it. Of the four findings that triggered #185's round 2, only one
   plausibly met that bar; the other three should have been filed.
3. **Scope the checklist to the blast radius.** When `harness-reach.sh` says `skip`, the release
   build and the harness runs are theatre. A docs-and-tests round needs the suites, the lints,
   the census and `--messages` — not a fifth agreeing harness measurement.
4. **One reviewer round.** A round plus a re-read plus a narrow third pass is three; the skill
   permits the third only for prose the second round introduced, and the cheapest way to never
   need it is rule 1.

And one addition:

5. **A PASS with prose findings gets a follow-up commit from the same implementer, with no
   second review** — and only when a document contradicts its own numbers (#93's kind 1). Every
   other prose finding is filed on **#93** or whatever issue succeeds it, named in the merge
   comment. Do not send a PASS back to a reviewer to confirm a paragraph.

**What this does not change: nothing about the football.**

## Verifying before you merge

**Verify the constraint yourself. Do not take the report.** Resolve the merge base before reading
a diff, never trust a `Packages/*/Sources` pathspec, and read `status --porcelain` for staged
changes — [the three ways a diff has lied](../../../docs/lessons.md#verifying-before-you-merge).
**Never stage-all and commit in a dead agent's worktree**: its index holds the pre-death
state.

**The CI gate rule: attempt the merge and read the refusal.** The 405 names the outstanding
required check; the check-runs API and `mergeable_state` both lag, and **a green push-event run
does not satisfy branch protection**. The expected-head parameter needs the **full 40
characters**.

**Forward-merge rule.** When two PRs are ready and either touches `Packages/*/Sources` or
`Tools/*/Sources`, the second forward-merges onto the first and lets CI re-run — **green on two
heads is not green on their union**.

**What to check depends on the issue.** Usually: no graded value moved — every `id:`, `low:` and
`high:` line in `Targets.swift` unchanged, no engine source in the diff. A band-correction branch
is the exception: there the check is that **every moved band traces to a fresh run of the
derivation script**.

## After a container restart

Check **every agent worktree for uncommitted work first**. Salvage to the scratchpad, commit,
push, re-dispatch.

## The failure mode to watch for in yourself

Every significant error has had one shape: **a claim taken from an intermediate artefact rather
than the source.** **Re-derive, do not re-quote — your own numbers included.** CLAUDE.md rule 10
binds an issue body and a brief, not just a test.
[The catalogue.](../../../docs/lessons.md#the-failure-mode-to-watch-for-in-yourself)

---

# Part 2 — The standing brief for implementers and reviewers

Hand this to every agent. Stories: [lessons](../../../docs/lessons.md), Part C.

## Before anything

Read `CLAUDE.md`: **rules 1–11 bind everything you do.** Read the issue **and every comment on
it** — a body can be stale against its thread — and fetch `origin/main` for the sha.

## Environment and timings

Swift 6.2. `preflight` runs CLAUDE.md's Commands block verbatim; by hand use that form, never a
variant. **Run every check in the foreground**, with the Bash tool's own `timeout` (up to
600000 ms): backgrounding one ends your turn and stalls the pipeline. Measured warm on a
four-core Linux container: FMSimulation debug **161–214 s**, release **15 s**; a harness seed
**16 s**; `engine` lane **4 min 2 s**, `docs` **8 s**.

## Every check, before you push

**This section is the implementer's**; a reviewer's is in Part 1. Run
**`./scripts/preflight.sh`**, which picks the lane from your diff and stops at the first failure,
and **paste `--report`'s block into the PR body**. Iterate with **`--iterate <SuiteName>`**, but
**run the full debug suite once before pushing**: one FMSimulation test is behind `#if DEBUG`.

## How you work

- **Commit the football tests RED first, then GREEN** — two commits minimum.
- **Every `@Test` carries exactly one kind tag**, as CLAUDE.md defines.
- **A `.football` test must be able to FAIL when its own football is broken.** Mutate the rule it
  cites and confirm red; if it cannot fail, it is a `.pin`
  ([why](../../../docs/lessons.md#a-football-test-must-be-able-to-fail)).
- **Goldens are regenerated in the same commit as the behaviour change**, mechanism in the
  message; **a doc that changes design is updated in that commit too.**
- **Code comments say WHY and name the gotcha with its citation.** They never mention an issue
  number, a wave, "the audit" or "the review" — those belong in commit messages, PR bodies,
  `docs/invariants.md` and the audit doc. A `.pin` test and a register of unreachable cases are
  the exceptions.
- **If the plan is wrong, or something you need is missing, STOP and report it on the issue.** A
  gap in the plan is a finding, not something to invent an answer to.

## Football comes from a reference, by article number, never from memory

The rulebook text is **not in the repository and will not be**; get your own with
`scripts/fetch-rulebook.sh <dir-outside-the-repo>`, and **read
`docs/reference/rulebook-acquisition.md` before citing it**. The available edition is
**2026** and we target **2025**; they differ in **exactly four articles — 6-1-3, 6-1-5, 6-1-6
and 19-2**, so cite freely elsewhere and in those four do not
([the trap](../../../docs/lessons.md#the-two-editions-differ-in-four-articles)). **If the article
you need is in neither reference, say so and stop**, and **never paste rulebook text into the
repo, commit messages included.**

### If you touch `docs/reference/playing-rules.md`

`playing-rules.md` is the project's own paraphrase, and an entry that misstates its article
**blocks a merge**. Read the article as printed — `./scripts/lint-reference.sh --show` prints
every article the branch diff cites — and write the entry from it, stating only what it states
and flagging any inference as one. Watch the terms of art
([examples](../../../docs/lessons.md#terms-of-art-in-the-reference)). **The lint
checks that a cited article *exists*, not that it says what the citation claims**, so reading it
is the check. **Reviewers run `--show` before judging an entry**, quote the header, and report the article as
printed, what the entry claims, whether it is **behaviour-bearing**, and whether an open issue
cites it — the last two decide whether it blocks.

## The shingle is the lint's job — do not write your own

`scripts/lint-reference.sh` scans whole files and whole commit messages, never a sub-diff, with
controls cut from the corpus at runtime: unless they come out 1, 1, 0 it prints no count and
exits 2, so **quote that control line beside your count**. `preflight` runs the tree scan and
`--messages` but not **`--n 8`**, worth a run when the branch added football prose. Run
`--messages` immediately before pushing.

## The harness

Release build, then `--games 400 --no-timing` at seeds 7 and 11, once per seed, before and after
your change. **Capture your own "before" on the `origin/main` you cut from and say which sha** —
an older baseline is not one — or paste `harness-reach.sh origin/main` showing `skip`. Paste
every moved row with **one line each naming the mechanism**; "noise" is not a mechanism unless
you give the count of differing games and a mechanism per game. **Read each move against that
row's measured noise floor and say which floor** (CLAUDE.md, Current work). **Never retune a
constant inside a fix** (rule 9); residuals go as a comment to the retune issue the tracker
names (E3 #49 today) — never close or relabel it.

### A new constant is model construction, not a retune, only if all three hold — measure each

1. **No pre-existing constant and no band moved** — show `Targets.swift` is numerically
   unchanged.
2. **The code comment names the row it was set from**, so the retune can find it.
3. **A sweep shows the shipped value is not the greenest available**, the graded row still out of
   band at branch head.

A constant whose shipped value differs from its stated derivation, toward a band, is doing
calibration work whatever the message says, and disclosure is not the remedy. Sweep four to six
values across the plausible range and paste the table.

## Landing beside other branches

**Green on your head is not green on `main`.** If a branch merges first and it touched
`Packages/*/Sources` or `Tools/*/Sources`, your corpus counts, goldens and harness rows were
measured against an engine that is gone.

    git fetch origin main && git merge origin/main     # a merge commit; NEVER rebase pushed history

Resolve keeping both sides, regenerate the goldens that moved, re-run the harness, push.

## Finishing

**Open the pull request yourself, as a draft, with your first push** — a bare branch gets no CI
run, CI firing on `push` only for `main`. When done, mark it ready, report, and end your turn.
**Do not wait on CI**: the orchestrator watches it and merges on green, and a red check comes back
to you as a message. **Do not merge and do not enable auto-merge.**

## Your report is the PR body

**There is no second report.** GitHub prefills the body from
**`.github/pull_request_template.md`**; fill every heading, deleting rather than "n/a"-ing those
that do not apply:

1. `Closes #N`, or `Refs #N` when the PR satisfies only part of an issue.
2. One paragraph on what changed, naming the **mechanism**.
3. **Every *Done when* line you closed, each with one line of evidence.**
4. **Measured**, **Assumed** and **Not checked**, as three bullet lists; a gap you filled by
   judgment is an **Assumed** line naming what with.
5. The `./scripts/preflight.sh --report` block, pasted whole.
6. Every moved harness row with **one mechanism each**, or `none moved` with the
   `harness-reach.sh` verdict.

**Cap: 500 words outside the report block**; evidence is the command and its output. **A
body missing Assumed or Not checked goes back before review**
([why](../../../docs/lessons.md#assumed-and-not-checked)). **Commit messages: one paragraph, the
mechanism**, the rulebook by article and season, **never its text**.

## Housekeeping

Worktrees each carry a `.build`; enough fill the disk. On "no space left on device" delete them;
they regenerate. Never delete another's source.
