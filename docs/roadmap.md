# Roadmap

**Status: designed.** This is the plan, not the tree. A ✅ marks work that is in the
repository today and was checked against `Packages/` and `Tools/` rather than against
another doc; everything unmarked is not built. M0 is done, M1 is nearly done, and
nothing beyond it has started.

Ordered by dependency and by risk, not by calendar. The shape follows one idea: **fix
the event stream contract early, then deepen the engine behind it.** Everything above
the engine — analysis, news, UI — is written once against a contract that doesn't move.

## M0 — Design foundation ✅

Docs, CLAUDE.md, project skills, ADR practice, twenty scoping decisions recorded in
[design-decisions.md](design-decisions.md).

*Exit:* a contributor can read the docs and know what the game is and where code goes.

## M1 — The stream and a living world

`FMCore`, `FMRandom`, `FMGeneration`, and a deliberately crude `FMSimulation`.

- ✅ Typed IDs, positions, ratings; contracts and cap arithmetic.
- ✅ `SplittableRandom` with known-answer tests (`Packages/FMRandom`).
- ✅ **The `PlayRecord` event stream shape** — the most important design work in the
  project (`Packages/FMCore`, specified in [play-record.md](play-record.md)).
- World generation: ✅ names, colleges, players with hidden ceilings and development
  traits, and 53-man rosters with a league talent spread; ✅ franchises — fictional
  cities with regions, nicknames, legible colours, and stadiums whose roof, climate,
  altitude and noise are real simulation input; ✅ draft classes — a three-year college
  pipeline with hidden ceilings, production carrying independent error, red flags, early
  declarations and mean-reverting class strength; ✅ seeded rivalry history — a
  fabricated event log in the same shape lived history will use, folded to intensity with
  decay (`Packages/FMGeneration`).
- ✅ **One world generator** — `WorldGenerator.generate(seed:shape:season:)` in
  `FMGeneration` returns the league, its teams, every roster and depth chart, the
  colleges, the draft pipeline and the rivalries. Team strength is drawn from the seed
  and centred on the league, so a club's quality owes nothing to its position in the
  table. Every tool and every game-building test builds its world with this call.
- ✅ `Tools/worldgen` — inspect any of it from a terminal, no app required.
- ✅ `League`, `Conference`, `Division` assembled to a validated `LeagueShape`, with a
  second validator for a legal shape filled in wrongly.
- ✅ Team identity event-sourced, so a replay shows the name and the building of the
  time rather than the ones a rebrand has since given the team.
- ⚠️ The `GameSimulator` game-state machine — clock, downs, possession, scoring,
  penalties, overtime — written once and shared with M5's spatial resolver
  ([ADR-0012](adr/0012-play-resolver-seam.md)). It exists, it sims a whole game, and a
  baseline caller runs both sides. It does not yet get the football right: regular-season
  overtime is never played, a touchdown on the last play of a half gets no try, the wrong
  team kicks off after a safety, the clock runs through a change of possession, and
  contact fouls are enforced from the wrong spot. Those are the A track of the audit
  backlog (#1) and they are what M1 has left.
- ✅ `DepthChart` with real rotation by position group, so every snap credits a real
  player and backups accumulate genuine statistics (`RotationProfile`, and `Lineup.fill`
  fielding from it).
- ✅ A crude matchup-lite `PlayResolver` emitting real participants and decision points,
  with the internal-consistency constraints from ADR-0012 asserted as tests.
- ✅ Injury availability — a player goes down and misses weeks, and next man up follows
  from the depth chart. Severity stays in M3.
- ✅ `Tools/simharness` running headless and reporting the calibration table.
- ✅ Configurable, validated league shape with 8- and 12-team test presets.
- ✅ `SituationClass` — the shared situational vocabulary both callers, the gameplan
  layer and analysis key off ([play-calling.md](play-calling.md#situational-football)).
- ✅ `DefensiveCall` — the defensive call as composed data, so defense is first-class in
  the model before either caller is written.

*Exit:* ✅ the world generator — `WorldGenerator.generate(seed:shape:season:)`, which the
exit criterion used to call `generateWorld(seed:)` — is reproducible byte-for-byte, pinned
by a whole-world checksum at three seeds in `GoldenWorldTests`. Still owed: a season sims
headless, and the event stream carries everything M2 needs without changes.

*Not met yet.* Generation is reproducible and the stream is in good shape, but a game
does not finish correctly and there is no season to sim — the season loop is M3. The
outstanding work is the audit backlog (#1), and M1 does not close until its A and B
tracks do.

## M2 — Analysis and narrative

`FMAnalysis` and `FMNarrative`. This is where the hook becomes real, and it validates
the contract before the expensive engine work starts.

- **Win probability** — the keystone ([ADR-0008](adr/0008-win-probability-keystone.md)).
- Leverage, player grades, situational splits, team tendencies.
- Causal summaries: why a drive stalled, why a unit is underperforming.
- League news, highlight selection, rivalry intensity that grows from results.

*Exit:* over a simulated season, the highlight reel surfaces genuinely notable plays,
the news reads like a league is happening, and "why is my run defense bad" has an
answer derived entirely from the stream.

## M3 — Season and career

- Schedule generation, standings with correct tiebreakers, playoff seeding and bracket.
- Injuries, fatigue, rest across a season.
- Offseason skeleton: retirements, camp progression.
- Coaching carousel: reputation, firing, AI hiring, applying elsewhere.

*Exit:* a ten-season career runs headless with no invariant violations, and win-total
spread lands in the calibration range.

## M3.5 — Roles, and a lineup you can move players around in

[ADR-0013](adr/0013-fluid-positions.md) decided that a player's personnel position and
his lineup position are different things. Nothing of it is built. It sits here because it
wants the season loop above it — development follows where a player actually played, and
that is a query over a season of `Participation` — and because M4's depth chart screen is
the first thing that cannot be drawn honestly without it.

**It is not a prerequisite for the spatial engine.** M5 can be built against positions as
they are keyed today and rekeyed afterwards; the seam is `Lineup.fill`, not the tick loop.

- **The depth chart is keyed by role, not by position.** Third-down back, nickel corner,
  dime corner. `DepthChart` and `RotationProfile` are both per position today and both
  become per role, which is a breaking change to a type `Lineup.fill` and
  `RosterGenerator` depend on.
- **A lineup legality checker, shared with the play designer.** Seven on the line, five
  ineligible, enforced from the rules of the sport rather than from archetypes. One
  checker, used by the lineup editor and by M6's play validator — building it twice would
  let the two disagree about what a legal formation is.
- **The AI positional-move question**, which ADR-0013 leaves open: a search over players
  against positions is cheap at roster size, but "rates higher somewhere else" is not the
  same as "worth moving", and the answer has to account for what he leaves behind and
  what the scheme needs. Until it is answered the AI clause in that ADR is intent rather
  than a built thing, and the arbitrage it creates is one only the human can work.

**Roles are defined once, with M6's formation vocabulary.** A role is what a formation
asks for; a formation is a set of roles with places to stand. Defining them in two
milestones produces two vocabularies that drift, so the role list lands here and M6's
formats name the same roles rather than inventing their own.

*Exit:* a receiver can be made the second tight end from the depth chart, the lineup that
results is legal by the checker, and an AI team makes a positional move that a human would
recognise as sensible.

## M4 — First playable

App target, `FMUI`, `FMPersistence`. The first build that is a game.

- Team hub, roster, player detail, depth chart, schedule, standings, news feed.
- Watch a game as an event feed with the analysis layer attached.
- Week advance; SwiftData save/load with round-trip tests.

*Exit:* install on a phone, start a career, play a season, background and resume without
loss.

## Audit owed at the end of M1

A designed system can be complete, thoroughly unit-tested, and **entirely unused**, and
nothing in the suite goes red. That is how the crude engine came to consult none of
`SchemeFit`, traits, penalties, `CallVulnerability`, stadium noise or scheme experience
while every one of them had passing tests of its own.

Before M2, sweep the whole codebase for the same failure: a type that exists, is tested,
and is referenced by nothing that runs. The structural fix is **wiring tests** — a suite
that asserts systems are *consulted*, not merely correct — because vigilance is not a
mechanism and this happened once already.

### First pass: the event vocabulary

`FMSimulation`'s `VocabularyCoverageTests` is the first of these. It sims forty games and
checks what came out against the vocabulary that exists, in both directions: a case the
engine cannot yet produce has to be named in a register with the milestone that closes
it, and the moment one *starts* being produced the test fails too, so the register cannot
rot into a list of things that used to be true.

Asking the question once found five things, all of the same shape — a value the type
system knew about that nothing ever wrote:

- **The kicking game had no kickers.** Every roster had carried a kicker, a punter and a
  long snapper since world generation existed, and none had ever been on the field: the
  resolver read `.kickAccuracy` and `.puntPower` off slot 0 and got the *quarterback's*.
  A team's kicker had no bearing on whether it made kicks.
- **The tight end never did anything.** He was placed on the field on every snap and the
  route loop took the first three receivers, so he never ran a route, was never thrown to
  and was never credited.
- **Targets were invisible.** All route runners were credited `.receiver` and the man
  actually thrown to was never distinguished, which makes target share, catch rate and
  drop rate unanswerable from the stream.
- **Every tackle was made by a cornerback.** Pursuit was `coverage.prefix(3)` for every
  kind of play, so a run up the middle was tackled by a corner and a linebacker never
  made a tackle all season.
- **And before that, every run credited four tackles**, to the defensive line, in the
  blocking loop before anyone had touched the ball — which also aimed contact fouls at
  the wrong man.

Three of those were the *same bug*: a more specific credit silently dropped because the
player already had a line on the play. That rule now lives in one place
(`PlayRole.outranks`), which is the actual fix.

Note what this says about the audit's scope. Coverage tests catch a case nothing
produces; they cannot catch a case produced by the *wrong* thing — the four bogus tackles
per run looked perfectly healthy from the outside. Those need an assertion about who the
credits land on, which is why the suite also checks that tackles reach all three levels
of the defence.

## Designed but not yet in the engine

An audit of the crude resolver found it reads `runFit` and the weather on a kick, and
nothing else. These are systems that exist, are designed and in several cases fully
tested, and that the engine has never consulted. Recorded here so they are deferred
deliberately rather than forgotten.

**Landing before M2**, because M2's analysis and narrative are built on this stream and
would otherwise be built against a league missing them:

- ✅ Endgame clock — spikes, kneels and timeouts. The clock rules underneath were already
  correct and tested; the caller has now learned to use them, and both sides call
  timeouts.
- ✅ Penalties. Both classes: procedural fouls from `discipline`, noise and tempo, and
  desperation fouls drawn at the matchup that beat the man committing them. Crowd noise
  is now the home-field mechanism [penalties.md](penalties.md) describes.
- ✅ Injury availability. A player goes down, misses games, and next-man-up follows from
  the depth chart. `InjuryEvent` is its own stream; severity and rehabilitation are M3's.
- ✅ Kick and punt returns. Kickoffs and punts are fielded, returned, fair-caught,
  muffed or downed, and the harness prints the return rates. Returns as pursuit geometry
  are M5.
- ✅ Crowd noise and stadium, through the penalty model.
- ✅ Weather beyond the kicking game. `Conditions` makes the ball harder to hold and
  harder to throw accurately in rain, snow, cold and wind, and the harness checks
  combined points in heavy rain against a dry game.
- Traits, as engine hooks rather than cosmetic modifiers. `Player.traits` is a
  `[TraitID]` that generation never fills and `FMSimulation` never reads, and there is no
  `Trait` type behind those identifiers yet.

**Deferred to M5, and still needed** — these want the spatial engine to be meaningful, not
merely to be wired up:

- `CallVulnerability`. Every defensive call is designed to give something up, and the
  resolver never asks what. Without geometry there is no honest way to make a soft spot
  actually soft.
- `SchemeExperience`. Coordinator familiarity decaying and rebuilding is a season-scale
  mechanic that needs a season loop to mean anything.
- Coordinator quality. Both callers are currently the same hardcoded pair of identifiers,
  so every team in the league calls plays identically. The real caller and its
  benchmark are [play-calling.md](play-calling.md)'s work.
- Stamina and fatigue within a game.

**Landed since this list was written:** personnel groups and defensive packages. The
caller picks an offensive grouping and a defensive package per snap, `Lineup` fields
them, and the harness checks the 11-personnel, nickel and base shares.

## M5 — The spatial engine

The big technical risk, taken once the contract and everything above it are proven.

- Tick loop, field geometry, 22 entities, assignment execution.
- Dropback passing with real pressure, separation, and reads — same events out.
- Run game, special teams, penalties.
- 2D field view rendering engine state directly.
- Replay from `(state, seed, sliders, decisionLog)`, with scrubbing.
- **Performance budget enforced by benchmark**: a season in ~60s.

*Exit:* the spatial engine passes the same golden and statistical tests as the crude
one, hits the budget, and a replayed game is identical to its original.

## M6 — Plays as data

- The play format: formations, assignments, routes, blocking rules, coverages. Formations
  are named in the **role vocabulary defined at M3.5**, not a second set of names, and the
  validator below is the legality checker built there rather than a copy of it. The
  offensive playbook entry — the `PlayDesign` — lands here; it should read like
  `DefensiveCall` already does, and until then `OffensiveCall.design` points at a
  playbook that does not exist.
- Validation — eleven players, legal formation, executable assignments.
- The premade concept library, authored in the format.
- The play designer.

*Exit:* a play drawn in the designer runs in a game, and its results are indistinguishable
in kind from an authored concept.

## M7 — The GM half

- Contracts: extensions, restructures, cuts with dead-money preview.
- Salary cap enforcement everywhere.
- Free agency with AI bidding; real negotiation with agent reservation values.
- Draft: scouting with genuine fog, a draft board, AI teams that pick sensibly.
- Trades with a valuation model that can refuse, and can beat you.

*Exit:* three AI-only offseasons produce cap-legal rosters, teams that draft well get
better, and a human tester cannot reliably fleece the trade AI.

## M8 — Texture

- Traits with real engine hooks, good and bad, with personality.
- Development: role, playing time, mentorship as nudges.
- Awards, records, league leaders, Hall of Fame ceremonies.
- Draft storylines, random league events, franchise history.
- Sliders UI.

*Exit:* a ten-season career review reads like a history worth screenshotting.

## M9 — Polish and beta

Onboarding, VoiceOver and Dynamic Type, haptics, performance pass, save-size audit,
TestFlight.

## Why this order

- **The contract comes before the engine** so nothing above it gets rewritten.
- **Analysis before the spatial engine** proves the hook is achievable and makes the
  crude engine's output immediately interesting.
- **A playable app at M4**, before the hardest work, so there's something to react to.
- **The spatial engine at M5** is the biggest risk; by then it's the only unknown left
  and it slots in behind a proven contract.
- **The GM half after the engine** because the engine is the hook and the thing that
  makes roster decisions legible.

## Deferred

Online leagues, iPad and Mac layouts, custom league import, 3D visualization.
