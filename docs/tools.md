# Tools

**Status: built.** Every tool and script on this page exists and runs today: `worldgen`,
`playsize`, `simharness`, `gamelog`, `scripts/lint-sim.sh`, `scripts/lint-reference.sh`,
`scripts/harness-reach.sh` and `scripts/test-census.sh`. Nothing here is a plan.

Command-line tools for inspecting the engine without an app, an Xcode, or a Mac.
Everything here runs in a Claude Code web session, so it works from a phone: ask
for a command and read the output.

**Everything is reproducible from a seed.** The same seed prints the same world
every time, so anything surprising can be re-run exactly.

**Every tool builds its world the same way.**
`WorldGenerator.generate(seed:shape:franchises:season:)` in `FMGeneration` is the single
entry point, so `worldgen --seed 7` and
`simharness --seed 7` are looking at the same league, and so are the engine's tests. Since
[decision 215](design-decisions.md#world-generation) that league's thirty-two clubs are
curated rather than drawn, so two seeds are two sets of players in one set of buildings.

## worldgen — look at generated content

```bash
cd Tools/worldgen && swift run worldgen --help
```

| Command | Shows |
| --- | --- |
| `swift run worldgen --show roster --team 3` | A full 53-man roster |
| `swift run worldgen --show starters --team 7` | Projected starting lineup |
| `swift run worldgen --show league --teams 32` | Talent summary and strength offset for every team |
| `swift run worldgen --show teams --teams 32` | Cities, colours, stadiums, divisions |
| `swift run worldgen --show class` | This year's draft class, top prospects and shape |
| `swift run worldgen --show pipeline` | All three visible classes at a glance |
| `swift run worldgen --show rivalries` | Seeded grudges, their history and heat |
| `swift run worldgen --show colleges` | The generated college pool |

Options: `--seed <n>` `--teams <n>` `--team <n>` `--season <n>` `--show <mode>`
`--franchises curated|random`

**The clubs are the same every time.** A world starts from the curated thirty-two in
`FMGeneration.FranchiseSet` ([decision 215](design-decisions.md#world-generation)), so
`--show teams` prints the same league at every seed — the same cities, nicknames,
colours and grounds, down to which of them have roofs. The league's own name is curated
with them, so the header line of `--show teams` reads the same at every seed too
([#82](https://github.com/knissley/football-manager/issues/82)); under
`--franchises random` it is drawn from the pools with everything else. What the seed
still moves is everything a career is played with: rosters, strengths, schemes, the
draft pipeline and the rivalries. `--franchises random` is the old pool draw, kept as a
last resort behind the flag and deliberately not refined before M8; it is the only way
to see two seeds name two different leagues. A league larger than thirty-two —
`--teams 64` — is the curated set finished from the pools.

`--teams` is rounded down to the nearest legal shape — two conferences of divisions of
four — so it is really a multiple of eight, and the header prints what was built. The
`STR` column in `--show league` is the strength offset the team was drawn at, in overall
points either side of the league's middle; it sums to zero across the league by
construction, so a run whose column is flat is a bug and not a quiet season.

Useful invocations:

```bash
# A contender and a rebuilding team from the same world, side by side
swift run worldgen --seed 42 --show starters --team 0
swift run worldgen --seed 42 --show starters --team 31

# Does the league's talent spread look right?
swift run worldgen --seed 7 --show league --teams 32

# The same team from a different world
swift run worldgen --seed 99 --show roster --team 3

# Does the roster have a past? The DRAFT column carries round, pick and season, or
# UDFA and the season he signed. Watch for: nobody undrafted, a team of first-round
# picks, a history only one draft deep, a starter who went in the seventh with a
# ninety ceiling on every roster. The footer counts how many were drafted — about
# three quarters league-wide, higher on a contender — and how many are in their first
# season, which is about a sixth of the league, eight or nine of fifty-three
# (docs/reference/calibration-sources.md).
swift run worldgen --seed 7 --show roster --team 3

# The league a career starts in. Two seeds, one league: this is the check that
# the curated set is what a world is built from.
swift run worldgen --seed 7 --show teams
swift run worldgen --seed 11 --show teams

# Does a drawn world read as a league someone drew, or as output? Watch for:
# repeated city stems, colliding abbreviations, a "South" division full of
# cold-weather cities, every stadium a temperate dome.
swift run worldgen --seed 42 --show teams --franchises random

# Is the class a distribution or a ranking? Watch for: the same positions at the
# top every year, a flat ceiling histogram, production that never disagrees with
# ability, nobody declaring early.
swift run worldgen --seed 7 --season 2030 --show class

# Does the invented past hold together? Watch for: two championship games in one
# season, every rivalry the same origin, a league that opens as all blood feuds
# or all indifference.
swift run worldgen --seed 42 --season 2030 --show rivalries
```

Reading this output has now caught four classes of bug that the tests did not:
athletic profiles decoupled from position, dead scheme modifiers, a roster built for
the wrong scheme, and — here — duplicate stadium names, colliding abbreviations, four
cities sharing a stem, and divisions named for regions they did not contain. It is
worth doing every time the generator changes.

## playsize — footprint, and a link guard

```bash
swift run --package-path Tools/playsize
```

Reports the in-memory size of a play record and what it implies at league scale.

It has a second job: it is a plain executable depending only on the `FM*`
modules, so it fails to build if one of them picks up a framework dependency.
That has already caught `Double.rounded()` — which resolves to libm's `round` —
twice. Test targets hide the problem because the testing library links
Foundation.

## simharness — calibration

```bash
swift run --package-path Tools/simharness -- --games 60
```

Simulates games headless and prints the [calibration table](match-engine.md#calibration)
with each row marked `ok` or `OFF`, and beside every row the real-league season and the
source its band came from and the rule areas it depends on. **Tuning is done against this
and never by playing the app.**

The bands are `Tools/simharness/Sources/simharness/Targets.swift`, and the doc table is
generated from them: `swift run simharness --targets-markdown` prints it, and the
package's test fails if the doc and the array disagree. A row marked `stale` was sourced
under a different rulebook than the run and is never `ok`; one marked `unsourced` keeps a
band nobody has cited and is never `ok` either.

```bash
cd Tools/simharness && swift run simharness --games 400 --seed 7 --rulebook 2024
```

`--rulebook 2024` plays today's `Rules.standard` and compares the kickoff rows against
the bands sourced from the 2024 season; `--rulebook 2025` plays with the touchback at the
35 and compares against 2025. If the kickoff rows land under both, the mechanism is right
rather than tuned. The default run plays `Rules.standard` against the 2025 targets, so
the 2024-sourced rows warn at startup until D2 lands.

Games are played between teams of drawn strength, from the same generator `worldgen`
prints — the header names the spread the league was drawn at. Before that, every
calibration game was between two clubs of exactly league-average strength, which is not a
matchup that occurs in the sport and made every row that depends on one team being better
than the other meaningless. Because it is the shipping world, the harness also inherits
the roughly one-in-eight clubs whose roster was assembled for a scheme they no longer
play ([decision 214](design-decisions.md#world-generation)), which it did not before: a
few points of scheme fit come off those teams, so the calibration table is measured over
a league with badly-fitted rosters in it rather than a league of perfectly-fitted ones.

The crude resolver owns the parametric rows — completion percentage, sack rate,
interception rate — because at matchup-lite fidelity those are inputs rather than
emergent properties.

It measures far more than the parametric rows: where the points come from, how drives
end and start, the shape of the carry and dropback distributions rather than their means,
field goals by distance, red zone conversion, personnel and package shares, fourth-down
behaviour, penalties by foul, injuries, the endgame, and the weather and home-road
splits. One row in [the calibration table](match-engine.md#calibration) has no value at
all — the spread of team win totals, which needs a season with a schedule and arrives
with M3; it prints under **Not measured here** so the row cannot be quietly forgotten.

The weather and rare-event rows need `--games 1000`; at 400 there are only twenty-odd
heavy-rain games and the row is noise.

Under **the shape of a carry** it prints the whole carry-length histogram as well as the
four graded shares. The shares are cumulative and overlapping, so a run game with nothing
between two yards and ten can satisfy every one of them; the histogram is what shows that,
and it carries the middle share — carries of three to nine — against a band derived from the
two graded rows either side of it rather than sourced on its own. The most common carry
length is printed with no target beside it, because nothing sources the mode; see
[calibration-sources.md](reference/calibration-sources.md).

The output is byte-identical across processes for a given seed and game count, so the
before-and-after comparison every engine fix depends on is a plain `diff`. A line that
moves between two runs of the same binary at the same seed is a bug in the harness's
read-out, not noise (#52) — with one deliberate exception, the `Budget` block below.

CI checks that on every push, as a hard-failing step of the `test` job: two
`--games 50 --no-timing --seed 7` runs and a `cmp`, with the difference printed if there
is one (#72). It was a local duty before that, done twice per seed by whoever remembered.

### The world checksum

The header names the league the run was played in, as one number:

```text
simharness — 400 games, seed 7
  32 teams, strength offset -2.8 to 2.5
  world checksum 23d435eb36f88a39  (no target: it names the league, it does not grade it)
```

It is `WorldChecksum` in `FMGeneration` — the same function `GoldenWorldTests` pins to a
checked-in constant, covering every part a generated world stores that can reach a snap:
every team and stadium, every roster and depth chart, the map of players the engine is
handed, the schemes, the strength offsets, and the draft pipeline and rivalries when a
world has them. Every variable-length group carries its length, so a depth chart
repartitioned over the same men is a different number. The doc comment on the type lists
what it reads and what it does not — the college pool by its size alone, a team's colours
not at all, and its name only as city-and-nickname joined, none of which is handed to
`GameSetup`. The number here is not
the golden's constant, because the harness generates a smaller world without the optional
parts, but it is the same function over it — which is what makes two *branches'* numbers
comparable.

It follows from the seed alone, so it does not disturb the byte-identical property above,
and it prints in `--no-timing` output too.

```bash
swift run --package-path Tools/simharness simharness --world-checksum-only --seed 7
# world checksum bb034c43d9254a63
```

`--world-checksum-only` generates the world, prints that one line and exits without
simulating — it takes a second, and it is how `scripts/harness-reach.sh` below asks two
builds whether they would play the same league.

### The Budget block

The run ends with a `Budget` block: the wall clock of the simulate calls alone, as ms per
game, the seconds that rate makes of a 272-game season, and the ~220 ms per game the
[60-second season budget](match-engine.md#performance-budget) allows, with the ratio
between them.

```text
  Budget
    Wall clock of the simulate calls alone — world generation, the weather draws
    and this report are outside it. Reporting only: no gate, and not a calibration
    target. It is the one block that moves between two runs of the same binary at
    the same seed, which is what --no-timing exists for.
    simulate calls                400 games in 5.90 s
    ms per game                   14.75
    seconds per 272-game season   4.01
    budget                        220.00 ms per game, 60 s a season (match-engine.md#performance-budget)
    ratio to budget               0.07x
```

**Reporting only.** Nothing gates on it, and timing is not a `CalibrationTarget`: a
wall-clock reading measures the machine that took it as much as the engine, so a band
would mean one thing on a laptop and another on a CI runner. What it is for is drift — the
budget is architectural ([ADR-0006](adr/0006-spatial-simulation.md)) and until this block
existed nothing measured it at all (#9).

It is printed **last**, after the verdicts, and it is the only part of the output that
moves between runs. `--no-timing` omits it, so the byte-identical check still works:

```bash
cd Tools/simharness
swift run -c release simharness --games 400 --seed 7 --no-timing | md5sum
```

Read the ratio, not the milliseconds. What one machine's milliseconds are worth is
unknown; what a doubling between two commits on the same machine means is not.

## gamelog — watch a game

```bash
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11
```

Simulates one game out of the same world `simharness` plays and prints it as a broadcast
log. One line per play: quarter and clock, the offence, down and distance, field position
in own or opponent terms, the concept, what happened and who did it, the personnel
matchup, any flag and how it was enforced, and the score after anything that scored. A
spot foul prints the spot it is enforced from rather than a yardage, because it does not
have one. A
drive summary at each change of possession and a scoreboard at the end of each period.

Options: `--seed <n>` `--home <i>` `--away <i>` `--week <n>` `--season <n>`
`--scenario <name>`

`--home` and `--away` are indices into the league at that seed, in identifier order, and
the header names the two teams it picked. They agree with `worldgen` and `simharness`:
all three call `WorldGenerator.generate(seed:shape:franchises:season:)`, and every stage of
it draws from its own labelled substream, so `worldgen`'s larger college pool no longer
shifts the
league behind it. At seed 7, `--home 3` and `worldgen --seed 7 --show roster --team 3` are
the same club.

`--week` is what the weather is drawn from: week 1 in a warm city is not the same game as
week 17 in a cold one.

Everything printed is a **query over the `PlayRecord` stream** — the score, the drive
boundaries and the period boundaries are folded out of the emitted plays using the same
`Rules` arithmetic the state machine used. The tool ends by comparing its own total
against the score the engine reported, and says so loudly if they disagree.

A drive summary reads `── NRW drive: 4 plays, 34 yards, 1:52 — touchdown`: snaps from
scrimmage, net yards, the clock the drive had the ball, and how it ended. A drive that ran
out of period rather than out of downs is named by the break it ran into — `end of half`,
`end of regulation`, or `end of game`. Overtime is where that is easy to get wrong, and
#87 is where it was: the end of a first or a third postseason overtime period is **not** a
break, because the next one begins with the ball where it was and the same side in
possession (16-1-4-f, 4-2-3), so a drive runs straight through it and is printed once,
when it really ends. The end of a second or a fourth is one — the third and the fifth
period open a new half with a kickoff (16-1-4-e, 16-1-4-i) — and the drive chart ends a
drive there as it does at halftime, because both read `Rules.periodResumesWithKickoff`.
The last
drive of a game runs to 0:00, because in regulation the clock is the only thing that ends
a game — a kick that wins it at 0:03 does not, the horn does. The exception is again
overtime, where a score ends the game where it stands: a walk-off drive is charged to the
play that won it, and since no `PlayRecord` carries the interval before a snap, that one
line is short by that interval and by nothing else.

**Read one game end to end before and after any engine change.** This is the recipe:

```bash
# Before the change, and again after it. Read both; diff them if the change was meant
# to be behaviour-preserving.
cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11 > /tmp/before.txt

# The same game in bad weather, which is a different game.
swift run gamelog --seed 7 --home 3 --away 11 --week 17

# A different matchup out of the same world, for a second opinion.
swift run gamelog --seed 7 --home 12 --away 5
```

Watch for the things a table of means cannot show: who kicks off after a safety, whether
a touchdown gets its try, whether a tie plays overtime, how much clock burns between the
last snap of one possession and the first of the next, whether the same quarterback takes
every snap of a drive, and whether a penalty leaves the ball where the rule puts it.

What happened while the ball was dead is printed above the snap it preceded, read off
that snap's record: `two-minute warning` on its own line, and `timeout: NRW (2 left)` for
each charged timeout with the side that took it and what it has left. A kick line carries
its three spots — `D. Dockery 40 yards to GRH 34, L. Wrenfield returns it 7 to GRH 41` —
so the gross of a returned punt and its return are both there, and a kickoff fielded in
the end zone says how deep (`67 yards to 2 deep`).

**Every charged timeout prints the same `timeout:` line, whoever called it.** A timeout
the rules charge after a play — the offence's instead of a ten-second runoff (4-7-1 Item
1), or an injury timeout after the two-minute warning (4-5-4-a) — keeps its `clock:`
announcement under that play and now carries the line beneath it:

```
        clock: injury timeout, charged as a team timeout (4-5-4)
        timeout: GRH (2 left)
```

so that `grep 'timeout:'` finds every stoppage of that kind rather than the subset a
bench asked for. That matters because a trace which hides a clock-stopping event invites
a reader to explain the seconds it saved by some other mechanism, and one already did:
three consecutive snaps costing no clock were read as broken interval accounting when
each had simply followed a timeout.

Aggregates hid every rules bug the September audit found. Each of them is obvious in
thirty seconds of this output, which is why it exists.

### --scenario — watch a conformance scenario

```bash
cd Tools/gamelog && swift run gamelog --scenario list
cd Tools/gamelog && swift run gamelog --scenario safety-free-kick
```

The rules-conformance scenarios are the acceptance language for the rules layer: each one
is a game whose plays are dictated, so that what is left to watch is the clock, the downs,
possession, scoring, enforcement and overtime. The suite in
`Packages/FMSimulation/Tests/FMSimulationTests/RulesConformanceTests.swift` asserts on
them and prints a verdict; `--scenario` prints the game, so a rule can be *shown* to a
person rather than described to him.

It is the same game and the same printer. The scenario, its world, its caller and its seed
all come from `FMSimulationScenarios`, the library the suite runs, so what a reader watches
is what the suite asserts on, and the play-by-play is `printPlayByPlay` — the one a seeded
game goes through.

`--scenario list` names them all. The name is a slug (`safety-free-kick`) because a shell
argument cannot be the test's own sentence; under each name the list prints what the suite
asserts about it, verbatim — the football sentence and the rule it comes from — and the
same lines head the game itself, so a reader knows what he is looking for before the first
play goes by. Most scenarios play a *whole* game, and the moment the citation points at is
usually a handful of plays: read the header, then find them.

```bash
# The rule the audit's S11 was about: the side scored upon free-kicks from its own 20.
swift run gamelog --scenario safety-free-kick | head -20

# S10: a touchdown as the fourth quarter expires gets its try, at 0:00 of that period.
# Down six, the kick wins it and the game ends on the try, so the tail is short.
swift run gamelog --scenario last-play-touchdown-down-six | tail -10

# The same rule down seven, where the try levels it: the try is at 0:00 of the fourth
# and a ten-minute overtime period follows, so the play-by-play runs on past it.
swift run gamelog --scenario last-play-touchdown-down-seven | tail -40

# And the other half of the same rule: a try that could not change the outcome is waived.
swift run gamelog --scenario last-play-touchdown-down-two | tail -10

# A11 (#74): the overtime period has a two-minute warning. A play ends at OT 2:01 with
# the clock running, and the next snap comes at 2:00 rather than a huddle later.
swift run gamelog --scenario play-ending-just-before-the-two-minute-warning-of-overtime | tail -30

# Postseason overtime pairs its periods into halves: a first period has no warning, a
# second has the first half's. The period label counts them — OT, 2OT, 3OT.
swift run gamelog --scenario play-ending-just-before-the-two-minute-warning-of-a-second-postseason-overtime-period | tail -30

# A12 (#76): the play clock. A forty-second clock expires with the ball not snapped in
# the third quarter — five yards, the same down, and the whole forty gone from a running
# game clock; the line says which clock it was.
swift run gamelog --scenario delay-of-game-on-a-running-clock | grep -B2 -A3 "play clock expired"

# The same foul on the first snap after a turnover on downs, against the twenty-five.
swift run gamelog --scenario delay-of-game-after-a-turnover-on-downs | grep -B2 -A3 "play clock expired"

# The last forty seconds (4-7-3): the defence jumps at 0:30 with no timeouts left, and the
# leading offence ends the game on the flag. The clock line under the flag is the election.
swift run gamelog --scenario neutral-zone-infraction-in-the-last-forty-seconds-with-the-offense-leading | tail -8

# An injury after the two-minute warning (4-5-4): with no timeouts left it is an excess
# timeout, the defence takes ten seconds off, and the next snap is ten seconds later than
# the play ended.
swift run gamelog --scenario injury-inside-two-minutes-with-no-timeouts-left | grep -B3 -A2 "excess injury"

# The same injury with a timeout in hand: charged, and the clock waits for the snap.
swift run gamelog --scenario injury-inside-two-minutes-with-a-timeout-left | grep -B3 -A2 "injury timeout"

# The basic spot on a takeaway (14-3-5-b, 14-4-3-a). A run from the offence's own 30 to
# its 40 with a defender flagged, stripped there, returned to the offence's 25: the ball
# reverts to the offence and the fifteen comes off the 40, not off the 30 — play 2 is
# first and ten at the opponents' 45.
swift run gamelog --scenario roughness-by-the-defense-on-a-run-that-ends-in-a-fumble-lost | head -15

# The same flag on a pass, which is a different rule (14-4-5-d, 8-6-1-d). The offence
# gets the better of two spots, where it snapped or where the ball was dead; here the
# interceptor was dropped behind where the ball was snapped, so it is the previous spot,
# the offence keeps it at its own 45, and the interception is wiped out. Read the two
# side by side: same field position, same foul, two answers, and the difference is what
# kind of play the foul was during.
swift run gamelog --scenario roughness-by-the-defense-before-an-interception | head -15

# The exception the strip sack makes common (14-3-6 Exception 1, 14-4-6-b). The ball
# comes loose behind the line, so the basic spot is behind the line and the fifteen comes
# off the previous spot wherever the foul was: the offence snapped from its own 40, was
# stripped at its own 34, and play 3 is first and ten at the opponents' 45 — not the 51
# that measuring from the fumble gives.
swift run gamelog --scenario roughness-by-the-defense-on-a-strip-sack | head -14

# And the other arm of 14-4-5-d, where the dead-ball spot is the better of the two. The
# pick is at the opponents' 20 and the interceptor is dropped at the opponents' 30, still
# downfield of the snap at the opponents' 45: play 3 is first and ten at the opponents'
# 15. Read it against the scenario above — one exception, two answers, and what decides
# is where the man with the ball was when he went down.
swift run gamelog --scenario roughness-by-the-defense-before-a-deep-interception | head -14

# A kickoff the returner fumbles and the kicking team carries in (8-7-3 Item 1, 11-2-1,
# 11-3-1, 11-3-4): the kickers' touchdown, the kickers' try, and the kickers kicking off
# again. The opening kickoff, so the first three lines of play are the whole rule.
swift run gamelog --scenario kickoff-fumbled-and-returned-by-the-kickers | head -14

# The article's second clause: an excess timeout for an injured *defender* inside the last
# forty seconds ends the half on the same terms a defensive foul does.
swift run gamelog --scenario injury-to-a-defender-in-the-last-forty-seconds | tail -8

# A flag during a down stops the clock at the end of it and enforcement is not free
# (4-4-e, 4-3-2-e). The second snap of the game draws a defensive holding; the down after
# the enforcement is snapped six seconds earlier than a clock that never stopped allows.
swift run gamelog --scenario defensive-holding-on-a-play-ending-in-bounds | head -18

# The same flag inside five minutes of the fourth quarter, where the clock waits for the
# snap instead (4-3-2-e-2) — and an offensive one outside every window in the same period,
# which restarts on the ready, because 4-3-2-e-3 reaches only a flag between downs.
swift run gamelog --scenario defensive-holding-inside-five-minutes-of-the-fourth-quarter | grep -B1 -A2 "defensive holding"
swift run gamelog --scenario offensive-holding-in-the-fourth-quarter-outside-five-minutes | grep -B1 -A2 "offensive holding"

# What a spike costs (4-4-f, 8-2-1 Item 3). The printed clock is the clock the ball was
# snapped on, so this reads straight off the page: the spike is snapped at 0:05, costs its
# own second, and the fourth down is snapped at 0:04 and played. Grep for it — the tail of
# this scripted game is the overtime a 0–0 tie runs into.
swift run gamelog --scenario spike-snapped-at-five-seconds-on-third-down | grep -B1 -A1 "spikes it to stop the clock"

# The same twenty seconds out: the spike at 0:20, the fourth down at 0:19.
swift run gamelog --scenario spike-snapped-at-twenty-seconds | grep -B1 -A1 "spikes it to stop the clock"

# A13 (#85): the late out-of-bounds window is judged where the runner stepped out. A
# play snapped outside 5:00 of the fourth quarter carries him out inside it, and the
# next snap comes with the clock stopped rather than a huddle later.
swift run gamelog --scenario runner-out-of-bounds-across-five-minutes-of-the-fourth-quarter | tail -30

# The mirror, and the first-half boundary, of the same rule: a play kept inside 5:00, and
# a runner out after a play snapped before the second quarter's warning, which the
# warning stops on its own.
swift run gamelog --scenario runner-out-of-bounds-inside-five-minutes-of-the-fourth-quarter | grep -B1 -A2 "out of bounds"
swift run gamelog --scenario runner-out-of-bounds-across-the-two-minute-warning-of-the-second-quarter | grep -B1 -A2 "out of bounds"

# A14 (#86): a third postseason overtime period opens a new half — a kickoff at 3OT
# 15:00, kicked to the side that lost the toss before overtime, and three timeouts each
# again; the 2OT boundary before it is played straight through.
swift run gamelog --scenario third-postseason-overtime-period | tail -60

# The choice is the toss loser's (4-2-2-a): electing to kick, it kicks off the third period.
swift run gamelog --scenario third-postseason-overtime-period-with-the-toss-loser-kicking-off | grep -A2 "end of 2OT"

# A fifth period after the toss of 16-1-4-i: a kickoff at 5OT 15:00, with the 4OT boundary
# before it played straight through.
swift run gamelog --scenario fifth-postseason-overtime-period | grep -A2 "end of 3OT\|end of 4OT"

# A half that ends between downs, on an excess injury timeout's runoff, is followed by the
# second-half kickoff like any other: the side that received the opening kick kicks, and
# the receivers have the ball after it — at their restart spot, or where the return ended.
swift run gamelog --scenario second-half-kickoff-after-an-injury-runoff-ends-the-first-half | grep -B3 -A2 "halftime ·"
swift run gamelog --scenario second-half-kickoff-returned-after-an-injury-runoff-ends-the-first-half | grep -A2 "halftime ·"
```

The men are not named in a scenario — a scripted outcome credits nobody, so the log says
"the back" and "the kicker" — and the header says so. Everything else reads exactly as a
seeded game does.

## Tests

```bash
swift test --package-path Packages/FMRandom
swift test --package-path Packages/FMCore
swift test --package-path Packages/FMGeneration
swift test --package-path Packages/FMSimulation      # minutes, not seconds — see below
swift test --package-path Tools/simharness          # the calibration table cannot drift from its doc
swift test --package-path Tools/gamelog             # what a drive summary says about the clock

# Integer maths must agree between debug and release
swift test -c release --package-path Packages/FMRandom
```

Every one of these is a hard-failing step of the `test` job in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml), on both architectures —
`Tools/simharness` since #9 and `Tools/gamelog` since #87, because nothing else compiles
either tool's tests, or in gamelog's case the tool itself.

**FMSimulation is the long one, and it has a budget: under two minutes of test time on a
four-core Linux container, and no suite simulates a game another suite has already
played.**

The second half of that sentence is what holds the first half up, and it is the part to
check when the number moves. Coverage — *can the engine produce this at all* — is asserted
against a forced draw that constructs its cases, never against a batch of games big enough
to stumble into one. Games are for the other question, *does this happen in play*, and
every suite that asks it reads `TestWorld.corpus`: forty games, played once, with the
number derived from the rarest thing anybody asserts over it.

How the number got out of hand is worth keeping. This line and CLAUDE.md's both said
`~45s` for a long time while the truth was minutes, because the answer to a test that went
red when a sample was re-drawn had three times been a bigger sample: the vocabulary
suite's went forty, ninety, two hundred and forty. That suite alone was **54 s** when it
was the only thing running.

Measured, four-core container, five runs of the whole FMSimulation suite: **85–111 s**,
against **170–200 s** for the same suite on the same machine before the sharing. An
earlier measurement on a different machine read 144 s for the same before-state and
[#106](https://github.com/knissley/football-manager/issues/106) read 201 s on a third, so
machines here differ by a factor of two — **measure yours rather than trusting the
number**, and compare a before and an after taken back to back. The suites run in
parallel, so the total is nearer the longest pole than the sum.

Every `@Test` in all six targets carries a kind tag, and
[`test-census`](#test-census--what-the-suite-asserts) below fails on one that does not.
What the kinds mean and what the suite currently looks like when you count it are in
[testing.md](testing.md).

### The conformance scenarios are a library, not test support

`FMSimulation` ships a second library, **`FMSimulationScenarios`**: the scripted games the
rules-conformance suite runs — `Snap` and the outcome vocabulary, `ScriptedCaller`,
`ScriptedGame`, the `Trace` a game produces, `ScenarioWorld`, and the scenarios themselves.
It is a plain `FM*` module: no Swift Testing, no Foundation, and `scripts/lint-sim.sh`
scans it like any other.

It is a library rather than a test target so that a tool can link it, which is what
`gamelog --scenario` does. What stays in `Packages/FMSimulation/Tests/` is the half only a
test can hold: the assertions over a `Trace` (`expectPlay` and the rest, in
`Scenarios/TraceAssertions.swift`) and the conformance suite itself.

Every scenario the suite runs is a case of `RulesScenario`, and that enum is the only way
to reach one — the scripts are internal to the library. So the list `--scenario list`
prints is the list the suite runs, by construction rather than by upkeep, and
`Scenarios/ScenarioLibraryTests.swift` pins the rest: that the listing names every
scenario with the football it is there to show, that the printed name is the name the tool
parses back, and that every scenario still runs.

## lint-sim — the determinism and purity lint

```bash
./scripts/lint-sim.sh
```

Prints `file:line: what` for every hit and exits 1; exits 0 on a clean tree; exits 2 when
it would otherwise have passed by scanning nothing — a `Sources/` directory that is gone,
or that is there and holds no Swift files. It takes two to five seconds depending on what
else the machine is doing — run it before committing. CI runs it as a hard-failing step,
on both architectures, in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml),
next to the self-test below.

It enforces two rules that were conventions with nothing behind them:

- The primitives [ADR-0003](adr/0003-deterministic-seeded-simulation.md) bans in the
  `Sources/` trees of `FMCore`, `FMRandom`, `FMGeneration` and `FMSimulation` —
  `.random(`, `SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement(`, `UUID(`,
  `Date(`, `Hasher(`, a clock or environment read — plus the framework imports
  [ADR-0004](adr/0004-pure-swift-domain-core.md) bans: `Foundation`,
  `FoundationEssentials`, `Dispatch`, `SwiftData`, `SwiftUI`, `UIKit` and the rest.
  `playsize` already catches a framework dependency at link time; this catches it at the
  import, with a line number.
- `Hasher` in a `*Golden*Tests.swift`. Swift randomises its hash seed per process, so a
  golden checksum built on `Hasher` agrees with itself inside one run and disagrees with
  yesterday's — it cannot detect the drift it exists to detect. Both goldens use FNV-1a.
  The world golden's checksum now lives in `FMGeneration` as `WorldChecksum`, so that
  `simharness` can print the same number; `Hasher(` is banned there by the rule above,
  which scans every `FM*` `Sources/` tree.

Comments are stripped before matching, so prose *about* the ban — the doc comment on
`SplittableRandom` naming `Int.random(in:using:)`, the one on each golden `Checksum`
saying it is deliberately not `Hasher` — does not trip the lint. String literals are
not stripped: interpolation can hold real code.

The stripper is not airtight, and a clean run is not proof. It walks a line at a time and
never rejoins what a comment split, so `Date/* x */()` matches no rule; the script header
says so at length. The golden tests, the replay contract tests and review are what catch
the rest.

That list of four packages is written out in the script rather than globbed.
`FMPersistence` is an `FM*` package that must *not* be scanned — SwiftData lives there by
design — so `Packages/FM*` would be the wrong check, not a shorter one. When `FMAnalysis`
or `FMNarrative` lands, add it to the `packages` array; nothing else will.

A file that genuinely needs an exemption goes in the `allowlist` array at the top of the
script as a `"<path> <rule-id>"` pair. It is empty today. Widening it to turn a red lint
green is the one thing it must not be used for.

### The self-test

```bash
./scripts/lint-sim.sh --self-test
```

The comment stripper is the subtle part of the script, and for a while nothing checked
it. `--self-test` lints
[`scripts/lint-sim-fixtures/`](../scripts/lint-sim-fixtures) instead of the packages.
That tree holds a Swift file per rule — never compiled, never part of a package, never
scanned by the real lint, because they carry banned tokens on purpose — each with a plain
hit plus the same token behind a line comment and inside a block comment. Alongside them
sit a negative control naming every banned token in comments, the golden `Hasher`
doc-comment case, and the shapes the stripper has to get right: a string literal holding
`//`, an escaped quote, a multi-line string, and a block comment that opens or closes
mid-line.

Every hit the tree must produce is listed in `scripts/lint-sim-fixtures/expected.txt` as
`path:line: rule-id`, and a difference in either direction fails — a hit that quietly
stops firing is caught as loudly as a new false positive. So a new rule needs a fixture
and an expectation line. It runs in under a second, and CI runs it as its own
hard-failing step.

## lint-reference — reproduced rulebook text, and citations that resolve

```bash
FM_RULEBOOK_TEXT=/path/to/rulebook.txt ./scripts/lint-reference.sh
```

Three checks over the documents, sources and commit messages where football prose lives.

1. **Reproduced text in the tree.** Runs of ten words the tree and the rulebook have in
   common. CLAUDE.md rule 8 allows a citation and forbids a copy, and until this script
   existed nothing checked it: three reproduced runs in `docs/reference/playing-rules.md`
   were found by a reviewer who happened to have the book open.
2. **Reproduced text in the commit messages the branch adds**, against its merge base.
   Same scanner, same two passes, same controls. [Commit messages](#commit-messages) says
   what a hit does and why the two arms differ.
3. **Citations resolve.** Every `rule-section-article` number in the four reference
   documents names an article the book actually has.

It **cannot** tell whether a cited article *supports* the claim beside it, and it says so
on every run, clean or not. `8-5-4` is a real article, so a citation to it passes check 3;
it was nonetheless the wrong article in six entries across three documents for weeks. A
green run means "no uncarried run, and no dangling number" and not "the citations are
right". That half stays a reading problem.

It also cannot see a reproduction shorter than its run length — nine words or fewer slip
straight through, and eight-word ones have happened. [The blind spot](#the-blind-spot-nine-words-or-fewer)
has the measurement and why the threshold is still ten.

**The corpus is not in the repository and will not be** — it is the copyrighted document
rule 8 is about. Point `FM_RULEBOOK_TEXT` at a plain-text extraction of the book, or leave
one at `.rulebook.txt` in the repository root, which `.gitignore` keeps out of the tree.
[`docs/reference/README.md`](reference/README.md#policing-this-directory) says how to get
one. With no corpus the script prints why and **exits 0**: CI has no rulebook, and a
skipped check must not be a red build.

### The three ways a shingle lies

Each of these produced a false clean during the audit backlog, and the script is built
against them rather than against a guess.

- **A per-line scan.** A reproduction broken by a hard wrap holds no ten consecutive words
  on any one line. Measured on `playing-rules.md`: five runs per line, ten with the lines
  joined. The script scans the joined word stream and labels each hit `line` or `joined`.
- **A sub-range.** An agent shingled one commit's diff and reported the count as its
  branch's. The script scans whole files and whole commit messages, never a diff or a line
  range, prints how many of each it scanned, and exits 2 rather than 0 if a policed
  directory has gone missing. A commit range is the one range it takes, and it is the
  whole of what the branch adds.
- **A control that could not fire.** An agent's control phrase was not in the book, so its
  control returned 0 and its clean run meant nothing. This script's controls are cut from
  the corpus **at runtime**, so they cannot be a phrase the corpus does not have: one on a
  single line, one split across a wrap, and a negative control that is the same words
  reversed. **If they do not come out 1, 1, 0 the script prints no count at all and exits
  2.** A count without a firing control is not a measurement.

### Commit messages

```bash
FM_RULEBOOK_TEXT=/path/to/rulebook.txt ./scripts/lint-reference.sh --messages
```

**Run this immediately before `git push`.** It is the last moment the thing it finds can
be fixed.

A commit message is in the repository as permanently as a file is, and rule 8 does not
stop at the tree. It is the harder of the two to put right: a file is edited, a published
message is only rewritten by rewriting history, which the conventions forbid on a shared
branch. The one run that made this check exist was caught while its branch was still local
and the commits could be replayed; one push later the choice would have been between
leaving it and rewriting published history.

**What is scanned.** The commits the branch adds against its merge base —
`git merge-base <base> HEAD`..HEAD, oldest first, each message whole. Not the whole
history: every commit already on the integration branch was scanned when it was somebody's
branch, and re-reporting them for ever is how a gate becomes wallpaper. `<base>` is
`origin/main`, or `main` if there is no remote. `--base <ref>` and `--range <a>..<b>`
override it; `--range` is what to reach for to audit history rather than to lint a branch.

**What a hit does**, and the two arms are different on purpose:

| where the commit is | what happens |
| --- | --- |
| not yet on the base branch | **violation, exit 1.** It can still be reworded, and this is the only moment it can. |
| already on the base branch | **reported, exit unchanged.** Nothing removes it but rewriting published history. |

The second arm is the one worth arguing about, and the argument is this: a gate that stays
red for ever over something nobody can fix is a gate people learn to route around, and
then it is not guarding the first arm either. The count is still printed on every run —
a run nobody can act on is still a run somebody should know about.

Only a range reaching back past the merge base can contain a published commit, so in
ordinary use the second arm is silent and `--range` is what wakes it.

**There is no baseline for messages, deliberately.** A run in the tree can be
irreducible — an article whose nouns are all defined terms leaves nothing to reword — and
that is what the baseline is for. A message has no such constraint: it is prose its author
wrote freely and can write again, and the remedy for a hit is to say it in our own words
and cite the article.

**Measured on `main`, September 2026:** 411 commit messages, **61 ten-word runs in 11 of
them**, 47 distinct — counted twice, once by this script and once by an independent
implementation that agreed on every figure. They are the second arm's whole justification:
every one is published and unfixable, and a gate that failed over them would have been
turned off in a week. They are concentrated in eleven messages that quoted article clauses
while describing a fix; the tree itself is clean at ten.

### The baseline

```bash
./scripts/lint-reference.sh --list        # the baseline line for every run found in the
                                          # tree — messages have no baseline, see above
```

[`scripts/lint-reference-baseline.txt`](../scripts/lint-reference-baseline.txt) carries any
run judged irreducible, one line each: path, a content key, a verdict and a note. The
**key**, not the run — writing the run into the repository is the thing being linted. A run
that is not in the baseline fails.

**It is empty, and it did not start that way.** The tree shared twenty-three ten-word runs
with the book when the script was written, and the first judgement was that all of them
were the sport's vocabulary rather than the book's prose — `docs/reference/README.md` says
terms of art cannot be reworded, and eight of them in the sport's own order is a ten-word
run whether or not anybody had the book open. That is a defensible claim about two hundred
files and a wrong one about the six entries it mattered for. Read one at a time against its
own article, every run had a paraphrase that cost nothing: the sides swap ends after the
first and third quarters; a flag before the snap walks off from the succeeding spot. The
count is zero at n=10 across the tree.

The irreducible case is real — a rule whose nouns are all defined terms can run out of ways
to be ten words long — so the mechanism stays. A line in it is a claim that somebody opened
the article and judged the run; `--list` prints the line to add. The baseline mechanism
itself is exercised by `baselined.md` in the self-test rather than by anything carried in
the tree.

### The blind spot: nine words or fewer

**A clean run means "no run of ten". It does not mean the tree holds none of the book's
prose.** Eight-word reproductions happen — one was written into a commit message and
caught only because an agent scanned at eight, below what the script asks for — and
CLAUDE.md rule 8 does not come with a word count.

Eight was measured over the whole tree and **rejected**. Shared runs, 214 files, against a
plain-text extraction of the book, September 2026:

| n | runs | distinct | files | baseline lines it would need |
| --- | --- | --- | --- | --- |
| 10 | 0 | 0 | 0 | 0 |
| 9 | 32 | 12 | 18 | 29 |
| 8 | 130 | 57 | 26 | 116 |
| 7 | 382 | 161 | 38 | 337 |
| 6 | 1039 | 371 | 56 | 854 |

Every distinct run at 8 and 9 was read against its own article. At 9 none is a
reproduction. At 8 two were, both reworded in the same change that recorded this table —
a clause of prose from the ten-second-runoff article, and a clock window set in quote
marks and announced as the article's words. The other 57 are chains of defined terms with
no synonym, a penalty's own name beside the article number rule 10 requires, a rule title
used as a heading, and coincidence.

**That is the successor to the twenty-three.** At ten, twenty-three runs and every one
reducible — every hit worth acting on. At eight, 116 baseline lines around two findings,
and a baseline line is a claim that somebody opened the article and judged the run. A
hundred and sixteen of those is a rubber stamp, and the baseline only works if it is read.
The cost of eight is not runtime; it is that the gate becomes noise and buries the next
real run inside it. `--n 8` runs the tree at eight on demand — worth doing on a branch
that added football prose. Expect the table, not zero, and read what moved.

Two things follow that no threshold fixes:

- **The threshold was never what hid commit messages.** Until check 2 existed the script
  read files and nothing else, so the run that prompted this measurement — which was in a
  message — would have escaped at any `--n`. [Check 2](#commit-messages) closes that, at
  the same ten words and with the same two passes; what it does not close is this same
  nine-word blind spot, now in one more place. **Shingle a message before you commit it**,
  per line and joined, at eight as well as ten, and run `--messages` before you push.
- **A short run is a reading problem.** At eight the script cannot tell a quotation from
  the same defined terms in the same order: the quoted clock window above sat among nine
  innocent uses of the identical words. Only opening the article separates them.

### Its self-test

```bash
./scripts/lint-reference.sh --self-test
```

Runs against [`scripts/lint-reference-fixtures/`](../scripts/lint-reference-fixtures) and
needs no corpus: the fixture tree ships its own, **invented for the fixture and not a
rulebook**, imitating the shape of one — numbered rules, sections and articles, with one
heading deliberately broken across a line the way a PDF extractor breaks them, so the
script's repair of that is exercised.

Six fixture documents, one per direction:

| fixture | what it pins |
| --- | --- |
| `one-line.md` | a run wholly inside one line is found |
| `wrapped.md` | a run **only** a joined scan can see is found, and labelled `joined` |
| `baselined.md` | a run whose key is in the fixture baseline is **not** reported |
| `paraphrase.md` | the same rules in our own words yield nothing |
| `blind-spot.md` | a **nine**-word run is invisible at ten and found at nine |
| `citations.md` | a number the corpus does not have is reported, and three that it does are not |

Plus `messages/`, four fixture **commit messages** for check 2. The self-test commits them
into a throwaway git repository — two on `main`, two on a branch cut from it — and points
the check at that instead of at this repository, because the alternative is committing
fixtures into the real history, which is permanent and is the thing the check exists to
stop. `main`'s first message carries a planted ten-word run and the branch's second
carries another, split across a wrap the way a wrapped message body splits one. Both
halves are asserted: the branch's run must be **found**, labelled `joined` and counted as a
violation; `main`'s must **not be read at all**, because it is behind the merge base. The
same run judged against a base that already contains it must come back advisory rather than
failing, so the second arm of the design has a case and not only a paragraph. The
throwaway repository is built with the ambient git configuration cut out — a global
hooksPath or signing key would otherwise decide whether the self-test passes on this
machine.

Plus `baseline-empty.txt`, a baseline holding only its own explanation, which must read as
no keys **without ending the run**. That one is a scar: `grep -v` exits 1 when it selects
nothing, and under `pipefail` that killed the lint the first time the real baseline was
emptied — the one path that matters on a clean tree was the one path nothing covered. The
check has to assign the result rather than test it inline, because a command substitution
used as an argument throws its status away.

Every hit the fixtures must produce is in `scripts/lint-reference-fixtures/expected.txt`
as `path:line: rule-id`, and a difference either way fails. `wrapped.md` is the one worth
protecting: rewrite the scanner to look at lines one at a time and both it and the
runtime control go red, rather than the script printing a comfortable zero. CI runs the
self-test as a hard-failing step, and the lint proper as a step that skips.

`blind-spot.md` is checked at two run lengths rather than one, and both halves matter: it
must yield nothing at ten, and at least one hit at nine. Asserting the miss alone would be
satisfied by a scanner that had stopped working altogether, which is the same failure as a
control that cannot fire. Widen the gate and it goes red on purpose — the blind spot is a
decision, and a decision nothing exercises is a comment.

The message fixtures are pinned the same way, and verified by mutation in three
directions: widen the planted run to eleven corpus words and the self-test goes red at two
hits; shorten it to nine and it goes red at none; widen the range from the branch's own
commits to the whole history and it goes red at four messages read instead of two, with
`main`'s planted run surfacing as the advisory it should have been.

## harness-reach — can this change reach the harness?

```bash
./scripts/harness-reach.sh origin/main
```

Prints exactly one line — `skip` or `run`, and why — and exits 0 for `skip`, 1 for `run`,
2 when it could not decide. Everything else it says goes to stderr, so the line is safe
to paste into a PR body.

```text
run  the engine's own sources moved against origin/main — 1 file(s): Packages/FMSimulation/Sources/FMSimulation/Fumbles.swift — run the harness
skip  no engine source moved against origin/main and the world is identical at seeds 7 11 (bb034c43d9254a63 85c82634e3d87e7e) — the harness cannot see this change
```

Every fix in the backlog runs `simharness --games 400` at two seeds, before and after, and
again in each review round. For a change the harness genuinely cannot see — the hundred
lines of rivalry generation in #64, which the calibration world never draws — that is four
sweeps to prove a negative. The rule was unconditional because "the harness cannot see
this" was an *argument a reviewer wrote*, and an argument holds only until somebody adds
rivalries to the harness world. This is the same claim, made by the tooling instead
(#72): CLAUDE.md takes this one line in place of the sweep, and the double run at a seed
is now CI's job rather than the implementer's.

It says `skip` only when both of these hold:

1. `git diff <base-ref>` is empty over the engine's own sources — `FMSimulation`,
   `FMCore` and `FMRandom`'s `Sources`, `Tools/simharness/Sources`, each package's
   `Package.swift`, and `FMGeneration`'s `WeatherGenerator.swift`, which the harness calls
   directly for every game. Files that are new and uncommitted count as changes; without
   that, an uncommitted file in `FMSimulation/Sources` would be invisible and the answer
   confidently wrong.
2. The world checksum at seeds 7 and 11 is the same on the working tree and on the base.
   It builds the base in a scratch directory extracted with `git archive` — nothing
   touches your index or working tree — and asks both with `--world-checksum-only`.

`FMGeneration`'s sources are deliberately absent from that first list. Generation reaches
the harness only through the world it builds, and the checksum covers every part a
`GeneratedWorld` stores that can reach a snap — including `world.players`, the map the
engine is handed, and the length of every variable-length group — so a generator change
that moves nothing the harness plays is exactly the case this tool exists to wave through.
The parts it leaves out are the ones no snap reads: the college pool beyond its size, a
club's colours, and the boundary between its city and its nickname. What it cannot speak
for is anything the world does not store: the weather drawn per game is why
`WeatherGenerator.swift` and that package's manifest are watched by name. Nor can it speak
for the toolchain — it compares two builds made minutes apart on one machine, which is the
case it is for.

### Its self-test

```bash
./scripts/harness-reach.sh --self-test
```

The test for the script, in the shape [`lint-sim.sh --self-test`](#the-self-test) uses. It
copies the working tree into a scratch repository, commits it as a base, and applies six
scripted changes whose answers are known:

| Scripted change | Expected | Which arm decides |
| --- | --- | --- |
| An engine constant in `Fumbles.swift` | `run` | the file list |
| A line appended to `docs/tools.md` | `skip` | both, having found nothing |
| `WorldGenerator.strengthSpread` | `run` | the checksum — no watched file moved |
| `RivalryGenerator`'s events per season | `skip` | the checksum — the harness draws no rivalries |
| `world.players` given five points of speed the rosters do not have | `run` | the checksum |
| A depth chart repartitioned over the same men | `run` | the checksum |

A scenario that answers wrongly, or answers rightly for the wrong reason — every case but
the first two is decided by the checksum with no watched file moved — fails the run and
prints what it got. If a fixture edit stops applying because the constant it names has
moved, that fails too, loudly, rather than turning into a scenario that tests nothing.

The last two are the first review round's findings on #72, kept as scenarios rather than
as a reviewer's memory: both moved the harness by hundreds of lines while the checksum
called the two leagues identical.

It builds a harness per scenario that reaches one — a few minutes on a warm Linux
container, longer from cold — so run it when you change the script. CI does not run it, deliberately: the determinism step in the `test` job is the cheap guard
that runs on every push.

## test-census — what the suite asserts

```bash
./scripts/test-census.sh
```

Counts the kind tag on every `@Test` in every test target, per target and per suite, and
prints the shares. Exits 1 on a test that carries no kind or carries two, naming it as
`file:line: what is wrong`; exits 2 when it would otherwise have passed by counting
nothing. It takes under a second — it is a text scan, not a build.

```text
test census — 717 @Test declarations in 5 targets

  target           football   contract       unit        pin   untagged   total
  FMRandom          0   0.0%    3   9.1%   30  90.9%    0   0.0%    0   0.0%      33
  FMCore           28   8.6%   27   8.3%  268  82.7%    1   0.3%    0   0.0%     324
  FMGeneration      0   0.0%   66  38.2%  107  61.8%    0   0.0%    0   0.0%     173
  FMSimulation     59  33.7%   50  28.6%   63  36.0%    3   1.7%    0   0.0%     175
  simharness        0   0.0%    9  75.0%    3  25.0%    0   0.0%    0   0.0%      12
  all              87  12.1%  155  21.6%  471  65.7%    4   0.6%    0   0.0%     717
```

The kinds are `.football`, `.contract`, `.unit` and `.pin`, defined in CLAUDE.md under
*Conventions → Tests* and declared per test target in `TestTags.swift`. What the shares
mean, and what the first census found, are in [testing.md](testing.md) — that page is
where a number from this table gets argued with, not this one.

`--list` prints one line per test, `file:line: kind`, which is how you find out what a
suite is made of without reading it:

```bash
./scripts/test-census.sh --list | grep FMSimulation | grep football | wc -l
```

CI runs the census as a hard-failing step of the `test` job on both architectures and
writes the table into the job summary, so the shares are in front of whoever opens the
run. It is architecture-independent — it reads source, not behaviour — so the two legs
print the same table, and that is the cost of not having a third job.

The scan is deliberately literal. A line that *begins* with `@Test` opens an attribute,
which is then accumulated until its parentheses balance: that is what makes a multi-line
attribute and a parameterised test count once each. Lines inside a `"""` string and
inside a `/* */` block are skipped, so prose about a `@Test` does not become one. A
`@Test` written any other way is meant to be missed here and caught in review — and the
per-target totals printed above are the check on that, because they have to agree with
what `swift test` reports it ran.

### Its self-test

```bash
./scripts/test-census.sh --self-test
```

The test for the script, in the shape [`lint-sim.sh --self-test`](#the-self-test) uses.
It censuses [`scripts/test-census-fixtures/`](../scripts/test-census-fixtures) instead of
the packages: two Swift files that are never compiled and never part of a package, one
carrying a test of each kind plus every shape the scan has to get right — a multi-line
attribute, a parameterised test, a tag on the `@Suite` rather than on the test, a struct
with no `@Suite` at all, and `@Test` written inside a doc comment, inside a block comment
and inside a multi-line string — and one carrying the four ways a test can fail to say
what kind it is.

Every test the fixture tree must produce is listed in
`scripts/test-census-fixtures/expected.txt` as `path:line: kind`, and a difference in
either direction fails: a shape that quietly stops being counted is caught as loudly as
one counted twice. So a new shape needs a fixture and an expectation line. It runs in
under a second, and CI runs it as its own hard-failing step.

## Formatting

```bash
swift format lint --strict --recursive --parallel Packages/ Tools/   # before committing
swift format --in-place --recursive --parallel Packages/ Tools/
```

`--strict` is not optional: without it `swift format lint` prints its findings and still
exits 0, so a script that trusts the exit code passes while CI fails.

## Getting a toolchain

Containers start without Swift. Web sessions need it installed once per session:

```bash
command -v swift || ./scripts/install-swift.sh
```

This requires the environment's network policy to allow `download.swift.org`.
