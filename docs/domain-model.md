# Domain model

**Status: partly built, sections marked.** Most of the world-and-league, player,
contract, scheme, play and rivalry types exist in `FMCore` today and are exercised by
`FMGeneration` and `FMSimulation`. The season calendar, statistics, development and the
coaching carousel are types that do not exist yet; those sections carry a
`Designed, not built` label.

Types described here live in `FMCore` unless noted. All are value types, `Sendable`,
and free of persistence and UI concerns.

Identifiers are typed wrappers over a stable `UInt64` (`PlayerID`, `TeamID`, …)
allocated by a counter in the world, **not** `UUID` — UUIDs are non-deterministic and
banned in the sim ([ADR-0003](adr/0003-deterministic-seeded-simulation.md)).


> **Positions are not fixed.** A player has a *personnel position* — what he is paid and
> traded as — and a *lineup position*, which is where he plays and which decides how he
> performs. Overall is position-relative: "a 99 receiver" means 99 as a receiver. See
> [ADR-0013](adr/0013-fluid-positions.md).

## World and league structure

```
World
 └── League
      ├── Conference ×2
      │    └── Division ×4
      │         └── Team ×4          (32 teams total)
      ├── Calendar                   (current season, phase, week)
      ├── Rules                      (cap number, roster limits, playoff format)
      └── FreeAgentPool
```

Structure is data, not hardcoded. A generated world *defaults* to 32 teams in two
conferences of four divisions, but the generator takes it as configuration so we can
test smaller leagues quickly.

**Team** — the enduring entity. It keeps its `TeamID` through a rename, a rebrand or a
move, so franchise history spans all of them; there is deliberately no separate
"franchise" concept, for the same reason a play has one identifier and not two
([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)).

It splits along one line that matters:

- **`TeamIdentity`** — city, nickname, abbreviation, colours. Editable at any time
  ([decision 106](design-decisions.md)) precisely *because* none of it reaches the
  simulation. It is a cached projection over `TeamIdentityEvent`; the stream is the
  truth, and `TeamSnapshot.projected(at:from:)` gives the identity of any past season.
- **`Stadium`** — name, capacity, roof, surface, climate, altitude, noise. This *is*
  simulation input: roof and climate decide the weather, altitude reaches kicking and
  fatigue, and noise is the mechanism behind home field advantage rather than a bonus
  applied on top of one ([penalties.md](penalties.md)).

Plus `MarketSize`, `Scheme`, and — still to come — `Roster`, `DepthChart`, `Contracts`,
`CoachingStaff`, `Finances`, `TeamStrategy` (the AI's rebuild-vs-contend posture), and
season record.

**League / Conference / Division** — the structure, fixed at world creation
([decision 105](design-decisions.md)). A division holds its members and a team does not
also record its division, because two copies of one fact drift. `LeagueShape` validates
the shape; `League.structureFailures` validates that what was built matches it, which
catches a short or duplicated division that a legal shape would otherwise carry all the
way to a broken schedule.

## Player

Split into stable identity, physical profile, ratings, and mutable state.

**Identity** — name, birth date, college, draft year/round/pick, years of experience,
handedness. Immutable after generation.

**Physical** — height, weight, and the athletic testing numbers a scout would see:
40-yard dash, vertical, broad jump, three-cone, bench. Generated correlated with
position and with the speed/strength ratings, so the combine tells you something
real but not everything.

**Position** — a primary `Position` plus a set of positions the player can fill:

```
Offense:  QB RB FB WR TE LT LG C RG RT
Defense:  EDGE DT LB CB S
Special:  K P LS
```

`EDGE` covers 4-3 DE and 3-4 OLB; whether a given EDGE fits your front is a scheme
fit question, not a separate position. Same idea for `S` (free/strong is usage) and
`LB` (off-ball).

**Ratings** — 0–99, the genre convention, because it's legible. Two tiers:

*General* (every player has them): awareness, speed, acceleration, agility, strength,
stamina, toughness, injuryResistance, discipline.

*Positional* (only the ones the position uses): throwPower, throwAccuracyShort/Medium/
Deep, underPressure, playAction; carrying, vision, breakTackle, elusiveness; catching,
catchInTraffic, routeRunning, releaseVsPress; runBlock, passBlock, blockAnchor,
handTechnique; powerMove, finesseMove, blockShedding, pursuit, tackling, hitPower;
manCoverage, zoneCoverage, ballHawk; kickPower, kickAccuracy, puntPower, puntAccuracy.

A rating a position doesn't use is absent, not zero. `Ratings` is a dictionary keyed
by a `RatingKey` enum with typed accessors, so adding a rating doesn't touch every
player struct.

**Hidden attributes** — `potential` (a ceiling band, not a number), `developmentTrait`
(slow / normal / quick / star), `workEthic`, `durabilityProfile`, `personality`.
These drive progression and are never shown directly; the UI shows scout estimates
with error bars that narrow with scouting investment and playing time.

**Traits** — the game's personality layer, and mechanically real. A trait is a named
hook into play resolution, not a stat modifier: *swim master* selects a different
pass-rush move with different timing, *sticky hands* widens an actual catch radius,
*choker* and *clutch* shift performance in high-leverage situations (leverage is
measured by [win probability](architecture.md#win-probability-is-shared-infrastructure),
so "high-leverage" is a computed fact, not a guess). Bad traits are as important as
good ones — *butter fingers* is a real fumble-rate hook and a real personality.

Clutch is genuinely mechanical in this world: a hidden attribute that measurably
changes high-leverage performance, not a media narrative.

Traits are why the spatial engine pays for itself in flavor. They are only possible as
engine hooks because the engine simulates the moment the trait describes.

**State** — `injury` (type, severity, weeks remaining, lingering effect), `fatigue`,
`morale`, `snapCount`, `formGrade` (recent performance, decays), `contractID`,
`rosterStatus` (active / inactive / injured reserve / practice squad / free agent).

## Contracts and the cap

The cap is the game's main constraint and it has to be right or the whole meta falls
apart. Model it properly rather than as a single salary number.

**Contract** — signing team, years, and per-year `base salary`, `roster bonus`, and
`incentives`, plus a `signingBonus` paid up front, `guarantees` per year, and the
year signed.

**Cap accounting**

- Signing bonus prorates evenly across contract years, capped at 5 years.
- A year's cap hit = base + roster bonus + prorated bonus share + likely-to-be-earned
  incentives.
- Releasing or trading a player accelerates all remaining proration into the current
  year as **dead money**. A post-June-1 designation splits it across two years.
- Team cap space = league cap + carryover − sum of active cap hits − dead money.

**Player movement** — draft, UFA, RFA with tenders, franchise tag (one per team per
year, at the position's top-5 average), practice squad, waivers with priority order,
trades with pick and cap validation.

Cap math is the highest-value thing to unit test in `FMCore`. It's easy to get subtly
wrong and every wrong answer is player-visible.

## Coaching staff

**Partly built.** `PersonnelRole`, the ratings and the ageing lifecycle exist in `FMCore`
and generation fills a staff. Nothing reads a coach: the engine's callers are the same
hardcoded pair for every team, and hiring, firing and the carousel are M3.


Head coach, offensive coordinator, defensive coordinator, special teams coordinator,
position coaches, scouts, trainers.

Each has `scheme` preferences, `ratings` (playCalling, development, motivation,
evaluation), and a `contract`. Coaches matter through three channels: scheme fit
modifiers in the sim, player progression rates, and in-game decision quality (when
to go for it, clock management).

## Scheme and gameplan

**Scheme** is a season-level identity — offensive family (e.g. spread, west coast,
power run, air raid) and defensive front/coverage shell tendencies. It determines
which ratings matter for scheme fit and what the roster *should* look like.

**Gameplan** is per-opponent, set weekly: run/pass balance, tempo, aggression on
fourth down, blitz rate, coverage shell mix, targets to attack, and matchups to
avoid. This is the main weekly decision surface.

**DepthChart** maps each position and package (base, nickel, dime, goal line,
3-WR, heavy) to an ordered list of `PlayerID`. Validity — every slot filled by an
eligible, healthy, active player — is a `FMCore` invariant with a checker, because
an invalid depth chart is the most likely source of sim crashes.

## Season calendar

**Designed, not built.** M3. There is no schedule, no week, no phase and no calendar
type; a game today is an arbitrary matchup with no season around it.


The phase machine that drives everything. Advancing is always "advance to next phase
or week," never an arbitrary date jump.

```
Preseason ─→ RegularSeason (18 weeks, 1 bye per team)
   ↑              │
   │              ▼
   │        Playoffs (7 seeds per conference, top seed byes) ─→ Championship
   │              │
   │              ▼
   │        Offseason
   │          ├── ExitInterviews & retirements
   │          ├── ContractDecisions (cuts, restructures, tags)
   │          ├── FreeAgency (multi-day bidding)
   │          ├── Combine & scouting
   │          ├── Draft (7 rounds)
   │          ├── UDFA signings
   │          └── TrainingCamp (progression resolves here)
   └──────────────┘
```

## Statistics

**Designed, not built.** M2. Statistics are a query over the stream and nothing performs
that query yet — the harness computes its own aggregates and is the only reader.


Three levels, because they have different retention rules:

- **`PlayRecord` stream** — every play's situation, both calls, engine decision points,
  and outcome. Retained in full for your games in the current season. A play is
  addressed by `PlayRef`, derived from `(game, index)` rather than allocated, so a
  reference survives the game being replayed instead of stored
  ([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)).
- **Replay tuple** — `(initialState, seed, sliderConfig, decisionLog)` for every other
  game. Re-simulates identically on demand, so any game in league history can be
  watched without having been stored.
- **`BoxScore`** — per-game, per-player aggregates. Retained for the career.
- **`SeasonStats` / `CareerStats`** — rolled up. Retained forever; records, awards, and
  the Hall of Fame depend on them.

Aggregates are derived from the event stream, never accumulated in parallel with it
([ADR-0007](adr/0007-event-stream-contract.md)) — one source of truth means the box
score can't drift from the play log.

## Plays

**Partly built.** `OffensiveCall` and `DefensiveCall` exist as composed data and the
engine calls with them. `PlayDesign` and the playbook they point at are M6.


A `Play` is data the engine executes and the designer edits: a formation, personnel,
and a per-player `Assignment` — a route with landmarks and timing, a blocking rule, or
a coverage responsibility.

Because plays are data, they need validation before reaching the engine: eleven
players, a legal formation, and every assignment executable. The premade concept
library is authored in the same format the designer writes, so there is no distinction
between a shipped play and one you drew.

## Rivalries

`Rivalry` holds an unordered `TeamPair`, the `RivalryOrigin` that started it, and the
history of what has happened since. Intensity is **not stored** — it is folded from that
history with decay, so a rivalry nobody feeds goes quiet. Without decay, intensity is a
running total that only rises, and after twenty seasons every pairing in the league is a
blood feud.

**Seeded history is a fabricated event log, not a starting number.** A new world's
invented past uses the same `RivalryEvent` vocabulary that lived history will: a playoff
elimination in 2026, a coach who crossed the divide in 2028. That is what lets a pre-game
write-up *cite* the history rather than report an intensity nobody can account for, and
it means M2's growth simply appends — nothing downstream can tell invented history from
lived history, because there is no difference. The same canonical-representation pattern
as gameplan rule sets, officiating profiles and composable schemes.

Divisional pairs are rivalries by construction. Everything else is earned, and its origin
carries the event that earned it — a `.postseason` rivalry has the January game in its
log, or the origin is an assertion with nothing behind it.

A brand-new world tops out at **heated**, deliberately. The seeded past gives texture;
the first genuine blood feud should be one you caused. `bitter` is reachable in a few
seasons of real events, and tested to be.

Intensity feeds the news voice, pre-game buildup, and drama detection. Nobody else's
league has your grudges.

## Career and the carousel

**Designed, not built.** M3.


The player is a `CareerProfile`, not a team. It holds employment history, a record, and
a `reputation` that AI owners read when hiring.

- Owners have expectations; falling short repeatedly gets you fired.
- Open jobs appear each offseason; you apply and compete with AI candidates.
- A rebuild is a gamble with your own job, which is the point.

This means the save's root is a career, and the league outlives your tenure at any one
team.

## Development

**Designed, not built.** Generation writes a hidden ceiling and a `DevelopmentTrait`;
nothing grows or declines. See [development.md](development.md).


Player development is player-driven and you nudge it
([decision 21](design-decisions.md#development-and-progression)). Traits, personality,
and `developmentTrait` do the work; your levers are indirect:

- **Role** — starter, rotational, situational
- **Playing time** — snaps are the main driver of growth for young players
- **Mentorship** — pairing a young player with a veteran of the same position

Progression resolves at training camp. How much authorship this actually delivers is
[an open question](design-decisions.md#open-questions).

## Appearance and identity

Cosmetic, editable, and outside the simulation entirely — the engine never reads it, and
it is not part of the replay tuple.

Appearance is **generated correlated with physicals** (a 340lb nose tackle and a 180lb
slot receiver don't roll from the same distribution), and edits are `AppearanceEvent`s
layered over that baseline rather than mutations of it. Two properties follow: a seed
still reproduces a world, and any historical view reconstructs the player as he looked
*then* — the 2029 replay shows the visor he wore in 2029, not the one you gave him last
week ([ADR-0009](adr/0009-event-sourcing-by-default.md)).

Name changes, gear, and jersey numbers are all the same kind of event.

## Invariants worth enforcing in code

These are the ones that will bite. Each gets a checker in `FMCore` and an assertion
in debug builds:

1. Roster size within league limits at every phase boundary.
2. Depth chart references only players on the roster, and fills every required slot.
3. Team cap space ≥ 0 at the start of the regular season.
4. Every player has at most one active contract; every active contract has a team.
5. Schedule: each team plays the correct number of games, has exactly one bye, and
   division opponents home-and-away.
6. Sum of a game's play-by-play yardage reconciles with the box score.
