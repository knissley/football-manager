---
name: next
description: Tell the owner where the design-then-orchestrate loop stands and what to do next — which session to open, which skill to invoke, and the exact prompt to paste. Reads the two trackers' Current state sections and the open PRs, edits nothing, files nothing. Load when the user says "/next", "what's next", "where are we", "what should I do now", or is starting a session and does not know which step of the loop they are at.
---

# What to do next

You are the concierge for the loop in `docs/design/playbook.md`. The owner runs three
kinds of session and cannot be expected to remember which step they are at. Your job is
to look at the two tracker bodies and say: *you are at step N; open this session; paste
this.* One next step, not a menu.

## Read, in order

1. `CLAUDE.md`, the section *How work flows*.
2. `docs/design/playbook.md`, the whole thing. Its step numbers are the ones you answer
   with.
3. The design tracker's body (the open issue labelled `design`; #183 today): its Current
   state section only.
4. The implementation tracker's body: the open issue labelled `tracker`, which the design
   tracker's Current state also names. Its Current state section only, including the
   gates it lists: the items the owner releases by hand, which differ per milestone.
5. The open pull requests, titles and authors.
6. The newest comment on each tracker, dated, so you can tell whether a wave summary is
   newer than the last design review.

Read the issue bodies through the GitHub tools available in the session (the GitHub MCP
tools on the web, `gh issue view <n>` locally). Do not read the comment threads beyond
the newest comment; the bodies are the state and the threads are history.

## Decide

Answer these in order and stop at the first that is true. Each names the playbook step.

1. **Is there no open issue labelled `design`?** The loop is not installed. Say so; the
   next step is to file the design tracker from the playbook's description of it.
2. **Does the implementation tracker's Current state say every issue is done and every
   gate it names has landed, with no exit audit recorded?** Step 7, the exit audit.
3. **Does it say the exit audit's findings are filed and the milestone is done, with no
   newer tracker open?** Step 8, the designer opens the next milestone.
4. **Is there a tracker for a new milestone whose Current state shows nothing in flight
   and no orchestrator plan?** Step 9, start the orchestrator on it.
5. **Is any issue on the implementation tracker `needs-owner`?** Answer it first; name
   the issue and the question its Current state records. Then step 6.
6. **Is the newest wave summary on the implementation tracker newer than the newest
   design review on the design tracker?** Step 6.
7. **Does the design tracker's Current state list a brief awaiting a verdict?** Step 5.
8. **Does it list proposed doc edits awaiting the owner, or drift owed with a designer
   proposal already posted?** Step 2.
9. **Does it list a missing stream fact not yet filed?** Step 3.
10. **Does it say the milestone ahead needs charting, and no chart is recorded?** Step 4
    in chart mode.
11. **Is the stream list for the milestone ahead not started?** Step 1 if no design
    review has ever been posted, otherwise step 6 with the stream list as the ask. Most
    urgent while the milestone in flight is the one that fixes the record contract, since
    a fact found missing after that costs a schema change rather than an edit.
12. **Otherwise**: step 4, with the first HITL topic in the design tracker's grill queue,
    in the mode it is marked (grill or prototype). If the queue holds only AFK questions,
    step 6, with answering them as the ask: they are the designer's to read, not the
    owner's to sit through.

If two of these are true at once and both are urgent (a `needs-owner` item and a missing
stream fact, say), name the first as the next step and the second as *also due*, and no
more than two.

## Say

```
You are at step <n>: <its title from the playbook>.
Session: <open a new session | go to the designer session | go to the orchestrator session>.
Paste:
<the exact prompt from the playbook, with the tracker numbers and the topic filled in>
Also due: <at most two, one line each, or "nothing">.
Read: <the trackers, shas and dates you read, so the owner can check you>.
```

## Rules

- **Re-derive, do not re-quote.** Counts, shas, gates and tracker numbers come from the
  bodies you read today, not from this skill, the playbook, or a previous answer. Nothing
  here is specific to one milestone's backlog; if an answer needs a gate's name, read it
  off the tracker.
- **One next step.** A list of everything that could be done is not help; the owner
  asked what to do now.
- **Edit nothing, file nothing, post nothing.** If the trackers disagree with each other
  or with the tree, say so in *Also due* and let the owner take it to the designer.
- **Say what you did not read.** If a tracker body has no Current state section, or a
  tool was unavailable, the answer says which step it assumed and why.
