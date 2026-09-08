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
| 33 | **Busts are emergent, not modelled** | No failure-cause taxonomy. Noisy draft scouting + a hidden development trait + scarce snaps already produce them |
| 34 | **What's hidden is growth, not current ability** | True attributes surface quickly once a player is in your building; the development trait and ceiling stay hidden. The gamble is "will he grow", and the cost of finding out is snaps you could have given a veteran |
| 35 | **Staff and org quality speed up your read** | Better organizations converge on a player's development trait faster. This is the sink for org perks and information-only coach skills — no diagnosis event, no currency spend |
| 36 | **Every team holds its own estimates** | AI teams evaluate from their own noisy reads, never a global truth value. Information asymmetry is what makes trades feel like negotiation rather than an exploitable function |
| 37 | **Estimates are seeded per (observer, player) and fixed** | Re-evaluating must not average the noise away and converge on truth for free |
| 38 | **Ceiling recovery is situational only** | A player buried behind a veteran with a good development trait can still get there; one whose attributes were simply low never will. Falls out of the model with nothing added |

## AI play calling

See [play-calling.md](play-calling.md).

| # | Decision | Implication |
| --- | --- | --- |
| 39 | **Your OC calls the plays; the gameplan is his guardrails** | Delegation quality becomes a staff decision, so coordinator hiring has real stakes and AI quality varies believably across the league |
| 40 | **AI quality is decision quality, never outcome modification** | A bad coordinator makes worse choices with the same information; his plays resolve through identical physics. Keeps the engine honest |
| 41 | **Continuous in-game adaptation, rate-limited** | Beliefs update drive by drive, capped by the coordinator's `adaptability`, with a floor on prior weight so he can't overreact to one play |
| 42 | **The defense reads formation, personnel, motion and tendency — never the call** | Non-negotiable: if the AI saw your call, every causal explanation would be a lie. Makes formation diversity mechanically valuable |
| 43 | **Opponent models are built from `PlayRecord` history** | Another event stream query; the same tendency data serves AI decisions, self-scouting, and interrogation. Same architecture as player evaluation |
| 44 | **The opponent model snapshot is part of `GameSetup`** | Otherwise replaying one game cascades into replaying the whole season before it |
| 45 | **Benchmarked against an oracle, a baseline, and a human** | Target: a good coordinator within ~1 point per game of a skilled human, with a 3-4 point spread across the league |

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

- **What the development currency actually buys.** Deferred, but its sink is now
  narrower: diagnosis accrues from staff quality rather than being purchased, so the
  currency needs a different job. Trait acquisition and attribute honing remain the
  obvious candidates.
- **Trade AI.** "Feels legit, not getting one over on the game" requires AI teams that
  can refuse, and that can beat you in ways you'd notice. Approach undecided.
- **How much scouting fog is shown.** Error bars that narrow with investment, or
  something less numeric?
