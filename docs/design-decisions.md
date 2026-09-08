# Design decisions

The settled answers that the rest of the docs encode. Recorded 2026-09-08 across five
rounds of scoping. Anything not listed here is still open.

Decisions with real architectural rationale get an [ADR](adr/); this is the index of
*what* was decided, not *why*.

## Foundational

| # | Decision | Implication |
| --- | --- | --- |
| 46 | **Event sourcing is the default state model** | The world is a fold over an ordered event log; current state is a rebuildable projection ([ADR-0009](adr/0009-event-sourcing-by-default.md)) |
| 47 | **Appearance, contracts, scouting grades and staff are all event-sourced** | A replay shows the gear he wore then; "how did our cap get like this" and "what did we grade him at" become ordinary queries |
| 48 | **Snapshot only where independent reproduction demands it** | `GameSetup`'s opponent-model snapshot is the model case, and each such boundary is justified where it appears |
| 97 | **Only players who did something are credited in a play record** | Crediting all 22 made participants three-quarters of a record; team is derived from the slot convention rather than stored. Cut a play from 756 to 424 bytes |
| 98 | **`FMCore` links with no Foundation and no libm** | `Double.rounded()` resolves to libm's `round`, so the module silently failed to link into any client that did not already pull in Foundation. Guarded by `Tools/playsize` |
| 96 | **No transcendental functions in seeded draws** | `log`, `exp` and trigonometry come from libm, whose results differ between platforms. Normal draws use the Irwin–Hall construction — exact arithmetic, tails bounded to ±6, which is the right trade for attributes clamped to 0...99 |

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
| 99 | **Performance reveals development rather than causing it** | A breakout is evidence about a hidden ceiling that was always there. High ceiling: real. Low ceiling: a one-season wonder. You cannot tell at the time ([development.md](development.md)) |
| 100 | **Nobody exceeds their ceiling, ever** | Generated once from a realistic distribution and never moved. A league of 99s would need a league of 99-ceiling players, which generation does not produce |
| 101 | **Talent is conserved at league level** | Aging decline offsets youth growth, so breakouts redistribute points rather than adding them. Makes balance a testable invariant rather than a tuning exercise |
| 102 | **Experience is weighted by leverage** | A great game in a blowout is worth less than one in a playoff elimination, and performance above expectation counts rather than raw production |
| 103 | **Awards are thresholds, not payouts** | The performance that won the award already counted; paying twice inflates. An award gates whether a leap can happen, never whether the ceiling moves |
| 104 | **A leap is the tail of one distribution, not a branch** | No breakout mechanic. Rare because ceilings are rare, not because a die came up sixes — and growth lands on attributes the position uses, never rolled |
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

## Gameplan

See [gameplan.md](gameplan.md).

| # | Decision | Implication |
| --- | --- | --- |
| 49 | **Two tiers: presets and dials over a canonical rule set** | Five-minute path and deep path both served; presets double as the teaching mechanism |
| 50 | **The `GameplanRuleSet` is canonical; tier 1 generates rules** | The caller reads only rules, so a tier-2 rule builder is additive UI rather than a second interpretation path |
| 51 | **Season identity plus weekly deltas** | A light week is a few tweaks, not a blank form; self-scouting has a stable baseline to measure drift against |
| 52 | **Keys of the week are capped `Directive`s** | First-class type, so bulk per-matchup directives are additive. The real later cost is conflict resolution and report legibility, not schema |
| 53 | **Hypotheses are graded independently of the result** | You can be right and lose. Separating "was your read correct" from "did you win" is what makes gameplanning a scientific loop |
| 54 | **The coordinator always proposes a plan** | The player never faces a blank form; the five-minute path is review-and-accept, and the proposal itself signals coordinator quality |
| 55 | **Gameplan changes are events; plan-vs-execution drift is a readout** | "You said run-heavy; he threw it 62% of the time" is self-scouting, coordinator evidence, and a reason to tighten guardrails, all at once |

## The weekly loop

See [weekly-loop.md](weekly-loop.md), which is a **provisional** document — a probe run
against the systems design rather than a UI commitment. These are the durable findings.

| # | Decision | Implication |
| --- | --- | --- |
| 90 | **The week is a queue of deadline-bearing items, not a calendar** | `WeekItem` with deadline and weight; no forced stops during a season you're simming through |
| 91 | **Every decision carries a default** | Ignoring the queue is a legitimate way to play. This is what makes a four-minute rebuild season and a ninety-minute title game the same loop |
| 92 | **A delegate must act on its own, not merely exist** | Strengthened from the delegation pattern — each delegate system needs an autonomous mode, not just an advisory one |
| 93 | **The decision log persists incrementally during a game** | The app can be backgrounded on any snap; writing at the whistle is a corrupted-replay bug waiting to happen |
| 94 | **A one-line causal summary is derivable from Findings** | Whatever the UI does with it, interrogation must be able to live in the default path rather than behind a tab |
| 95 | **In-season and offseason share one item model** | Draft day is a queue item with auto-draft as its default; nothing new to learn |

**Deliberately not decided yet:** dashboard layout, post-game presentation, the game-watching
screen, and every other presentation choice sketched in that doc. Those get a real design
pass at M4 ([roadmap](roadmap.md)), informed by a running build rather than by argument.

## Traits

See [traits.md](traits.md).

| # | Decision | Implication |
| --- | --- | --- |
| 82 | **A trait must do something a rating cannot** | Conditional, branch-selecting, distribution-shaping, or threshold-changing. Otherwise it's a number with a nickname |
| 83 | **Ratings are the baseline, traits are the character** | Two 78-rated receivers play noticeably differently; 60-100 traits, most players carrying one to three |
| 84 | **Revelation is evidence-based, with the evidence shown** | Inferred from the event stream — the fifth use of state-a-claim-measure-it-show-it |
| 85 | **`TraitBelief` is per observer** | You confirm your own players faster because you see practice; a rival learns from game tape, sometimes before you do. Grounds the trade asymmetry concretely |
| 86 | **Staff can suspect before the maths confirms** | Hunches are graded, so a coach who is repeatedly right becomes someone you trust |
| 87 | **A trait that never fires stays hidden** | Your backup's clutch trait is unknown until he takes a high-leverage snap — playing him is how you find out |
| 88 | **Traits are gained and lost through `DevelopmentEvent`** | Ageing is transformation, not just decline; injury can add negative traits; the deferred currency has an obvious job |
| 89 | **Traits change inputs, branches and thresholds — never outcomes** | No post-hoc fudge factors. Each trait is testable in isolation on a fixed seed |

## Contracts

See [contracts.md](contracts.md).

| # | Decision | Implication |
| --- | --- | --- |
| 72 | **You negotiate a structure, not a number** | The same total can be built many ways; the problem is satisfying him at least cap pain to you. Football-specific rather than a generic haggle |
| 73 | **Preferences are hidden, seeded per player, and fixed** | No re-rolling by reopening talks |
| 74 | **Counters leak preferences** | The delta between offer and counter points along his preference gradient, making negotiation readable |
| 75 | **Agent style distorts the signal systematically** | You read through a consistent bias, so learning the league's agents is the same meta-game as learning your scouts |
| 76 | **Staff intelligence gives a partial read up front** | Rewards staff investment and stops the information game being pure trial and error |
| 77 | **Probing costs patience, and lowballs insult** | Plus a market that moves under you while you stall — otherwise you binary-search the reservation value and it's a slider again |
| 78 | **Agents are named characters with memory and cross-client leverage** | Third use of the writer/scout machinery; who represents a player is real information |
| 79 | **Presets generate structures over a canonical representation** | Same two-tier pattern as gameplan, so a deeper authoring surface is additive |
| 80 | **All four failure modes are live** | Walking, holdouts and trade demands, league-wide relationship damage, and locker room effects — the last kept legible as an interrogable Finding |
| 81 | **Every offer, counter and signing is a `ContractEvent`** | "How did our cap get like this" walks the real history: the restructure that bought a playoff run and the dead money that paid for it |

## Draft and scouting

See [draft-and-scouting.md](draft-and-scouting.md).

| # | Decision | Implication |
| --- | --- | --- |
| 63 | **Scouts are named characters with tracked accuracy** | Same machinery as writers; hiring and firing them is meaningful, and their record is computed from `EvaluationEvent` history |
| 64 | **Scout bias is systematic, not random** | A scout who overrates speed does so consistently, so learning to correct for your own staff is a multi-season meta-game that costs nothing to implement |
| 65 | **Investment narrows variance; it never re-rolls** | Estimates seeded per `(scout, player, depth)`. Deeper draws from a tighter distribution; repeating a depth returns the same answer forever, so the fog can't be farmed away |
| 66 | **Two budgets: staff coverage plus focused spend** | Coverage is the org infrastructure you inherit and leave behind; focused spend is triage across the class |
| 67 | **Grade, ranges and prose, layered** | Round grade with confidence band on the card, attribute ranges on detail, attributed scout prose underneath |
| 68 | **Combine measurables sit outside the fog** | A 40 time is known precisely by everyone; the counterweight that keeps a class navigable |
| 69 | **A public consensus board exists alongside yours** | The gap between them is where draft value lives, and every pick is really a bet on that gap |
| 70 | **Draft day is live, with a clock and trade offers** | The slide, the run, and the offer are the moments; AI trade prices come from their own boards, so it's negotiation not a lookup |
| 71 | **Auto-draft from your board is built first** | A four-minute rebuild season is a stated requirement, so the fast path is built before the live event, not after |

## News and narrative

See [news-and-narrative.md](news-and-narrative.md).

| # | Decision | Implication |
| --- | --- | --- |
| 56 | **Two stages: detection in `FMAnalysis`, rendering in `FMNarrative`** | Selection is the hard problem and is objectively testable; the same Finding rendered by two writers is the variety engine |
| 57 | **Named recurring writers with memory** | Callbacks and running feuds are the strongest anti-fatigue mechanism; no template produces contextual copy |
| 58 | **Pundit credibility is computed and visible** | Predictions are graded against the event stream — the third use of "state a claim, measure it, show the result", after gameplan hypotheses and scouting grades |
| 59 | **Odd things are true world events, reported straight** | Generated and event-sourced so they persist and compound; they reach narrative and perception, never play resolution |
| 60 | **Harshness tracks expectation, not record** | A rebuild going to plan isn't punished; criticism is always specific and evidence-backed |
| 61 | **`MediaPressure` is an `FMAnalysis` metric, not an `FMNarrative` artifact** | `FMNarrative` stays a pure leaf. The owner system reads a measurement, so `FMSimulation` never depends on prose generation |
| 62 | **Media feeds owner patience only** | Lagging and aggregated, never per-article, and one input among record, expectation delta, finances and tenure |

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
