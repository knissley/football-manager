# The playbook: running the loop

**Status: built.** This is the operator's checklist for the loop
[`README.md`](README.md) describes: which session to open, which skill to invoke, what
to paste, and what comes back. Start at [*What just happened?*](#what-just-happened)
and go to the step it names. `/next` reads the two trackers and does this lookup for you.

Two issues carry all the state. **#1** is the implementation tracker (the audit backlog
today; the next milestone's tracker replaces it). **#183** is the design tracker. Each
keeps its state in the body's *Current state* section and its history in comments. When
in doubt, read those two sections and nothing else.

## The sessions

| Session | How many | Lives for | Model | Resumes from |
|---|---|---|---|---|
| Orchestrator | one per backlog | the whole backlog | strongest | the implementation tracker's body |
| Designer | one | across milestones | strongest | #183's body |
| Grill | one per idea | that idea | mid-tier is fine | nothing; you copy the brief out |
| Audit | one per milestone exit | that audit | strongest | nothing; findings are filed |

The agents you never create are the orchestrator's: it dispatches implementers into
worktrees and a fresh-context reviewer per PR as subagents. The designer and the grill
dispatch nobody. If a long-lived session dies, open a new one with the same skill and
tracker number; it continues from the issue body, not from memory.

## What just happened?

| Event | Go to |
|---|---|
| Nothing yet; I want to know where things stand | [`/next`](#next) |
| I have an idea, or an hour and a queued grill topic | [Step 4](#step-4-grill-one-idea) |
| A grill session ended with a brief | [Step 5](#step-5-carry-the-brief-to-the-designer) |
| The orchestrator posted a wave summary on the implementation tracker | [Step 6](#step-6-run-the-designer-after-every-wave-summary) |
| The designer proposed doc edits and I agree | [Step 2](#step-2-approve-the-designers-edits-as-a-docs-pr) |
| The designer found a fact the record does not carry | [Step 3](#step-3-a-missing-stream-fact-goes-to-the-implementation-tracker-now) |
| An issue on the implementation tracker is `needs-owner` | Answer it on the issue, remove the label, then [Step 6](#step-6-run-the-designer-after-every-wave-summary) |
| The implementation tracker's Current state says everything is done | [Step 7](#step-7-the-exit-audit) |
| The exit audit's findings are filed | [Step 8](#step-8-the-designer-opens-the-next-milestone) |
| The designer has filed the next milestone's issues and tracker | [Step 9](#step-9-start-the-orchestrator-on-the-new-tracker) |
| A session died or the container restarted | [Resuming](#resuming) |

## The steps

### Step 1: start the designer

A new session on the repository at `main`, strongest model. If `command -v swift` finds
nothing, run `./scripts/install-swift.sh` first: the skill's reading order ends with one
printed game. Paste:

```
/game-designer

The design tracker is #183. Read its Current state, then produce a state-of-the-design
review: drift between the roadmap and the tree, contradictions among decisions, the
unknowns for the milestone in flight and the one ahead, what a fan notices in one
printed game that no issue covers, and your questions for me with recommendations.
Post the review as a comment on #183 and rewrite its Current state. Then deepen the
milestone ahead: its stream list checked line by line against docs/play-record.md,
its cut line, and its fun check. Do not edit any doc yet; list the proposed edits in
your review and I will approve them.
```

What comes back: one review comment on #183, a rewritten Current state, and a list of
proposed doc edits. You answer its questions in the session.

### Step 2: approve the designer's edits as a docs PR

In the designer session: *"open the docs PR."* It cuts a branch from `main`, edits only
files it owns (the vision, the roadmap, the decisions, `docs/design/`), checks the
implementation tracker's Current state for an in-flight issue whose Files list names any
of them, and opens a PR that CI lints. You merge it. The orchestrator's branches merge
`main` in and are unaffected.

### Step 3: a missing stream fact goes to the implementation tracker now

The one case where design work enters a running milestone. If the stream list finds a
fact the next milestone needs and `PlayRecord` does not carry, the designer drafts an
issue in the standard body (`.claude/skills/orchestrator/references/issue-template.md`)
on the record track with a `Where it fits` line. You read it. It is filed on the
implementation tracker with a comment there, and the orchestrator slots it before the
retune. The contract stops moving when the milestone closes, so this never waits.

### Step 4: grill one idea

A fresh session per idea, on the repository, any capable model. Take the next topic from
#183's grill queue, or your own. Paste:

```
/design-grill

The idea: <one sentence>. Milestone I think it belongs to: <M?>. Walk me up the ladder
one rung at a time, recommend at each, and wait for my answer. End with the brief.
```

It asks nine questions in order (the player's decision, the moment, the football truth,
systems touched, what the record must carry, the fun test, cost and home, the cut,
contradictions), recommends at each, and waits. It ends with a brief and the three
things the designer should push back on. It never edits the repository. Copy the brief.

### Step 5: carry the brief to the designer

In the designer session:

```
Brief for review:
<paste the brief>
```

What comes back: accepted, parked, or rejected, posted on #183 with the reason. If
accepted, the designer proposes a docs PR that adds `docs/design/briefs/<slug>.md`, links
it from its milestone in the roadmap, adds a decision line for anything it settled, and
runs `/adr` for anything it reversed. Then Step 2. Parked ideas go to
[`parking-lot.md`](parking-lot.md) in the same PR.

### Step 6: run the designer after every wave summary

When the orchestrator posts a wave summary comment on the implementation tracker, or you
answer a `needs-owner` question that changes a decision, go to the designer session:

*"Wave summary posted on #1; run the state-of-the-design review."*

Same output as Step 1. A session with nothing to report still posts the header, so the
absence of a review never has to be interpreted.

### Step 7: the exit audit

When the implementation tracker's Current state says everything is merged and the
retune has landed, a fresh session audits the milestone against its exit criteria in
the roadmap. H5 #47 is the skill for this; until it lands, the session runs the way the
September audit did: read-only, findings reported to you first, issues filed together
after you have read them. Findings go on the implementation tracker before the milestone
is called done, and its Current state says so.

### Step 8: the designer opens the next milestone

In the designer session: *"The exit audit has run; open M<n+1> as a backlog."* It turns
the milestone's depth into issues in the standard body with tracks, waves, dependencies
and `Where it fits` lines, drafted in one data file rendered to a review page. You read
the page. It files the issues in dependency order and a tracker issue titled
`M<n+1> tracker`, labelled `tracker`, with a Current state section at the top. The old
tracker is closed with a comment naming the new one.

### Step 9: start the orchestrator on the new tracker

A new session on the repository:

```
/orchestrator <tracker number>
```

It reads the tracker's Current state, dispatches implementers and reviewers, verifies in
the tree, merges, rewrites the tracker body, and posts a wave summary per wave. You read
summaries and answer `needs-owner`. You are back at Step 6, deepening the milestone
after this one.

## Resuming

- **The orchestrator died.** New session, `/orchestrator <tracker number>`. It reads the
  tracker's Current state and the in-flight entries, checks `git worktree list`, and
  continues. Nothing in the dead conversation was state.
- **The designer died.** New session, `/game-designer`, then *"resume from #183."*
- **A grill died.** Start it again; a grill has no state worth saving before the brief.
- **A container restarted under the orchestrator.** It checks every worktree for
  uncommitted work before anything else; the skill says how.

## What you never do

- Give the orchestrator an idea. Ideas go through Step 4 and Step 5; only an issue you
  have read reaches a wave.
- Edit the roadmap or a decision while an in-flight issue's Files list names it. Wait for
  the merge, or let the issue carry the change.
- Read a tracker's comments to find out where things stand. The body's Current state is
  the state; if a comment disagrees, the body wins.
- Retune inside a fix, regenerate a golden to pass a red test, or paste rulebook text.
  Those are CLAUDE.md rules 8 and 9 and the orchestrator polices them; the playbook only
  repeats them so the owner recognises a breach when reading a PR.

## `/next`

In any session on the repository, `/next` reads `CLAUDE.md`, this playbook, #183's
Current state, the implementation tracker's Current state and the open PRs, and tells
you which step you are at, which session to open, and the exact prompt to paste. It
edits nothing and files nothing.
