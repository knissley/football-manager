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

## Open questions

Not yet decided. Each needs an answer before the system it touches is built.

- **Sliders vs. records.** If sliders change mid-career, records stop being comparable.
  Lock them at career creation, or stamp each record with the config that produced it?
- **Development authorship.** Decision 21 is the least directive option available.
  Confirm it delivers enough sense of authorship, or add an offseason focus lever.
- **Scouting risk vs. development control.** These dial against each other: strong
  development control makes a draft bust recoverable and defuses scouting tension.
  Where's the balance point?
- **Trade AI.** "Feels legit, not getting one over on the game" requires AI teams that
  can refuse, and that can beat you in ways you'd notice. Approach undecided.
- **Coach/GM progression.** The carousel implies a reputation model. Does the coach
  also have developing skills, or only a record and a reputation?
- **How much scouting fog is shown.** Error bars that narrow with investment, or
  something less numeric?
