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

**`row:yardsPerPlay`'s band is stale and is knowingly left so.** Sack yardage is negative
on every play that has any, and therefore negative in every game. The accumulator that
folded the per-season components used `Counter` addition, which discards a key whose
running total is not strictly positive, so the sack component never survived its first
addition: the totals simply had no such key, it read back as 0 through the same subscript
every metric uses, and the numerator of both yards-per-play rows lost it entirely. Nothing
raised, and the band that came out of the derivation is the band on file.

Re-derived over the same release with the accumulator corrected, and rounded by the same
band policy:

| Row | 2023 | 2024 | Band as derived | On file |
| --- | --- | --- | --- | --- |
| `row:yardsPerPlay` — the harness's definition | 5.36 → **5.08** | 5.48 → **5.22** | 5.0–5.8 → **4.8–5.5** | 5.0–5.8 |
| yards per play, all yards over all scrimmage plays — not a row; the source of the prose figure | 5.54 → **5.27** | 5.70 → **5.44** | — | 5.5–5.7 |

The band is **not** moved here. Correcting a derived source figure is not a retune, and
moving a band is; the two are kept apart deliberately, so this records the measurement and
leaves the move to the retune that owns it. Until then `Targets.swift` states 5.0–5.8 with
a note giving the league's net figure as 5.5–5.7, and
[match-engine.md](../match-engine.md)'s band table repeats that note. Both are the stale
derivation. The rule at the top of this file decides which way the disagreement resolves:
if a number in `Targets.swift` cannot be reproduced by the script, the script wins.

No other row moved. The re-derivation was run over all four seasons both ways and diffed
in full: the script prints 130 rows — 128 metric rows and two summary rows — and three
moved, these two and the home scoring edge [below](#home-field-and-weather). The other 127
were identical to the digit, as were the game counts, the win-total sigma and the
between-club sigma. `row:marginSigma` is among the unmoved, because it is carried as two
non-negative halves written to survive exactly this.

### Why the other passes were not caught

Both print with **no band at all**, which is the honest output rather than a gap. The
play-by-play charts neither a drop nor a break-up: a drop is a charting judgement made by
a third party watching the film, and the feed names the defender on a pass defensed only
in the seasons and releases that carry the participation columns. Neither has been
computed here, and typing a plausible-looking figure in place of an uncomputed one is the
failure this file exists to prevent.

| Row | Season | Source |
| --- | --- | --- |
| `row:dropsPerTarget` — drops per target | unsourced | — |
| `row:passesDefensedPerGame` — passes defensed per game (both teams) | unsourced | — |

**What a band would have to be computed from.** For drops: a charting release that marks
one, per target, over the same two seasons the per-play rows use, with the denominator
targets rather than attempts — a throwaway has no target and must not be in it. For
passes defensed: the league's own defensive stat, per team-game and doubled for both
teams, counting balls knocked away and excluding interceptions, which
`row:interceptionRate` already bands. Until one of those is read, the engine's values are
observations and nothing grades them.

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

The harness also prints that total split **by side** (which bench asked) and **by half**
(the allotment is per half and nothing carries out of one — three a half, two in a
regular-season overtime period, 2025 rulebook 4-5-1 Item 1). Neither split is banded, and
neither is a row: nobody has computed one. What a sourcing would read is in the same
play-by-play file every `S1` row comes from — `timeout_team` against `posteam` for the
side, `qtr` for the half — and running it belongs to
[#42](https://github.com/knissley/football-manager/issues/42) rather than to a fix, so the
harness prints the two with the reason they have no target beside them. They are printed
at all because the total alone cannot tell a bench spending its second-half timeouts from
one hoarding them past the whistle, which is the thing the total exists to catch.

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

**No share is sourced for any grouping but eleven.** `row:personnel11` is the only
offensive participation share in `Targets.swift`, and nothing here, in
[the bands the harness cannot measure](#bands-the-harness-cannot-measure) or in
[what a generated world claims](#what-a-generated-world-claims-and-nothing-sources) bands
twelve, ten or an empty set. What the file does source about the rest of the mix is the
tight end count [below](#who-took-the-snap): 77.1–87.2 tight end player-snaps per team-game
against 58.9–66.8 plays from scrimmage, which is more than one tight end on the average
snap however the two bands are paired, and which therefore says that a snap that is not
eleven personnel mostly carries a second tight end rather than a fourth receiver. A
caller's mix is set from those two, because there is no figure for twelve to set it from,
and a twelve-personnel share stated as football without one is a number from memory.
Computing one is the derivation the rows above already perform — the source's
participation feed names the grouping on every play — and it is cheap; it is simply not
done, and this line says so rather than leaving the gap to be filled by remembering.

**No share is sourced for the defensive answer to a two-tight-end grouping either.** The
package rows band how often each front is on the field over *all* snaps; nothing here bands
how a defence answers one grouping. What the two bands above do say, on their own, is that
the four-back front cannot answer every heavier grouping: `row:personnel11`'s 62.3-71.9%
leaves 28.1-37.7% of snaps in a grouping that is not eleven personnel, and the smallest
that share can be is larger than `row:packageBase`'s largest. At the midpoints, 32.9 snaps
in a hundred are a heavier grouping against 22.6 in a four-back front, so 31.3% of the
heavier snaps are answered with a fifth defensive back. The caller's three-in-ten share
against a two-tight-end grouping is that figure and nothing else; applied to one grouping
rather than to all the heavier ones it realises less than 31.3%, which is the conservative
side of a derivation with no figure behind it. Computing the real share is the same cheap
derivation as above and is likewise not done.

**`row:ypcOutnumberedByOne` is currently ungradable, and it is a property of the rows
rather than of the source.** The harness grades it on first and ten only, counting blockers
as the five linemen plus every tight end plus every back after the first against a box of
eleven less the defensive backs. Minus one needs eleven personnel against a four-back front
or four-or-more receivers against a nickel back; the caller answers the first from nickel
and the second from a dime, so neither pairing occurs on first and ten and the row prints
`n/a` rather than a value and a verdict. The band is sound and the sample is empty.

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

**The middle, which is derived rather than sourced.** Those four are cumulative and they
overlap, so a distribution that stuffs half its carries and springs the rest can satisfy
every one of them while having nothing at all between two yards and ten — which is what
this engine did. The claim they cannot make between them is that the *ordinary* carry is
the largest part of the run game. Every carry falls in exactly one of three, so

    three to nine = 100 − (two or fewer) − (ten or more)

and with the two rows above at 40.6–46.5 and 9.6–11.2 the middle share is between **42.3
and 49.8** wherever the truth sits inside them. Nothing was computed for this: it is
arithmetic on two bands that are already here, and the floor is the corner that holds
however they fall. That the middle also beats the two-or-fewer share holds at the bands'
midpoints — 46.0 against 43.6 — and **not** at every corner, so it is a reading of where
the bands centre and is written here rather than asserted. It is not a `row:` and must not
be written as one.

**Where the 42.3 floor is graded, which is not in the suite.** The arithmetic above runs
both ways: `row:carries2orFewer` at or under 46.5 *and* `row:carries10plus` at or under
11.2 **is** three-to-nine at or over 42.3. So the two rows grade the derived floor between
them, over four hundred games at two seeds, and nothing else needs to. The suite's
`test:theMiddleIsTheLargestPartOfTheRunGame` used to assert 42.3 as well, over forty games
— a sample whose jackknifed standard error on that share is 1.46 points against a margin of
2.7, so it could not tell the engine's 45.0% from the floor and was passing on which forty
games it drew. It now asserts what forty games can resolve, both read off these bands
rather than off the engine: that the middle is at least an even share of the three parts
(33.3%, nine points inside the derived floor, eight standard errors clear) and that it
beats the ten-or-more share (which the bands put at a gap of 31.1 at their worst corner,
twenty-two errors clear). The harness line beside the histogram still names that test as
where the derivation is written down; it is not where the floor is asserted.

**What the mode of a carry is, nothing sources.** The most common single carry length is
the other thing a reader of the histogram wants, and no band for it exists: the four rows
above are cumulative shares and none of them speaks to the density at one yard. Deriving
one is cheap — the same play-by-play the four rows come from, counted by gained yards
instead of thresholded — and it is worth doing when somebody next opens the script, because
a mode is the one statistic a stuff-or-break distribution and a real one differ on most
visibly. Until then the harness prints the engine's mode with no target beside it and says
why, and nobody should assert a range for it from memory.

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

The harness prints two more home-field aggregates with **no band at all** — the home win
rate and the home scoring edge — because most of what they measure is travel, rest and
short weeks, none of which exists before there is a schedule to travel on (M3). What the
engine models is the crowd, so the mechanism gets the row and the aggregate gets a note.

Their values, from the run of `scripts/calibration-sources.py` over the 2022-25
play-by-play release described at the top of this file: the home side won **55.5%** of
decided games in 2023 and **53.3%** in 2024, and outscored the visitor by **2.68** points
a game in 2023 and **1.87** in 2024.

Those last two read 2.92 and 2.00 until the script's accumulator was corrected. The
scoring edge is a *signed* quantity, and the accumulator folded per-season components with
`Counter` addition, which discards any key whose running total is not strictly positive —
so each partial sum that dipped below zero was silently thrown away and the edge came out
overstated. Nothing graded the figure and no harness verdict depended on it, which is why
it survived. It is stated here as a number about the sport, so it is a claim like any
other.

### Scoreboard

| Row | Season | Source |
| --- | --- | --- |
| `row:gamesWithin3` — games within 3 | 2023-24 | S1 |
| `row:gamesWithin7` — games within 7 | 2023-24 | S1 |
| `row:gamesBy14plus` — games decided by 14 or more | 2023-24 | S1 |
| `row:marginSigma` — spread of the point differential | 2023-24 | S1 |
| `row:betweenTeamSigma` — spread of it that is the clubs | 2023-24 | S1 |

The first two say how often a game is close. The last three say how far apart the scores
get, and how much of that distance is the clubs rather than the afternoon — which is what
tells a league drawn too wide from an engine that is simply wild.

`row:marginSigma` is the standard deviation of the home side's points less the road
side's, over games: 14.40 in 2023 and 14.43 in 2024. `row:gamesBy14plus` is the share
decided by two scores or more: 37.5% and 33.1%. Both come off the same finals the two
`gamesWithin` rows read and add nothing to the derivation but arithmetic.

`row:betweenTeamSigma` is the club part of `row:marginSigma`, and it is the one that took
a decision. Each club's point differential is gathered by club and split the way a one-way
random-effects model splits any repeated measure: the variance of the club season means,
less the pooled within-club variance divided by the games each club played. The
subtraction is the whole point — a season is short, so the spread of the club *means* is
inflated by exactly that much, and without the correction a league of identical clubs
reports a spread it does not have. That gives **4.83 in 2023 and 5.73 in 2024**, and
`scripts/calibration-sources.py` prints it beside the win-total sigma on every run.

What it assumes is in the script's own doc comment, and all of it is listed there because
the number sets a generation constant: a roughly balanced schedule, home field as a
constant rather than a club trait, and a club's strength not moving during the season.
Each of those, violated, pushes the estimate **up** — schedule imbalance and in-season
drift both read as between-club spread — so it is an upper estimate of a club's true
spread and not a lower one. The band is not a gate for a second reason: four hundred games
gives a club twenty-five, and at that length the estimator's own error is about as wide as
the band.

#### What the spread of team strength was set from

`WorldGenerator.strengthSpread` draws each club's rating offset uniformly on ±*S*. Before
[#116](https://github.com/knissley/football-manager/issues/116) *S* was 8, a number from an
audit plan with no source at all. There is no way to source a *rating*: the scale is this
project's own invention and no season publishes one
([ADR-0005](../adr/0005-generated-fictional-content.md) and the shelf
[below](#not-worth-computing)). What can be sourced is what a rating spread *produces*, so
*S* is set by matching `row:betweenTeamSigma` to the sourced figure above, with the engine
as the transfer and the target outside it.

Three measurements, all from `simharness --strength-spread`, which exists for this. **Take
them at 1,600 games and eight worlds per setting, and do not mix lengths**: a 400-game run
reads the between-club spread about 2% high, which is harmless in a row and is not harmless
in a slope.

1. **The floor.** At *S* = 0 every club is drawn from the same distribution, and the
   between-club spread is still **4.23** — eight worlds of 1,600 games. Two rosters drawn
   the same way are not the same roster, and that difference alone is most of a real
   league's spread.
2. **The transfer.** Between-club variance above the floor is proportional to *S*²: the
   slope is **1.211** points of differential per point of *S*, from 1.2208 at *S* = 4 and
   1.2005 at *S* = 8.
3. **The solve.** The draw must contribute √(5.28² − 4.23²) = 3.16 points, so
   *S* = 3.16 / 1.211 = **2.61** — where 5.28 is the mean of the two sourced seasons.

Checked at the answer rather than assumed: eight worlds of 1,600 games at the shipped width
report a pooled **5.33** against the 5.28 it was solved for.

**The shipped constant is 2.63, not the 2.61 this tree solves to, and the difference is the
rule below doing its job.** 2.63 was derived on the tree before this one; re-measuring here
gives 2.61, a drift of 0.8% against a measured noise floor of 2%, so the constant was held
and the drift recorded rather than moved by less than the instrument resolves. Any reader
checking the arithmetic will land on 2.61 and should: that is the re-measurement, and this
paragraph is where it is written down.

**The floor and the slope belong to the engine, so re-measure them rather than inheriting
them.** They were 4.06 and 1.065 when this was first derived, which solved to 3.17; the run
game then grew a middle ([#118](https://github.com/knissley/football-manager/issues/118))
and both moved — a carry that gains its ordinary yards rather than its extreme ones makes
the better club's advantage travel further, so the slope rose and the width needed fell. The
same three steps against the same sourced target gave 2.55. Then the defence learned to
answer two tight ends with a fifth defensive back some of the time
([#130](https://github.com/knissley/football-manager/issues/130)), the floor fell from 4.28
to 4.16 and the slope rose again, and the same three steps gave 2.63. Twice in one day, from
two engine changes neither of which was about the world. Anything that changes what a snap
does can move this constant without anybody touching it, which is the argument for
`row:betweenTeamSigma` existing at all: it is what notices.

#### When to move the constant, and when to leave it

Re-measuring on every engine change and *shipping* on every engine change are different
things, and without the second rule written down the constant never converges: each landing
reopens it, and the value chases the last thing that moved rather than settling on what the
sport says. The rule is the deliverable; this is it.

**The noise floor is about 2%, and it is measured rather than asserted.** Two independent
handles give the same figure. The check at the answer lands a pooled 5.38 against the 5.28
it was solved for, which is 2%. And the same quantity read at 400 games rather than 1,600
comes back about 2% high, which is why a derivation must not mix run widths. Take 2% of the
constant as the smallest difference worth acting on.

So, after re-measuring the floor and the slope on the tree in front of you and solving:

- **Within 2% of the constant already in the tree — keep it, and record the drift.** Both
  numbers, and the floor and slope that produced each, go in the pull request. This is not
  laziness or chasing avoided by fiat: it is declining to move a constant by less than the
  instrument can resolve, which would be fitting noise.
  *Worked example:* 2.63 against a re-solve of 2.61 is 0.8%, inside the floor, so the
  constant was held and the drift written into the three steps above.
- **Beyond it — move it**, and say which engine change moved the slope or the floor, in the
  same terms the rest of this section uses.
  *Worked example:* 2.55 against a re-solve of 2.63 is 3.2%, past the floor, so the
  constant moved and the engine change that moved it was named.

Two things this rule is not. It is **not** a licence to skip the measurement: the drift is
only reportable because somebody measured it, and an unmeasured "probably still fine" is
the failure this whole file exists to prevent. And it is **not** a tolerance on the *band* —
`row:betweenTeamSigma` grades what a generated league actually does, at whatever width is
shipped, and a row out of band is a finding whether or not the constant was left alone.

#### When re-derivation stops

The rule above says whether to move once you have re-derived. On its own that is an
infinite loop, because the thing it measures keeps moving.

**This constant is provisional by construction.** It is derived from engine measurements,
so it drifts whenever the engine lands. Re-derive when the branch that owns it lands, and
apply the rule above on the tree it ships on. Do **not** re-derive again because a later
branch moved the engine: record the drift instead, and let the retune own the final value.
`row:betweenTeamSigma` is what makes that drift visible rather than silent — which is the
whole reason it is graded rather than left as a note.

**E3 ([#49](https://github.com/knissley/football-manager/issues/49)) owns the final
derivation.** It is the pass that settles what a snap does, so it is the only place the
floor and the slope stop moving underneath the solve, and it should re-derive once at the
end against whatever engine it leaves behind.

**How much does it actually move?** Measured in one day, across three engine landings, each
by the same three steps against the same sourced target of 5.28:

| after | floor | slope | solve | what moved the engine |
| --- | --- | --- | --- | --- |
| the tree before the run game had a middle | 4.06 | 1.065 | **3.17** | — |
| [#118](https://github.com/knissley/football-manager/issues/118) | 4.28 | 1.212 | **2.55** | a carry became three outcomes rather than a draw on a hole |
| [#130](https://github.com/knissley/football-manager/issues/130) | 4.16 | 1.237 | **2.63** | a two-tight-end grouping began drawing the fifth defensive back |
| [#133](https://github.com/knissley/football-manager/issues/133) | 4.23 | 1.211 | 2.61 — **held at 2.63** | when a pre-snap foul is drawn, which is not how yards are gained |

That table is worth more than any one of the three values. It is the measured answer to
*how far does this constant move when the engine changes*, which nobody had before, and it
is the argument for both halves of the rule: the moves are real rather than noise — two of
the three are past the floor — and they are small enough that waiting for the retune costs
little. A reader who wants to know whether a stale width matters should read the rows here
rather than re-run the derivation.

**Read the floor as a finding, not a detail.** Four fifths of the sourced spread — two
thirds of its variance — is already spent on roster-draw noise before a single club is
called a contender, which is why the sourced *S* is as narrow as it is: what the league
deliberately draws is the smaller part of what separates two clubs. Narrowing the roster
draw would buy back room for deliberate structure; that is a generation decision and nobody
has taken it.

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

Those ten count **accepted** fouls, which is what the league publishes. Two rows beside
them count something else and are unsourced for two different reasons.

| Row | Season | Source |
| --- | --- | --- |
| `row:interferenceDrawnPerGame` — defensive interference flags thrown, accepted or not | unsourced | — |
| `row:interferenceOnCompletions` — the share of them on a pass that was then completed | unsourced | — |

The first is a count of flags rather than of enforced fouls, and nobody has computed a
band for one: the feed carries declined penalties, so it could be computed — per game,
both teams, the same two seasons — but it has not been, and it is printed because an
accepted rate is the residue of a draw that may be much larger. Interference is where that
went wrong: the accepted rate graded near its band while two thirds of the flags were
flying on passes that were then completed and being declined.

The second is **not a league rate at all** and must not be sourced as one. Its band of zero
is the engine's own promise, taken from 8-5-1: the foul is contact that spoils an eligible
receiver's chance at the ball, so on the one matchup this engine draws it on, the flag and
the catch cannot both have happened. The offence's push-off is excluded and printed beside
it, because a catch that an offensive interference penalty brings back (8-5-2,
8-5-Penalty) is the sport working normally.

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
| Yards per play, the league's net definition: 5.5–5.7 — **stale**, re-derives to 5.3–5.4, see [above](#the-passing-and-running-game-per-team-per-game) | 2023-24 | `row:yardsPerPlay` |
| First downs per team-game including penalty first downs: 17.8–18.3 | 2023-24 | `row:firstDownsPerTeamGame` |
| Yards per carry by defenders actually in the box: 4.5–4.7 | 2023-24 | `row:ypcEvenCount` |
| Even against outnumbered, the sport's own gap: 4.3–4.6 against 4.5–4.7 | 2023-24 | `row:ypcOutnumberedByOne` |
| Fourth downs gone for, rising: 23.3% | 2025 | `row:fourthDownWentForIt` |
| Fourth and one, went for it, rising: 76.3% | 2025 | `row:fourthAndOneWentForIt` |
| Two-point conversion swung from 55% to 41% on about 130 tries a season | 2023-24 | `row:twoPointConversion` |
| Illegal formation was called about twice as often in 2024 as in 2023 | 2023-24 | `row:penalty.illegalFormation` |
| Twenty-one kick return touchdowns, against fourteen the season before | 2025 | `row:kickReturnTouchdowns.2025` |
| Five onside kicks recovered of 52 attempted | 2025 | `row:onsideRecovery.2025` |
| The home side won 53–56% of decided games and outscored by 1.9–2.7 points, most of which is not the crowd | 2023-24 | `row:preSnapRoadVsHome` |

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

**The spread of team strength.** Done, and it is a `row:` — `row:betweenTeamSigma` under
[Scoreboard](#scoreboard), with the derivation of `WorldGenerator.strengthSpread` from it
beside the row. It is listed here only so a reader who comes looking finds the answer
rather than opening a second derivation of it. Two things to carry away if you do not read
that section: no *rating* spread was sourced, because none can be — what was sourced is
what a rating spread produces — and there was **no published figure to find**. The
between-club figure is derived from S1 by this repository's own script, the way every other
band here is, and is not a number anybody published as a number.

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

## What a test claims about a game and nothing sources

The section above is the shelf for a generated *world*. This is the same shelf for a
*game*: a rate a test in the engine's own suite would like to assert about the sport, which
nothing in this file bands. Read it the same way — a derivation and whether it is worth
doing, never a number, because none of these has been computed either.

**Pressure, split by how long the ball is held.** `row:pressureRate` bands pressure per
dropback pooled over every dropback there is, 2023-24, source S2. Nothing here splits it:
not by pass depth, not by play action, not by the time the passer held the ball. That is a
rate rather than a rule, so [`playing-rules.md`](playing-rules.md) has nothing to say about
it either, and the question the gap leaves open is a live one.

**And nothing here sources when a pass rush arrives either**, which is the same gap read
from the other side. The engine decides pressure by asking whether the first man home beat
the hold the concept asks for, so it needs a distribution for the arrival, and this file
bands none — no time-to-pressure, no time-to-sack, nothing that would shape one. So the
arrival window is an explicit modelling decision rather than a sourced one, in the sense
`GameClock.readyForPlayDelay` is: it is stated, with its consequence, under *Pass play* in
[`../match-engine.md`](../match-engine.md), and it is not a number anybody computed from a
season. What the reference *does* constrain is the **level** — `row:pressureRate` — and
that is the rush win multiplier's to answer for, not the window's.

This mattered concretely. The arrival used to be drawn on `[1500, 2899]` while the holds
ran from 1,400 ms to 3,400 ms, so three of the five pass concepts sat outside the window
entirely: a screen was un-pressurable by construction at exactly 0.0000, and play action
and a deep drop came back pressured on the *same* 1,360 of 2,450 paired dropbacks,
identical to the snap. A window that spans the holds fixes the instrument; it does not
answer the question above, and a retune should not read it as if it had.

The derivation, if it is ever wanted: S2 is the participation release this file already
reads for `row:pressureRate` — one row per play, already joined to the play-by-play by
`scripts/calibration-sources.py` — and the split would bucket the same pressure flag by
whatever that release carries for how long the passer held the ball. **Whether it carries
such a column at all is not checked here**; if it does not, the split wants another release
from the same project, and finding it is part of the sourcing job rather than settled by
this line. A play-action flag is a second question and a harder one, since a pass off a fake
is not something every feed publishes.

Worth doing only when something turns on it, and today nothing does. What the suite asserts
about the hold is `test:pressureNeverFallsAsTheHoldGrows` and
`test:theArrivalWindowSpansTheRouteHolds`, and both are `.contract` — a longer hold is never
pressured less often than a shorter one off the same rush, and every hold has arrivals on
both sides of it. Both follow from the resolver's own definition of pressure and need no
band. A band becomes wanted the day somebody means to separate two holds on purpose, or to
shape the arrival from a season rather than from the model: either is a modelling change, it
would move `row:pressureRate` with it, and it should not be made on the strength of a figure
nobody computed.
