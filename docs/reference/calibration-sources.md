# Where the calibration numbers came from

**Status: built.** Every row below exists in
`Tools/simharness/Sources/simharness/Targets.swift` today, and
`InvariantsTraceabilityTests` fails if one named here does not. Two sections are the
exception. [Bands the harness cannot measure](#bands-the-harness-cannot-measure) are not
rows and have no verdict in a harness run, so each names the `test:` that checks it
instead. [Completions that lose yardage](#a-sourced-figure-with-no-row-completions-that-lose-yardage)
is a figure the harness could grade and does not: it is derived and recorded, nothing
checks it, and it is written without a `row:` so that nothing reads it as a claim about
`Targets.swift`.

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

**How to get them:** `scripts/fetch-calibration-data.sh <dir outside the repo>` downloads all
three, for the seasons the derivation reads, and writes a `MANIFEST.txt` beside them
([docs/tools.md](../tools.md#fetch-calibration-data--get-the-data-the-bands-were-derived-from)).
These are rolling release tags served from a fixed URL, so **a derivation cites the release it
read and not merely the season**: quote the manifest's line for the file you folded — its byte
count, sha256 and the release's `Last-Modified` — beside the number you derived. Figures
recorded here before that script existed name the season only, which is why a re-derivation
can differ from one of them without either being wrong.

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

**`row:yardsPerPlay`'s band was derived from a corrupted total, and has been corrected.**
Sack yardage is negative on every play that has any, and therefore negative in every game.
The accumulator that folded the per-season components used `Counter` addition, which
discards a key whose running total is not strictly positive, so the sack component never
survived its first addition: the totals simply had no such key, it read back as 0 through
the same subscript every metric uses, and the numerator of both yards-per-play rows lost it
entirely. Nothing raised, and for the life of the tool the band on file was the one that
came out of that derivation.

Re-derived over the same release with the accumulator corrected (`109de07`), and rounded by
the same band policy:

| Row | 2023 | 2024 | Band as derived | Was on file |
| --- | --- | --- | --- | --- |
| `row:yardsPerPlay` — the harness's definition | 5.36 → **5.08** | 5.48 → **5.22** | 5.0–5.8 → **4.8–5.5** | 5.0–5.8 |
| yards per play, all yards over all scrimmage plays — not a row; the source of the prose figure | 5.54 → **5.27** | 5.70 → **5.44** | — | 5.5–5.7 |

**The band is moved, and the prose figure with it.** The rule at the top of this file is
what decides it: if a number in `Targets.swift` cannot be reproduced by the script, the
script wins. `yardsPerPlayOfficial` is the second row above and is **not** a row in
`Targets.swift` — it is a script output, and the only thing that quoted it was
`row:yardsPerPlay`'s prose note, which said 5.5–5.7 and now says 5.3–5.4.

### Correcting a band and retuning to one are different things

They were run together in one sentence here, which is how the correction above sat unmade
for as long as it did. They are two cases and only the second is a retune:

- **The band is numerically wrong because its derivation was corrupt.** Restoring it is a
  **defect fix**, and it belongs to whoever found it. No engine constant moves, no engine
  behaviour moves, and the row is being made to grade against the number its own source
  always said. This is the case above.
- **The band is right and the engine does not fit it.** Moving the band would be **a
  retune**, and it belongs to the retune issue
  ([#49](https://github.com/knissley/football-manager/issues/49)), which is owner-gated.
  Nothing else may move it, and a fix that finds a row out of band against a *corrected*
  target reports the residual there rather than widening anything.

The test for which one you are in is not how far the band moves; it is what changed. If the
derivation changed, it is the first. If only the engine's reading of it did, it is the
second.

**What the correction did to the engine's verdict, measured rather than argued.** The
harness was never corrupted — only the derivation script — so the row and its band were
measuring different quantities, the engine about 0.15 low against a band about 0.2 high.
Correcting it removes that mismatch rather than moving a goalpost, and it does so in the
engine's favour: on the old definition, with sack yardage dropped, seed 11 would read 5.54,
which is *above* the corrected ceiling. Against the corrected band, at 400 games in release:

| | printed | vs 5.0–5.8, the stale band | vs 4.8–5.5, the corrected one |
| --- | --- | --- | --- |
| seed 7 | 5.3 | ok | **ok** |
| seed 11 | 5.4 | ok | **ok** |

**Both calibration seeds are not the whole story, and the rest of it is a residual.** Read
at 400 games at each of the thirty seeds the noise sweep uses, the row has a mean of 5.45
against a corrected ceiling of 5.5, and **ten of the thirty grade `OFF`** — seeds 2, 3, 8,
9, 14, 16, 17, 19, 27 and 29 — where against the stale band all thirty were `ok`. Six of
the ten print 5.5 or 5.6 at one decimal and only give up their verdict because a row graded
outside its band prints the decimals that put it there; reading the rounded column alone
would have counted five and been wrong by half.

**That is a residual and not a reason to widen anything.** It is case two above, and it is
[#49](https://github.com/knissley/football-manager/issues/49)'s. Sacks are the component
whose yardage this row was missing, and `row:sackRate` reads about 4.6 against a band of
6.1–7.2, so the retune that raises it pushes this row down. The ten seeds sit between
0.003 and roughly a tenth above the ceiling, which is the order a sack-rate move covers;
how much exactly is the retune's to measure, and nothing here should be moved on the
strength of an estimate.

No other row moved. The re-derivation was run over all four seasons both ways and diffed
in full: the script prints 130 rows — 128 metric rows and two summary rows — and three
moved, these two and the home scoring edge [below](#home-field-and-weather). The other 127
were identical to the digit, as were the game counts, the win-total sigma and the
between-club sigma. `row:marginSigma` is among the unmoved, because it is carried as two
non-negative halves written to survive exactly this.

### The second place a negative play was dropped: the harness's own pass sum

The fold above was in the derivation script. **There was a separate clamp in the harness**,
and it discarded a different quantity: every pass attempt was summed as `max(0, yards)`, so
a ball caught behind the line for a loss was accumulated as nothing. One clamped number was
then handed to four rows — passing yards, yards per attempt, yards per play and yards per
completion — of which only yards per play has a band derived that way. The other three were
measured with the loss thrown away and graded against a target that counted it.

The word doing the hiding was **"gross"**, which `Targets.swift` used for the clamped
quantity in one note and for the signed one eleven lines below. It is not used for either
now: each of the four rows says in words whether a completion for a loss is counted, the
register that decides which is `PassYardage` in the harness, and a test in the simharness
package reads the notes back against it.

What the source does, measured over the same release, regular-season completions:

| Season | Completions | For a loss | Yards discarded by the clamp |
| --- | ---: | ---: | ---: |
| 2023 | 11,808 | 379 (3.21%) | −1,089 |
| 2024 | 11,629 | 337 (2.90%) | −926 |

So `c["passYards"] += yards` is signed in the data as well as in the code — which was listed
as unchecked when the defect was filed — and the two sums the script keeps side by side,
`passYards` and `passYardsPositive`, are genuinely two quantities rather than one written
twice. Per team-game the clamp was worth about 2.0 yards in 2023 and 1.7 in 2024 on the
league's own numbers; what it was worth in the harness is smaller, because the engine throws
such a catch less often than the league does, and how much less is
[#167](https://github.com/knissley/football-manager/issues/167)'s question.

`row:yardsPerCompletion` diverged twice over: the numerator was clamped and the denominator
was the older gains-only inference, where the script divides by the completions. Both halves
are resolved together — the row now divides signed yards by every completion the record says
was one — and the gains-only set is kept only for the catch leaderboard, which ranks on it.

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
| `row:throwawaysPerDropback` — throwaways per dropback | unsourced | — |
| `row:checkdownsPerDropback` — checkdowns per dropback | unsourced | — |
| `row:firstReadShare` — throws to the first read, over throws to a read | no band by design | — |
| `row:targetShare.wideReceiver` — targets to wide receivers, over targets | 2023-24 | S1 joined to S2 |
| `row:targetShare.tightEnd` — targets to tight ends | 2023-24 | S1 joined to S2 |
| `row:targetShare.runningBack` — targets to backs | 2023-24 | S1 joined to S2 |

**What the quarterback did with the ball** (C3 #44) prints beside the catch rows and, like
them, with no band. A throwaway is a charting judgement in the sense a drop is, and no feed
marks a checkdown; the figures C3's plan once carried for both — 2 to 3% and 10 to 15% of
dropbacks — were from memory and were withdrawn under rule 10. The share of throws that
went to the first read has no band *by design*: a read order is coaching design and nothing
charts it, and the row is printed because `row:pressureRate`'s move under C3 is bounded by
it. **Target share by position group is the one of these a source bands**, and it is the
footprint the read order and the checkdown leave: a table that never reads the tight end,
or a passer who checks down three times as often as the sport does, shows up here and
nowhere else the harness can see.

**How the target share is joined.** The play-by-play names the targeted receiver by
identifier (`receiver_player_id`) and carries no position; the participation row for the
same play carries positions and names no receiver. They join **by index**: that row's
`offense_players` and `offense_positions` are two `;`-separated lists written in one order,
so the targeted man's position is the entry at his index in the first. **The weekly roster
release (S3) was not needed** — over 2023 and 2024 every regular-season target with an
identifier resolved this way (17,483 of 17,483 and 17,013 of 17,013), with no play missing
its participation row. The denominator is **targets, not attempts**, the convention
`row:dropsPerTarget` states: an attempt the feed names no receiver on — a throwaway, a
spike, a ball batted down at the line — has no target and is in neither half of the ratio
(832 such attempts in 2023, 798 in 2024). The three shares do not sum to 100. About three
targets in a thousand go to a man the feed lists at a lineman's or a defender's position,
and they stay in the denominator, because a share of the three would say something other
than what the row's label says.

Two of C3's three figures stay unbanded for good: a throwaway is a charting judgement and
no feed marks a checkdown. Neither is planned, and the rows print with that reason on them.

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
| `row:ypcOutnumberingByOne` — yards per carry, outnumbering by one | 2023-24 | S2 |

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

### The count-advantage buckets, and which of them the engine can fill

All three rows grade first and ten only, counting blockers as the five linemen plus every
tight end plus every back after the first, against a box of eleven less the defensive backs.
So minus one needs eleven personnel against a four-back front, or four-or-more receivers
against a nickel back; plus one needs a tight end or a second back against five defensive
backs.

**How much of the sport each bucket is**, derived from the same participation release and
printed by the script as `ypcShareOutnumberedByOne`, `ypcShareEvenCount` and
`ypcShareOutnumberingByOne`. None of the three is a row: the harness reads its own shares
off the counts it prints beside each bucket.

| Bucket | 2023 | 2024 | Engine, 400 games, seeds 7 and 11 |
| --- | ---: | ---: | ---: |
| outnumbered by one | 12.7% | 11.1% | **0.2%** — 23 carries of 11,685 and 11,634 |
| even count | 64.8% | 67.4% | **92.3%** |
| outnumbering by one | 20.0% | 20.2% | **7.1%** — 827 and 779 carries |

**`row:ypcOutnumberedByOne` reads `n/a`, and the reason is the engine's, not the row's.**
It was diagnosed — in this file, in [play-calling.md](../play-calling.md) and in the issue
that asked for it to be regraded or retired — as grading a box that modern defensive
football has designed out. The table above is what settles that, and it says otherwise: the
sport plays this box on one first-and-ten designed carry in eight. The bucket is not empty
in the harness either; it holds 23 carries at both calibration seeds, which is too thin for
a mean and is why the row prints no value. Every one of the 23 is eleven personnel against a
four-back front, and the source runs that same pairing on 18.8% of 2023's first-and-ten
carries from eleven personnel and 18.3% of 2024's, against the engine's 0.3%.

So the band is sound, the row is sound, and what is wrong is the engine's **joint**
personnel-and-package answer rather than either marginal: `row:personnel11`,
`row:packageNickel` and `row:packageBase` all grade `ok` at both seeds while the pairing of
one to the other is nearly deterministic where the sport's is not. **That is a residual for
the retune ([#49](https://github.com/knissley/football-manager/issues/49)), and no band or
denominator here is to be moved to accommodate it.** Retiring the row would record a claim
about the sport that the source contradicts.

`row:ypcOutnumberingByOne` is the bucket the engine's first-and-ten running has moved into,
and it is graded: about 800 carries a seed, banded from the same source at 4.0–4.9 with
4.33 in 2023 and 4.55 in 2024.

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

### The release the sixteen 2026-09-15 rows were derived from

`row:sacksPerPressure`, `row:redZoneTripsPerTeamGame`, `row:twoPointTriesRun`,
`row:twoPointTriesPass`, `row:outOfBoundsShare`, `row:outOfBoundsShareTrailingLate`,
`row:puntTouchbacksFromPlusTerritory` and the nine `row:runShare.*` buckets were derived by
`scripts/calibration-sources.py` on 2026-09-15, from the releases
`scripts/fetch-calibration-data.sh` fetched that day. These are rolling release tags served
from a fixed URL, so the manifest's lines are the citation and the season alone is not:

```
# file	bytes	sha256	release-last-modified
play_by_play_2023.csv.gz	19169807	4649804ee0f0a40b41e51ec75a1ce921949d7fab5459213488656b92f78560e8	Thu, 12 Feb 2026 10:24:52 GMT
play_by_play_2024.csv.gz	19362351	23370d5d10f8104d80d46a1fc5e61f4f6f5a3263fe96fe2dd629913cfcb08c06	Thu, 13 Aug 2026 12:26:27 GMT
pbp_participation_2023.csv	49967956	ad01aeb4045ee19a4f086ff38b52b14c8f427d3401e529c3078a4545921650a9	Thu, 04 Sep 2025 10:25:30 GMT
pbp_participation_2024.csv	49688308	b1f436a98b2a7759eb4ed1181e072a35c2666f9aeb356a49c943d28d6be6b0b9	Thu, 04 Sep 2025 10:24:49 GMT
```

`row:sacksPerPressure` is the only one of the sixteen that reads the participation feed; the
other fifteen read the play-by-play alone. The same run reproduced all 140 rows that were
already in the derivation, to the digit, which is what says the new components and the new
metrics did not disturb the bootstrap's draw order.

### What the caller called, by down and distance

Run share in the nine buckets the engine's own `DownAndDistanceClass` splits second, third
and fourth down into. **"Second and 4 to 6" is a derived split rather than a column in the
data**, so the derivation writes the split out: a play is bucketed by its down and its
`ydstogo`, 1 to 3 short, 4 to 6 medium, 7 or more long, and a goal-to-go snap is in none of
the nine because goal-to-go is its own class and takes precedence over the down. First down
is one class and is not split by distance, so it has no row either.

The denominator is the calls a coordinator chooses between — a designed run or a dropback —
so a sack and a scramble count as the pass they were called as, and a kneel and a spike are
in neither half: both are clock plays rather than a choice about the sport. The harness
reads the call off `PlayRecord.calls.offense.concept` and the bucket off
`DownAndDistanceClass(situation)`, which is the same split on both sides of the comparison.

| Row | Season | Source |
| --- | --- | --- |
| `row:runShare.secondShort` — runs called, second and 1 to 3 | 2023-24 | S1 |
| `row:runShare.secondMedium` — runs called, second and 4 to 6 | 2023-24 | S1 |
| `row:runShare.secondLong` — runs called, second and 7 or more | 2023-24 | S1 |
| `row:runShare.thirdShort` — runs called, third and 1 to 3 | 2023-24 | S1 |
| `row:runShare.thirdMedium` — runs called, third and 4 to 6 | 2023-24 | S1 |
| `row:runShare.thirdLong` — runs called, third and 7 or more | 2023-24 | S1 |
| `row:runShare.fourthShort` — runs called, fourth and 1 to 3 | 2023-24 | S1 |
| `row:runShare.fourthMedium` — runs called, fourth and 4 to 6 | 2023-24 | S1 |
| `row:runShare.fourthLong` — runs called, fourth and 7 or more | 2023-24 | S1 |

The fourth-down buckets are the thin ones: about 150 run-or-pass calls a season on fourth
and 4 to 6, against tens of thousands on second down, and the band policy's resampling
widens them accordingly — `row:runShare.fourthMedium` spans 0.9 to 11.5% and catches only a
gross miss. They are kept because a caller that never runs on fourth and short, or runs on
fourth and twelve, is a caller a fan would notice.

### Where a play ends laterally

| Row | Season | Source |
| --- | --- | --- |
| `row:outOfBoundsShare` — plays ending out of bounds | 2023-24 | S1 |
| `row:outOfBoundsShareTrailingLate` — out of bounds, trailing late | 2023-24 | S1 |

The denominator is the plays from scrimmage that ended with the ball dead in the field of
play or out of bounds. The harness reads that off `PlayEnding.tackled` and `.outOfBounds`;
the feed carries no "tackled" flag, so the derivation writes the same set as everything else
being absent — not an incompletion, not a touchdown, not an interception, not a fumble lost,
not a safety. A score, an incompletion and a takeaway are in neither half on either side:
none of them is a play the carrier could have taken to the sideline instead.

The trailing-late row is the same share on snaps taken trailing inside two minutes of either
half, which is the harness's `SituationClass.isDesperation`; the derivation matches it with
`half_seconds_remaining <= 120` in the second or fourth period and a negative
`score_differential`. The gap between the two rows is the two-minute drill. A runner going
out of bounds starts the clock on the Referee's ready signal, except that it starts on the
snap after the two-minute warning of the first half and inside the last five minutes of the
second (2025 rulebook, 4-3-2-a); this bucket sits inside both windows, so there the sideline
buys a down and elsewhere it mostly does not.

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
| `row:sacksPerPressure` — pressures ending in a sack | 2023-24 | S2 |
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
| `row:redZoneTripsPerTeamGame` — red zone trips per team-game | 2023-24 | S1 |
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
| `row:twoPointTriesRun` — two-point tries carried in | 2023-24 | S1 |
| `row:twoPointTriesPass` — two-point tries thrown | 2023-24 | S1 |

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
| `row:puntTouchbacksFromPlusTerritory` — touchbacks, punts from inside the 45 | 2023-24 | S1 |

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
| Yards per play, the league's net definition: 5.3–5.4 — corrected from 5.5–5.7, see [above](#the-passing-and-running-game-per-team-per-game) | 2023-24 | `row:yardsPerPlay` |
| First downs per team-game including penalty first downs: 17.8–18.3 | 2023-24 | `row:firstDownsPerTeamGame` |
| Yards per carry by defenders actually in the box: 4.5–4.7 | 2023-24 | `row:ypcEvenCount` |
| Even against outnumbered, the sport's own gap: 4.3–4.6 against 4.5–4.7 | 2023-24 | `row:ypcOutnumberedByOne` |
| The outnumbered box is 11.1–12.7% of first-and-ten designed carries, and the engine reaches it on 0.2% | 2023-24 | `row:ypcOutnumberedByOne` |
| The outnumbering box is 20.0–20.2% of them, and by defenders actually in the box the carry gained 4.5–4.7 | 2023-24 | `row:ypcOutnumberingByOne` |
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

## A sourced figure with no row: completions that lose yardage

**Derived, and deliberately not a `Targets.swift` row.** A row in that table is a promise
`simharness` prints a verdict for on every run, and nothing asked for this to be graded.
What follows is a sourced figure the engine can be read against by hand, in the shape of
the rows above so that whoever decides to grade it does not have to derive it again.

`scripts/calibration-sources.py` prints three ids for it on a plain run, from S1 — the same
release every row above was computed from — under the same band policy:

| Script id | What it is | 2023 | 2024 | se over 400 games | Band the policy gives |
| --- | --- | --- | --- | --- | --- |
| `completionsNegative` | completions that lose yardage, share of completions % | 3.21 | 2.90 | 0.139 | 2.6–3.5 |
| `completionsNegativePerGame` | the same completions per game, both teams | 1.393 | 1.239 | 0.0579 | 1.12–1.51 |
| `completionNegativeYards` | yards lost per completion that lost yardage | 2.87 | 2.75 | 0.105 | 2.5–3.1 |

Season 2023-24, source S1, both seasons' regular season and nothing else. **The release it
was read from**, as `scripts/fetch-calibration-data.sh` recorded it — the two files folded,
by name, bytes, sha256 and the release's last-modified date, because these are rolling tags
and the season alone does not name what was read:

```text
play_by_play_2023.csv.gz  19169807  4649804ee0f0a40b41e51ec75a1ce921949d7fab5459213488656b92f78560e8  Thu, 12 Feb 2026 10:24:52 GMT
play_by_play_2024.csv.gz  19362351  23370d5d10f8104d80d46a1fc5e61f4f6f5a3263fe96fe2dd629913cfcb08c06  Thu, 13 Aug 2026 12:26:27 GMT
```

In counts rather
than rates, because a band says nothing about how thin the sample under it was: **379 of
2023's completions lost yardage and 337 of 2024's**, over 272 regular-season games each.
Those two counts were already in the tree — `scripts/calibration-sources.py` states them in
the comment that explains why `passYards` is carried signed — and the accumulator added for
this section reproduces them, which is the cheapest check that it counts what it says it
counts.

**What the figure is a statement about, and what it is not.** Forward progress puts the
ball dead at the furthest point a runner or an airborne receiver reached toward his
opponent's goal, however far an opponent afterwards drives him back, and the airborne catch
is spotted where that opponent first made contact after control (2025 rulebook, 3-12-1 and
7-3-3; the entries are in [`playing-rules.md`](playing-rules.md)). So a completion can only
lose yardage when the catch itself was behind the previous spot. The source agrees, which
is worth recording because it makes the rate a measurement of one thing rather than two:
**372 of 2023's 379 and 331 of 2024's 337 were caught behind the line**, by the release's
own air-yards column. The handful that were not are the case 3-12-1 does not reach — a
runner who gives ground of his own accord is spotted where he is put down — and they are
about one in seventy of the rate, not a second mechanism inside it.

**What the engine does.** Measured with `Tools/gamelog` on `18f78be`, thirty games: ten
seeds (7, 11, 23, 37, 41, 53, 61, 72, 89, 97) against three matchups (`--home 3 --away 11`,
`--home 12 --away 5`, `--home 1 --away 9`).

| | source, 2023-24 | engine, thirty games |
| --- | --- | --- |
| completions that lose yardage, share of completions | 2.6–3.5% | 1.99% (24 of 1,203) |
| the same per game, both teams | 1.12–1.51 | 0.80 |
| yards lost per such completion | 2.5–3.1 | 1.58 |
| largest single loss | 11 in 2023, 24 in 2024 | 3 |

**All twenty-four were screens**, of 148 screens called — no other concept threw the ball
behind the line and completed it in thirty games. That is the same zero the earlier
measurement found at `797138a`, where the count was 26 in thirty games rather than 24; the
difference between the two is the engine having moved under it, and neither is a 400-game
reading.

**The verdict, and whose it is.** The engine reads below all three bands, and the gap is
not the same size in each. The two rate rows are about two standard errors low for a
thirty-game sample — twenty-four events carry a Poisson spread of about ±0.16 a game, and
the shortfall from the band's floor is 0.32 — so they are a finding rather than a
settled miss, and a 400-game reading would settle them. The third is not a sample-size
question at all: the engine's *largest* completion loss over thirty games is three yards,
against a source whose *mean* is 2.7 to 2.9 and whose worst single play is eleven and
twenty-four yards in the two seasons. The engine throws behind the line about as deep as a
screen and never deeper, so it cannot produce the tail the source has, and the mean follows
from that rather than from the rate.

**All three are residuals for the retune, [#49](https://github.com/knissley/football-manager/issues/49),
and nothing here should be chased by a fix** (CLAUDE.md rule 9). Whether the concept set is
the mechanism — whether a swing pass, a checkdown into the flat or a jet look ought to be
able to be caught behind the line, rather than only a screen — is a separate question, and
this release labels no concept, so nothing here answers it.

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
5. Re-take the noise sweep and regenerate [the floor table](#every-graded-row-with-its-floor)
   — `scripts/harness-noise.py --sweep` then `--report`. A new row has no floor until it is
   measured, and the *edge margin* column of every existing row is read against the band it
   had when the sweep was taken, so a moved band leaves that column quietly stale.

A band the harness cannot measure skips steps 2 and 3 and lands in the test instead: derive
it with the script, put the band and its citation in the test's name and doc comment, and
add it to [the table above](#bands-the-harness-cannot-measure) naming that test. It is not a
`row:` and must not be written as one — `InvariantsTraceabilityTests` reads every `row:` in
this file as a claim that `Targets.swift` carries it.

A figure the harness *could* grade but nobody has decided to skips steps 2 to 5 as well:
derive it with the script, record it with its seasons, its source and the band the policy
gives, and say in as many words that it is not a row. The same rule about `row:` applies,
for the same reason. Grading it later is then steps 2 to 5 and nothing else, because the
derivation is already on file.


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

**Who rushes, and who is there to block him.** C5 (#45) takes the rush from the call's own
count out of the eleven on the field rather than from the four men on the ball, drops a
lineman and sends a linebacker on a zone blitz, takes the men sent out of the coverage they
left, and keeps a back in for the rusher the line has nobody for. None of it is sourced and
none of it can be from what this file reads: where an extra rusher comes from, who picks
him up, and which of the five eligibles stays in are coaching design of the same kind as the
read order below — not a rule and not a rate, and no feed publishes a protection call. It
is stated as such under *Pass play* in [`../match-engine.md`](../match-engine.md) and graded
by what it produces: `row:pressureRate` and `row:sackRate` above, which are pooled over
every dropback there is and split by nothing, so neither can say whether a five-man pressure
should pressure more often than a four-man one. What the suite asserts instead is the
resolver's own promise — the count a call names is the count that comes
(`test:aCallResolvesARepForEveryManItSends`) — and the one thing the rulebook does decide,
which is that the eleven have eleven jobs between them and no man both rushes and covers
(2025 rulebook, 5-1-1; `test:noDefenderRushesAndCoversTheSameSnap`).

A band becomes wanted the day somebody means to set the pressure a blitz produces against
the pressure a four-man rush produces. The derivation would be S2's pressure flag split by
the rusher count the same release carries, if it carries one — **not checked here** — and it
would want a blitz-rate figure beside it, because a rate conditioned on a call the engine
calls on 3.7% of dropbacks says as much about the caller as about the rush.

**The read order, and everything the passer does with it.** C3 (#44) has the quarterback
work a read order per pass family — who first, who second, at what break, how deep — on a
perceived separation that carries his own error, against a threshold set by the depth of
the throw (`ReadProgression` and `CrudeResolver.Reads`, decided on
[#169](https://github.com/knissley/football-manager/issues/169)). None of it is sourced and
none of it can be from what this file reads: a read order is coaching design, not a rule and
not a rate, and no feed carries a passer's error or the window he judged. It is authored,
stated as such in the file that holds it and under *Pass play* in
[`../match-engine.md`](../match-engine.md), and graded by what it produces — the passing
rows above, the unbanded rows in the catch section, and target share by position group,
which E8 (#179) banded. Every number in it is a starting value in the sense of the arrival
window's, retuned in E3 (#49) and not before; the thresholds moved twice before they landed,
for a reason measured and recorded in the same section of the match-engine doc.

Worth doing only when something turns on it, and today nothing does. What the suite asserts
about the hold is `test:pressureIsTheArrivalBeatingTheBallOut` and
`test:theArrivalWindowSpansTheRouteHolds`, and both are `.contract` — a dropback is
pressured exactly when the first man home arrived before the record's own ball-out moment,
snap by snap off the same rush, and every read's break has arrivals on both sides of it.
Both follow from the resolver's own definition of pressure and need no band. The ball-out
moment is the break of the read the quarterback threw to (`ReadProgression`, C3 #44), which
is why the first of those is no longer the chain of concept holds it used to be: a family
has no single hold any more. A band becomes wanted the day somebody means to separate two holds on purpose, or to
shape the arrival from a season rather than from the model: either is a modelling change, it
would move `row:pressureRate` with it, and it should not be made on the strength of a figure
nobody computed.


## The measured noise floor

Every band above says where a row *should* land. Nothing said how far a row moves **when
nothing changes**, and that is the number every review of a moved row actually needs. It
was assumed rather than measured — "rates are binomial, counts are Poisson, so this
interaction is smaller than the noise" — and that assumption dismissed candidate rows on
branch after branch. This section is the measurement.

The sweep is `scripts/harness-noise.py --sweep`; its raw output is
[`harness-noise-sweep.tsv`](harness-noise-sweep.tsv) beside this file, which names the
commit it was taken on, the machine, and each contiguous chunk of runs. **The floors below
were taken on the tree that landed C3 (#44): `97992f8` with the working tree the sweep's
header names, which became the commit after it — at 30 seeds (1 to 30), 400 games each.**
Re-take them after any change that moves engine behaviour; the sweep is about eleven
minutes of release compute. The sweep before this one was taken on `367bd12`, and every
figure below that names a row was re-read from this one.

### What a seed changes, and why one number is not enough

`simharness` takes one `--seed`, and that seed does **two** things: it generates the world
— rosters, schemes, stadiums, who is good — and it seeds every game's weather and play
draws. **There is no flag that holds the world fixed and varies only the draws**, so a
plain seed-to-seed spread is a *combined* figure and calling it sampling noise is wrong.

The two are separated without changing the harness. Every per-game quantity in the run
loop is derived from the loop index alone, so a 200-game run is exactly the first 200
games of the 400-game run at the same seed — same league, same games, same draws. The
difference between the two is therefore a contrast in which the league cancels, and its
spread across seeds is the run's own sampling error. Three columns follow:

| column | what it is | when it is the floor you want |
| --- | --- | --- |
| **σ same league** | how far the row moves when the games are redrawn in **one** league | a before-and-after at a fixed seed — which is what the backlog's own rule runs |
| **σ league** | how far the row moves because the league is a different league | it never moves alone; it is the part more games cannot remove |
| **σ seed-to-seed** | the two together | comparing two seeds, or any change that moves the generated world |

A before-and-after at one seed resamples the draws twice, so the floor for the **difference**
is `σ same league × √2`, not `σ same league`.

**That the split is real, and not an artefact of the estimator, has its own check that does
not use the estimator at all.** Sampling error falls as `1/√games`; world-to-world variation
does not fall with games at all, because a longer run plays more games in the *same* league.
So take the plain cross-seed spread at each of the three game counts and read the ratio
`σ(100 games) / σ(400 games)`: **2.00 is a purely-sampling row, 1.00 is a purely-league row.**
Over the 147 rows that have all three counts the median is **1.55**, quartiles 1.24 and 1.81,
range 0.88 to 2.71 — 38 rows at or above 1.80 and 32 at or below 1.20. Almost every row is a
mixture, which is what the two columns say, and a handful sit at each pure extreme.
`row:targetShare.wideReceiver` at 0.88, `row:firstReadShare` at 0.94 and
`row:checkdownsPerDropback` and `row:throwawaysPerDropback` at 0.97 do not narrow with a
longer run — who a league's passers throw to is a fact about its rosters;
`row:outOfBoundsShare` at 2.71, `row:fieldGoalsUnder30` at 2.60 and
`row:runShare.thirdMedium` at 2.59 narrow with it as a coin would. `scripts/harness-noise.py
--summary` prints this block first.

### What the sweep found

**Seventy-one rows print a different verdict at different seeds.** Not a different value —
a different `ok`/`OFF` mark, on an unchanged tree. `row:yardsPerCarry` reads 4.10 to 5.00
against a band of 3.90–4.60; `row:runShare.fourthMedium` reads 9.20 to 21.00 against
0.90–11.50. For those rows a verdict is a fact about the seed, not about the engine.

**Of what?** 150 rows print a value at 400 games, but only **132** of them carry a pass/fail
grade: the other eighteen print `stale` or `unsourced`, which is a statement about the band's
provenance and cannot change with the seed. So the share is **71 of 132, 54%** — 41 rows are
`OFF` at all thirty seeds, 20 are `ok` at all thirty, and the rest are neither. Quote the 132
denominator: `71/150` counts eighteen rows that are constant by construction and understates
the finding.

On the sweep before, taken in C3
([#44](https://github.com/knissley/football-manager/issues/44))'s commit, it was 69 of 113.
The denominator gained nineteen rows: the sixteen E2 added, and
`row:targetShare.wideReceiver`, `row:targetShare.tightEnd` and `row:targetShare.runningBack`,
which carried no band when that sweep was taken. Of E2's sixteen, eight flip, seven are `OFF`
at all thirty seeds and one — `row:outOfBoundsShare` — is `ok` at all thirty.

**The rest of the movement is not E2's and is not attributed to it.** #89 and #97 both landed
beneath this sweep, and #97 resamples about half the games at every seed, so a row can join or
leave the flip list without anything about it changing. Four joined that are not E2's
(`row:fieldGoals30to39`, `row:penalty.delayOfGame`, `row:safeties`,
`row:targetShare.runningBack`) and ten left (`row:drives4to7`, `row:fieldGoalAttempts40to49`,
`row:fumblesKept`, `row:kickReturnTouchdowns.2025`, `row:penalty.illegalFormation`,
`row:snaps.backfield`, `row:snaps.offensiveLine`, `row:snaps.quarterback`, `row:tiesPerGame`,
`row:ypcOutnumberingByOne`). Which of those are the coin toss and which the overtime endgame
is not separated here, and neither is E2's: E2 moved no engine behaviour, and no band moved.

### The two sets this does *not* conflate

"Flipped in 30 seeds" and "its spread crosses its own band edge" are different questions and
the answers only partly overlap. A row can flip on one outlying seed with its mean a
comfortable distance from the edge, and a row can sit half a floor from an edge and happen
not to cross it in thirty draws. Both are reported, separately:

| set | how it is defined | rows |
| --- | --- | --- |
| **flipped** | more than one `ok`/`OFF` mark across the thirty seeds — an *observed* crossing | 71 |
| **edge margin under one floor** | the mean is within one `σ seed-to-seed` of the nearer band edge — a *predicted* crossing | 45 |
| both | | 40 |
| flipped with a margin of a floor or more | | 31 |
| margin under a floor, never seen to flip | | 5 |

Seventy-six distinct rows are in one set or the other. Neither number is the other's proxy, and
a review that wants "will this row's verdict be stable" wants the union.

**The 71 that flipped**, in full — this is the list
[#108](https://github.com/knissley/football-manager/issues/108) is cross-referenced to. That
issue made the printed column carry enough digits to agree with its own verdict; this one
says which rows will disagree with *yesterday's* verdict anyway, on an unchanged tree:

`row:averageStart.2025`, `row:betweenTeamSigma`, `row:carries10plus`,
`row:carries20plus`, `row:carries2orFewer`, `row:carriesStuffed`,
`row:completionPercentage`, `row:completionsZeroOrFewer`,
`row:defensiveReturnTouchdowns`, `row:driveEndDowns`, `row:driveEndPunt`,
`row:driveEndTouchdown`, `row:drives3orFewer`, `row:drives8plus`, `row:dropback40plus`,
`row:fieldGoalAttemptsUnder30`, `row:fieldGoals30to39`, `row:fieldGoals40to49`,
`row:fieldGoals50plus`, `row:fieldGoalsPerTeamGame`, `row:firstDownGain`,
`row:firstDownsPerTeamGame`, `row:fourthAndOneWentForIt`, `row:fourthDownAttempts`,
`row:fourthDownConversion`, `row:fourthDownKicked`, `row:fourthDownPunted`,
`row:fourthDownWentForIt`, `row:fumblesLost`, `row:gamesBy14plus`, `row:gamesWithin3`,
`row:gamesWithin7`, `row:interceptionRate`, `row:kickoffTouchbacks.2025`,
`row:marginSigma`, `row:nonOffensiveTouchdowns.2025`, `row:onsideKicks.2025`,
`row:onsideRecovery.2025`, `row:overtimeLength`, `row:overtimeRate`,
`row:packageNickel`, `row:penalty.defensivePassInterference`,
`row:penalty.delayOfGame`, `row:penalty.falseStart`, `row:playsPerDrive`,
`row:playsPerGame`, `row:points`, `row:pointsFromFieldGoals`,
`row:pointsFromTouchdowns`, `row:preSnapRoadVsHome`, `row:pressureRate`,
`row:puntsPerTeamGame`, `row:redZoneTouchdownRate`, `row:redZoneTripsPerTeamGame`,
`row:runShare.fourthLong`, `row:runShare.fourthMedium`, `row:runShare.secondMedium`,
`row:runShare.secondShort`, `row:runShare.thirdLong`, `row:safeties`,
`row:snaps.defensiveBack`, `row:snapsInsideOwn10`, `row:targetShare.runningBack`,
`row:thirdDownDistance`, `row:threeAndOut`, `row:turnovers`, `row:twoPointTries`,
`row:twoPointTriesPass`, `row:twoPointTriesRun`, `row:yardsPerCarry`,
`row:ypcEvenCount`.

**The five with a margin under one floor that were not seen to flip** — the ones to expect
next, since thirty seeds is not many: `row:heavyRainPoints` (0.1 floors),
`row:playerGamesLost` (0.1), `row:onsideRecovery.2024` (0.3),
`row:kickReturnTouchdowns.2024` (0.5) and `row:onsideKicks.2024` (0.6). All five are `stale` or
`unsourced` rows, which is why no `ok`/`OFF` mark moved: the margin is real, the verdict
column simply does not report it.

`scripts/harness-noise.py --summary` prints the 71 with each row's range and band, and the
five with their margins. The 45 are not a list of their own there — read them off the *edge
margin* column of the table below, which is where the number comes from.

**The binomial/Poisson model is a good description of the same-league floor and a poor one
of the seed-to-seed floor.** Against the same-league floor the ratio is a median 1.00, and
**one** row of 86 is outside a factor of two: `row:points` at 2.15, because points arrive in
threes and sevens and a Poisson count of them under-states the spread by exactly that much.
Against the seed-to-seed floor the median is 1.40 and **twenty-two of 85 rows are outside a
factor of two**. The model has no term for the league, so the further a comparison crosses
worlds the more optimistic it gets. All twenty-one, since a row not named here is a row
whose model a reviewer may still reach for — every one of them is *under*-stated by the
model, and the carry family is the worst of it:

`row:carries2orFewer` 6.53×, `row:carriesStuffed` 5.13×, `row:completionPercentage` 4.85×,
`row:dropbackNoGain` 4.57×, `row:points` 4.56×, `row:carries10plus` 4.31×,
`row:dropback10plus` 3.47×, `row:firstDownsPerTeamGame` 3.30×, `row:driveEndTouchdown` 3.29×,
`row:puntsPerTeamGame` 2.89×, `row:carries20plus` 2.86×, `row:pressureRate` 2.73×,
`row:snaps.frontSeven` 2.62×, `row:snaps.defensiveBack` 2.60×, `row:driveEndPunt` 2.54×,
`row:snapsInsideOwn10` 2.50×, `row:snaps.offensiveLine` 2.44×, `row:drives8plus` 2.22×,
`row:drives3orFewer` 2.16×, `row:snaps.receiver` 2.11×, `row:threeAndOut` 2.10× and
`row:interceptionRate` 2.07×.

The near-misses in the same-league column are worth naming because they are the rows where
games are not independent within a league: `row:snaps.frontSeven` 1.59,
`row:snaps.defensiveBack` 1.54 and `row:snaps.offensiveLine` 1.44 all sit about half again
above the model. Four rows sit *below* it — `row:snaps.quarterback` 0.65,
`row:playsFromScrimmage` 0.66, and `row:snaps.backfield` and `row:drivesPerTeamGame` 0.68
— most of them because they
count something a play produces once by construction, and a Poisson count of a
near-deterministic quantity over-states.

**Thirty-two rows move mostly because the league moved**, not because the games did —
counting the rows whose `σ league` is at least twice their `σ same league`:
`row:checkdownsPerDropback` and `row:targetShare.runningBack` 5.8 to one,
`row:targetShare.wideReceiver` 4.9, `row:carries2orFewer` 4.8, `row:firstDownGain` 4.7,
`row:yardsPerCarry` 4.6, `row:rushingYards` 4.5. The read rows are the league's from
the first sweep they appear in: who gets thrown to is who the rosters are, and a longer run
in one league cannot move it. This is the one that changes what to do about a wide row. The
league component **does not shrink with `--games` at all** — a longer run plays more games in
the *same* league — so for those rows `--games 1000` buys nothing a reviewer wants. What
buys it is more seeds.

**`--games` has a number per row now, not folklore.** `scripts/harness-noise.py --summary`
prints, for each row whose band is narrower than the four floors a seed needs to land inside
it reliably, the games that would close the gap — 402 for `row:onsideRecovery.2025`, 556
for `row:nonOffensiveTouchdowns.2025` and 560 for `row:nonOffensiveTouchdowns.2024`, 614 for
`row:onsideRecovery.2024`,
807 for `row:fieldGoals50plus`, 816 for `row:tiesPerGame`, 1,253 for `row:overtimeLength` —
or **more seeds** for the nineteen where no number of games will: `row:rushingYards`,
`row:yardsPerCarry`, `row:interceptionRate`, `row:pointsFromFieldGoals`, `row:ypcEvenCount`,
`row:ypcOutnumberingByOne`, `row:carriesStuffed`, `row:carries2orFewer`,
`row:carries10plus`, `row:carries20plus`, `row:dropbackNoGain`, `row:driveEndTouchdown`,
`row:onsideKicks.2025`, `row:onsideKicks.2024`, `row:marginSigma`, `row:betweenTeamSigma`,
`row:penalty.defensiveHolding`, `row:penalty.offside` and
`row:penalty.neutralZoneInfraction`. The weather rows
are the one place the folklore could not be checked: `row:heavyRainPoints` has too few rain
games in a 200-game run for the sweep to give it a same-league figure at all, so
`--games 1000` there remains an instinct rather than a measurement.

**Thirty-seven rows carry a band narrower than four floors**, which means a seed can land outside
the band with the engine exactly on target. That is a finding for the retune
([#49](https://github.com/knissley/football-manager/issues/49)), not something to fix here:
nothing in this section moves a band, a target or engine behaviour.

### What to do with a row that moved

The rule is in [`../match-engine.md#calibration`](../match-engine.md#calibration), which is
where a reviewer will be standing. In short: compare the move against the floor for the
comparison that was actually run, and say which floor that was.

### How to read the table

- Every figure is in the row's own printed units. The sweep reads the printed table —
  `simharness` has no machine-readable mode — so each reading carries the rounding of its own
  last digit, and each σ has that rounding's variance removed before it is printed here
  (Sheppard's correction). **A row's display precision is not constant across seeds**: since
  [#108](https://github.com/knissley/football-manager/issues/108) a row graded outside its
  band prints the decimals that put it outside, so the correction is applied per reading
  rather than per row.
- **σ from printing** is that rounding expressed as a σ — `q/√12` for the row's own last
  digit, about **0.029 for a row printed to 0.1** — and it is published beside every measured
  σ so that no floor here has to be taken on trust that it is measuring the engine. Read the
  two together: a σ comfortably above this column is a property of the engine, a σ near it is
  mostly a property of the display. It varies by row and, since
  [#108](https://github.com/knissley/football-manager/issues/108), within a row, because a
  row graded outside its band prints extra digits; the column is the average over the thirty
  readings. The rows to look at before trusting a small same-league σ are the ones where the
  floor is more than half the σ beside it: **`row:firstDownGain`** (floor 0.03, σ 0.05),
  **`row:yardsPerPlay`** and **`row:fourthDownAttempts`** (0.03 against 0.04),
  **`row:safeties`** and **`row:kickReturnTouchdowns.2024`** (0.003 against 0.005) — each a
  real measurement, but only just — and **`row:yardsPerCarry`** and **`row:playsPerDrive`**,
  whose same-league σ sits at the printed resolution and carries the † below.
  **`row:playsPerGame`** and **`row:overtimeLength`** are the two rows printed as whole
  numbers, so they carry the largest floor in the table at 0.26 and 0.29; for
  `row:playsPerGame` that is two fifths of its 0.69 σ.
- **†** marks a σ whose raw spread was not more than twice the rounding removed from it.
  Read it as an upper bound; the row's real floor is somewhere below the printed column's
  resolution. Two rows are in that state on both σ — `row:spikesPerGame` and
  `row:interferenceOnCompletions` — and two more on the same-league σ alone,
  `row:yardsPerCarry` and `row:playsPerDrive`, which a resample of one league's games moves
  by less than the tenth of a yard the column prints.
- **σ league** is `sqrt(σ seed-to-seed² − σ same league²)`, floored at zero. Eleven rows come
  back with the same-league figure at or above the seed-to-seed one; for those the league's
  share is not distinguishable from zero at 30 seeds, and `0.00` means exactly that rather
  than a measurement. `row:overtimeLength` is the one gross case — it averages about a dozen
  overtime games in 400, so its difference contrast is heavy-tailed and its split should not
  be read at all.
- **edge margin** is the distance from the mean to the nearer band edge, in seed-to-seed σ.
  Under one is a row whose ordinary spread reaches its own edge. It divides by the **raw**
  seed-to-seed spread, before the rounding correction — so it is a shade smaller than
  dividing by the published *σ seed-to-seed* column would give, and errs towards flagging a
  row rather than clearing it. **This column and nothing else in this file depends on a
  band**, so a retune that moves a band leaves it stale; the fix is to re-run the sweep, not
  to edit a number.
- **verdicts seen** lists every mark the row printed across the 30 seeds. More than one is a
  verdict that is not a property of the engine.
- A row with no model σ has a reason, and `scripts/harness-noise.py` carries it by name:
  either no naive model describes the quantity (a ratio of two sums, a standard deviation,
  a share of points) or the harness prints no trial count to model against
  (`row:thirdDownConversion`, `row:redZoneTouchdownRate`, `row:extraPointsMade`,
  `row:fourthAndOneWentForIt`, `row:dropsPerTarget`, `row:interferenceOnCompletions`).

### How far to trust these numbers

Three checks, each measured rather than argued:

1. **The estimator against a known answer.** `scripts/harness-noise.py --self-test` builds a
   synthetic sweep whose league and sampling components are set by hand and requires the
   decomposition to recover both to within 1%. It runs in CI.
2. **The estimator against itself.** A 100-game prefix is a longer lever arm on the same
   quantity than a 200-game prefix, and the two must give the same σ once the lever is
   divided out. Over 144 rows the ratio is a median 1.02 and **nothing** is outside a factor
   of two; two rows disagree by more than 1.4, `row:fieldGoalAttempts40to49` at 1.41 and
   `row:runShare.thirdShort` at 0.71.
3. **The floor against a disjoint set of seeds.** The same sweep at seeds 31–60 is committed
   beside the published one as
   [`harness-noise-replication.tsv`](harness-noise-replication.tsv) — taken in the same
   commit as the published sweep, from the same binary. This check can be re-run without
   eleven minutes of compute:

   ```bash
   python3 scripts/harness-noise.py --replicate docs/reference/harness-noise-replication.tsv
   ```

   It gives a median ratio of **0.96** for the seed-to-seed floor over 147 rows (range
   0.63–1.65) and **1.00** for the same-league floor over 143 (range 0.60–1.57), with
   **nothing** outside a factor of two either way. A σ from 30 seeds carries about 13% of
   its own error, so agreement to a few per cent in the median is what this should
   reproduce to, and the tails are the size a 30-seed σ's own error predicts.

What is **not** checked: the floors are from one machine and one toolchain, and a row whose
value differs in the last bit between architectures would have a different floor there. The
sweep has not been run on arm64. Nor is the replication a check on the *harness* — both
sweeps were taken from one binary on one machine, so what it reproduces is that a floor is a
property of the row rather than of the thirty seeds it was read from.

### Every graded row, with its floor

Generated by `scripts/harness-noise.py --report` from the committed sweep. Regenerate it
in the same commit as any change that moves engine behaviour.

**Re-taken in the same commit as the sixteen rows E2 added**, on the merge of
[#97](https://github.com/knissley/football-manager/issues/97), which draws the coin toss and
so resamples about half the games at each seed — and of
[#89](https://github.com/knissley/football-manager/issues/89) beneath it, which moved the tie
rate and the two overtime rows. The sweep before was stale for both reasons whatever E2 did.
E2 itself moved no engine behaviour: it changed what the harness derives, not what the games
do, and every pre-existing graded row printed the same value at both calibration seeds on
either side of it. Every row added here is measured here, and no row is owed.

**150 of the 152 rows in `Targets.swift` are here. The two that are not have no spread
because they have no value**: `row:winTotalSigma` and `row:ypcOutnumberedByOne` print `—`
and grade `n/a` at every one of the thirty seeds. The harness says why for the first —
it wants a season played to a schedule rather than arbitrary matchups, and that is M3's —
and for the second the reason is in the block above it, which now prints a carry count for
every bucket that has one and takes a mean only above two hundred: the outnumbered bucket
holds about twenty carries a seed, which is a sample too thin to average rather than no
sample at all. A row with no reading cannot have a floor; when either starts printing a
number, the tool picks it up with no change to it. `row:heavyRainPoints` is a third,
partial case: it prints a value at 400 games but not at 200, so it has a
seed-to-seed σ and no same-league split, which is why its two component columns are `—`.

<!-- harness-noise:start -->
| row | mean | min–max | σ seed-to-seed | σ same league | σ league | σ from printing | model σ | same league / model | seed-to-seed / model | edge margin | verdicts seen |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `row:points` | 23.75 | 22.40–25.60 | 0.79 | 0.37 | 0.69 | 0.03 | 0.17 | 2.15x | 4.56x | 0.4 | OFF ok |
| `row:passingYards` | 203.87 | 188.30–213.60 | 6.07 | 2.16 | 5.68 | 0.03 | — | — | — | 2.9 | OFF |
| `row:rushingYards` | 143.37 | 127.00–155.00 | 8.10 | 1.74 | 7.91 | 0.03 | — | — | — | 4.1 | OFF |
| `row:yardsPerCarry` | 4.61 | 4.10–5.00 | 0.24 | 0.05 | 0.23 | 0.03 | — | — | — | 0.0 | OFF ok |
| `row:completionPercentage` | 62.01 | 58.60–64.80 | 1.45 | 0.35 | 1.40 | 0.03 | 0.30 | 1.18x | 4.85x | 0.6 | OFF ok |
| `row:sackRate` | 3.73 | 3.40–4.00 | 0.14 | 0.11 | 0.08 | 0.03 | 0.11 | 1.00x | 1.21x | 16.9 | OFF |
| `row:interceptionRate` | 2.68 | 2.30–3.10 | 0.21 | 0.10 | 0.18 | 0.03 | 0.10 | 1.01x | 2.07x | 0.4 | OFF ok |
| `row:thirdDownConversion` | 34.75 | 33.20–36.68 | 0.95 | 0.41 | 0.85 | 0.03 | — | — | — | 2.1 | OFF |
| `row:playsFromScrimmage` | 67.50 | 66.80–68.10 | 0.31 | 0.19 | 0.25 | 0.03 | 0.29 | 0.66x | 1.08x | 3.8 | OFF |
| `row:penaltiesPerGame` | 15.15 | 14.50–15.70 | 0.33 | 0.21 | 0.25 | 0.03 | 0.19 | 1.06x | 1.67x | 5.1 | OFF |
| `row:thirdDownDistance` | 7.33 | 7.20–7.50 | 0.09 | 0.03 † | 0.09 | 0.03 | — | — | — | 0.7 | OFF ok |
| `row:firstDownGain` | 5.08 | 4.80–5.30 | 0.15 | 0.03 † | 0.14 | 0.03 | — | — | — | 0.1 | OFF ok |
| `row:yardsPerAttempt` | 6.17 | 5.80–6.50 | 0.18 | 0.06 | 0.17 | 0.03 | — | — | — | 2.3 | OFF |
| `row:yardsPerPlay` | 5.03 | 4.80–5.30 | 0.12 | 0.00 † | 0.12 | 0.03 | — | — | — | 1.9 | ok |
| `row:yardsPerCompletion` | 9.93 | 9.60–10.20 | 0.13 | 0.08 | 0.10 | 0.03 | — | — | — | 2.7 | OFF |
| `row:dropsPerTarget` | 10.23 | 9.40–10.90 | 0.39 | 0.17 | 0.35 | 0.03 | — | — | — | — | unsourced |
| `row:passesDefensedPerGame` | 5.131 | 4.680–5.440 | 0.186 | 0.127 | 0.136 | 0.003 | 0.113 | 1.12x | 1.64x | — | unsourced |
| `row:throwawaysPerDropback` | 6.12 | 5.00–7.10 | 0.55 | 0.12 | 0.54 | 0.03 | — | — | — | — | unsourced |
| `row:checkdownsPerDropback` | 14.39 | 11.40–17.20 | 1.29 | 0.22 | 1.27 | 0.03 | — | — | — | — | unsourced |
| `row:firstReadShare` | 83.67 | 81.20–86.10 | 1.08 | 0.30 | 1.04 | 0.03 | — | — | — | — | unsourced |
| `row:targetShare.wideReceiver` | 68.55 | 64.30–72.60 | 1.91 | 0.38 | 1.87 | 0.03 | — | — | — | 2.9 | OFF |
| `row:targetShare.tightEnd` | 8.85 | 7.90–9.70 | 0.49 | 0.25 | 0.42 | 0.03 | — | — | — | 23.0 | OFF |
| `row:targetShare.runningBack` | 22.59 | 18.90–26.20 | 1.64 | 0.28 | 1.61 | 0.03 | — | — | — | 1.8 | OFF ok |
| `row:runShare.secondShort` | 67.19 | 65.00–68.80 | 1.12 | 1.27 | 0.00 | 0.03 | — | — | — | 1.8 | OFF ok |
| `row:runShare.secondMedium` | 51.82 | 50.10–53.10 | 0.76 | 0.65 | 0.39 | 0.03 | — | — | — | 0.3 | OFF ok |
| `row:runShare.secondLong` | 22.57 | 21.80–23.70 | 0.45 | 0.40 | 0.20 | 0.03 | — | — | — | 7.5 | OFF |
| `row:runShare.thirdShort` | 94.11 | 93.20–95.00 | 0.47 | 0.55 | 0.00 | 0.03 | — | — | — | 89.6 | OFF |
| `row:runShare.thirdMedium` | 21.88 | 20.50–23.30 | 0.70 | 0.83 | 0.00 | 0.03 | — | — | — | 16.5 | OFF |
| `row:runShare.thirdLong` | 9.50 | 8.40–10.60 | 0.46 | 0.39 | 0.25 | 0.03 | — | — | — | 0.9 | OFF ok |
| `row:runShare.fourthShort` | 90.28 | 87.10–92.90 | 1.15 | 0.81 | 0.81 | 0.03 | — | — | — | 28.6 | OFF |
| `row:runShare.fourthMedium` | 15.02 | 9.20–21.00 | 3.11 | 2.71 | 1.54 | 0.03 | — | — | — | 1.1 | OFF ok |
| `row:runShare.fourthLong` | 4.78 | 0.90–10.60 | 2.02 | 1.95 | 0.50 | 0.03 | — | — | — | 1.4 | OFF ok |
| `row:playsPerGame` | 169.64 | 168.00–171.00 | 0.92 | 0.61 | 0.69 | 0.26 | 0.65 | 0.93x | 1.42x | 0.4 | OFF ok |
| `row:tiesPerGame` | 0.0039 | 0.0000–0.0100 | 0.0029 | 0.0033 | 0.0000 | 0.0003 | 0.0031 | 1.04x | 0.93x | 1.3 | ok |
| `row:overtimeRate` | 3.12 | 1.00–5.00 | 1.04 | 0.87 | 0.57 | 0.03 | 0.87 | 1.00x | 1.20x | 0.1 | OFF ok |
| `row:overtimeLength` | 411.87 | 309.00–515.00 | 45.05 | 50.44 | 0.00 | 0.29 | — | — | — | 1.1 | OFF ok |
| `row:playerGamesLost` | 90.70 | 79.80–99.40 | 5.21 | 5.21 | 0.00 | 0.03 | — | — | — | 0.1 | unsourced |
| `row:scramblesPerGame` | 2.08 | 1.80–2.20 | 0.10 | 0.07 | 0.07 | 0.03 | 0.07 | 0.98x | 1.34x | 14.1 | OFF |
| `row:kneelsPerGame` | 1.61 | 1.50–1.70 | 0.07 | 0.07 | 0.01 | 0.03 | 0.06 | 1.10x | 1.11x | 2.5 | ok |
| `row:spikesPerGame` | 0.20 | 0.10–0.30 | 0.00 † | 0.02 † | 0.00 | 0.03 | 0.02 | 0.96x | — | 3.8 | ok |
| `row:timeoutsPerGame` | 5.12 | 4.80–5.50 | 0.16 | 0.09 | 0.14 | 0.03 | 0.11 | 0.79x | 1.43x | 12.0 | OFF |
| `row:outOfBoundsShare` | 13.53 | 13.20–13.90 | 0.18 | 0.17 | 0.05 | 0.03 | — | — | — | 4.6 | ok |
| `row:outOfBoundsShareTrailingLate` | 32.46 | 30.10–34.70 | 0.92 | 1.18 | 0.00 | 0.03 | — | — | — | 11.3 | OFF |
| `row:pointsFromTouchdowns` | 68.72 | 66.80–71.40 | 1.07 | 0.43 | 0.98 | 0.03 | — | — | — | 1.3 | OFF ok |
| `row:pointsFromFieldGoals` | 19.90 | 17.00–21.90 | 1.17 | 0.51 | 1.06 | 0.03 | — | — | — | 1.0 | OFF ok |
| `row:personnel11` | 67.03 | 66.30–67.50 | 0.25 | 0.16 | 0.19 | 0.03 | 0.20 | 0.79x | 1.24x | 18.8 | ok |
| `row:packageNickel` | 69.14 | 68.60–69.70 | 0.24 | 0.18 | 0.16 | 0.03 | 0.20 | 0.89x | 1.21x | 0.3 | OFF ok |
| `row:packageBase` | 23.35 | 22.90–23.70 | 0.24 | 0.17 | 0.16 | 0.03 | 0.18 | 0.94x | 1.29x | 7.0 | ok |
| `row:ypcEvenCount` | 4.91 | 4.40–5.30 | 0.25 | 0.06 | 0.25 | 0.03 | — | — | — | 0.4 | OFF ok |
| `row:ypcOutnumberingByOne` | 5.42 | 4.92–6.30 | 0.32 | 0.22 | 0.23 | 0.03 | — | — | — | 1.6 | OFF |
| `row:snaps.quarterback` | 67.50 | 66.81–68.10 | 0.31 | 0.19 | 0.25 | 0.03 | 0.29 | 0.65x | 1.07x | 2.2 | OFF |
| `row:snaps.backfield` | 73.08 | 72.40–73.60 | 0.34 | 0.20 | 0.27 | 0.03 | 0.30 | 0.68x | 1.11x | 2.0 | OFF |
| `row:snaps.receiver` | 182.96 | 180.60–185.20 | 1.01 | 0.63 | 0.79 | 0.03 | 0.48 | 1.31x | 2.11x | 11.8 | OFF |
| `row:snaps.tightEnd` | 81.36 | 80.50–82.10 | 0.34 | 0.25 | 0.24 | 0.03 | 0.32 | 0.78x | 1.07x | 12.4 | ok |
| `row:snaps.offensiveLine` | 336.24 | 333.00–339.20 | 1.58 | 0.93 | 1.27 | 0.03 | 0.65 | 1.44x | 2.44x | 2.1 | OFF |
| `row:snaps.frontSeven` | 418.87 | 415.00–422.10 | 1.89 | 1.15 | 1.50 | 0.03 | 0.72 | 1.59x | 2.62x | 7.3 | OFF |
| `row:snaps.defensiveBack` | 323.56 | 319.90–327.00 | 1.65 | 0.98 | 1.33 | 0.03 | 0.64 | 1.54x | 2.60x | 0.2 | OFF ok |
| `row:carriesStuffed` | 18.87 | 17.00–21.30 | 1.27 | 0.33 | 1.23 | 0.03 | 0.25 | 1.33x | 5.13x | 0.8 | OFF ok |
| `row:carries2orFewer` | 42.50 | 39.50–46.80 | 2.04 | 0.42 | 2.00 | 0.03 | 0.31 | 1.35x | 6.53x | 0.9 | OFF ok |
| `row:carries10plus` | 11.54 | 9.70–13.00 | 0.87 | 0.22 | 0.84 | 0.03 | 0.20 | 1.07x | 4.31x | 0.4 | OFF ok |
| `row:carries20plus` | 2.82 | 2.20–3.40 | 0.30 | 0.10 | 0.28 | 0.03 | 0.10 | 0.96x | 2.86x | 1.1 | OFF ok |
| `row:dropbackLoss` | 4.93 | 4.70–5.20 | 0.12 | 0.12 | 0.04 | 0.03 | 0.13 | 0.91x | 0.96x | 18.0 | OFF |
| `row:dropbackNoGain` | 37.58 | 35.10–40.40 | 1.32 | 0.33 | 1.28 | 0.03 | 0.29 | 1.13x | 4.57x | 2.3 | OFF |
| `row:dropback10plus` | 21.64 | 19.70–23.60 | 0.85 | 0.22 | 0.82 | 0.03 | 0.24 | 0.91x | 3.47x | 2.5 | OFF |
| `row:dropback20plus` | 6.53 | 5.90–7.10 | 0.26 | 0.14 | 0.22 | 0.03 | 0.15 | 0.94x | 1.76x | 4.5 | OFF |
| `row:dropback40plus` | 1.40 | 1.20–1.60 | 0.10 | 0.09 | 0.05 | 0.03 | 0.07 | 1.22x | 1.44x | 1.0 | OFF ok |
| `row:pressureRate` | 26.86 | 25.40–28.00 | 0.72 | 0.31 | 0.65 | 0.03 | 0.26 | 1.16x | 2.73x | 1.3 | OFF ok |
| `row:sacksPerPressure` | 13.90 | 13.10–14.80 | 0.37 | 0.32 | 0.20 | 0.03 | — | — | — | 16.3 | OFF |
| `row:completionsZeroOrFewer` | 5.69 | 5.30–6.10 | 0.23 | 0.17 | 0.16 | 0.03 | 0.18 | 0.91x | 1.25x | 0.4 | OFF ok |
| `row:driveEndPunt` | 39.51 | 37.00–41.80 | 1.31 | 0.50 | 1.21 | 0.03 | 0.51 | 0.98x | 2.54x | 0.4 | OFF ok |
| `row:driveEndTouchdown` | 22.57 | 20.30–26.10 | 1.45 | 0.36 | 1.40 | 0.03 | 0.44 | 0.82x | 3.29x | 0.8 | OFF ok |
| `row:driveEndDowns` | 4.82 | 4.20–5.70 | 0.36 | 0.24 | 0.27 | 0.03 | 0.23 | 1.05x | 1.58x | 0.3 | OFF ok |
| `row:drivesPerTeamGame` | 11.28 | 10.90–11.60 | 0.20 | 0.08 | 0.18 | 0.03 | 0.12 | 0.68x | 1.65x | 2.1 | ok |
| `row:playsPerDrive` | 5.98 | 5.80–6.20 | 0.10 | 0.05 | 0.08 | 0.03 | — | — | — | 1.2 | OFF ok |
| `row:firstDownsPerTeamGame` | 18.26 | 17.30–19.30 | 0.50 | 0.12 | 0.48 | 0.03 | 0.15 | 0.79x | 3.30x | 1.3 | OFF ok |
| `row:drives3orFewer` | 31.73 | 29.50–33.70 | 1.06 | 0.43 | 0.96 | 0.03 | 0.49 | 0.89x | 2.16x | 1.5 | OFF ok |
| `row:drives4to7` | 39.55 | 38.60–40.60 | 0.54 | 0.39 | 0.38 | 0.03 | 0.51 | 0.75x | 1.05x | 2.1 | OFF |
| `row:drives8plus` | 28.73 | 26.90–30.70 | 1.06 | 0.49 | 0.94 | 0.03 | 0.48 | 1.03x | 2.22x | 0.9 | OFF ok |
| `row:threeAndOut` | 18.99 | 17.40–20.70 | 0.87 | 0.38 | 0.78 | 0.03 | 0.41 | 0.91x | 2.10x | 0.1 | OFF ok |
| `row:redZoneTripsPerTeamGame` | 3.349 | 3.170–3.553 | 0.091 | 0.044 | 0.080 | 0.003 | — | — | — | 2.2 | OFF ok |
| `row:redZoneTouchdownRate` | 59.96 | 56.80–64.40 | 1.91 | 0.91 | 1.68 | 0.03 | — | — | — | 0.4 | OFF ok |
| `row:averageStart.2025` | 32.05 | 31.80–32.70 | 0.20 | 0.17 | 0.10 | 0.03 | — | — | — | 1.3 | OFF ok |
| `row:averageStart.2024` | 32.05 | 31.80–32.70 | 0.20 | 0.17 | 0.10 | 0.03 | — | — | — | 1.8 | stale |
| `row:ownHalfStarts.2025` | 89.17 | 87.80–89.80 | 0.47 | 0.35 | 0.31 | 0.03 | 0.33 | 1.08x | 1.44x | 8.4 | ok |
| `row:ownHalfStarts.2024` | 89.17 | 87.80–89.80 | 0.47 | 0.35 | 0.31 | 0.03 | 0.33 | 1.08x | 1.44x | 7.6 | stale |
| `row:puntsPerTeamGame` | 4.53 | 4.10–4.90 | 0.22 | 0.08 | 0.20 | 0.03 | 0.08 | 1.07x | 2.89x | 0.6 | OFF ok |
| `row:netPunt` | 37.37 | 36.70–38.00 | 0.36 | 0.19 | 0.31 | 0.03 | — | — | — | 5.6 | OFF |
| `row:grossPunt` | 43.08 | 42.40–43.60 | 0.30 | 0.09 | 0.28 | 0.03 | — | — | — | 6.4 | OFF |
| `row:puntReturnYards` | 11.82 | 11.20–12.40 | 0.26 | 0.20 | 0.18 | 0.03 | — | — | — | 4.6 | OFF |
| `row:twoPointTries` | 0.205 | 0.160–0.240 | 0.019 | 0.015 | 0.011 | 0.003 | 0.016 | 0.96x | 1.20x | 0.8 | OFF ok |
| `row:twoPointConversion` | 42.81 | 36.40–52.60 | 3.87 | 3.84 | 0.48 | 0.03 | 3.86 | 0.99x | 1.00x | 2.4 | ok |
| `row:twoPointTriesRun` | 0.0837 | 0.0650–0.1240 | 0.0119 | 0.0115 | 0.0032 | 0.0003 | — | — | — | 1.5 | OFF ok |
| `row:twoPointTriesPass` | 0.1213 | 0.0950–0.1500 | 0.0146 | 0.0118 | 0.0087 | 0.0003 | — | — | — | 0.8 | OFF ok |
| `row:kickoffTouchbacks.2025` | 19.14 | 16.90–20.70 | 0.90 | 0.56 | 0.71 | 0.03 | 0.61 | 0.92x | 1.49x | 0.3 | OFF ok |
| `row:kickoffTouchbacks.2024` | 19.15 | 16.90–20.70 | 0.90 | 0.56 | 0.71 | 0.03 | 0.61 | 0.93x | 1.49x | 46.4 | stale |
| `row:fieldGoalsPerTeamGame` | 1.76 | 1.70–1.90 | 0.04 | 0.04 | 0.02 | 0.02 | 0.05 | 0.81x | 0.96x | 0.8 | OFF ok |
| `row:fieldGoalsUnder30` | 96.69 | 94.90–98.20 | 0.83 | 0.98 | 0.00 | 0.03 | 0.95 | 1.03x | 0.87x | 4.0 | ok |
| `row:fieldGoals30to39` | 92.59 | 89.00–95.30 | 1.50 | 1.53 | 0.00 | 0.03 | 1.29 | 1.19x | 1.16x | 2.1 | OFF ok |
| `row:fieldGoals40to49` | 82.81 | 79.10–86.70 | 1.87 | 1.65 | 0.87 | 0.03 | 1.76 | 0.94x | 1.06x | 0.6 | OFF ok |
| `row:fieldGoals50plus` | 71.37 | 63.80–78.10 | 3.40 | 3.22 | 1.10 | 0.03 | 3.36 | 0.96x | 1.01x | 1.0 | OFF ok |
| `row:fieldGoalAttemptsUnder30` | 25.29 | 22.90–26.90 | 1.09 | 1.22 | 0.00 | 0.03 | 1.16 | 1.06x | 0.95x | 0.0 | OFF ok |
| `row:fieldGoalAttempts30to39` | 29.32 | 27.70–31.80 | 1.07 | 0.98 | 0.44 | 0.03 | 1.21 | 0.81x | 0.89x | 2.4 | ok |
| `row:fieldGoalAttempts40to49` | 32.58 | 30.20–34.30 | 1.12 | 0.92 | 0.65 | 0.03 | 1.25 | 0.74x | 0.90x | 3.1 | OFF |
| `row:fieldGoalAttempts50plus` | 12.79 | 10.10–15.40 | 1.51 | 0.79 | 1.29 | 0.03 | 0.89 | 0.89x | 1.70x | 4.2 | OFF |
| `row:extraPointsMade` | 97.01 | 96.20–98.00 | 0.43 | 0.42 | 0.07 | 0.03 | — | — | — | 7.0 | ok |
| `row:fourthDownPunted` | 59.13 | 57.60–60.80 | 0.94 | 0.66 | 0.67 | 0.03 | 0.63 | 1.05x | 1.50x | 0.6 | OFF ok |
| `row:fourthDownKicked` | 23.11 | 21.70–24.40 | 0.73 | 0.55 | 0.48 | 0.03 | 0.54 | 1.03x | 1.36x | 0.0 | OFF ok |
| `row:fourthDownWentForIt` | 17.75 | 16.60–18.80 | 0.56 | 0.48 | 0.28 | 0.03 | 0.49 | 0.99x | 1.14x | 1.2 | OFF ok |
| `row:fourthDownAttempts` | 1.36 | 1.27–1.50 | 0.06 | 0.05 | 0.03 | 0.03 | 0.04 | 1.13x | 1.40x | 1.0 | OFF ok |
| `row:fourthDownConversion` | 56.37 | 51.10–61.60 | 2.28 | 1.22 | 1.92 | 0.03 | 1.50 | 0.81x | 1.51x | 1.6 | OFF ok |
| `row:fourthAndOneWentForIt` | 69.11 | 66.50–74.20 | 1.77 | 1.49 | 0.95 | 0.03 | — | — | — | 2.9 | OFF ok |
| `row:fumblesLost` | 0.568 | 0.500–0.630 | 0.032 | 0.025 | 0.021 | 0.003 | 0.027 | 0.92x | 1.20x | 0.6 | OFF ok |
| `row:fumblesKept` | 0.572 | 0.520–0.630 | 0.025 | 0.032 | 0.000 | 0.003 | 0.027 | 1.19x | 0.92x | 2.4 | ok |
| `row:turnovers` | 1.453 | 1.270–1.600 | 0.075 | 0.036 | 0.066 | 0.003 | 0.043 | 0.85x | 1.77x | 1.1 | OFF ok |
| `row:nonOffensiveTouchdowns.2025` | 0.173 | 0.140–0.210 | 0.018 | 0.017 | 0.005 | 0.003 | 0.015 | 1.16x | 1.20x | 1.3 | OFF ok |
| `row:nonOffensiveTouchdowns.2024` | 0.173 | 0.140–0.210 | 0.018 | 0.017 | 0.005 | 0.003 | 0.015 | 1.18x | 1.22x | 1.8 | stale |
| `row:defensiveReturnTouchdowns` | 0.137 | 0.110–0.170 | 0.017 | 0.014 | 0.010 | 0.003 | 0.013 | 1.03x | 1.29x | 0.2 | OFF ok |
| `row:kickReturnTouchdowns.2025` | 0.037 | 0.020–0.050 | 0.006 | 0.008 | 0.000 | 0.003 | 0.007 | 1.11x | 0.86x | 2.6 | ok |
| `row:kickReturnTouchdowns.2024` | 0.037 | 0.020–0.050 | 0.006 | 0.007 | 0.000 | 0.003 | 0.007 | 1.09x | 0.86x | 0.5 | stale |
| `row:onsideKicks.2025` | 0.213 | 0.150–0.280 | 0.030 | 0.023 | 0.019 | 0.003 | 0.023 | 1.00x | 1.29x | 0.9 | OFF ok |
| `row:onsideKicks.2024` | 0.213 | 0.150–0.280 | 0.030 | 0.023 | 0.019 | 0.003 | 0.023 | 1.00x | 1.29x | 0.6 | stale |
| `row:onsideRecovery.2025` | 10.01 | 3.00–19.80 | 4.42 | 3.55 | 2.63 | 0.03 | 3.27 | 1.09x | 1.35x | 1.4 | (OFF) (ok) |
| `row:onsideRecovery.2024` | 10.01 | 3.00–19.80 | 4.42 | 3.55 | 2.63 | 0.03 | 3.27 | 1.09x | 1.35x | 0.3 | stale |
| `row:kickoffsReturned.2025` | 76.91 | 74.70–78.90 | 0.97 | 0.54 | 0.81 | 0.03 | 0.65 | 0.83x | 1.50x | 3.2 | ok |
| `row:kickoffsReturned.2024` | 76.91 | 74.70–78.90 | 0.97 | 0.54 | 0.81 | 0.03 | 0.65 | 0.83x | 1.50x | 42.3 | stale |
| `row:kickoffReturnYards.2025` | 20.66 | 20.10–21.40 | 0.25 | 0.13 | 0.21 | 0.03 | — | — | — | 13.7 | OFF |
| `row:kickoffReturnYards.2024` | 20.66 | 20.10–21.40 | 0.25 | 0.13 | 0.21 | 0.03 | — | — | — | 19.7 | stale |
| `row:puntsReturned` | 42.69 | 40.90–44.70 | 1.01 | 0.67 | 0.75 | 0.03 | 0.82 | 0.81x | 1.22x | 2.2 | ok |
| `row:puntTouchbacksFromPlusTerritory` | 2.72 | 0.90–5.00 | 0.87 | 0.78 | 0.38 | 0.03 | — | — | — | 9.0 | OFF |
| `row:snapsInsideOwn10` | 1.688 | 1.440–1.980 | 0.115 | 0.058 | 0.099 | 0.003 | 0.046 | 1.27x | 2.50x | 1.2 | OFF ok |
| `row:safeties` | 0.020 | 0.008–0.040 | 0.008 | 0.005 | 0.006 | 0.003 | 0.005 | 1.07x | 1.54x | 1.2 | OFF ok |
| `row:preSnapRoadVsHome` | 1.232 | 1.120–1.360 | 0.063 | 0.056 | 0.029 | 0.003 | — | — | — | 0.7 | OFF ok |
| `row:heavyRainPoints` | 2.34 | -3.50–8.00 | 2.66 | — | — | 0.03 | — | — | — | 0.1 | unsourced |
| `row:gamesWithin3` | 19.94 | 15.80–23.00 | 1.91 | 1.77 | 0.73 | 0.03 | 2.00 | 0.88x | 0.96x | 0.2 | OFF ok |
| `row:gamesWithin7` | 45.92 | 39.00–52.00 | 2.92 | 2.51 | 1.49 | 0.03 | 2.49 | 1.01x | 1.17x | 0.5 | OFF ok |
| `row:gamesBy14plus` | 34.79 | 28.00–41.80 | 3.28 | 1.78 | 2.75 | 0.03 | 2.38 | 0.75x | 1.38x | 2.0 | OFF ok |
| `row:marginSigma` | 15.09 | 13.50–17.20 | 0.93 | 0.57 | 0.73 | 0.03 | — | — | — | 0.5 | OFF ok |
| `row:betweenTeamSigma` | 6.120 | 4.210–7.300 | 0.638 | 0.554 | 0.315 | 0.003 | — | — | — | 0.2 | (OFF) (ok) |
| `row:penalty.offensiveHolding` | 2.200 | 1.990–2.420 | 0.124 | 0.093 | 0.082 | 0.003 | — | — | — | 2.5 | ok |
| `row:penalty.falseStart` | 2.800 | 2.490–3.210 | 0.146 | 0.081 | 0.122 | 0.003 | — | — | — | 1.0 | OFF ok |
| `row:penalty.defensivePassInterference` | 1.400 | 1.140–1.610 | 0.114 | 0.067 | 0.092 | 0.003 | — | — | — | 1.4 | OFF ok |
| `row:penalty.defensiveHolding` | 1.435 | 1.190–1.670 | 0.118 | 0.073 | 0.092 | 0.003 | — | — | — | 5.9 | OFF |
| `row:penalty.unnecessaryRoughness` | 0.370 | 0.310–0.430 | 0.031 | 0.031 | 0.002 | 0.003 | — | — | — | 4.5 | OFF |
| `row:penalty.delayOfGame` | 0.790 | 0.710–0.870 | 0.043 | 0.037 | 0.022 | 0.003 | — | — | — | 1.8 | OFF ok |
| `row:penalty.offside` | 0.948 | 0.800–1.130 | 0.071 | 0.042 | 0.057 | 0.003 | — | — | — | 4.1 | OFF |
| `row:penalty.illegalFormation` | 0.181 | 0.130–0.250 | 0.026 | 0.026 | 0.000 | 0.003 | — | — | — | 2.0 | ok |
| `row:penalty.roughingThePasser` | 0.109 | 0.080–0.140 | 0.015 | 0.016 | 0.000 | 0.003 | — | — | — | 10.4 | OFF |
| `row:penalty.neutralZoneInfraction` | 0.617 | 0.450–0.750 | 0.060 | 0.047 | 0.037 | 0.003 | — | — | — | 3.5 | OFF |
| `row:interferenceDrawnPerGame` | 1.400 | 1.140–1.610 | 0.114 | 0.067 | 0.092 | 0.003 | 0.059 | 1.14x | 1.93x | — | unsourced |
| `row:interferenceOnCompletions` | 0.00 | 0.00–0.00 | 0.00 † | 0.00 † | 0.00 | 0.03 | — | — | — | — | unsourced |
<!-- harness-noise:end -->
