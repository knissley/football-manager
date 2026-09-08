# 0008. Win probability as shared infrastructure

**Status:** Accepted
**Date:** 2026-09-08

## Context

Several apparently unrelated product requirements turn out to need the same thing:

- Explaining why a team is winning or losing, decomposed by unit and situation
- A league-wide highlight reel that surfaces genuinely notable plays
- Knowing that a Week 18 game against a rival has a playoff spot on the line, so the
  app can build it up beforehand
- AI coaches making sensible fourth-down, two-point, and clock-management decisions

Each could be built separately with its own heuristics. Highlights could use a "big
play" rule of thumb, drama could use standings proximity, the AI could use a lookup
table.

## Decision

Build one win-probability model in `FMAnalysis`, early, and derive all four from it.

- **Interrogation** aggregates WP swings by unit, personnel, and situation.
- **Leverage** is `|ΔWP|` for a play. The highlight reel is a sort over leverage across
  the league — a query, not a feature.
- **Drama** is computed by simulating the remaining schedule and measuring how much a
  game moves each team's playoff odds.
- **AI decisions** maximize win probability, with coach aggression shifting thresholds.

## Consequences

- Four requirements collapse into one system with one place to be correct and one place
  to tune. The highlight reel in particular becomes nearly free given the event stream.
- Highlights are principled rather than heuristic: a 4-yard fourth-quarter conversion
  that swings the game outranks a meaningless 60-yard catch in a blowout, which is what
  a real highlight show does.
- The AI gets consistent decision-making for free, and its choices are explainable in
  the same currency the player sees — the app can show you what the coach was thinking.
- **A wrong WP model is wrong everywhere at once.** Bad calibration means bad
  highlights, bad drama detection, bad AI decisions, and misleading explanations,
  simultaneously. It needs its own tests: monotonicity properties (leading is never
  worse than trailing at the same field position) and calibration checks against
  simulated outcome frequencies.
- WP must be fast — it's evaluated per play across the league, and inside the AI's
  fourth-down search. A lookup/regression over a compact state (score margin, time,
  down, distance, field position, timeouts) rather than a nested simulation.
- It has to exist before the analysis layer is useful, which puts it early in M2, ahead
  of features that look more urgent.

## Alternatives considered

**Separate heuristics per feature.** Each is simple in isolation and none blocks the
others. Rejected: four sets of tuning, four ways to be inconsistent, and a highlight
reel that disagrees with the analysis screen about what mattered.

**Defer WP until the AI needs it.** Would let the news and highlights ship sooner on
simpler rules. Rejected because those rules would then be replaced, and the early
version of the feature would be the one that sets expectations.
