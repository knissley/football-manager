# The weekly loop

**Status: designed.** None of this exists: there is no app target, no screen, and no
week to advance. The findings it records about data and architecture are durable and
several are already decisions; the screens are sketches.

> **Provisional.** This was written as a *probe* — a way to test whether the
> systems design stores the right data and models the right decisions, by forcing it onto
> a phone screen. Its findings about data and architecture are durable and are recorded as
> decisions; its screens, layouts and interactions are **sketches, not commitments**, and
> should be redesigned properly at M4 when the interactive UI is actually built.
>
> Read the wireframes below as "something roughly like this must be possible", not as
> "this is the design".

Eighty-nine systems decisions meet a phone screen. This is where the five-minute path
either exists or doesn't.

## The week is a queue, not a calendar

No days, no forced stops. Things surface when they need you, ordered by deadline and
consequence, and you work the list until it's empty.

```
WeekItem
  kind      injury · expiring contract · gameplan approval · roster move
            · practice-squad elevation · trade offer · cap warning · media
  deadline  when it must be resolved
  weight    how much worse things get if you ignore it
  default   what your staff does if you never open it
  state     pending · resolved · auto-resolved
```

**Every item has a default.** This is the rule that makes the whole game work: ignoring
the queue is a legitimate way to play, because your staff handles it. A rebuilding season
you sim in four minutes is the same loop as a title run you agonise over — you just let
more defaults fire.

It's also the delegation pattern from every other system, stated at the level of the
app rather than the feature:

> **Every deep system needs a competent delegate, and every decision needs a default.**
>
> Coordinator calls plays · scouting director drafts · negotiator closes deals ·
> staff clears the queue

## The dashboard *(sketch)*

One arrangement that works: a my-team landing whose first module is the queue. Shown to
demonstrate that the fast path and a familiar landing can coexist, not to fix a layout.

```
┌─────────────────────────────────┐
│ NEEDS YOU                    3  │  ← the queue, top items, tappable
│  · Gameplan ready to approve    │
│  · Ellis (hamstring) — IR?      │
│  · Trade offer: 3rd for Vance   │
├─────────────────────────────────┤
│ WEEK 11  ·  at Ironsides (7-3)  │  ← next opponent, rivalry heat
│ Playoff odds 61%  ▲4            │  ← from the win-probability model
├─────────────────────────────────┤
│ 6-4  ·  2nd in the North        │
│ Roster: 2 out, 3 questionable   │
│ Cap: $4.1M  ·  2 deals expiring │
├─────────────────────────────────┤
│ AROUND THE LEAGUE          →    │  ← news teaser, ambient not blocking
├─────────────────────────────────┤
│        ▶  PLAY WEEK             │  ← anchored, always reachable
└─────────────────────────────────┘
```

Playoff odds come free from the win-probability keystone
([ADR-0008](adr/0008-win-probability-keystone.md)) — the same Monte Carlo that powers
drama detection.

## The two paths, concretely

**Five minutes.** Open → three items → approve the coordinator's gameplan, confirm the IR
move, decline the trade → Play Week → Sim → read the headline. Roughly ninety seconds,
and nothing was skipped, because defaults covered the rest.

**Ninety minutes.** Same entry, but you open the gameplan properly, set your keys of the
week as hypotheses, watch the game with the field up, take control on third downs and in
the red zone, then work the full causal breakdown afterwards.

Same loop. The player chooses resolution, exactly as they do inside a game.

## Watching a game *(sketch)*

Portrait, field pinned above a scrolling play feed. The durable parts here are the
*requirements* below the wireframe, not the arrangement.

```
┌─────────────────────────────────┐
│      [ 2D FIELD — pixel ]       │  ~35%, always visible
│   3rd & 6  ·  KES 42  ·  2:04   │
├─────────────────────────────────┤
│ 1st & 10  Inside zone      +4   │  ↑ scrolls, newest at bottom
│ 2nd & 6   PA deep cross    +11 ⚡│  ⚡ = high leverage
│ 3rd & 6   ...                   │
│      [ TAKE THIS SNAP ]         │  ← inline, one tap in
├─────────────────────────────────┤
│  ▶ ‖  1× 2× 4×   ⏭ drive  ⏭ end │
└─────────────────────────────────┘
```

- **One tap in, one tap out.** Taking control must never feel like entering a mode, or
  toggle-at-will collapses into a decision you avoid making.
- **Skip to end of drive / end of game** are always present. The escape hatch is what
  makes dropping in safe.
- Tapping any play row expands its causal detail — the interrogation layer, inline.
- Works one-handed, and survives being interrupted mid-drive.

**A persistence requirement falls out of this.** A game you're calling needs its decision
log ([ADR-0003](adr/0003-deterministic-seeded-simulation.md)) to replay — and the app can
be backgrounded on any snap. So the decision log must be **persisted incrementally during
the game**, not written at the whistle. Cheap if built in; a corrupted-replay bug if not.

## After the game *(sketch)*

The durable requirement is that a **one-line causal summary must be derivable** from
Findings, so that interrogation can live in the default path rather than behind a tab.
How it's presented is a UI decision for M4. One illustration:

> **Lost 24–17.** The interior line gave up pressure on 41% of dropbacks.
>
> `Why` · `Box score` · `Highlights`

The result alone would make interrogation an analytics tab you have to go looking for.
Putting the cause in the headline puts the game's entire pitch in the default path,
thirty seconds after every result, without forcing anyone into a report they didn't want.

- **Why** — Findings ranked by leverage, each tappable through to the plays.
- **Box score** — the conventional numbers.
- **Highlights** — the leverage-ranked reel, already free from the WP model.

## The offseason is the same loop

Different items, longer deadlines: exit interviews, contract decisions, free agency
rounds, the combine, the draft, camp. Draft day is a queue item that opens a full-screen
live event, with auto-draft as its default
([decision 71](design-decisions.md)).

Nothing new to learn, and a whole offseason can be defaulted through in a couple of
minutes.

## What this probe found

The loop was designed to stress the systems work, and these findings are durable
regardless of what the UI eventually looks like.

No systems decision broke:

- The coordinator proposing a gameplan ([54](design-decisions.md)) becomes *approve
  gameplan* — a one-tap queue item.
- Auto-draft-first ([71](design-decisions.md)) is exactly the draft item's default.
- Contract mandates are the negotiation item's default.
- News stays ambient and browsable rather than blocking.

One requirement did get *stronger*: it isn't enough for a deep system to have a delegate.
**The delegate must act on its own when you don't**, or the queue can't drain and the
five-minute path is a fiction.

## Durable requirements

What the rest of the project must satisfy, whatever the UI becomes:

1. **`WeekItem` carries a default.** Every decision type must have a resolution that can
   fire without the player.
2. **Delegates run unattended.** Each delegate system needs an autonomous mode, not just
   an advisory one.
3. **The decision log persists incrementally**, mid-game.
4. **A one-line causal summary is derivable** from Findings.
5. **Playoff odds are computable on demand** — a Monte Carlo over the remaining schedule.
6. **In-season and offseason share one item model.**

## Build order

`WeekItem` with deadlines, weights and defaults lands in the season engine at M3. The
screens are M4, and get a real design pass then.
