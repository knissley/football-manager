---
name: orchestrator
description: Run the audit backlog — dispatch implementers to issues, verify what they report, and merge. Load when driving issues from the tracker (#1) to merged rather than implementing one yourself, and use its second half as the brief handed to every implementer and reviewer.
---

# Orchestrating the audit backlog

The backlog is tracked in **#1**. This skill is how work gets from a `status:ready` issue to
`main` without the owner approving each PR, and what every implementer must be told before it
starts.

Two halves. **Part 1 is yours.** **Part 2 is the brief you hand to each implementer** — paste
it, or point them here.

---

# Part 1 — The orchestrator's job

You dispatch subagents to implement issues. **You never implement an issue yourself.** What
you do personally: read every report critically, **verify the hard constraints in the tree
rather than trusting the report**, merge, and correct the record when something turns out
wrong. You may edit issues, split them, or file new ones — and you say so on the tracker.

## The state machine

Every backlog issue carries `audit-backlog`, a `track:<A–I>` and usually a `wave:<0–4>`.

**`status:` is the state, and every open issue has exactly one:** `ready` → `in-progress`,
plus **`blocked`** — **not dispatchable**. `done` is the fourth and it lands on an issue GitHub
has already closed, so no *open* issue should be carrying it. (A `status:review` label also
exists and is carried by **nothing** — measured across all 115 backlog issues, open and
closed. It is not part of the flow; do not start using it without deciding what it would
mean.)

**`blocked` says the issue cannot be picked up. It does not say why.** There are two reasons
and they are not the same:

- **An open dependency.** Named in the issue's *Depends on* line.
- **A pending decision**, which is what the separate **`needs-owner`** label marks.

**`needs-owner` is a flag, not a status.** It is orthogonal, so an issue waiting on a decision
is **`status:blocked` + `needs-owner`** — both. That keeps the invariant that every open issue
carries exactly one `status:`, which is what makes "what can I dispatch" a total query rather
than one with a hole in it.

The practice drifted once and an orchestrator did the drifting: two issues carried
`needs-owner` with **no** `status:` at all, which made them invisible to a query for either
ready or blocked work. Both are fixed, and all four `needs-owner` issues now carry a status.

**It is one query, so run it rather than trusting this paragraph** — list the open issues
labelled `needs-owner` and confirm each also carries a `status:`. Add the status to any that
does not.

**When you meet a `blocked` issue, establish which of the two reasons it is** — the label will
not tell you. One sat `blocked` for a day after every dependency had closed, because nobody
re-checked: it was genuinely not dispatchable, but the reason had become a scope question and
no `needs-owner` said so, so it read as waiting for work that had already landed. Check the
dependencies. If they have cleared, the reason is a decision: add `needs-owner` and **write
down what the question is**, because a flag without a question is as stuck as a stale label.

Issues auto-close on merge via `Closes #N` in the PR. **Flip the label to `status:done`
yourself; GitHub does not.** A PR that satisfies only part of an issue says **`Refs #N`, not
`Closes`**, and the issue stays open with a comment naming which *Done when* items are met.

## Maintaining the tracker

**#1's body is the state. Its comments are history.**

- **The Current state section at the top of #1's body is rewritten in place** — `main` sha,
  counts, what is in flight, what is waiting on the owner, the queue. Update it when `main`
  moves, when an issue lands, when something becomes owner-gated, or when the queue changes.
  **Never append current state as a comment.**
- **Comments are for what is cross-cutting and permanent**: a residual reported to the retune,
  a standing-rule change, a wave summary, a correction to something already on the record.
- **Do not post a status comment describing where things stand.** Three such comments were
  posted in twenty-four hours, each superseding the last, and a fresh session reading the
  thread top-to-bottom met the stale one first. That is the failure this convention exists to
  prevent, and posting one more is how it comes back.
- Counts and shas in that section are **measured, not carried forward** — query the labels and
  read the sha. A count quoted from the previous version of the section is exactly the mistake
  the failure-mode section below describes.

The wave tables further down #1 are a filing-time record, not an index: **39 of the 115
backlog issues do not appear in them at all** — measured 2026-09-12, and re-derivable by
diffing the issue numbers in those tables against the `audit-backlog` label query. (#1's own
body said 38 until that count was taken; an off-by-one in the sentence warning you the tables
are unreliable.) **The live backlog is the labels.**

## Dispatching

1. **Every dispatch gets its own worktree.** Agents sharing one checkout have produced a
   commit landing on the wrong branch carrying two other agents' work, and a reset that took
   an agent's only copy of its red tests. Recovery worked only because the contaminated commit
   was pinned to a ref *before anything else was attempted*.
2. **Batch issues that touch the same file onto one branch.** Issues that would conflict in
   `Targets.swift` or `PlayRecord.swift` are cheaper as one branch than as three with
   conflicts — but where a batch would blur what each issue decided, run them **one at a
   time**, and tell the second to inherit the first's convention rather than re-decide it.
3. **Agents open their own PR. They never merge and never enable auto-merge.**
4. **Tell agents to push early**, even a WIP commit. A container restart has killed an agent
   an hour into its work; it survived only because its worktree happened to persist. Untidy
   and safe beats clean and gone.
5. **Hold a slot free.** Throughput is not the constraint; attention is. The findings that
   mattered came from reading a result carefully, not from having more in flight.
6. **Keep a check-in scheduled while any agent runs**, and delete the triggers when you pause
   so nothing dispatches unattended.

## Verifying before you merge

**Verify the constraint yourself. Do not take the report.** A report can be honest and still
wrong, and three of these were only caught by re-deriving.

Three ways a diff has lied:

- **`git diff -- 'Packages/*/Sources'` silently matches nothing.** It returns an empty diff
  even when those files changed. Use `git diff --name-only <a>..<b> | grep '/Sources/'`, or
  `scripts/harness-reach.sh origin/main`, which answers "can the harness see this change" and
  prints its reasoning.
- **A two-dot `git diff origin/main..branch` lies once `main` has moved** — it showed a
  landed PR's work as if it had been reverted. Resolve `git merge-base` first.
- **`git diff --stat` shows nothing for *staged* changes.** Only the first column of
  `git status --porcelain` revealed a staged deletion of a file a live agent had just created.

**Never `git add -A && commit` in a dead agent's worktree.** Its index holds the pre-death
state while the branch ref moves under it, so a commit there silently reverts live work and
deletes files the live agent added. Two worktrees on one branch is the hazard — check for it.

**The CI gate rule: attempt the merge and read the refusal.** The 405 names the outstanding
required check and comes from the thing that actually decides. Both the check-runs API and
`mergeable_state` lag, in both directions. **A green run on the push event does not satisfy
branch protection** — the gate wants the required check in the PR context, and has refused a
merge with *"2 of 2 required status checks are in progress"* while the push run on the
identical sha was fully green. The expected-head parameter needs the **full 40 characters**.

**Forward-merge rule.** When two PRs are ready and either touches `Packages/*/Sources` or
`Tools/*/Sources`, the second forward-merges onto the first and lets CI re-run before it
merges. **Green on two heads is not green on their union.**

**What to check depends on the issue.** Usually: no graded value moved — every `id:`,
`low:` and `high:` line in `Targets.swift` unchanged, and no engine source in the diff. A
band-correction branch is the deliberate exception: bands move there by design, and the check
is instead that **every moved band traces to a fresh run of the derivation script**.

## After a container restart

Check `git worktree list` and **every agent worktree for uncommitted work before anything
else**. Salvage to the scratchpad first, then commit and push, then re-dispatch. That
sequence is the only reason a multi-seed sweep survived once.

## The failure mode to watch for in yourself

Every significant error — the orchestrator's and the agents' — has had one shape: **a number
or claim taken from an intermediate artefact instead of from the source.**

A closed-issue count quoted forward without re-counting. "197 lines identical" that were 197
grep *matches* across 131 lines. A share computed over a denominator that included rows
carrying no grade. A healthy CI run cancelled because a report said "stalled for two hours"
and nobody ran `date -u` — it was four minutes old. An arithmetic slip travelling doc →
report → issue body → brief, each step citing the last. An issue citing the wrong article
number, which would have shipped into the project's own football reference. And an issue filed
claiming a defect that was **correct football all along** — implementing its plan would have
put a bug in, *and it would have looked like an improvement* because the rate it moved would
have gone toward the league's.

**Re-derive, do not re-quote — including your own numbers, and including anything in an issue
body you wrote.** CLAUDE.md rule 10 binds an issue body and a dispatch brief, not just a test.

---

# Part 2 — The standing brief for implementers and reviewers

Hand this to every agent.

## Before anything

Read `CLAUDE.md` at the repo root. **Rules 1–11 bind everything you do.** Then read the issue
**and every comment on it** — comments record what superseded what, and an issue body can be
out of date with its own thread.

`git fetch origin main` and read the sha yourself. It moves several times a day.

## Environment and timings

Swift 6.2. **CLAUDE.md's Commands block is the canonical invocation for every `swift`
command** — use it verbatim rather than a variant, because predicting CI is the entire point
of running these before you push, and CI runs exactly what that block says. This section used
to add a flag that appears nowhere else in the repo and that CI does not pass; anyone who
finds a build that genuinely needs one should add it *there*, with the reason.

**Run every check in the foreground**, using the Bash tool's own `timeout` parameter (up to
600000 ms). An agent that backgrounds a check ends its turn and stalls the pipeline.

Budget your turn against measured figures, not guesses: FMSimulation's suite is roughly two
minutes of test time and about three minutes of wall clock with the build; a 400-game harness
run is two to three minutes per seed in release; a cold release build is about five minutes; a
thirty-seed noise sweep is about eleven minutes if you build release once and run back to back.

## Every check, before you push

The four package suites, plus `swift test -c release` for FMRandom (and for FMGeneration when
its goldens move); `swift format lint --strict` (**without `--strict` it prints its findings
and still exits 0**, so a script trusting the exit code passes while CI fails);
`scripts/lint-sim.sh` and its self-test; `scripts/test-census.sh` and its self-test;
`scripts/lint-reference.sh` over the tree **and** with `--messages`;
`python3 scripts/calibration-sources.py --self-test`;
`python3 scripts/harness-noise.py --self-test`; and `playsize` builds.

## How you work

- **Commit the football tests RED first, then GREEN.** Two commits minimum. A test derived
  from the code afterwards is a regression pin, not a football test.
- **Every `@Test` carries exactly one kind tag** — `.football` (true of the sport, from the
  reference, citation in the name), `.contract` (a promise the engine makes about itself),
  `.unit` (arithmetic), `.pin` (pins current behaviour; the name says what and why).
- **A `.football` test must be able to FAIL when its own football is broken.** Mutate the rule
  it cites and confirm it goes red. A test has been tagged `.football` while asserting a
  modelling substitution, and another stayed green under mutation because a *different* defect
  kept its assertion true. If it cannot be made to fail, it is a `.pin`.
- **Goldens are regenerated in the same commit as the behaviour change**, with the mechanism
  named in the message — never to make a red test pass.
- **A doc that changes design is updated in the same commit.**
- **Code comments say WHY and name the gotcha with its citation.** They never mention an issue
  number, a wave, "the audit" or "the review" — those go in commit messages, PR bodies,
  `docs/invariants.md` and the audit doc. The exceptions are a `.pin` test and a register of
  unreachable cases.
- **If the plan is wrong, or something you need is not in the issue, STOP and report it on the
  issue.** Do not guess past it. The questions were asked when the issue was written; a gap in
  the plan is a finding, not something for you to invent an answer to.

## Football comes from a reference, by article number, never from memory

`docs/reference/playing-rules.md` is the project's own paraphrase and the next implementer
reads it as authoritative.

The rulebook text itself is **not in the repository and will not be**. Get your own copy:

    scripts/fetch-rulebook.sh /some/path/outside/the/repo

Sixteen seconds, and it prints the `export FM_RULEBOOK_TEXT=…` line the reference lint wants.
Read **`docs/reference/rulebook-acquisition.md`** before citing anything from it. Two things
that page covers and you must not skip:

- The readily available edition is **2026**. This project targets **2025**, and they differ in
  **exactly four articles — 6-1-3, 6-1-5, 6-1-6 and 19-2**. Everywhere else they are
  identical, so cite freely; in those four, do not.
- The likeliest concrete trap is **6-1-6**. Both editions let the declaration be made at any
  point in the game; the 2026 change is that it drops the condition that the declaring team be
  behind. So under 2025 it is available throughout, **but only to a team that is trailing** —
  do not implement an unconditional onside declaration.

**If the article you need is in neither reference, say so and stop** rather than citing from
memory.

**Never paste rulebook text into the repository — and that includes commit messages.** A
message is permanent and cannot be corrected after a merge. Branches have put verbatim text in
messages that are now unfixable. Paraphrase in a message exactly as you would in code.

**No model identifiers** in code, docs, commit messages or PR text, beyond the attribution
trailers this session's tooling specifies. **No real player, team, league or logo names**
anywhere.

### If you touch `docs/reference/playing-rules.md`

An entry that misstates its article **blocks a merge**, even though it is prose.

1. Read the article and write the entry from it — not from the surrounding entries, not from
   memory.
2. State only what the article states. If you are adding an inference, say in the entry that
   it is one.
3. Watch the terms of art. Entries have shipped wrong by swapping one: "the free *kick* ends"
   is not "the free-kick *down* is over", and "outside the inbounds lines" (the hash marks) is
   not "at the sideline".
4. Run the shingle over your diff and report the count.

**Note the lint's limit:** `scripts/lint-reference.sh` validates that a cited article
*exists*, not that it says what the citation claims. Citations have been wrong in exactly that
way and passed. The check is reading the article, not the lint.

**Reviewers** report each reference finding with (a) the article as printed, (b) what the
entry claims, (c) whether it is **behaviour-bearing** — would an implementer derive engine
behaviour from it, or is it descriptive — and (d) whether any open issue cites that article.
Those two classifications decide whether it blocks, so state them rather than leaving the call
implicit.

## Shingling is untrusted — verify your own

Agents have reported a false clean three ways: using a shared script that had been silently
replaced by a per-line-only version; shingling a sub-diff and reporting it as the branch's;
and using a control phrase that was not in the book, so the control returned 0 and the zero
meant nothing.

**Quote a firing positive control beside your count. A count without one is not a
measurement.** Scan the **branch** diff and the **commit messages** — not a sub-diff — **per
line and with the added text joined** (a match across a wrapped comment hides from a per-line
scan), at **n = 8 as well as n = 10**.

## The harness

Release build, then `--games 400 --no-timing` at seeds 7 and 11, once per seed, before and
after your change. **Capture your own "before" on the `origin/main` you actually cut from and
say which sha it is** — a stored baseline from an older `main` is not a baseline. Or paste
`scripts/harness-reach.sh origin/main` showing `skip` if your change provably cannot reach the
harness.

Paste every row that moved with **one line each naming the mechanism**. "Noise" and
"resampled" are not mechanisms unless you also give the count of differing games and a
mechanism per differing game.

**Read each move against that row's measured noise floor**, in
`docs/reference/calibration-sources.md`, and **say which floor you used** — a before-and-after
at one seed and a comparison across two seeds have different ones. Roughly half of the graded
rows print a different verdict at different seeds **with nothing changed at all**, so check
whether a row you are about to explain is one of them before explaining it.

**Never retune a calibration constant inside a fix** (rule 9). If a row moves, report it; do
not chase it. Residuals go to the retune issue as a comment — never close it, never relabel
it.

### A new constant is model construction, not a retune, only if all three hold — and you must measure all three

1. **No pre-existing constant and no band moved** — show `Targets.swift` is numerically
   unchanged.
2. **The code comment names the row it was set from**, so the retune can find it.
3. **A sweep shows the shipped value is not the greenest available**, and the graded row is
   still reported out of band at branch head.

A constant whose shipped value differs from its own stated derivation, in the direction of a
band, is doing calibration work whatever the commit message says — and disclosure is not the
remedy. Run the harness at four to six values across the plausible range and paste the table.

## Landing beside other branches

**Green on your head is not green on `main`.** Your checks ran on a head containing the `main`
you cut from. If another branch merges first and it touched `Packages/*/Sources` or
`Tools/*/Sources`, your corpus counts, goldens and harness rows were measured against an
engine `main` no longer has.

    git fetch origin main && git merge origin/main     # a merge commit; NEVER rebase pushed history

Resolve keeping both sides, regenerate whichever goldens moved naming the mechanism, re-run
the harness against the new `main`, and push. Do not argue that your checks were already
green.

## Finishing

Push, and **open the pull request yourself** — body per CLAUDE.md: the issue it closes,
measured versus assumed, harness rows before and after. **Do not merge it and do not enable
auto-merge.** Wait for CI and report each check conclusion by name. A red check is yours to
fix before you report done.

## Your report must contain, in so many words

1. The commit shas, by stage.
2. Every *Done when* item from every issue you closed, each with its evidence.
3. **What you MEASURED versus what you ASSUMED**, as two explicit lists.
4. **A "not checked" list** — everything you did not verify, stated plainly.
5. Harness figures before and after, and every moved row with its mechanism.
6. Every place the issue's plan was silent and you filled a gap — enumerated, with what you
   filled each with.

**A report missing (3) or (4) goes back before it is reviewed.**

## Housekeeping

Agent worktrees each carry their own `.build`, and enough of them will fill the disk. If a
build fails with "no space left on device", that is the cause and it is recoverable: delete
the `.build` directories under the worktrees — they are regenerable — and the space is
immediately writable. Never delete another worktree's source, and never delete anything from
your own worktree's git history.
