# Design decisions

The settled answers that the rest of the docs encode. Recorded 2026-09-08 across five
rounds of scoping. Anything not listed here is still open.

Decisions with real architectural rationale get an [ADR](adr/); this is the index of
*what* was decided, not *why*.

## Product

| # | Decision | Implication |
| --- | --- | --- |
| 1 | **Role: GM + head coach** | Both roster and tactical systems need real depth |
| 2 | **Hook: a sim you can interrogate** | The engine and its explainability are the headline; stories are the payoff |
| 3 | **Scope: hobby, no deadline** | Depth over ship date; build the interesting parts first |
| 4 | **Career: coaching carousel** | You can be fired and hired elsewhere; needs reputation and AI hiring |
| 5 | **Literacy: fan-level, game teaches** | Real terminology, explained in context |
| 6 | **Whimsy: playful and winking** | Football played straight; the world around it knows it's a game |

## Simulation

| # | Decision | Implication |
| --- | --- | --- |
| 7 | **Genuinely spatial engine** | 22 players with positions and velocities on a tick; outcomes emerge from geometry ([ADR-0006](adr/0006-spatial-simulation.md)) |
| 8 | **Match view: 2D field** | The view renders engine state directly — the dots *are* the sim |
| 9 | **One engine for the whole league** | Detail retained for your game; others replayable from seed |
| 10 | **~60 seconds per simulated season** | ~220ms/game, ~1.5ms/play. A hard budget from line one ([ADR-0006](adr/0006-spatial-simulation.md)) |
| 11 | **Plays are editable data, with a designer** | The play format is the engine's input and the editor's document |
| 12 | **Play calling: toggle at will** | Sim ahead or take any snap. The AI play-caller must be good enough to trust |
| 13 | **Clutch is real and mechanical** | A hidden attribute that genuinely modifies high-leverage performance |
| 14 | **Sliders are league-wide** | World tuning, not a personal difficulty dial — keeps stats comparable |
| 15 | **League shape configurable, real by default** | 32/17/7 to start; a 4-team league for fast tests |
| 26 | **Sliders lock at career creation** | Slider config is part of world identity, not mutable state. Records need no stamping; new settings mean a new career |

## Interrogation and narrative

| # | Decision | Implication |
| --- | --- | --- |
| 16 | **Per-play causal breakdown** | The engine records its own decision points as first-class data |
| 17 | **Full replay with scrubbing** | Replay from `(state, seed, sliders, decision log)` — see [ADR-0003](adr/0003-deterministic-seeded-simulation.md) |
| 18 | **Player grades and situational splits** | Derived from the event stream, never accumulated separately |
| 19 | **Season-level tendencies** | Self-scouting and opponent scouting as gameplanning inputs |
| 20 | **Rivalries seeded at generation, then grown** | Plausible history on day one; real grudges accumulate |

## Development and progression

| # | Decision | Implication |
| --- | --- | --- |
| 21 | **Player development is player-driven; you nudge** | Traits and personality drive growth; you influence via role, playing time, mentorship |
| 22 | **Coach has both a skill tree and a spendable currency** | Two economies: personal abilities, and capital spent on players |
| 23 | **Coach skills affect information and staff, never the field** | Scouting, intel, development, negotiation. The physics stay untouched — the engine never winks |
| 24 | **Carousel: personal skills carry, org perks don't** | Organizations need visible infrastructure (scouting dept, facilities, medical) as a new domain concept |
| 25 | **Development is an append-only event log** | `DevelopmentEvent` with a `source`; the deferred currency is one more case. Makes nudges legible and development interrogable *(proposed — confirm)* |

## Presentation and editing

| # | Decision | Implication |
| --- | --- | --- |
| 27 | **Player editing is cosmetic only** | Name, appearance, gear, jersey number. Nothing touching the sim, so careers stay honest and records comparable |
| 28 | **Any player in the league is editable** | Full ownership of your world; a direct mitigation for the generated-content cold start ([ADR-0005](adr/0005-generated-fictional-content.md)) |
| 29 | **Appearance is presentation data, not sim data** | Keyed by `PlayerID`, outside `FMCore`'s sim types and outside the replay tuple. The engine never reads it |
| 30 | **Seen as portraits, readable dots, an inspect view, and full ceremonial renders** | Player-of-the-week cards, trophy hoists and Hall of Fame moments render fully |
| 31 | **Pixel art** | One style covers field sprites and portraits from a shared parts library; two resolutions (small sprites, chunkier portraits with real facial variety) |
| 32 | **Appearance generated correlated with physicals** | A 340lb nose tackle and a 180lb slot receiver don't roll from the same distribution; the editor edits deviations from that baseline |

## Open questions

Not yet decided. Each needs an answer before the system it touches is built.

- **Bust recoverability.** *Under discussion.* Proposal: a failing player carries a
  hidden `failureCause` — unknowable at the draft, diagnosable afterwards through
  organization and coach-skill investment. Situational causes (scheme, role, coaching,
  confidence) are fixable; "the tools were never there" is not, and the diagnosis tells
  you which so you can stop spending. Recoverability decays with age, and the cause is
  seeded per player and fixed so re-diagnosing can't converge on truth for free.
  Open sub-questions: does a recovered player ever reach his original ceiling, does
  diagnosis cost currency or accrue from staff quality over time, and is there any
  pre-draft bust-risk signal at all.
- **Trade AI.** "Feels legit, not getting one over on the game" requires AI teams that
  can refuse, and that can beat you in ways you'd notice. Approach undecided.
- **How much scouting fog is shown.** Error bars that narrow with investment, or
  something less numeric?
