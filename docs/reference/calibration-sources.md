# Where the calibration numbers came from

**Status: built.** Every row below exists in
`Tools/simharness/Sources/simharness/Targets.swift` today, and
`InvariantsTraceabilityTests` fails if one named here does not. The exception is the
section on [bands the harness cannot measure](#bands-the-harness-cannot-measure): those are
not rows and have no verdict in a harness run, so each names the `test:` that checks it
instead.

This is the external truth for the *rates*, the way
[`playing-rules.md`](playing-rules.md) is the external truth for the rules. CLAUDE.md's
rule 10 says a claim about a rate cites a real-league season and the source the number came
from: this file is where an agent checks that instead of remembering a figure. The harness
printed eighteen ties in four hundred games on every run for a week and nobody had written
down that the real number is two.

## What is here and what is not

**Hand-entered aggregates only.** No data set is checked into this repository. Each band is
a pair of numbers typed into `Targets.swift`, and this file records the season it describes
and the source it was computed from. Nothing about a real player, team or league is stored
beyond that ([ADR-0005](../adr/0005-generated-fictional-content.md)).

**The bands themselves are not repeated here.** They live in `Targets.swift`, the table in
[`../match-engine.md#calibration`](../match-engine.md#calibration) is generated from that
array by `simharness --targets-markdown`, and a test in the simharness package fails if the
two disagree. A third hand-kept copy would be a third thing to keep true, and a retune moves
every band while leaving every season and source exactly where it was. So: season and source
per row here, band in the generated table.

## The sources

| Key | What it is | What it covers |
| --- | --- | --- |
| **S1** | nflverse play-by-play data, built from the league's official play-by-play feed | every regular-season play; the per-play, per-drive and per-game rows |
| **S2** | nflverse participation data from Next Gen Stats | personnel groupings, box counts and pressure |
| **S3** | nflverse weekly roster data — one row per man per club per week | who is on a roster and how long he has been in the league; the generated world's own shape, not a game's |

Every sourced band was computed by `scripts/calibration-sources.py`, which prints each
row's value in every season alongside the band the policy produces. **If a number in
`Targets.swift` cannot be reproduced by the script, the script wins.** Regular-season games
only, sliders at default. S3 is derived by the same script under `--rosters`, and what it
bands is a *world* rather than a game — see [below](#bands-the-harness-cannot-measure).

## The band policy

Stated once, in the script's header, and repeated here only in summary: a row's band spans
the sourced seasons' values, widened on each side by the larger of 5% of the mean and twice
the standard error of a 400-game harness run, the error measured by resampling whole games.
Rare events — ties, return touchdowns — get the width their rarity demands.

Per-play and per-drive rates come from **2023 and 2024**. A row that depends on a rule the
2025 rulebook changed is sourced from **2025 alone**, and its 2024 variant is kept beside it
so `simharness --rulebook 2024` can check the mechanism against the season it was played in.

## When a season is the wrong season

A band measured under one rulebook can be wrong under another, so each row declares the
rule areas it depends on — the kickoff, the onside kick, overtime, pass interference, the
try — and the harness prints, at startup, every row sourced under rules the run is not
playing. **A stale row is never `ok`.** Until D1 ([#41](https://github.com/knissley/football-manager/issues/41))
lands, `Rules.standard` still carries 2024 kickoff values while the target rulebook is 2025,
so the default run lists the 2024-sourced kickoff rows as stale by design; D2
([#46](https://github.com/knissley/football-manager/issues/46)) is what makes the 2025 rows
land.

## The rows

Season is the real-league season the band describes; source is the key above. A row marked
`unsourced` has no band anybody has cited, prints as such, and is never `ok`.

### The passing and running game, per team per game

| Row | Season | Source |
| --- | --- | --- |
| `row:points` — points | 2023-24 | S1 |
| `row:passingYards` — passing yards | 2023-24 | S1 |
| `row:rushingYards` — rushing yards | 2023-24 | S1 |
| `row:yardsPerCarry` — yards per carry | 2023-24 | S1 |
| `row:completionPercentage` — completion percentage | 2023-24 | S1 |
| `row:sackRate` — sack rate per dropback | 2023-24 | S1 |
| `row:interceptionRate` — interception rate | 2023-24 | S1 |
| `row:thirdDownConversion` — third down conversion | 2023-24 | S1 |
| `row:playsFromScrimmage` — plays from scrimmage | 2023-24 | S1 |
| `row:penaltiesPerGame` — penalties (both teams) | 2023-24 | S1 |
| `row:thirdDownDistance` — average third down distance | 2023-24 | S1 |
| `row:firstDownGain` — yards gained on first down | 2023-24 | S1 |
| `row:yardsPerAttempt` — yards per pass attempt | 2023-24 | S1 |
| `row:yardsPerPlay` — yards per play | 2023-24 | S1 |
| `row:yardsPerCompletion` — yards per completion | 2023-24 | S1 |

### The shape of the stream

| Row | Season | Source |
| --- | --- | --- |
| `row:playsPerGame` — plays per game | 2023-24 | S1 |
| `row:tiesPerGame` — ties per game | 2025 | S1 |
| `row:overtimeRate` — games reaching overtime | 2025 | S1 |
| `row:overtimeLength` — seconds played per overtime | 2025 | S1 |

### Injuries

| Row | Season | Source |
| --- | --- | --- |
| `row:playerGamesLost` — player-games lost per season | unsourced | — |

### The endgame

| Row | Season | Source |
| --- | --- | --- |
| `row:scramblesPerGame` — scrambles per game | 2023-24 | S1 |
| `row:kneelsPerGame` — kneels per game | 2023-24 | S1 |
| `row:spikesPerGame` — spikes per game | 2023-24 | S1 |
| `row:timeoutsPerGame` — timeouts spent per game | 2023-24 | S1 |

### The season, which the harness cannot play until M3

| Row | Season | Source |
| --- | --- | --- |
| `row:winTotalSigma` — spread of team win totals (σ) | 2023-24 | S1 |

### Where the points come from

| Row | Season | Source |
| --- | --- | --- |
| `row:pointsFromTouchdowns` — share of points from touchdowns | 2023-24 | S1 |
| `row:pointsFromFieldGoals` — share of points from field goals | 2023-24 | S1 |

### Who is on the field

| Row | Season | Source |
| --- | --- | --- |
| `row:personnel11` — snaps in 11 personnel | 2023-24 | S2 |
| `row:packageNickel` — snaps against nickel | 2023-24 | S2 |
| `row:packageBase` — snaps against base | 2023-24 | S2 |
| `row:ypcEvenCount` — yards per carry, even count | 2023-24 | S2 |
| `row:ypcOutnumberedByOne` — yards per carry, outnumbered by one | 2023-24 | S2 |

### Who took the snap

Player-snaps per team-game on plays from scrimmage, by the roster position group of each
man on the field. The source's participation feed lists every man on every play by his
roster position; the engine counts the roster position of each man `PlayRecord.onField`
names, so the two measure the same thing. The defence's front is one group because the
feed writes a four-man front's edge rushers as DE and a three-man front's as OLB, and a
line and a linebacker corps would be split by scheme rather than by job. Plays the feed
has no row for still had twenty-two men on them, so the per-snap count over the plays it
covers is scaled to the plays from scrimmage a team runs.

| Row | Season | Source |
| --- | --- | --- |
| `row:snaps.quarterback` — quarterback player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.backfield` — backfield player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.receiver` — receiver player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.tightEnd` — tight end player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.offensiveLine` — offensive line player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.frontSeven` — front seven player-snaps per team-game | 2023-24 | S2 |
| `row:snaps.defensiveBack` — defensive back player-snaps per team-game | 2023-24 | S2 |

Per snap, that is one quarterback and five linemen, 1.1 backs, 1.3 tight ends and 2.6
receivers on offence, and 6.1 in the front seven against 4.9 defensive backs — which is the
personnel rows above said another way, and the check on the record is that the count
comes out of `onField` rather than out of the substitution the engine made.

### The shape of a carry

| Row | Season | Source |
| --- | --- | --- |
| `row:carriesStuffed` — carries stuffed (0 or fewer) | 2023-24 | S1 |
| `row:carries2orFewer` — carries of 2 or fewer | 2023-24 | S1 |
| `row:carries10plus` — carries of 10 or more | 2023-24 | S1 |
| `row:carries20plus` — carries of 20 or more | 2023-24 | S1 |

### The shape of a dropback

| Row | Season | Source |
| --- | --- | --- |
| `row:dropbackLoss` — dropbacks losing yards | 2023-24 | S1 |
| `row:dropbackNoGain` — dropbacks with no gain | 2023-24 | S1 |
| `row:dropback10plus` — dropbacks of 10 or more | 2023-24 | S1 |
| `row:dropback20plus` — dropbacks of 20 or more | 2023-24 | S1 |
| `row:dropback40plus` — dropbacks of 40 or more | 2023-24 | S1 |
| `row:pressureRate` — pressure rate per dropback | 2023-24 | S2 |
| `row:completionsZeroOrFewer` — completions for 0 or fewer yards | 2023-24 | S1 |

### How drives end

| Row | Season | Source |
| --- | --- | --- |
| `row:driveEndPunt` — drives ending in a punt | 2023-24 | S1 |
| `row:driveEndTouchdown` — drives ending in a touchdown | 2023-24 | S1 |
| `row:driveEndDowns` — drives ending on downs | 2023-24 | S1 |
| `row:drivesPerTeamGame` — drives per team-game | 2023-24 | S1 |
| `row:playsPerDrive` — plays per drive | 2023-24 | S1 |
| `row:firstDownsPerTeamGame` — first downs per team-game | 2023-24 | S1 |
| `row:drives3orFewer` — drives of 3 plays or fewer | 2023-24 | S1 |
| `row:drives4to7` — drives of 4 to 7 | 2023-24 | S1 |
| `row:drives8plus` — drives of 8 or more | 2023-24 | S1 |
| `row:threeAndOut` — three and out | 2023-24 | S1 |
| `row:redZoneTouchdownRate` — red zone touchdown rate | 2023-24 | S1 |

### Field position, which follows from the kickoff and so has a variant per rulebook

| Row | Season | Source |
| --- | --- | --- |
| `row:averageStart.2025` — average start (own yard) | 2025 | S1 |
| `row:averageStart.2024` — average start (own yard) | 2024 | S1 |
| `row:ownHalfStarts.2025` — drives starting in own half | 2025 | S1 |
| `row:ownHalfStarts.2024` — drives starting in own half | 2024 | S1 |
| `row:puntsPerTeamGame` — punts per team-game | 2023-24 | S1 |
| `row:netPunt` — net punt (yards) | 2023-24 | S1 |
| `row:grossPunt` — gross punt (yards) | 2023-24 | S1 |
| `row:puntReturnYards` — yards per punt return | 2023-24 | S1 |
| `row:twoPointTries` — two-point tries per team-game | 2023-24 | S1 |
| `row:twoPointConversion` — two-point conversion rate | 2023-24 | S1 |

### Kicking

| Row | Season | Source |
| --- | --- | --- |
| `row:kickoffTouchbacks.2025` — kickoff touchbacks | 2025 | S1 |
| `row:kickoffTouchbacks.2024` — kickoff touchbacks | 2024 | S1 |
| `row:fieldGoalsPerTeamGame` — field goals per team-game | 2023-24 | S1 |
| `row:fieldGoalsUnder30` — field goals made, under 30 | 2023-24 | S1 |
| `row:fieldGoals30to39` — field goals made, 30-39 | 2023-24 | S1 |
| `row:fieldGoals40to49` — field goals made, 40-49 | 2023-24 | S1 |
| `row:fieldGoals50plus` — field goals made, 50+ | 2023-24 | S1 |
| `row:fieldGoalAttemptsUnder30` — attempts under 30, share | 2023-24 | S1 |
| `row:fieldGoalAttempts30to39` — attempts 30-39, share | 2023-24 | S1 |
| `row:fieldGoalAttempts40to49` — attempts 40-49, share | 2023-24 | S1 |
| `row:fieldGoalAttempts50plus` — attempts 50+, share | 2023-24 | S1 |
| `row:extraPointsMade` — extra points made | 2023-24 | S1 |

### Fourth down

| Row | Season | Source |
| --- | --- | --- |
| `row:fourthDownPunted` — fourth downs punted | 2023-24 | S1 |
| `row:fourthDownKicked` — fourth downs kicked | 2023-24 | S1 |
| `row:fourthDownWentForIt` — fourth downs gone for | 2023-24 | S1 |
| `row:fourthDownAttempts` — fourth down attempts per team-game | 2023-24 | S1 |
| `row:fourthDownConversion` — fourth down conversion rate | 2023-24 | S1 |
| `row:fourthAndOneWentForIt` — 4th and 1: went for it | 2023-24 | S1 |

### Turnovers and the return game

| Row | Season | Source |
| --- | --- | --- |
| `row:fumblesLost` — fumbles lost per team-game | 2023-24 | S1 |
| `row:fumblesKept` — fumbles kept per team-game | 2023-24 | S1 |
| `row:turnovers` — turnovers per team-game | 2023-24 | S1 |
| `row:nonOffensiveTouchdowns.2025` — touchdowns not by the offence | 2025 | S1 |
| `row:nonOffensiveTouchdowns.2024` — touchdowns not by the offence | 2024 | S1 |
| `row:defensiveReturnTouchdowns` — interception and fumble return TDs | 2023-24 | S1 |
| `row:kickReturnTouchdowns.2025` — kickoff and punt return TDs | 2025 | S1 |
| `row:kickReturnTouchdowns.2024` — kickoff and punt return TDs | 2024 | S1 |
| `row:onsideKicks.2025` — onside kicks per game | 2025 | S1 |
| `row:onsideKicks.2024` — onside kicks per game | 2024 | S1 |
| `row:onsideRecovery.2025` — onside kicks recovered | 2025 | S1 |
| `row:onsideRecovery.2024` — onside kicks recovered | 2024 | S1 |
| `row:kickoffsReturned.2025` — kickoffs returned | 2025 | S1 |
| `row:kickoffsReturned.2024` — kickoffs returned | 2024 | S1 |
| `row:kickoffReturnYards.2025` — yards per kickoff return | 2025 | S1 |
| `row:kickoffReturnYards.2024` — yards per kickoff return | 2024 | S1 |
| `row:puntsReturned` — punts returned | 2023-24 | S1 |

### Backed up

| Row | Season | Source |
| --- | --- | --- |
| `row:snapsInsideOwn10` — snaps inside own 10 | 2023-24 | S1 |
| `row:safeties` — safeties per team-game | 2023-24 | S1 |

### Home field and weather

| Row | Season | Source |
| --- | --- | --- |
| `row:preSnapRoadVsHome` — pre-snap fouls, road vs home | 2023-24 | S1 |
| `row:heavyRainPoints` — combined points, heavy rain vs dry | unsourced | — |

### Scoreboard

| Row | Season | Source |
| --- | --- | --- |
| `row:gamesWithin3` — games within 3 | 2023-24 | S1 |
| `row:gamesWithin7` — games within 7 | 2023-24 | S1 |

### The ten most common accepted fouls, per game, both teams

| Row | Season | Source |
| --- | --- | --- |
| `row:penalty.offensiveHolding` — offensive holding per game | 2023-24 | S1 |
| `row:penalty.falseStart` — false start per game | 2023-24 | S1 |
| `row:penalty.defensivePassInterference` — defensive pass interference per game | 2023-24 | S1 |
| `row:penalty.defensiveHolding` — defensive holding per game | 2023-24 | S1 |
| `row:penalty.unnecessaryRoughness` — unnecessary roughness per game | 2023-24 | S1 |
| `row:penalty.delayOfGame` — delay of game per game | 2023-24 | S1 |
| `row:penalty.offside` — defensive offside per game | 2023-24 | S1 |
| `row:penalty.illegalFormation` — illegal formation per game | 2023-24 | S1 |
| `row:penalty.roughingThePasser` — roughing the passer per game | 2023-24 | S1 |
| `row:penalty.neutralZoneInfraction` — neutral zone infraction per game | 2023-24 | S1 |

## The figures stated in words

A band is a pair of numbers and says nothing about how thin the sample under it was. These
are the counts and rates `Targets.swift` states in prose beside a band, kept here so a
reader can see what a band is standing on. Every one of them is in the tree already; none
was computed for this file.

| Figure | Season | Row |
| --- | --- | --- |
| One tie in 272 games | 2025 | `row:tiesPerGame` |
| Fourteen of 272 games reached overtime | 2025 | `row:overtimeRate` |
| About 345 seconds of overtime played per period, before both teams possessed | 2023-24 | `row:overtimeLength` |
| Completion rate counting only completions that gained: 61.1–62.4 | 2023-24 | `row:completionPercentage` |
| Yards per play, the league's net definition: 5.5–5.7 | 2023-24 | `row:yardsPerPlay` |
| First downs per team-game including penalty first downs: 17.8–18.3 | 2023-24 | `row:firstDownsPerTeamGame` |
| Yards per carry by defenders actually in the box: 4.5–4.7 | 2023-24 | `row:ypcEvenCount` |
| Even against outnumbered, the sport's own gap: 4.3–4.6 against 4.5–4.7 | 2023-24 | `row:ypcOutnumberedByOne` |
| Fourth downs gone for, rising: 23.3% | 2025 | `row:fourthDownWentForIt` |
| Fourth and one, went for it, rising: 76.3% | 2025 | `row:fourthAndOneWentForIt` |
| Two-point conversion swung from 55% to 41% on about 130 tries a season | 2023-24 | `row:twoPointConversion` |
| Illegal formation was called about twice as often in 2024 as in 2023 | 2023-24 | `row:penalty.illegalFormation` |
| Twenty-one kick return touchdowns, against fourteen the season before | 2025 | `row:kickReturnTouchdowns.2025` |
| Five onside kicks recovered of 52 attempted | 2025 | `row:onsideRecovery.2025` |
| The home side won 53–56% of decided games and outscored by 2–3 points, most of which is not the crowd | 2023-24 | `row:preSnapRoadVsHome` |

## Bands the harness cannot measure

The harness plays games, so every row above is something a game produces. A **world** has
sourced numbers of its own — how old a roster is, how much of it arrived this year — and
the harness never sees them, because nothing about them changes when a snap does. They are
banded here all the same, and the band lives in the test that measures it rather than in
`Targets.swift`: a row in that table is a promise `simharness` prints a verdict for, and a
row nothing prints would be a promise nobody keeps. One band is in that table. What else a
generated world claims about the sport, and what a band for each would have to be computed
from, is [further down](#what-a-generated-world-claims-and-nothing-sources).

| Band | Season | Source | Where it is checked |
| --- | --- | --- | --- |
| Share of a roster in its first season: 0.145–0.171 | 2023-25 | S3 | `test:firstSeasonShare` |

**The derivation**, which `scripts/calibration-sources.py --rosters <dir>` reproduces from
the `roster_weekly_<season>.csv` files of the nflverse weekly roster release: a club's
opening roster is week 1 of the regular season with a status of `ACT` or `INA` — the active
list plus that week's inactives, which is the fifty-three a club carries, and not the
practice squad; a first-season player is one with `years_exp == 0`. That gives 281 of 1,729
in 2023 (0.1625), 274 of 1,754 in 2024 (0.1562) and 266 of 1,740 in 2025 (0.1529). The band
policy widens the span of the three by 5% of their mean, which is larger than twice the
standard error of the measurement the test makes (eight generated leagues, 13,568 men), and
so is what governs: **0.145 to 0.171**.

Three more numbers come off the same three files, and are recorded here because they were
measured rather than assumed even though nothing asserts them.

**How old a roster is.** A week-1 roster's mean age was 26.04, 26.19 and 26.34 in those
three seasons, against 26.33 in a generated league over seeds 1, 5, 7 and 11
([#67](https://github.com/knissley/football-manager/issues/67)) — inside the real range, at
the top of it. Before that issue it was 25.75, below every one of the three.

**How wide that is.** The same rosters' age standard deviation was 3.16, 3.19 and 3.31.
A generated league's is 3.29 to 3.37 across those four seeds, straddling the top of the real
range; before #67 it was 3.57 to 3.71, entirely above it. That pair of moves is the argument
for flooring a reserve's age centre two seasons above the entry age rather than truncating
the old centres alone. Truncating alone was measured at the same four seeds: mean 26.06, at
the bottom of the real range, spread 3.31 to 3.42, at its top and above, and a first-season
share of 0.19 — 0.186 pooled over the eight seeds the test reads, against 0.154 for what
landed, and outside the band above either way.

**When a first-season player arrives.** They were about a seventh twenty-one, a quarter to a
third twenty-two, about a third twenty-three and a seventh to a quarter twenty-four;
`DraftHistory.entryAge` draws 20/45/25/10 across the same four ages, which is a year young.

None of the three is banded: a number nobody asserts is a note, not a target.

**What a kick is worth by the leg that struck it.** The kicking rows above are aggregates
over everybody who kicked: `row:fieldGoals50plus` says the league makes 63.7-74.9% from
fifty and beyond, and says nothing about how that splits between the leg that is trusted
from fifty-eight and the one that is not trusted from forty-eight. The engine now models
that split — `PlaceKick` reads `kickPower` as well as `kickAccuracy`, and how far a club
will kick from follows from it — and the harness prints attempts and makes from
forty-five and beyond by leg tier so the split is visible. **Nothing sources a band for
it.** The shape was fitted to the aggregate rows above and to the two ends the sport does
state plainly — a league-average kicker's curve, which is the aggregate, and a man who is
not a kicker at all — not to a published make rate by leg. So the printed tiers carry no
target and none should be invented for them: what grades the model is the aggregate rows
it was fitted to, `row:fieldGoals50plus` and `row:fieldGoalAttempts50plus`. A band here
would need a per-kicker distance-by-distance split computed from the play-by-play with
kickers grouped by something standing in for leg, which nothing in this repository does.

## Where the harness measures something else

Two rows measure a definition of their own rather than the source's, and the difference
is written into the row's note rather than corrected by moving the band. They are listed
here so nobody reads a gap as an engine finding:

- `row:yardsPerPlay` and `row:rushingYards` — designed runs only, scrambles excluded, which
  is not how the league counts either.
- `row:grossPunt` — the harness measures a touchback's gross to the goal line. That the
  source did the same is **assumed, not read from it**: the published figure is a mean over
  punts and does not say how a touchback entered it. The band is sourced; the measurement
  convention behind it is our reading, and if the reading is wrong the row is biased by
  whatever share of punts are touchbacks. Settling it means going back to the source,
  which is a retune's job and not a fix's.

`row:netPunt` used to be here: the harness spotted a punt touchback at the goal line
rather than the 20, so its net read high on touchbacks. The record now carries where
every punt was fielded, the net is read off it with a touchback netted to the 20 as the
source nets one, and the row fell about two yards when it stopped flattering itself.

A third used to be here. `row:completionPercentage` counted a completion only when it
gained, so it read about three points low while showing green — S14 in the
[audit](../audit-is-this-football.md). The record carries `Outcome.passResult` now and the
row reads it ([#22](https://github.com/knissley/football-manager/issues/22)); the rows
still on the older inference — `row:yardsPerCompletion`'s denominator and the catch
leaders — are [#42](https://github.com/knissley/football-manager/issues/42)'s.

## Adding or moving a row

1. Compute it with `scripts/calibration-sources.py`, which names the seasons and applies
   the band policy. Do not type a figure from memory, and do not widen a band to make a run
   green — that is a retune, and a retune is its own issue.
2. Add the row to `Targets.swift` with its season, its source and the rule areas it depends
   on.
3. Regenerate the table in `match-engine.md`
   (`swift run --package-path Tools/simharness simharness --targets-markdown`), or the
   simharness package's own test fails.
4. Add the row to this file, and name it from an invariant in
   [`../invariants.md`](../invariants.md), or `InvariantsTraceabilityTests` fails.

A band the harness cannot measure skips steps 2 and 3 and lands in the test instead: derive
it with the script, put the band and its citation in the test's name and doc comment, and
add it to [the table above](#bands-the-harness-cannot-measure) naming that test. It is not a
`row:` and must not be written as one — `InvariantsTraceabilityTests` reads every `row:` in
this file as a claim that `Targets.swift` carries it.


## What a generated world claims and nothing sources

The table above holds one band, and it is the only claim about a generated world that
anything in this repository asserts as football. This is the rest of the shelf. It exists
because a generation defect has twice had to be asserted as something other than football
for want of a band, and because the next agent to want one should find the question already
asked rather than reach for a figure.

**Read it as a list of derivations, not of numbers.** Each line says what a band would have
to be computed from — a season, a release, and the count to take off it — and whether that
is worth doing. Not one of them states a band, because none has been computed. Typing a
plausible-looking figure in place of an uncomputed one is the precise failure this file
exists to prevent, so a line that says no source was located is the honest output and is
finished as it stands.

None of these is a `row:` and none may be written as one: `InvariantsTraceabilityTests`
reads every `row:` in this file as a claim that `Targets.swift` carries it, and a band about
a world belongs in a test rather than in that array for the reason
[the section above](#bands-the-harness-cannot-measure) gives.

### Worth computing

**What a roster is made of, by position group.** `RosterShape.standard` fixes the
fifty-three a club carries position by position, and the argument its doc comment makes for
the split is the personnel a defence spends its snaps in rather than a roster anybody
counted. The derivation would be the one `--rosters` already performs — week 1 of the
regular season, status `ACT` or `INA`, the seasons S3 already covers — counted by the
position group each man is listed at instead of by his years of experience. **Whether that
release names a position at all is not checked here**; if it does not, the count wants
another release from the same project, and which one is part of the sourcing job rather
than settled by this list. This is the cheapest of the six and the one nothing else would
catch: the snaps rows above grade who is *on the field*, not who is *carried*, so a club
carrying too few linemen and too many corners is in band on every one of them. Note where
the band would have to be asserted, because it is not where this list sits: the shape is an
`FMCore` constant, so the test reading it is `FMCore`'s, and sourcing this raises that
package's football share rather than `FMGeneration`'s.

**How old a roster is, and how wide.** Mean age and age spread are measured above, over the
same three seasons, and deliberately left as notes on the ground that a number nobody
asserts is not a target. That was right while nothing had gone wrong in that dimension;
[#67](https://github.com/knissley/football-manager/issues/67) has since gone wrong in
exactly it, and was caught by the first-season share rather than by either of these. Banding
them is nearly free — `--rosters` prints both already and only the policy's widening remains
to apply. Do it with the entry ages below rather than before them: whatever changes the
shape of the age model moves all three, and banding two of them first would only mean
rederiving them afterwards.

### Not a sourcing problem

**When a first-season player arrives.** Already derived — same release, same policy,
recorded above. What blocks it
([#90](https://github.com/knissley/football-manager/issues/90)) is that no setting of the
generation constants reproduces the mix, because the family the ages are drawn from is the
wrong shape. That is a modelling decision for the owner, not a band anybody is missing. The
line is here only to stop it being counted as a sourcing gap, which it has been.

**The spread of team strength.**
[#116](https://github.com/knissley/football-manager/issues/116) is sourcing it, from the
published per-game point-differential figures, and will record it here under this file's own
rules. Not duplicated here, and nobody should open a second derivation of it.

### Not worth computing

**Rating distributions by position group.** There is nothing to source. A rating on this
project's scale is the project's own invention: no season and no publisher produces one, and
importing somebody else's would import the likeness
[ADR-0005](../adr/0005-generated-fictional-content.md) forbids along with it. What can be
sourced is what a rating distribution *produces* — the spread of team strength above, and
the per-position rates the harness already grades — which is how it already stands. Marking
this line `unsourced` would imply a source exists and somebody has been lazy, and neither is
true.

**Ball security by position.** The band
[#115](https://github.com/knissley/football-manager/issues/115) wanted. Sourceable in
principle, expensive in practice, and the band it produced would probably not be worth
carrying. It needs a fumble count and a touch count split by the carrier's position, which
means joining the play-by-play release to a roster release to learn what each man plays —
the only line here needing two data sets — and a fumble per touch is rare enough that the
policy's rare-event widening would hand back a band wide enough to admit most of what the
engine could plausibly do. The claim actually wanted is a *ratio* between two positions,
and the policy bands a value, so the policy would need extending as well. The `.contract`
that landed instead — that the engine reads no positional penalty into ball security which
the rules do not draw — is cheaper and, against the defect in question, stronger. Worth
revisiting only if the fumble rows are still out of band once
[#49](https://github.com/knissley/football-manager/issues/49) has retuned the total, since
that is the case where the split matters and the total cannot speak to it.
