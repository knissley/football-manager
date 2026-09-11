# Penalties

**Status: partly built, sections marked.** Both classes of foul are in the engine:
procedural fouls drawn from `discipline`, noise and tempo, and desperation fouls drawn at
the matchup that beat the man committing them, with accept/decline evaluated on both
branches. The harness prints the per-foul rates and the road-versus-home pre-snap ratio.
*Not built:* officiating in any form — there is no `OfficiatingProfile`, no per-category
tightness and no crew, so the whole [Officiating](#officiating) section is design. Nor is
there an officiating slider. *Known wrong:* fouls after a score are not
enforced on the kickoff or the try (#48, C9); until then a foul by the team scored upon is
recorded declined and the score stands. Live-ball fouls are enforced from the right spot
(#18) and a flag on a try moves the try (#19), both fixed in wave 1.

A soul-crushing offside in a playoff game has to be possible. Getting there means
being careful about *why* flags happen, because the obvious implementation — roll
a die each play — produces penalties that are frequent, meaningless and
inexplicable.

## Two classes, and only one of them is a roll

**Discipline penalties** are procedural. False start, offside, twelve men,
illegal formation. No matchup produced them; somebody broke a rule. These come
from a player's `discipline` rating, his coaching, and the situation.

**Delay of game is the one that is neither**, and it used to sit in the list
above as though it were. In the sport it is not a foul anybody commits: it is a
clock running out `[2025 · 4-6-1, 4-6-2]`, and the whistle at the end of it is
the foul `[2025 · 4-6-4]`. Drawn beside the down like a false start, it was a
rate nothing could answer — and the thing the sport answers it with, a charged
timeout, could not reach it, so a bench spending one to avoid the five yards
bought nothing at all.

So the interval is settled first and the consequence second.
`PlayResolver.overrunsThePlayClock` asks whether this offence gets this snap
away inside the clock in force — the clock's length is the rules layer's, the
tempo and the crowd are the resolver's — and the answer is a fact about the
interval rather than a foul. The rules layer then puts it to the offence, which
may stop the clock with a charged timeout `[2025 · 4-3-2]` and play the down for
the price of a timeout instead of five yards, and only what nobody stopped
becomes a flag. A resolver that has no model of the interval never loses a play
clock, so a scripted game is not sprinkled with delays of game it did not ask
for.

**Desperation penalties** are what a player does when he is *losing*. A hold is
what happens when a tackle is about to give up a sack. Defensive interference is
what happens when a corner is beaten deep. Their probability rises with how badly
the matchup is going, so they **emerge from the resolution model** rather than
being drawn beside it.

*When* a foul can be drawn is a rule, not a preference, and the two coverage
families differ. Defensive holding and illegal contact are restrictions that begin
at the snap, so they are drawn in the coverage loop, on any receiver, before
anybody has thrown anything. Interference cannot exist until a forward pass is in
the air — `[2025 · 8-5-1]`, which also confines the defence's restrictions to the
window between the throw and the ball being touched — so both kinds are drawn only
once a target has been chosen. A sack, a scramble and a throwaway carry no
interference at all.

Drawing them **only on the target's matchup is our simplification, and 8-5-1 does
not say it.** That article protects any eligible receiver and gives both sides the
same right to the ball, so the real game has interference away from the throw: a
defender hooking the man on the far side, an offensive pick nowhere near the catch.
The crude resolver picks one target and keeps no separation for anyone else once
the ball is gone, so the target's matchup is the only one it has to draw on. What
the simplification costs is exactly those away-from-the-ball flags.

**The defence's interference is drawn as the cause of an incompletion, not beside
one.** The order is: draw the flag at the throw, then resolve the catch with the
flag in hand. 8-5-1 defines the foul as contact that spoils an eligible
receiver's chance at the ball, so the flag and a catch by that receiver are two
events that cannot both have happened — and a model that throws one and then
completes the pass is graded on whatever the accept-or-decline choice leaves
behind, which is how a draw three times too large sat under a rate near its band.
The offence's is the other way round and stays that way: 8-5-2 lists a shove or a
push-off that buys a receiver room, and the Penalty clause of Rule 8 Section 5
costs ten yards from the previous spot, which brings a catch back rather than
presuming there was not one.

**And neither kind is drawn on a throw nobody could reach** `[2025 · 8-5-3-c]`,
which makes contact that would otherwise be interference permissible when the pass
is clearly uncatchable by the players involved. The article's own exception is the
offence's blocking downfield `[2025 · 8-3-2, 8-5-4]`, which this engine does not
model as an act of its own, so the exception has nothing to except here. Without
that gate the defence's spot foul hands the offence the ball at the catch point
for contact the rules do not make a foul at all.

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

**Partly built.** The second half is built and is how fouls are drawn today: a hold or an
interference comes out of losing a matchup rather than a separate roll. *Designed, not
built:* Hard Count, and every other trait — nothing in `FMSimulation` reads a trait.

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

**Designed, not built.** No `OfficiatingProfile` type exists, and foul rates come from
the player, his coaching and the situation with nothing officiating them. The last
paragraph is the one that is already true in principle: `PersonnelRole.official` is a
case, and `Personnel`'s hidden retirement age gives an official the same career every
other person in the league gets. What does not happen is anyone being *made* — nothing
calls `PersonnelGenerator`, so no world contains an official to age. The point of
recording the design now is still the last paragraph's: the representation is chosen so
that dropping named crews later deletes a generator rather than unpicking a feature.

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
first down, which side can commit it, and **where it is enforced from**, which is
`Foul.enforcement` and one of three families (2025 rulebook, 14-3-4):

- **The previous spot.** Every foul before the snap (14-4-1); the offence's fouls at
  or behind the line — holding, illegal use of hands, ineligible downfield (14-3-6,
  exception 1); and the passing game until the catch — defensive holding, illegal
  contact, interference by the offence (8-6-1). Walked off from the line of scrimmage,
  the down replayed unless the foul carries a first down.
- **The spot of the foul.** Interference by the defence (8-6-1-b), which is what makes
  deep interference the highest-variance call in the sport; in the end zone it is the 1,
  or half the distance from the previous spot when that was inside the 2. And a block in
  the back, a blindside block or a low block beyond the line by the team in possession,
  which is behind the basic spot of a run that went on past it (14-3-6). The resolver
  measures the spot and reports it as `PenaltyRecord.enforcementSpot`; a block during a
  run is placed halfway along it, and a block during a return halfway along the return,
  both modelling conventions.
- **The succeeding spot** — the dead-ball spot, with the play's gain counting. The
  contact family: facemask, unnecessary roughness, horse collar, the helmet, roughing
  the passer on a completion (14-3-5-a, 14-3-6, 8-6-1-d); and conduct after the
  whistle (12-3-1). On a play that lost yards or fell incomplete the previous spot is the
  better one for the offence, and that is the one used. A defensive foul in this family
  is an automatic first down. A live-ball foul in this family by the team that scored
  wipes its score, because the play is enforced and replayed: from the spot of the foul
  by the three-and-one method (14-3-6), which the record does not carry, so the
  previous spot stands in; a dead-ball conduct foul by the scorer leaves the score
  standing, recorded declined, until C9 (#48) enforces it on the try or the kickoff.

Enforcement is computed **in the frame of the team that will snap next**, once, in
`Rules.enforce`. A foul by the team that ended the play without the ball is walked off
against it; a foul by a defence that took the ball away gives it back (14-4-3-a); a
personal foul by an offence that lost the ball leaves the new possessor in possession,
walked off from the dead-ball spot in its frame (14-4-3-b). Half the distance to the
goal is measured from whichever spot the foul is enforced from (14-2-1), so a facemask at
the 6 after a run gives the 3. Measuring every foul from the previous spot, as the engine
did until wave 1, offered the offence fifteen yards from the old line against its own
twenty-yard run, so the whole contact family was declined.

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
