# Player development

How players grow, decline, and occasionally leap — and why the league does not
inflate into a collection of 99s.

## Performance reveals development; it does not cause it

A defensive end has been on your roster three years and finally posts ten sacks.
Does he compound on that, or was it a career year?

The answer was fixed before the season started. Every player carries a hidden
**ceiling** and a hidden **development trait**
([decisions 21 and 34](design-decisions.md)). A breakout season is *evidence*
about those values, not an input to them:

- High ceiling, good trait → the season was real. He keeps climbing.
- Low ceiling → that was variance around what he already was. He regresses.

**You cannot tell which at the time**, which is exactly the fog the rest of the
game already runs on. Same shape as scouting a prospect, discovering a trait, or
working out whether a bust is fixable: hidden truth, observable evidence, belief
held per observer.

This is also why there is no wheel to spin. Nothing is rolled at the moment of
reveal. The outcome was determined by who the player always was, and the season
told you — which is suspense, not a slot machine.

## What you control

Development is player-driven and you nudge it. Your levers are the roster
decisions you were making anyway:

| Lever | Effect |
| --- | --- |
| **Snap share** | The main driver for young players — and it costs you wins now |
| **Role** | Starter, rotational, situational; a role he can succeed in produces evidence |
| **Scheme fit** | A player asked to do what he is good at develops faster |
| **Mentorship** | Pairing a young player with a veteran of the same position |
| **Coaching** | Position coaches and coordinators change the rate, never the ceiling |

You caused the breakout by playing him. That is the authorship a random boost
takes away.

## Experience is weighted by leverage

Snaps are not equal. Development experience accrues from playing time weighted by
**leverage** — the win-probability swing of the situation
([ADR-0008](adr/0008-win-probability-keystone.md)).

A great game in a Week 17 blowout is worth less than the same game in a playoff
elimination. That is true to how the sport talks about itself, and it costs
nothing new: leverage is already computed for highlights, drama detection and AI
decisions.

Performance *above expectation* is what counts, not raw production. A running
back with 1,400 yards behind a great line has produced less evidence about
himself than one with 900 behind a bad one.

## Awards are thresholds, not payouts

An award does not grant a boost. The performance that won it has already been
counted, and paying it twice inflates the league.

Instead an award is a **threshold**: evidence strong enough that, *if* the
player's hidden ceiling supports a leap, this is the offseason it happens. Player
of the week is a small marker; Rookie of the Year or MVP is a large one. A player
who has reached his ceiling wins the award and does not move, which is both
realistic and the reason the system cannot inflate.

## The leap is the tail, not a separate mechanic

There is no "breakout" branch in the code. Growth is a single distribution whose
magnitude is gated by:

1. **Distance to ceiling** — the hard cap
2. **Development trait** — slow, normal, quick, or star
3. **Accumulated leverage-weighted experience**
4. **Age curve**
5. **Coaching and scheme fit**

A leap is simply the upper tail of that distribution. It is rare because ceilings
are rare, not because a die came up sixes.

Growth lands on the attributes his position and role actually use. A defensive
end's leap goes into pass-rush attributes; it never goes into kick power. Which
attributes improve is determined by position, scheme and traits — not rolled.

Every change is a `DevelopmentEvent`
([ADR-0009](adr/0009-event-sourcing-by-default.md)), so *why* a player grew is an
ordinary query, and the offseason reveal has evidence attached rather than being
an unexplained number change.

## The conservation law

The question underneath all of this is why the league does not drift upward
forever. Two structural answers, neither of which is tuning:

**Nobody exceeds their ceiling.** Ceilings are generated once from a realistic
distribution and never move. A league of 99s would require a league of 99-ceiling
players, which generation does not produce.

**Talent is conserved at the league level.** Aging decline offsets youth growth,
so total league talent is roughly stationary across decades. Breakouts do not add
points to the league — they *redistribute* them. For every end who leaps there
are veterans falling off and prospects who never arrived.

That turns balance from a tuning exercise into something the harness can assert.

## Calibration targets

Checked across fifty simulated seasons in `Tools/simharness`, alongside the
[match engine's targets](match-engine.md#calibration):

| Metric | Target |
| --- | --- |
| Mean league overall rating | Stationary within ±1.5 across 50 seasons |
| Standard deviation of ratings | Stationary within ±1.0 — no drift toward uniformity |
| Players rated 90+ | Stationary within ±20% of the starting count |
| Players who leap in a season | 1.5–3% of players under 26 |
| Of those, regressing the next season | 25–40% — one-season wonders are real |
| Peak age by position group | Within a year of the real curve |
| Career length distribution | Stationary |

The last row matters more than it looks: if careers lengthen, talent accumulates
even with fixed ceilings.

## Build order

1. Hidden ceiling and development trait in generation.
2. `DevelopmentEvent` and the projection that folds it into current ratings.
3. Age curves and decline — before growth, so conservation is testable early.
4. Leverage-weighted experience accrual.
5. Camp resolution and the offseason reveal.
6. Awards as thresholds.
7. Calibration against the table above.
