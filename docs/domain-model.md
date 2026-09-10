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

*Designed, not built:* `League`, `Conference`, `Division`, `Team` and `Rules` exist and
are what `LeagueShape` validates. **`World`, `Calendar` and `FreeAgentPool` do not** —
no `World` type in `FMCore` owns one, there is no calendar (M3) and no free agency (M7).
Generation returns a `WorldGenerator.GeneratedWorld` — seed, season, league, teams,
colleges, draft pipeline and rivalries — which is what a world is until `FMCore` has a
type for one.

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

*Where both come from:* not from the seed. A world's thirty-two clubs are the curated
table in `FMGeneration.FranchiseSet` — identity, market, the city's climate and altitude,
and the building down to its roof, surface, capacity and noise
([decisions 215 and 216](design-decisions.md#world-generation)). A `Franchise` is
generation's shape for that row and never leaves `FMGeneration`; what a world holds is
`Team`. The seed still draws everything a club is *doing* — its scheme, its roster, its
depth chart and the strength it was built at — so two careers are two leagues in the same
buildings. The old pool randomiser is still there behind `FranchiseSource.randomised`, as
a last resort rather than a default.

Plus `MarketSize` and `TeamScheme`, and — still to come — `Roster`, `DepthChart`,
`Contracts`, `CoachingStaff`, `Finances`, `TeamStrategy` (the AI's rebuild-vs-contend
posture), and season record.

*What is on `Team` today:* `id`, `region`, `identity`, `stadium`, `market` and `scheme`,
and nothing else. `DepthChart` is a built type but it does not hang off `Team` — the
engine is handed one per side — and a roster, a staff and a set of contracts exist only
as what generation returns alongside a team.

**League / Conference / Division** — the structure, fixed at world creation
([decision 105](design-decisions.md)). A division holds its members and a team does not
also record its division, because two copies of one fact drift. `LeagueShape` validates
the shape; `League.structureFailures` validates that what was built matches it, which
catches a short or duplicated division that a legal shape would otherwise carry all the
way to a broken schedule.

## Player

**Partly built, and this section runs ahead of the type in three places** — the hidden
attributes, the traits and the state. Identity, physical, position and ratings are built
and are what generation fills.

Split into stable identity, physical profile, ratings, and mutable state.

**Identity** — name, birth season, college, the season he first counted against a roster,
and draft season/round/pick/overall for a drafted player. Immutable after generation.
A drafted player's first season *is* his draft season and the type does not let the two
disagree; an undrafted player carries his own, which is what stops accrued seasons being
guessed from a birthday. `experience(in:)` counts from it and `isRookie(in:)` asks whether
it is this season — true of an undrafted rookie as well as a drafted one.

The season he first counted against a roster is **optional, and `nil` means he has not
arrived**: a college prospect has not been drafted and has not been signed, so there is no
such season, he is not a rookie in any season, and he has accrued nothing. He used to take
the season he was generated in, which made every prospect a rookie in the season his class
became eligible — before he had entered the league
([#67](https://github.com/knissley/football-manager/issues/67)). He gets one when somebody
takes him, which is a decision in `FMSimulation` and not a fact about him.
*Designed, not built:* handedness is not on the type.

Generation gives the league you inherit a past: roughly three quarters of every roster was
drafted, the round coming off the player's ceiling against a league-wide band, and the rest
arrived undrafted (`FMGeneration.DraftHistory`). It is history, not a draft — nothing picks
anybody, and the draft you run is a decision in `FMSimulation`.

**How old that league is.** A man's age is drawn once, at world creation, around a centre
that is his position group's peak for a starter and a few years under it for the men behind
him — but never under `PlayerGenerator.entryAge + 2`, because the spot behind a starter
holds a *developing* player and developing happens in the league. The draw is **truncated,
not clamped**: a value outside 21...38 is redrawn rather than rounded onto the edge, and the
floor is `DraftHistory.youngestEntryAge` rather than a number of its own, since a league
cannot hold a man younger than the youngest age anybody enters it at. Clamping instead put
266 of 1,696 men at seed 7 on exactly twenty-one, all of them rookies by arithmetic, and a
quarter of every roster was in its first season. It is now about a sixth, which is the
sourced band in
[`reference/calibration-sources.md`](reference/calibration-sources.md#bands-the-harness-cannot-measure),
and a generated league's mean age is 26.3 against 26.0–26.3 in the seasons that band came
from.

The mean and the spread land; the *shape* does not. A real week-1 roster peaks at 24 and
falls away to the right, while a mixture of draws around position peaks comes out flatter:
5.4% of a generated league is 21 against 2.3% real, and the 23-to-25 band holds 30.8%
against 39.5%. That matters beyond looks, because nobody in the league can be 21 and not in
his first season, so the fat young end fixes what share of first-season players are 21 —
0.354 generated against 0.143 real — before `DraftHistory.entryAge` is consulted at all.
Both histograms are recorded in
[`reference/calibration-sources.md`](reference/calibration-sources.md#bands-the-harness-cannot-measure);
nothing asserts either yet.

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

A rating a position doesn't use is absent, not zero. `Ratings` is a **flat array indexed
by `RatingKey.rawValue`, plus a two-word presence bitmap** rather than a dictionary: a
lookup is an array read with no hashing, and "absent" is representable. Neither reason is
about the tick loop — `Ratings` is not read there. The engine copies the handful of
values a play needs into flat entity arrays at the snap and reads those; this type is the
domain representation. Raw values are gapped so a new key can be inserted without
renumbering, and a test asserts every key fits the array. Typed accessors mean adding a
rating doesn't touch every player struct.

**Hidden attributes** — `HiddenAttributes` carries `ceiling` (a number, 0–99, not a
band), `developmentTrait` (slow / normal / quick / star), `workEthic` and `durability`.
Generation fills all four and they are never shown.

*Designed, not built:* `personality`, and the scout estimates with error bars that narrow
with investment and playing time — there is no scout. Nothing consumes any of the four
either: progression is M3.

**Traits** — *designed, not built.* `Player.traits` is a `[TraitID]` that generation
never fills and `FMSimulation` never reads, and there is no `Trait` type behind those
identifiers. Everything in this paragraph is the design [traits.md](traits.md) holds, and
most of it wants the spatial engine to be a hook rather than a modifier.

The game's personality layer, and mechanically real. A trait is a named
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

**State** — `status: RosterStatus` (active / inactive / injured reserve / practice squad
/ free agent / retired), and nothing else.

*Designed, not built:* `injury`, `fatigue`, `morale`, `snapCount`, `formGrade` and
`contractID` are none of them fields on `Player`. Two of the six have a home elsewhere
already and should probably stay there: an injury is its own event stream
(`InjuryEvent`), and a snap count is a query over `Participation` rather than a tally on
the player ([ADR-0007](adr/0007-event-stream-contract.md)).

## Contracts and the cap

The cap is the game's main constraint and it has to be right or the whole meta falls
apart. Model it properly rather than as a single salary number.

**Contract** — signing team, years, and per-year `baseSalary`, `rosterBonus` and
likely/not-likely-to-be-earned incentives, plus prorated bonuses and a per-year
`guaranteedSalary`, and the year signed.

**Cap accounting**

- Signing bonus prorates evenly across contract years, capped at 5 years.
- A year's cap hit = base + roster bonus + prorated bonus share + likely-to-be-earned
  incentives.
- Releasing or trading a player accelerates all remaining proration into the current
  year as **dead money**. A post-June-1 designation splits it across two years.
- Team cap space = league cap + carryover − sum of active cap hits − dead money.

**Player movement** — *designed, not built,* with one exception: the franchise tag
figure is real arithmetic today (`SalaryCap.franchiseTagValue`, the greater of the
position's top-five average and 120% of the prior salary). The draft, UFA, RFA with
tenders, the practice squad, waivers with priority order, and trades with pick and cap
validation are M7, and none of them has a type.

Cap math is the highest-value thing to unit test in `FMCore`. It's easy to get subtly
wrong and every wrong answer is player-visible.

## Coaching staff

**Designed, not built.** `Personnel` carries `id`, `name`, `birthSeason`, `role`,
`careerStartSeason` and a hidden `retirementAge`, and nothing else — no ratings, no
scheme preference, no contract. `PersonnelRole` and that ageing lifecycle are the built
parts; the ratings and contract in the paragraphs below are design. And nothing produces
a coach: `PersonnelGenerator` has no caller outside its own tests, so a generated world
contains no staff at all. The engine's two callers are a hardcoded pair of
`PersonnelID`s, identical for every team. Hiring, firing and the carousel are M3.

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

*Designed, not built:* there is no `Gameplan` type. Scheme is built — `TeamScheme`
(an `OffensiveScheme` and a `DefensiveScheme`), `SchemeFit`, and generation's
`SchemeIdentity` — and the resolver reads fit. The gameplan half arrives with the weekly
loop at M4. See [gameplan.md](gameplan.md).

**DepthChart** is an ordered list of `PlayerID` **per position**, best to worst, with a
player allowed to appear at more than one. `RotationProfile` turns that order into snap
shares, `rotation(unavailable:)` drops anyone who cannot play, and
`unmannedPositions(unavailable:)` names any position nobody is left to play.

*Designed, not built:* **keying by package** (base, nickel, dime, goal line, 3-WR,
heavy) and a **validity checker** — every slot filled by an eligible, healthy, active
player, as an enforced `FMCore` invariant. `unmannedPositions` answers a narrower
question and nothing enforces anything. Both arrive with the rekeying at
[M3.5](roadmap.md), where the chart becomes keyed by role and the checker is shared with
the play designer ([ADR-0013](adr/0013-fluid-positions.md)).

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

The ceiling is applied to the invented log, never to the fold, and it **removes the least
history that satisfies it**: the smallest single event that brings the pair under
`bitter` — the cut that leaves it hottest — and never the event that earned an earned
origin. Taking the biggest event instead would land the hottest pairs mid-band, having
removed exactly the memorable year the seeded past is there to give. Clamping the fold
would clamp lived history with it, and the band you are playing towards would be
unreachable. Nothing downstream can tell a capped history from any other, because a
capped history is just a shorter one.

It runs **last**, after the league-wide title-game reconciliation, because that stage is
the one thing that can raise a pair: it demotes every title game after the first claim on
a season, so a pair that loses a title game to the ceiling would free that season and let
the next claimant keep one. Weighting the draw is not a ceiling either — before this
existed, nine of the first sixty worlds opened with a blood feud in them.

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

**Designed, not built.** Nothing here exists: no `AppearanceEvent`, no appearance
generation, no gear and no jersey numbers. `PersonName` and the team's own
`TeamIdentityEvent` are the only pieces of this in the tree. M8.

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

**Designed, not built.** None of these six has an assertion behind it. Two have
something adjacent: `League.structureFailures` checks the league's shape, and
`DepthChart.unmannedPositions` names positions nobody can play — both are queries a
caller may ignore, not enforced invariants. `FMCore` and `FMGeneration` do use
`precondition` thirteen times, every one of them guarding a function's own arguments and
none of them guarding an invariant below. Several of these are about a season that does
not exist yet.

These are the ones that will bite. Each gets a checker in `FMCore` and an assertion
in debug builds:

1. Roster size within league limits at every phase boundary.
2. Depth chart references only players on the roster, and fills every required slot.
3. Team cap space ≥ 0 at the start of the regular season.
4. Every player has at most one active contract; every active contract has a team.
5. Schedule: each team plays the correct number of games, has exactly one bye, and
   division opponents home-and-away.
6. Sum of a game's play-by-play yardage reconciles with the box score.
