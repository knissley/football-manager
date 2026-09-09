# Audit: is this football?

A deliberate pass over the engine asking one question — *does this behave like the sport?*
— rather than *do the units work?* Separate from the end-of-M1 systems inventory, which
asks whether designed systems are wired in. This one assumes they are and asks whether
what comes out is a football game.

Findings in severity order. Every number is from `simharness --games 400 --seed 7`, whose
output now carries the rows that produced them.

## Why the audit found so much

The calibration table measures the passing and running game — yards, completion rate,
sack rate, third-down rate — and **almost nothing about a game of football**. There was no
row for where drives start, how they end, what fraction of points come from kicks, or what
a final score looks like. The engine was tuned against the rows that existed, and
everything the rows did not cover drifted unchecked.

Every finding below is visible in one page of harness output. Nobody had printed that
page.

## S1 — The scoreboard does not play football

`Rules.advance(from:outcome:)` switches on `PlayEnding` alone and never looks at
`PlayKind`. A try is therefore not modelled as a try:

- **A made extra point scores 3 points**, and is recorded as a `.fieldGoal`.
- **A successful two-point conversion scores 6 points**, and is recorded as a
  `.touchdown`.
- **The two-point try is snapped from the 15**, not the two. `Rules.twoPointSnapYard = 2`
  is defined and read by nothing, so a conversion needs fifteen yards. Across 800
  team-games: 44 attempts, **zero successes**.

The evidence is on the scoreboard. Summing scores at their correct values gives 19.3
points per team-game; the engine's own total is 23.0. The 3.7-point gap is exactly
1.8 extra points × 2 points too many. And the most common finals are 24-21, 24-12, 30-24,
21-18, 30-21 and 18-15 — every one a multiple of three, because a touchdown with the kick
is worth nine and a field goal is worth three.

**The `points 20.0–26.0` calibration row is a false pass.** Corrected, the engine scores
19.3 and is under target. Every tuning decision made to keep that row green was made
against a broken number.

## S2 — Field position is a dead variable

Field position is one of the two or three things a football game is *about*. Here it
barely moves.

- **94.6% of drives start in the offence's own half** (real: 75–80%). Average start is the
  own 24 (real: own 28–29).
- **Every kickoff is a touchback, 100% of the time.** No returns, no squibs, and no onside
  kick — so a trailing team can never get the ball back after scoring, which removes a
  whole phase of endgame football.
- **Kickoff touchbacks use the punt spot.** `Advancement` routes both through
  `puntTouchbackSpot`, the own 20. A kickoff touchback is the 30 under current rules (the
  25 before 2024), so every possession after a score starts five to ten yards too deep.
- **No punt returns.** A punt is a fair catch or a touchback. Net punting reads 44.5 yards
  against a real 41–42 — flattering, because nothing is ever returned.
- **No fumbles at all**, and an interception is spotted where it was caught with no return,
  so a pick six is arithmetically impossible.

Turnovers end 8.2% of drives against a real 11–12%, and the short field that makes a
turnover worth more than its count does not exist.

## S3 — One personnel grouping, one defensive package, all game

Every snap of every game is `11` personnel against `base` defence. `PersonnelGroup` and
`DefensivePackage` are complete, tested `FMCore` types that the engine never sets: nothing
in `FMSimulation` writes `Situation.offensePersonnel` or `.defensePackage`.

- On third and fifteen the defence has four defensive backs. **Nickel — the most-played
  defence in the modern game — never appears**, nor dime, goal-line or prevent.
- `DefensiveCall` carries a `package` the resolver never reads. Of its six dimensions
  three are read (`coverage`, `rush`, `runFit`) and three ignored (`frontAlignment`,
  `package`, `disguised`). `OffensiveCall.usedMotion` is ignored too.
- The kicking units field **eight men, not eleven**.
- `DepthChart.unmannedPositions`, written to report a group with nobody left to play it,
  is called by nothing. A depleted group silently plays a man short.

## S4 — Fourth down and the endgame are too tame

- **Drives end on downs 1.5% of the time**; real is 5–6%. `BaselineCaller` punts or kicks
  in nearly every fourth-down situation, so the most-discussed decision in the modern game
  barely occurs.
- Two-point tries happen 0.1 times per team-game and have never succeeded (see S1).
- **9.8 drives per team-game** against a real 11.3–11.7.

## S5 — The kicking curve is wrong in the middle

| distance | engine | real |
| --- | --- | --- |
| 0–29 | 99.0% | ~98% |
| 30–39 | 88.6% | ~91% |
| 40–49 | **69.4%** | ~82% |
| 50–55 | 60.1% | ~62% |

The ends land and the middle sags by thirteen points. The extra point runs through the
same curve as a 32-yard field goal, which is why it is made 85% of the time against a real
94–96%.

Nothing about a kickoff depends on the kicker: the outcome is a constant, so leg strength
is irrelevant on the one play it most obviously matters.

## S6 — 21 of 33 fouls never occur

Never produced: encroachment, illegal formation, illegal motion, illegal shift, illegal
substitution, illegal use of hands, illegal block in the back, blindside block, chop
block, tripping, ineligible receiver downfield, illegal man downfield, **offensive pass
interference**, horse-collar, illegal use of the helmet, low block, **roughing the
kicker**, running into the kicker, illegal touching, unsportsmanlike conduct, taunting.

Special teams draw no flags at all: `Penalties.preSnap` runs only on run and pass
families, so there is no false start on a field goal and no offside on a punt.

## S7 — Calibration runs in conditions no game is played in

The harness passes no stadium and no weather, so every calibration game is at "Neutral
Field" with crowd noise 50 and clear skies. **Home-field advantage and weather are
mechanisms with no evidence behind them** — they have never been measured, because the
measurement has never included a home field or a forecast.

## What this changes about how we calibrate

The calibration table needs rows for the game and not only the play: where drives start,
how they end, the split of points by source, kick accuracy by distance, and the shape of a
final score. Those rows are now in the harness under **Is this football?** and should move
into [`match-engine.md`](match-engine.md#calibration) as targets rather than observations.
