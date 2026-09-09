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
| 15 | **League shape configurable, real by default** | 32/17/7 to start. Test presets are 8 teams (structural floor) and 12 teams (real division races) — 4 teams cannot express two conferences and tests nothing structural |
| 26 | **Sliders lock at career creation** | Slider config is part of world identity, not mutable state. Records need no stamping; new settings mean a new career |

## Interrogation and narrative

| # | Decision | Implication |
| --- | --- | --- |
| 16 | **Per-play causal breakdown** | The engine records its own decision points as first-class data |
| 17 | **Full replay with scrubbing** | Replay from `(state, seed, sliders, decision log)` — see [ADR-0003](adr/0003-deterministic-seeded-simulation.md) |
| 18 | **Player grades and situational splits** | Derived from the event stream, never accumulated separately |
| 19 | **Season-level tendencies** | Self-scouting and opponent scouting as gameplanning inputs |
| 20 | **Rivalries seeded at generation, then grown** | Plausible history on day one; real grudges accumulate. Refined by decisions 166–171 |

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
| 65 | **Investment narrows variance; it never re-rolls** | Estimates seeded per `(scout, player, depth, collegeSeason)`. Deeper draws from a tighter distribution; repeating a depth *within a season* returns the same answer, so the fog can't be farmed away. Refined by decision 157 once prospects could develop |
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

## Schemes and identity

| # | Decision | Implication |
| --- | --- | --- |
| 126 | **Scheme belongs to the team, not the coach** | You choose it freely. Coordinator quality is *how well it is run* — the season-level version of gameplan guardrails |
| 127 | **The cost of switching is familiarity, and familiarity decays** | An unfamiliar coordinator runs a scheme at 60% and reaches full command in four seasons. A penalty that fades is a different thing from a gate that opens only when the right name appears on a hiring list |
| 128 | **Familiarity is tracked per component, not per family** | A west-coast coach moving to spread keeps his zone-blocking background; moving to power run he keeps nothing. Related schemes share, unrelated ones do not |
| 129 | **Scheme fit is a weight delta, not a multiplier** | A scheme can make a rating *start* counting — a guard's agility is worthless in gap and central in zone. A multiplier on a zero weight is silently nothing |
| 130 | **Every scheme de-emphasises something** | A modifier set that only adds emphasis barely moves anyone once weights renormalise. An identity is as much what it stops valuing as what it starts valuing |
| 131 | **Offseason changes are free; mid-season carries a steep install penalty** | The desperation move real teams occasionally make stays available and stays expensive |
| 132 | **Generated teams have identities, occasionally clashing with their talent** | A run-heavy club with a gifted young passer is a team that ought to change, and a good AI will. Puts the trade market's logic into the world on day one |

## Module boundaries

| # | Decision | Implication |
| --- | --- | --- |
| 124 | **`FMGeneration` runs once, at world creation** | It describes the league you inherit; every later change is a decision in `FMSimulation` |
| 125 | **AI roster management shares no mechanism with generation** | Generation assigns from full knowledge; an AI team must earn a roster under a cap from noisy estimates. Reusing generation's heuristics would make its trades and drafts theatre. They share only `RosterShape` |

## Penalties and officiating

See [penalties.md](penalties.md).

| # | Decision | Implication |
| --- | --- | --- |
| 111 | **Two classes: discipline and desperation** | Procedural fouls come from ratings and situation; holding and interference emerge from *losing a matchup*, so a flag is explicable rather than random |
| 112 | **Home field advantage emerges from crowd noise** | Noise raises visiting pre-snap fouls, so the advantage is a mechanism rather than a bonus applied after the fact |
| 113 | **Twelve men is a substitution failure against tempo** | Makes hurry-up a genuine weapon rather than only a clock tactic |
| 114 | **Hard Count is a two-sided trait** | Draws opponent offside, raises your own false-start and delay risk |
| 115 | **Drawing fouls is a by-product of winning matchups** | No trait reaches across to modify an opponent's rate; a beaten defender holds because he is losing |
| 116 | **The engine never reads leverage** | A flag is not likelier in January. It is equally likely and simply matters more, and the analysis layer surfaces it because |ΔWP| is enormous |
| 117 | **Accept/decline is yours while calling plays, your coordinator's otherwise** | Both branches compared on win probability, so the better option is always known and explicable |
| 118 | **`OfficiatingProfile` is the contract; crews are a generator over it** | Walking back named officials means deleting a generator, not unpicking a feature |
| 119 | **Thirty-three fouls, with pass interference the only spot foul** | Sounds like a broadcast rather than a rulebook subset, and each one has real enforcement |

## Characters and lifecycle

| # | Decision | Implication |
| --- | --- | --- |
| 120 | **Every non-player character ages and retires** | Coaches, scouts, agents, writers, officials and trainers are all `Personnel` with a hidden retirement age. Without it, a fiftieth season is covered by the columnist who started it |
| 121 | **One identifier space and one lifecycle for all of them** | Modelling five professions separately means writing the same lifecycle five times and getting it slightly different each time |
| 122 | **Cohorts are generated spread across their careers** | Generating everyone at the same stage retires a whole profession in one offseason, then again in lockstep a generation later |
| 123 | **Retirement age is hidden, like a player's ceiling** | You learn someone is near the end by watching, which makes succession something a general manager has to think about |

## League customisation

See [`LeagueShape`](../Packages/FMCore/Sources/FMCore/LeagueShape.swift).

| # | Decision | Implication |
| --- | --- | --- |
| 105 | **League structure is editable at world creation, and fixed thereafter** | Conferences, divisions and team counts determine the schedule, the bracket and every record in league history. Same reasoning as sliders locking at creation |
| 106 | **Names, cities, colours and uniforms are editable at any time** | None of them mean anything to the simulation. They are events, so a replay shows the uniform worn then |
| 107 | **Validation names the failure and explains it** | A player who has just tried to build a one-conference league is told the championship game would have nobody to play, not that their input was invalid |
| 108 | **All failures are reported at once** | Someone fixing a custom league should not be led through problems one at a time |
| 109 | **Invariants: two conferences, two teams per division, every division winner makes the playoffs, an even team count, and a schedule the structure can actually support** | The validator exists to catch shapes that break the sport, not shapes that are merely unfamiliar — four conferences, or one big division per conference, are allowed |
| 110 | **Expansion is a separate, deferred feature** | Adding a team to a *running* league needs a draft and a schedule rebuild. Not the same thing as editing configuration |

## Presentation and editing

| # | Decision | Implication |
| --- | --- | --- |
| 27 | **Player editing is cosmetic only** | Name, appearance, gear, jersey number. Nothing touching the sim, so careers stay honest and records comparable |
| 28 | **Any player in the league is editable** | Full ownership of your world; a direct mitigation for the generated-content cold start ([ADR-0005](adr/0005-generated-fictional-content.md)) |
| 29 | **Appearance is presentation data, not sim data** | Keyed by `PlayerID`, outside `FMCore`'s sim types and outside the replay tuple. The engine never reads it |
| 30 | **Seen as portraits, readable dots, an inspect view, and full ceremonial renders** | Player-of-the-week cards, trophy hoists and Hall of Fame moments render fully |
| 31 | **Pixel art** | One style covers field sprites and portraits from a shared parts library; two resolutions (small sprites, chunkier portraits with real facial variety) |
| 32 | **Appearance generated correlated with physicals** | A 340lb nose tackle and a 180lb slot receiver don't roll from the same distribution; the editor edits deviations from that baseline |

## Situational football and defense

| # | Decision | Implication |
| --- | --- | --- |
| 133 | **One situational vocabulary, in `FMCore.SituationClass`** | Down-and-distance, field, score and time buckets live in one type. A gameplan rule, an AI policy, a tendency table and a post-game report cannot disagree about what "third and long" means |
| 134 | **The classification decides nothing** | It is a description other systems key off, not a policy. Anything that reads like a recommendation (`isFourthDownTerritory`) is explicitly a description of the situation, with the decision left to a win-probability call |
| 135 | **One classification per snap, offence-relative** | Like `Situation`, it reads from the possessing team's point of view. The defence reads the *same* value and draws the opposite conclusion — a two-minute drill is `isDesperation` to one bench and `isClockBurn` to the other. Mirroring a flipped copy would be two vocabularies again |
| 136 | **Defense is toggleable snap by snap, exactly as offense is** | Same profile shape, same gameplan mechanism, same opponent model, same benchmark. Watching the opponent run a two-minute drill at you is the same product as running one |
| 137 | **A defensive call is composed data, not a named label** | `DefensiveCall` carries coverage, rush, front alignment, package, run fit and disguise. The engine reasons about components; named calls are a convenience layer over the composition, so a designed call needs no new engine case |
| 138 | **`CallVulnerability` has no `none` case** | Every defensive call trades something away, structurally. A call that covered everything would make offensive decisions meaningless and leave the analysis layer nothing true to say about why a play worked |
| 139 | **Conceding yards can be the defence winning** | Prevent and quarters give up the underneath throw on purpose. The analysis layer reads `concedesUnderneath` so a nine-yard completion on second and fifteen is not scored as an offensive success |
| 140 | **Both callers advance together at every build step** | Building the offensive caller first and retrofitting defense produces a defense whose job is to lose to it |

## The play model

| # | Decision | Implication |
| --- | --- | --- |
| 141 | **"Play" means the collision** | The word is reserved for what occurred on a down. `PlayID` is retired rather than renamed, so it cannot silently mean two things again ([ADR-0010](adr/0010-plays-designs-and-calls.md)) |
| 142 | **Design, call and play are three levels with three lifetimes** | A `PlayDesign` lives across seasons in a playbook and is editable; a call exists for one snap; a play is permanent history. Different lifetimes is what makes them different types rather than one type viewed three ways |
| 143 | **Both calls are stored by value in the record** | Editing a design in the play designer changes the playbook, never what happened. The same guarantee ADR-0009 makes for gear and appearance, one level down. Measured cost: two bytes *less* per play than the reference it replaced |
| 144 | **A play's identity is derived, not allocated** | `PlayRef` is `(game, index)`, computed. No allocator, so a game replays independently with no counter state to carry, and a link to a play in an unretained game still resolves ([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)) |
| 145 | **Allocated identity for source-of-truth streams; derived for caches over a seed** | The general rule ADR-0011 extracts. The eight world streams keep monotonic sequence numbers; `PlayRecord` is the one stream that is discarded and rebuilt, and it cannot |
| 146 | **There is no global play ordering** | A week's games are concurrent. Ordering is `index` within a game; across games it comes from the schedule |

## Franchises

| # | Decision | Implication |
| --- | --- | --- |
| 147 | **One entity for a team, not a franchise-and-team pair** | A team keeps its `TeamID` through a rename, rebrand or move, so history spans all of them. A second concept would be a second identity for one thing, which is the mistake ADR-0010 and ADR-0011 just removed from plays |
| 148 | **Identity is event-sourced; the stored value is a cache** | `TeamSnapshot.projected(at:from:)` folds from a `founded` event. Watching a game from four seasons ago shows the name and the building of the time, exactly as it shows the gear of the time |
| 149 | **The founding state is an event, not a field outside the log** | It is what makes the fold total — every later state is reachable by replaying from the beginning, so a projection is provably faithful rather than merely plausible. A stream with no founding event projects to nothing rather than to a blank team |
| 150 | **A relocation moves the city and the stadium in one event** | Two events could interleave and put a team in a building it never played in |
| 151 | **A stadium is simulation input; an identity is not** | Roof and climate decide the weather, altitude reaches kicking and fatigue, noise raises the *visiting* offence's pre-snap penalties. Home field advantage is therefore a mechanism, not a bonus |
| 152 | **Colours are checked for contrast at generation** | Two darks on a jersey is a scoreboard nobody can read. `hasReadableContrast` is enforced by a test across twelve seeds, not left to chance |
| 153 | **Divisions are regional, and named for the region they hold** | A "South" division full of cold-weather cities reads as generated on sight. City demand is computed per region from the shape before anything is generated, because an even spread and then dealing leaves regions short |
| 154 | **A name ledger is threaded through generation** | Nicknames, stadium names, abbreviations and city stems are all finite pools whose collisions are invisible per team and obvious in a standings table. Four teams named Saltflat-something passes a uniqueness test on the full name |
| 155 | **The generator validates the league it built** | Demand arithmetic should make a malformed league unreachable. It is checked anyway, so a future change surfaces here rather than as a broken schedule several systems downstream |

## Draft classes

| # | Decision | Implication |
| --- | --- | --- |
| 156 | **Prospects exist three years before their draft, and a prospect is a `Player`** | He keeps the identifier he will carry into the Hall of Fame, so "we have had eyes on him since he was a sophomore" is a query rather than a fiction. No separate prospect type — the same one-entity rule as teams and plays |
| 157 | **Estimates re-seed per college season** | Refines [decision 65](#draft-and-scouting). Within a season, repeating a depth returns the same answer and nothing can be farmed. Across seasons there is genuinely new tape, so a riser can be seen. [Decision 34](#player-development) keeps the real secret: watching converges on current ability, never on ceiling or development trait |
| 158 | **College production carries independent error** | A good player on a bad team looks ordinary; a limited one in the right system looks better than he is. Without independent error, production is ability wearing a hat and there is nothing for a scout to be wrong about. Context does not overturn a twenty-point ability gap — it overturns a close call, which is where scouting happens |
| 159 | **Classes vary strongly, and the variation is mean-reverting** | Some years are loaded, some barren, so "this is the year to trade up" is a real thought. A loaded class makes the next few likelier to be thin, which is what keeps [the conservation law](development.md) intact over fifty seasons. Reversion is spread over a window — reverting on the previous year alone produces an annual alternation nobody would believe |
| 160 | **Character concerns are football-professional only** | Work ethic, coachability, film study, maturity, scheme buy-in. The game invents people; inventing conduct allegations about them buys a more realistic draft broadcast at a price the rest of the design will not pay. Medical is the other half, and it is the one that produces the classic late slide |
| 161 | **A flag's severity and its visibility are independent** | Correlating them would mean a serious problem is always an obvious one, and the slide nobody can explain at the time would stop happening. The interesting tail is the real concern nobody has surfaced |
| 162 | **Underclassmen declare or return** | A projected high pick comes out; a fringe junior goes back and arrives next season as a different prospect with another year of tape. Seniors never had the choice |
| 163 | **A cohort is not a draft class** | A cohort is a year group; a class is who is actually available. Conflating them reported early entrants against the year they would have graduated, leaving the current draft missing its best young players |
| 164 | **Class shape is zero-sum; only overall strength moves the total** | A year can be deep at quarterback and empty at edge while carrying normal total talent. Keeping the two separable is what lets conservation be asserted on one number |
| 165 | **Position is weighted per group and decoupled from talent rank** | Weighting per position inflated whichever groups have more enum cases — five offensive line positions against one quarterback. And assigning positions down the ceiling curve made every class's best players the same positions in the same order, which is not a draft |

## Rivalries

| # | Decision | Implication |
| --- | --- | --- |
| 166 | **Seeded history is a fabricated event log, not a starting number** | The invented past uses the same `RivalryEvent` vocabulary lived history will, so a write-up can cite what happened and M2's growth simply appends. Nothing downstream can tell invented from lived history, because there is no difference |
| 167 | **Intensity is folded with decay, never stored** | A rivalry nobody feeds goes quiet. Without decay it is a running total that only rises, and after twenty seasons every pairing in the league is a blood feud |
| 168 | **Origin sets a floor; history does the rest** | Two teams in a division care a little on principle. Two who met once in January and never again fade back to nothing, which is why the structural floor belongs to structure and not to history |
| 169 | **An earned origin carries the event that earned it** | A `.postseason` rivalry has the January game in its log, or the origin is an assertion with nothing behind it |
| 170 | **A new world tops out at heated** | The seeded past gives texture; the first genuine blood feud should be one the player caused. `bitter` is reachable through lived history, and tested to be, so the band is not dead |
| 171 | **League-wide facts are enforced across the whole set, not per pair** | History invented per pair had three rivalries independently playing in the same championship game. One title game per season, league-wide; the extras become playoff eliminations, which can legitimately happen several times a year |

## The crude engine

| # | Decision | Implication |
| --- | --- | --- |
| 172 | **The play resolver is a seam; the sport's rules are not** | Clock, downs, possession, scoring, penalties and overtime are written once and survive M5. What gets deleted is one resolver ([ADR-0012](adr/0012-play-resolver-seam.md)) |
| 173 | **The crude resolver is matchup-lite, not outcome tables** | Real named matchups without geometry, so `Participation` and `DecisionPoint` carry real data. Empty decision arrays would leave the interrogation layer unbuildable until M5 — the exact risk ADR-0007 exists to remove |
| 174 | **Its decision points must agree with its own outcome** | A fabricated causal chain that looks plausible lets the analysis layer appear to work while reading noise. If it reports pressure at 2.1s and a sack, the sack is by that rusher |
| 175 | **Scaffolding, deleted at M5 — not a permanent fast-sim** | Two resolvers would have to agree forever, and every calibration change would land twice. Unwatched games are already stored as replay tuples and reproduce exactly |
| 176 | **Parametric calibration rows now; emergent ones at M5** | Completion percentage, sack rate and penalties are inputs at this fidelity, so there is no reason not to hit them. The spread of team win totals is emergent and is taken seriously — it is the number the league's credibility rests on |
| 177 | **Every snap credits a real player, with real rotation** | Backs share carries, the defensive line rotates heavily, the offensive line barely at all. Snap counts look real and a backup breaking out is possible. `DepthChart` is FMCore machinery M4 and M5 need anyway, not resolver code |
| 179 | **`Outcome.finalSpot` reports where the ball came to rest** | `yards` is the offence's net, which says nothing once the defence has the ball — an interception returned thirty yards is not "minus thirty" for anybody. Costs nothing: the record's fixed part is still 131 bytes, absorbed by padding |
| 180 | **Advancement clamps a contradiction rather than reinterpreting it** | A gain that reaches the end zone but is not reported as a touchdown produces a legal spot, not a silent score. The contradiction is the resolver's bug to fix, and papering over it would hide exactly the fabricated-causal-chain failure ADR-0012 names |
| 181 | **Accept/decline is certain where it is certain and crude where it is not** | Nobody declines their own score, nobody accepts a flag leaving the other side's score standing, and losing the ball dominates. Third-and-twenty-two against fourth-and-ten is a real expected-points question, and win probability is what answers it ([ADR-0008](adr/0008-win-probability-keystone.md)) — so the proxy is provisional, documented as provisional, and not pinned by tests |
| 178 | **Injury availability in M1; severity in M3** | A player can go down and miss weeks, so M2's news gets the sport's biggest recurring story and "why is my run defense bad" can answer "your nose tackle has been out since week 4" |

## Variance and the tails

| # | Decision | Implication |
| --- | --- | --- |
| 182 | **Per-game form: a rating is a central tendency, not a constant** | Players have good and bad days for reasons no model captures. Drawn once per game from the game's seed and the player's identifier, so a replay shows the same day |
| 183 | **Form exists to correlate a player's plays *within* a game** | Independent per-play randomness concentrates — a game is a sum of a hundred draws and sums of independent draws cluster. Without it, a maximum of three passing touchdowns in four hundred team-games, and never four: **narrower than pure chance**, with records permanently unreachable |
| 184 | **Ordinary variation is modest; the outlier tail is real** | Most days sit within eight rating points, so talent still decides a season. A rare day well outside that is what lets a generational player in the right situation chase a number nobody should reach |
| 185 | **Explosive plays are what give a passing game a tail** | A receiver who beats everyone with an angle on him is in open field, not three yards further on. The run had a burst through the hole and the pass had no equivalent, which is exactly why the run had a tail and the pass had none |
| 186 | **Scheme fit reaches the engine, not just the roster screen** | The resolver never mentioned a scheme, so a player in a system built around him performed exactly as one it wasted. `SchemeFit` was an elaborate no-op. Fit is worth a few points — enough to decide a close matchup, not to overturn talent |
| 188 | **Form, development and traits are three different timescales** | A career, a season, and one Sunday. Confusing them would make a bad day look like decline, or a leap look like luck |
| 189 | **Form is drawn before kickoff and never reacts** | A model that noticed a player was having a good day and made him better would be the engine authoring a narrative. This only admits that the rating was an average all along |
| 190 | **Form is visible after the fact, never before** | The analysis layer can say *he was off all day* from the stream. A performance nobody can account for is what the interrogation hook promises not to produce. Visible beforehand it would be a lineup cheat |
| 191 | **Team form exists, and is driven by causes** | Travel, a short week, a hostile crowd, the game before. A shared draw with no reason behind it is indistinguishable from an excuse — and team-level variance is the direct lever on the spread of team win totals |
| 187 | **A balanced player fits everywhere; an uneven one does not** | Scheme boosts and penalties cancel on a balanced profile. A burner is a vertical receiver and a bad air-raid one; a route technician is the reverse. The design only shows on players with a shape |

## The endgame clock

| # | Decision | Implication |
| --- | --- | --- |
| 192 | **A timeout is not a play and produces no `PlayRecord`** | The next play's situation already carries the counts, so *they burned their last one with a minute forty left* is a query over the stream rather than a new event type |
| 193 | **Both sides are asked for a timeout, every snap** | The defence spends them to get the ball back, which is the half nothing in a football game ever does if you only model the team holding it |
| 194 | **Kneeling is arithmetic against the defence's timeouts** | Three kneels from first down, each burning the play clock, less what the defence can claw back. Kneel a play early and you hand the ball over; run one you did not need to and a won game becomes a fumble |
| 195 | **A spike costs a down, so it is a last resort** | Only when the clock is running and there is no timeout to spend instead. Spiking with timeouts in hand wastes a down; spiking on a stopped clock wastes one for nothing |
| 196 | **Kneels and spikes credit the quarterback** | They are snaps somebody took. Crediting nobody would leave his snap count short and put plays in the stream that happened to no one |

## Penalties in the engine

| # | Decision | Implication |
| --- | --- | --- |
| 197 | **Desperation fouls are drawn at the matchup that beat the man** | Not beside the play — *at* the moment he loses. So the flag and the reason for it are the same event, and a bad offensive line holds more without anybody tuning a holding rate |
| 198 | **Procedural fouls are the only ones that are a roll** | False start, offside, delay, twelve men. Nobody was beaten; somebody broke a rule, and the rule comes from `discipline`, the noise he is working in, and the tempo he is asked to play at |
| 199 | **Crowd noise is asymmetric, or it is weather** | It raises the *visiting* offence's pre-snap fouls and spares the home team. Tested in both directions, because a symmetric effect would be a stadium quirk rather than home field advantage |
| 200 | **Twelve men is a substitution failure, so hurry-up causes it** | Defensive personnel churn against offensive tempo. Which makes hurry-up a weapon rather than a clock tactic: it does not only save time, it catches defences with twelve on the grass |
| 201 | **The penalty model never reads leverage** | A flag is not likelier because it is January. It is exactly as likely as it always was and simply matters more, and the analysis layer surfaces it because the swing in win probability is enormous. Arranging the drama would break the honesty pillar |

## Injuries

| # | Decision | Implication |
| --- | --- | --- |
| 202 | **Injuries are drawn from the play's participants, not inside the resolver** | An injury is about who was involved in contact, not about how the contact was modelled. So it survives the spatial resolver replacing the crude one, at which point real contact severity can feed it instead of the play kind |
| 203 | **An injury is located by the play it happened on** | `PlayRef` names the game, the game names the week. No stamped date to disagree with anything — the same derived-identity rule that governs plays ([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)) |
| 204 | **A knock played through is still an event** | *He was hurt in the third and stayed in* is a real thing to be able to say, and it is the same event as one that ends a season, only smaller |
| 205 | **Availability only in M1; severity in M3** | He is out, and for how many games. Rehabilitation, reaggravation and long-term effects built against a resolver being deleted would be tuned twice |

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
