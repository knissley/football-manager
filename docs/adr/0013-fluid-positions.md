# 0013. Separate a player's personnel position from where he lines up

**Status:** Accepted
**Date:** 2026-09-09

## Context

`Player.position` is a single stored value, and everything reads it as though it were a
fact about the player: the depth chart is keyed by it, `Lineup.fill` matches on it, the
contract market prices by it, and `Player.overall` means "overall at that position".

Football does not work that way. A big, fast receiver lined up at tight end is a matchup
problem and a poor blocker, and both of those are true at once. A rangy safety plays
linebacker in nickel. In a 3-4 the edge rusher *is* an outside linebacker. Teams have not
carried a fullback as a matter of course for two decades, and nothing about the sport
requires one.

The engine currently forces the opposite. `SlotLayout.offense(_:)` places a `.fullback`
for the second back because that is what the code was written to do, not because the
grouping demands it. Positions are matched by name, so a player can only fill a slot that
carries his label.

Two capabilities already exist and are unused. `PositionWeights.overall(_:at:)` is public,
takes *any* position, and its documentation already says a player evaluated at a position
he carries no ratings for "scores from what he does have rather than being punished for
absences" — a receiver at quarterback rates badly for throwing and well for running,
which is exactly the intended behaviour. And `Participation` records the position a player
occupied on every snap, so how much he actually played somewhere is already a query over
the event stream.

What breaks without a decision: the roster screen cannot answer "how good is he at tight
end", the AI cannot value a positional move, and every lineup rule stays hardcoded in slot
tables rather than following from the rules of the sport.

## Decision

**A player has a personnel position and a lineup position, and they are different things.**

- **Personnel position** is his identity. It is what he is paid like, traded as, and
  listed as. It changes rarely and deliberately.
- **Lineup position** is where he plays on a given snap. It is assigned through the depth
  chart, changes freely, and decides everything about how he performs.

**Overall is position-relative and always was.** "A 99 overall receiver" means 99 *as a
receiver*. `overall(at:)` is the honest form; the bare number means "at his personnel
position". The roster screen shows what he will be on game day, marks him as out of
position, and that mark is sometimes a *positive* — the point of moving him.

**The depth chart is keyed by role, not by position.** Third-down back, nickel corner,
dime corner. A role is what a formation asks for and what a player is assigned to, which
is what lets a coverage linebacker be the designated dime defender and stay on the field.

**The scheme owns the base formation, and it must always be fieldable.** A 3-4 fields
three down linemen and four off-ball defenders; the roster has to be able to produce that
eleven. Packages morph it during a game as the situation calls for them.

**Legality is enforced from the rules of the sport, not from archetypes.** Seven on the
line of scrimmage, five ineligible. That permits one back, five linemen and any mix of
tight ends and receivers — and no fullback ever — while ruling out the absurd. The same
check governs play design: a player drawing up a play cannot draw an illegal one.

**Development follows where he actually played.** A season spent at tight end develops
blocking more than a season spent split wide, and the snap counts that decide it are a
query over `Participation`, not a parallel tally. On top of that every player carries an
**adjustable development path** — deep accuracy, route running, run blocking, speed rush —
which the user sets and changes whenever.

**There is no unfamiliarity cost.** A converted player is exactly as good as his ratings
at the new position say he is. Learning curves are a system we are choosing not to build.

**The AI does all of this too.** A capability the user has and the other thirty-one teams
do not is not a feature, it is a permanent structural edge.

## Consequences

The roster becomes the most interesting screen in the game. Finding that a receiver rates
better as a tight end than the tight ends do is exactly the discovery the GM half is for,
and it costs nothing to try.

It creates a real arbitrage, deliberately: sign a receiver at receiver prices, play him at
tight end, get tight end production. That is GM skill and it should pay — but it is only
skill if the AI can do it too, which is why the AI clause above is not optional.

`DepthChart` is rekeyed from position to role, which is a breaking change to a type that
`Lineup.fill`, `RosterGenerator` and the rotation profile all depend on. `RotationProfile`
is currently per position and will need to be per role.

`Player.overall` as a bare number becomes a smaller, more careful thing. Every place that
compares players — trade value, contract demands, best available, the draft board — has to
say *at what position*, and the honest default is his personnel position.

Development gains a dependency on the season's event stream. That is the right direction
per [ADR-0007](0007-event-stream-contract.md) and it means development cannot be computed
without the games having been played, which is a constraint on the offseason ordering.

We are committed to a legality checker that both the lineup editor and the play designer
share. Without it the freedom becomes nonsense, and building it twice would let them
disagree.

The cost we are accepting: two numbers for one player, in a genre where users are used to
one. If the roster screen does not make "68 as a tight end, 81 as a receiver" immediately
legible, this reads as a bug rather than a decision.

## Alternatives considered

**Keep positions fixed and add an out-of-position penalty.** Much simpler, and it is what
most games in the genre do — a flat rating hit for playing somewhere you are not listed.
It loses the whole point: the penalty is a number pulled from nowhere, whereas
`PositionWeights.overall(_:at:)` derives it from the ratings the player actually has, so a
big receiver at tight end is bad at blocking *and* good at everything else, rather than
uniformly worse.

**One position, freely editable.** Let the user change `Player.position` and be done. It
collapses the two concepts, which means either a Sunday experiment rewrites his contract
market, or the market ignores where he plays. Both are wrong, and the second is the one
that quietly breaks the economy.

**Constrain the roster rather than the eleven** — require four linebackers to run a 3-4.
Appealing because it is easy to check and easy to explain. Rejected because it enforces
the constraint in the wrong place: it would forbid a coverage safety from being the fourth
linebacker, which is precisely the move this ADR exists to allow.

**Model unfamiliarity.** A converted player being worse than his ratings for a season is
real football and would add texture. Rejected for now as a system whose learning curve we
would have to tune with no way to validate it, and which makes every positional move feel
punitive at the moment the user is being invited to experiment.

## Open

**How does an AI coach identify a move worth making?** The user can eyeball a roster and
notice a receiver who would rate better at tight end. A search over every player against
every position is cheap enough at roster size, but "rates higher" is not the same as
"worth doing" — it has to account for what he leaves behind and what the scheme needs.
Unresolved, and until it is, the AI clause above is a statement of intent rather than a
built thing.
