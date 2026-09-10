# Penalties

**Status: partly built, sections marked.** Both classes of foul are in the engine:
procedural fouls drawn from `discipline`, noise and tempo, and desperation fouls drawn at
the matchup that beat the man committing them, with accept/decline evaluated on both
branches. The harness prints the per-foul rates and the road-versus-home pre-snap ratio.
*Not built:* officiating crews with tendencies. *Known wrong:* live-ball fouls are
enforced from the previous spot (#18), a flag on a try does not move the try (#19), and
fouls after a score are not enforced on the kickoff (#48).

A soul-crushing offside in a playoff game has to be possible. Getting there means
being careful about *why* flags happen, because the obvious implementation — roll
a die each play — produces penalties that are frequent, meaningless and
inexplicable.

## Two classes, and only one of them is a roll

**Discipline penalties** are procedural. False start, offside, delay of game,
twelve men, illegal formation. No matchup produced them; somebody broke a rule.
These come from a player's `discipline` rating, his coaching, and the situation.

**Desperation penalties** are what a player does when he is *losing*. A hold is
what happens when a tackle is about to give up a sack. Defensive interference is
what happens when a corner is beaten deep. Their probability rises with how badly
the matchup is going, so they **emerge from the resolution model** rather than
being drawn beside it.

That second class is what makes a flag explicable: *he held because he was beaten
in 1.9 seconds*, with the pressure decision point sitting right there in the play
record. It also means a bad offensive line commits more holds without anyone
tuning a holding rate — which is both true and satisfying.

## Home field advantage should emerge from this

Crowd noise raises false starts, illegal shifts, and delay of game for the
visiting offence. Model that and home advantage becomes a **mechanism** — noise,
pre-snap penalties, drives stalling — rather than a "+2 to the home team" applied
after the fact, which the engine's honesty pillar would otherwise have to swallow.

The same shape covers twelve men on the field. That is a *substitution* failure,
not a player failure: its probability comes from defensive personnel churn
against offensive tempo. Which makes hurry-up a genuine weapon rather than a
clock tactic — it does not merely save time, it catches defences with twelve on
the grass.

## Cadence

**Hard Count** is a quarterback trait that raises the opponent's offside and
neutral-zone rate — and raises his own line's false-start and delay-of-game risk.
A good trait with a real cost, which is what the [traits](traits.md) design asks
for, and it turns fourth-and-short into a genuine decision.

Beyond that, **drawing a foul is a by-product of winning a matchup rather than a
separate mechanic.** A receiver who beats his man draws interference because the
defender is losing; an edge rusher who beats his tackle draws a hold. No trait
needs to reach across and modify an opponent's rate — the existing model already
produces the effect, and every trait keeps acting on its own holder.

## The engine never reads leverage

A flag is not more likely because it is January. That would be authoring drama,
and [pillar 1](vision.md#design-pillars) forbids it.

It does not need to be. The penalty is exactly as likely as it always was and
simply *matters* more, and the highlight and news layers surface it automatically
because |ΔWP| is enormous ([ADR-0008](adr/0008-win-probability-keystone.md)). The
moment lands precisely because nothing arranged it.

Fatigue and crowd noise do affect discipline, and both correlate with late, loud,
tense situations — so the effect a player expects arrives without the engine ever
knowing what a playoff game is.

## Accept or decline

The choice is **yours while you are calling plays, and your coordinator's when
you are not** — consistent with toggle-at-will everywhere else.

Both branches are simulated and compared on win probability, so the recommended
option is always known and always explicable: *declining leaves them third and
twelve; accepting gives them fourth and five*. Your coordinator's play-calling
quality determines how often he takes the better branch, which is one more small
place a good staff is visible.

## Officiating

The engine reads an **`OfficiatingProfile`** — per-category tightness, known
before kickoff so it is a gameplanning input rather than a random tax, and modest
in magnitude, shifting rates by something like 15–20% rather than doubling them.

Where the profile *comes from* is a separate question, and deliberately so. Named
crews with tendencies are one generator; an anonymous per-game roll is another.
The engine cannot tell the difference, so **walking back named officials means
deleting a generator, not unpicking a feature.** Same pattern as gameplan presets
over a rule set: keep the rich representation canonical and make the convenient
surface a generator over it.

Officiating variance is a league-wide slider, which locks at career creation like
the rest ([decision 26](design-decisions.md)).

Officials are `Personnel`, so they age and retire like everyone else. A crew you
have learned to dread will eventually stop working, and somebody new will take
over — which is the answer to the fiftieth-season problem that named officials
would otherwise create.

## The foul list

Thirty-three fouls: the pre-snap set, blocking and line-of-scrimmage fouls,
coverage and receiving, contact, kicking, and conduct. Enough that play-by-play
sounds like a broadcast rather than a rulebook subset, and bounded enough that
each one can have real enforcement.

Each carries its standard yardage (5, 10 or 15), whether it awards an automatic
first down, and which side can commit it. **Pass interference is the only spot
foul**, enforced from where it happened, which is what makes deep interference
the highest-variance call in the sport.

Declined penalties are recorded too. A flag that was thrown and waved off is part
of what happened, and discarding it would make the play log disagree with what a
viewer saw.

## Calibration

Penalties are part of the [match engine's targets](match-engine.md#calibration):
the accepted total per game across both teams at default sliders, and the mix — a
band per game for each of the ten most common fouls, sourced from the 2023 and 2024
seasons. Holding and false starts lead, interference is rare but enormous.

Two effects worth asserting once the engine exists, because they are the point of
modelling penalties this way rather than as a die roll:

- Road teams commit measurably more pre-snap penalties than home teams.
- Teams facing hurry-up offences commit measurably more substitution fouls.

## Build order

Penalties land in M2 with the crude engine, and deepen with the spatial one.

1. `Foul`, yardage, automatic first downs, spot fouls — done, in `FMCore`.
2. Pre-snap discipline penalties from ratings, coaching and crowd noise.
3. Accept/decline on win probability, with coordinator quality.
4. Desperation fouls emerging from matchup resolution.
5. `OfficiatingProfile`, sourced from named crews.
6. Substitution fouls against tempo.
7. Calibration, including the road and hurry-up effects above.
