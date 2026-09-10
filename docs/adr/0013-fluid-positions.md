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

## Amendment 2026-09-10 — what measurement found

Recorded after the September 2026 audit measured the two premises the decision rests on
and found both untrue of the tree, and after the first of them was made true. The
decision above is unchanged; this section is an amendment under the rule in
[README.md](README.md), and the body it amends was not edited to match.

**The honest penalty did not exist, and now does.** The context above says a player
evaluated at a position he carries no ratings for "scores from what he does have rather
than being punished for absences", and the alternatives section rejects a flat
out-of-position penalty because `overall(at:)` "derives it from the ratings the player
actually has". It did the opposite. A rating a position did not use was absent, and
`PositionWeights.overall` dropped the weight of any absent key and renormalised over the
rest, so a receiver at quarterback was scored on his awareness and speed alone. Measured
at seed 7 on the tree the audit read: receivers averaged 66.7 at quarterback against 62.2
at receiver, a kicker rated a 64 quarterback, and running backs rated 65.9 at linebacker
against natives at 61.6. Absence was a bonus, and "68 as a tight end, 81 as a receiver"
was a number nobody could trust.

The mechanism is replaced ([decision 217](../design-decisions.md#ratings),
[#25](https://github.com/knissley/football-manager/issues/25)). Every player carries every
key; a rating his position does not train is present and low, drawn by generation from an
untrained table by key family and by whether the job sometimes asks for it; and
`overall(at:)` weighs it like any other. The same probe afterwards: receivers 36.5 at
quarterback, kickers 33.8, backs 35.7 at linebacker, tight ends 52.3 at left tackle
against natives at 72.6, nobody out-rating the best native at any of the four, and nobody
moved at his own position. The penalty the decision wanted is derived from the ratings
the player has, as the alternatives section says — it is only that he now has all of
them, and the ones he never trained are the low ones.

**Snaps by position are a query, but not the one the decision names.** The context says
`Participation` records the position a player occupied on every snap, so how much he
played somewhere "is already a query over the event stream". It was not. Decision 97 made
credits sparse, so `Participation` named only the men who did something — linemen on
three to five of every five snaps, safeties on 17% of run plays — and a snap count could
not be asked of the stream. The query that development-follows-snaps reads is the
on-field record ([#21](https://github.com/knissley/football-manager/issues/21),
[play-record.md](../play-record.md)): `PlayRecord.onField`, twenty-two roster indices in
slot order into `GameResult.rosters`, and `snapCounts(rosters:)` over a game's plays.
Credits stay sparse; presence is its own fact. This paragraph is written against that
record as pushed on `fix/wave2-b-record`, ahead of its merge.

**Nothing requires a fullback.** The decision says legality "permits one back, five
linemen and any mix of tight ends and receivers — and no fullback ever", which misstates
its own point: the rules of the sport do not forbid a fullback, they do not require one.
Read it as: seven on the line and five ineligible permit a formation with no fullback in
it, and `SlotLayout.offense(_:)` placing one for the second back was the code's habit,
never the sport's demand.

**The arbitrage stays gated until the AI can work it.** The consequences section says the
receiver-at-tight-end arbitrage "is only skill if the AI can do it too", and the open
question above admits the AI clause is a statement of intent. Until that question is
answered nobody gets the move: the depth chart is keyed by position, `Lineup.fill`
matches on it, and a receiver cannot be made the second tight end by a human either. The
rekeying by role, the legality checker and the AI move question are implemented together
at [M3.5 of the roadmap](../roadmap.md) — after M3 and before the first depth chart
screen in M4, with roles defined once alongside the M6 formation vocabulary — so the
freedom and the AI's use of it land in the same milestone. The open question above is
scheduled there rather than left open.
