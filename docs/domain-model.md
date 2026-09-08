# Domain model

Types described here live in `FMCore` unless noted. All are value types, `Sendable`,
and free of persistence and UI concerns.

Identifiers are typed wrappers over a stable `UInt64` (`PlayerID`, `TeamID`, …)
allocated by a counter in the world, **not** `UUID` — UUIDs are non-deterministic
and banned in the sim (see [architecture](architecture.md#why-fmrandom-is-its-own-module)).

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

**Team** — identity (city, nickname, colors, stadium, market size), `Roster`,
`DepthChart`, `Contracts`, `CoachingStaff`, `Scheme`, `Finances`, `TeamStrategy`
(the AI's rebuild-vs-contend posture), and season record.

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

Three levels, because they have different retention rules:

- **`PlayByPlay`** — every play's full context and outcome. Current season only.
- **`BoxScore`** — per-game, per-player aggregates. Retained for the career.
- **`SeasonStats` / `CareerStats`** — rolled up. Retained forever, drives records,
  awards, and Hall of Fame.

Aggregates are derived from play-by-play at game end, never accumulated in parallel
with it — one source of truth means the box score can't drift from the play log.

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
