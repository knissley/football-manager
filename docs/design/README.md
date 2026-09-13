# Design

**Status: built.** This directory and the skills it names are the process; the briefs
in it are the depth behind the roadmap.

The project runs in one loop: **design, then orchestrate, then repeat.** The designer
decides what a milestone is for and what it needs; the orchestrator lands it; an audit at
the milestone's exit says whether it is football; the designer reads the audit and the
next milestone opens. The owner sits between every pair of those, and nothing crosses
from one to the next except through a document or an issue.

## The loop

1. **An idea** comes from the owner, from a printed game, from an audit, or from the
   roadmap's own unknowns.
2. **A grilling session** (`/design-grill`, one idea, a fresh session) works it into a
   brief in the shape of [`briefs/TEMPLATE.md`](briefs/TEMPLATE.md). The session never
   edits the repository; the brief is text the owner carries.
3. **The designer** (`/game-designer`) judges the brief against the vision, the roadmap,
   the decisions and the reference: accepted, parked, or rejected. An accepted brief lands
   in `briefs/` and is linked from its milestone in `docs/roadmap.md`; a settled choice
   becomes a line in `docs/design-decisions.md`, or an ADR when it rejected a real
   alternative; a parked idea goes to [`parking-lot.md`](parking-lot.md) with the trigger
   that would promote it.
4. **Deepening.** While milestone N is in flight, the designer keeps N+1 current: its
   depth, its stream list (the facts the record must carry), its cut line, and its fun
   check.
5. **Opening a milestone.** When N's tracker reports done and its exit audit has run, the
   designer turns N+1's depth into a filed backlog: issues in the standard body, waves, a
   tracker. The owner reads the review page first.
6. **Orchestration.** The owner runs `/orchestrator <tracker>`. The orchestrator keeps the
   tracker's Current state section, dispatches, verifies, lands, and posts a wave summary
   per wave. The designer reads each summary and posts a state-of-the-design review.
7. **The exit audit.** A fresh session runs the audit skill (`H5`, when built) against the
   milestone's exit, and its findings are filed before the milestone is called done.

## Who owns what

| File or place | Owner | Others may |
|---|---|---|
| `docs/vision.md` | designer | read |
| `docs/roadmap.md` | designer | an issue may correct a status mark it lands |
| `docs/design-decisions.md` | designer | an issue may add a `Reopened` or `Amended` note it earns |
| `docs/adr/` | whoever decides, via `/adr` | amend by dated section only |
| `docs/design/` | designer | grilling sessions read; nobody else writes |
| `docs/weekly-loop.md`, `docs/gameplan.md`, `docs/schemes.md`, `docs/traits.md`, `docs/draft-and-scouting.md`, `docs/news-and-narrative.md`, `docs/play-calling.md`: the system designs | the designer, for what is designed | the issue that builds a part of one edits that part and the status line |
| `docs/reference/`, `docs/invariants.md`, `docs/play-record.md`, `docs/match-engine.md` and the rest | the issue that changes the thing they describe | the designer reads them as truth and files an issue when they are wrong |
| the implementation tracker and its issues | orchestrator | the designer comments; the owner decides |
| the design tracker | designer | the owner decides |

Both trackers keep their **state in the body**, rewritten in place, and their **history in
comments**. A fresh session reads the body's Current state section, not the thread.

**Two writers never edit one file at once.** The designer does not touch a file named in
the Files list of an issue that is in progress, or that the tracker's Current state names
as in flight. The orchestrator's agents do
not edit the vision, the roadmap's plan, or a decision's text beyond what their issue
says. When the two need the same file, the designer waits for the merge.

## Where a thing goes

- A rule of the sport: `docs/reference/`, cited by article and season, in our own words.
- A fact the record must carry: the milestone's stream list in the roadmap, then an issue
  on the record track.
- A moment a player should have: the milestone's fun check in the roadmap.
- A choice: `docs/design-decisions.md`, one line and a reason.
- A choice that rejected a real alternative: an ADR.
- An idea worked through: a brief.
- An idea not now: the parking lot.
- A question for the owner: the design tracker.
- Work: an issue in the standard body.

## Cadence

- The designer runs after every wave summary and at every milestone boundary. A session
  that finds nothing still posts the header on the design tracker.
- Grilling sessions run whenever the owner has an idea worth an hour. Four are queued at
  any time on the design tracker, in the order the roadmap needs them.
- The stream list for M2 through M4 is due before M1's retune closes, because the
  contract stops moving after that.
