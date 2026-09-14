---
name: orchestrator
description: Run a filed backlog from its tracker issue — dispatch implementers to issues, verify what they report, and merge. Load when driving issues from a tracker (today #1, the audit backlog) to merged rather than implementing one yourself, and use its second half as the brief handed to every implementer and reviewer.
disable-model-invocation: true
---

# Orchestrating a backlog

**Argument: the tracker issue number.** With none, the open issue labelled `tracker`; today
that is **#1**, the audit backlog, and the next one is whatever tracker the designer
(`/game-designer`) opens for the next milestone. The tracker's body names the label its
issues carry. This skill is how work gets from a `status:ready` issue to `main` without the
owner approving each PR, and what every implementer must be told before it starts.

Two halves. **Part 1 is yours.** **Part 2 is the brief you hand to each implementer** — paste
it, or point them here.

---

# Part 1 — The orchestrator's job

You dispatch subagents to implement issues. **You never implement an issue yourself.** What
you do personally: read every report critically, **verify the hard constraints in the tree
rather than trusting the report**, merge, and correct the record when something turns out
wrong. You may edit issues, split them, or file new ones from what an agent measured — each filed
one carries a `Where it fits` line naming the batch it lands in and what it must follow, and
you say so on the tracker. **You are not the designer.** An idea that is not a defect a fan
would notice in the printed game goes to the owner and the design tracker, never into a wave.

## The state machine

Every backlog issue carries the backlog's label (`audit-backlog` today), a `track:<letter>`
and usually a `wave:<n>`.

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

**The tracker's body is the state. Its comments are history.**

- **The Current state section at the top of the tracker's body is rewritten in place** —
  `main` sha, counts, what is in flight, what is waiting on the owner, the queue. Update it
  when `main` moves, when an issue lands, when something becomes owner-gated, or when the
  queue changes.
  **Never append current state as a comment.**
- **Cap it at 400 words**, and keep it to five things: the `main` sha; the counts; what is in
  flight, one entry per branch carrying the handoff below; what waits on the owner, with the
  question; and the queue. It reached about 2,000 words and was rewritten at that length on
  every merge, which is both the cost and the reason it goes stale — a section nobody can
  re-read in a minute is one nobody re-derives. **Reasoning, findings and anything that
  explains *why* go to a comment**, which is where this skill already puts history, and the
  section links it.
- **An in-flight branch's entry is the handoff.** Per branch: its name, head sha, the issues
  it closes, what has been verified on that head (which checks, which harness seeds, which
  review round and its result), and the exact next action. A session that pauses rewrites
  these before it deletes its triggers; a session that resumes reads them and continues from
  the body, not from memory.
- **Comments are for what is cross-cutting and permanent**: a residual reported to the retune,
  a standing-rule change, a wave summary, a correction to something already on the record.
- **Do not post a status comment describing where things stand.** Three such comments were
  posted in twenty-four hours, each superseding the last, and a fresh session reading the
  thread top-to-bottom met the stale one first. That is the failure this convention exists to
  prevent, and posting one more is how it comes back.
- Counts and shas in that section are **measured, not carried forward** — query the labels and
  read the sha. A count quoted from the previous version of the section is exactly the mistake
  the failure-mode section below describes.

The wave tables further down the tracker are a filing-time record, not an index: **39 of
the 115 backlog issues do not appear in them at all** — measured 2026-09-12, and re-derivable
by diffing the issue numbers in those tables against the `audit-backlog` label query. (The
body said 38 until that count was taken; an off-by-one in the sentence warning you the tables
are unreliable.) **The live backlog is the labels.** A table the state document declares
unreliable is the re-quoting trap the last section of this part describes, so **do not
maintain the tables by hand**: when you next rewrite the body, regenerate them from the label
query, or delete them and keep only the notes beneath, which are the part labels cannot
recover.

## Scope, and the wave summary

Two standing rules, agreed with the owner at the re-audit of 2026-09-11 and until now
recorded only in a comment on #1, which by this skill's own convention is history:

- **No new rules-layer or resolver issue is dispatched unless it moves a graded harness row
  or a fan would notice it in the printed `gamelog` game.** Correct and cited is not
  sufficient; the A track grew from nine issues to nineteen on correctness alone.
- **Every wave summary re-reads each closed issue's plan and Done-when against the current
  harness output**, not against the PR's claims, and lists any plan item that did not land.
  Two such items (C10's chip-shot share, C11's net-punt separation) were found this way and
  are now inputs to the retune.

A wave summary is one comment and carries: what merged, with shas; every harness row that
moved across the wave, with its mechanism; what changed in the plan and why; what waits on
the owner; and the re-read above.

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

## Review, before you merge

When an implementer reports done and its PR is open, dispatch **one reviewer with a fresh
context**: it gets the PR body — which is the implementer's report — the diff, every *Done
when* line of every issue the PR closes, `CLAUDE.md`, and Part 2 of this skill.

**The reviewer does not re-run the suites.** The implementer's `preflight` run is the first
pass over them; CI is the second and third, running on every push to the PR on two
architectures (`ubuntu-24.04` and `ubuntu-24.04-arm`). A reviewer's run would be the fourth
agreeing green of the same trees, and it buys nothing the CI conclusions do not already say.
What the reviewer adds is reading, not repetition.

**What it reads:**

- **The diff**, against the merge base it resolves itself — `git merge-base origin/main
  HEAD`. A two-dot `git diff origin/main..branch` lies once `main` has moved.
- **Every article the branch cites.** `./scripts/lint-reference.sh --show` prints them; the
  reviewer reads the article as printed before judging the entry beside it, and quotes the
  header it printed. The lint validates that an article *exists*, not that it says what the
  citation claims, so this is the only check there is.
- **The `preflight --report` block in the body, against the tree**: the `Targets.swift`
  checksum at the merge base, the `harness-reach` verdict against the files the branch
  actually moved, and which steps the block says ran. A lane that does not match the diff, or
  a checksum that does not reproduce, is a finding.
- **Each *Done when* line against the evidence the body gives for it**, and the Assumed and
  Not-checked lists for anything that should have been measured.

**What it runs itself** — and nothing else, unless a claim in the body cannot be judged any
other way, in which case it says which claim:

- `./scripts/lint-reference.sh --show` on the branch's citations.
- `./scripts/preflight.sh --lane docs` — seconds, and it catches the lints, the census and
  `--messages` on the head as pushed.
- **Any mutation the implementer claims.** A `.football` test that cannot fail when its own
  football is broken is a `.pin`; re-break the rule and confirm red, rather than believing the
  sentence that says it was done.

**It returns `pass`, or concrete failures, each with the command that shows it.** A finding
with no reproducing command is an opinion, and goes where the cost rules below send it.

- Before it calls a reference finding pre-existing, it runs `git show origin/main:<path>` and
  greps; two of eight findings on one branch were mis-classified from reports.
- A second round is for behaviour, football, or rule 8 to 11 failures only. Prose findings go
  where the cost rules below send them.
- **After two failed rounds the issue stops**, and you say so on it. A narrow third round is
  allowed only when the second failure was prose the first fix introduced, and it is written
  on the issue before it runs.
- The review adds no status: the issue stays `status:in-progress` until the merge.

The reviewer's pass is not your verification. It read the head; the section below is what you
check yourself, in the tree, before the merge.

## Cost discipline for a dispatch round

Agreed with the owner 2026-09-13, after PR #185 took about two and a half hours and a large
share of a session's budget to land 309 added lines of which one was an engine change. Rounds
two and three were roughly 1.5 of those hours, touched no engine source, and ran the full
pre-push checklist each time over wording. **The four rules are the owner's, verbatim:**

1. **Merge on a reviewer's PASS.** A PASS with non-blocking findings is a merge, not a fix
   round.
2. **Route non-blocking prose findings to #93**, which exists for exactly this and whose own
   taxonomy says doc-duplication, process-history and snapshot findings "batch without
   loss". The **one** exception is #93's kind 1 — a doc whose own numbers contradict it —
   which stays in the PR that introduced it. Of the four findings that triggered #185's
   round 2, only one plausibly met that bar; the other three should have been filed.
3. **Scope the checklist to the blast radius.** When `harness-reach.sh` says `skip`, the
   release build and the harness runs are theatre. A docs-and-tests round needs the suites, the
   lints, the census and `--messages` — not a fifth agreeing harness measurement.
4. **One reviewer round.** A round plus a re-read plus a narrow third pass is three; the skill
   permits the third only for prose the second round introduced, and the cheapest way to never
   need it is rule 1.

And one addition, which is how rules 1 and 2 meet a PASS that still found something:

5. **A PASS with prose findings gets a follow-up commit from the same implementer, with no
   second review** — and only when a document contradicts its own numbers (#93's kind 1).
   Every other prose finding is filed on **#93** or whatever issue succeeds it, named in the
   merge comment. Do not send a PASS back to a reviewer to confirm a paragraph.

**What this does not change: nothing about the football.** Articles are still read as printed
rather than trusted from a lint, `.football` tests are still mutation-verified, `Targets.swift`
is still checked numerically against the base, and a report's numbers are still re-derived
rather than re-quoted. Those checks are cheap relative to what they prevent. The expensive part
was never rigour; it was re-running a full checklist three times over wording.

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

Swift 6.2. `preflight` runs CLAUDE.md's Commands block verbatim; by hand, use that block's
form and never a variant.

**Run every check in the foreground**, using the Bash tool's own `timeout` parameter (up to
600000 ms). An agent that backgrounds a check ends its turn and stalls the pipeline.

Budget against the seconds `preflight` prints on a four-core Linux container with warm
`.build`: FMSimulation's debug suite **161–214 s**, 173 s warm on its own, against **15 s**
under `-c release`; a 400-game harness seed **16 s**; a whole `engine`-lane run **4 min 2 s**
and a `docs` one **8 s**.

## Every check, before you push

**This section is the implementer's.** A reviewer does not re-run the suites — CI runs them
on every push, on two architectures — and what a reviewer does run is in Part 1, under
*Review, before you merge*.

Run **`./scripts/preflight.sh`**: it picks the lane from your diff, runs what CI runs over the
trees you touched, and stops at the first failure naming the step and its log. **Paste
`--report`'s block into the PR body**: lane, base sha, `harness-reach` verdict,
`Targets.swift` checksum. Its format step passes `--strict`, which is what makes a finding
fail: without it the linter prints its findings and exits 0. CI additionally compares two
50-game harness runs at seed 7 for determinism; `preflight` does not.

Iterate with **`--iterate <SuiteName>`**: `swift test -c release --filter` in the package
declaring it, since a debug suite spends its time building the game corpus unoptimised. **Run
the full debug suite once before you push:** one FMSimulation test, in `FormAndFitTests`, is
behind `#if DEBUG`, which release does not compile.

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

1. Read the article as printed: `./scripts/lint-reference.sh --show` prints every article the
   branch diff cites. Write the entry from it, not from the surrounding entries and not from
   memory.
2. State only what the article states. If you are adding an inference, say in the entry that
   it is one.
3. Watch the terms of art. Entries have shipped wrong by swapping one: "the free *kick* ends"
   is not "the free-kick *down* is over", and "outside the inbounds lines" (the hash marks) is
   not "at the sideline".

**Note the lint's limit:** it validates that a cited article *exists*, not that it says what
the citation claims. Reading the article is the check, and `--show` is how.

**Reviewers run `--show` before judging an entry**, quote the article header it prints, and
report each finding with (a) the article as printed, (b) what the entry claims, (c) whether it
is **behaviour-bearing** — would an implementer derive engine behaviour from it, or is it
descriptive — and (d) whether any open issue cites that article.
Those two classifications decide whether it blocks, so state them rather than leaving the call
implicit.

## The shingle is the lint's job — do not write your own

`scripts/lint-reference.sh` scans whole files and whole commit messages — never a sub-diff —
per line **and** joined, with its controls cut from the corpus at runtime: unless they come
out 1, 1, 0 it prints no count and exits 2. **Quote that control line beside your count.**
`preflight` runs the tree scan and `--messages`; **`--n 8`** it does not, and that is worth a
run on a branch that added football prose — expect `docs/tools.md`'s table, not a zero. Run
`--messages` immediately before you push: afterwards a message takes rewriting history.

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
not chase it. Residuals go to the issue the tracker names as the retune (E3 #49 today) as a
comment — never close it, never relabel it.

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

**Open the pull request yourself, as a draft, with your first push:** a bare branch gets no CI
run now that CI fires on `push` only for `main`. Mark it ready when done, with the body
`.github/pull_request_template.md` gives you and the `--report` block in it. **Do not merge
it and do not enable auto-merge.** Wait for CI and report each check conclusion by name. A
red check is yours to fix before you report done.

## Your report is the PR body

**There is no second report.** The PR body is what you hand back, and the reviewer and the
orchestrator read it as the report — a message that restates it is waste, and a fact that
lives only in that message is lost the moment your session ends.

GitHub prefills the body from **`.github/pull_request_template.md`**. Fill every heading it
gives you and delete the ones that do not apply rather than writing "n/a" beneath them:

1. `Closes #N` — or `Refs #N` when the PR satisfies only part of an issue.
2. One paragraph on what changed, naming the **mechanism**.
3. **Every *Done when* line of every issue you closed, each with one line of evidence.**
4. **Measured**, **Assumed** and **Not checked**, as three bullet lists. A place where the
   issue's plan was silent and you filled the gap by judgment is an **Assumed** line, and it
   names what you filled it with.
5. The `./scripts/preflight.sh --report` block, pasted whole — it prints its own fence.
6. Every harness row that moved, with **one mechanism each**, or `none moved` with the
   `harness-reach.sh origin/main` verdict that shows the change could not reach the harness.

**Cap: 500 words outside the report block.** The last twelve merged bodies averaged about
2,200, one of them for a single visibility change. Evidence is a line, not a narrative: the
command and what it printed, not the story of running it.

**A body missing Assumed or Not checked goes back before it is reviewed.** Those two lists are
where the real findings have come from; a body without them reads as certainty nobody has.

**Commit messages: one paragraph, and the mechanism.** Cite the rulebook by article number and
season; **never rulebook text** — a pushed message cannot be corrected after a merge, and
branches have already put verbatim text in messages that are now unfixable. No model
identifiers beyond the attribution trailer this session's tooling specifies.

## Housekeeping

Agent worktrees each carry their own `.build`, and enough of them will fill the disk. If a
build fails with "no space left on device", that is the cause and it is recoverable: delete
the `.build` directories under the worktrees — they are regenerable — and the space is
immediately writable. Never delete another worktree's source, and never delete anything from
your own worktree's git history.
