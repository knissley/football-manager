# AI play calling

The highest-risk system in the project. Because play calling is toggleable at will, the
AI calls most of the snaps in your own career and *every* snap in the other fifteen
games each week. Its quality sets the ceiling on league statistics, quick-sim
credibility, and whether the news feed is reporting on a league that plays good
football.

If delegating feels like losing, the feature dies and the player calls all 1,100 plays
of a season by hand.

## Your coordinator calls the plays

Delegation is a **staff decision**, not an anonymous engine. Your offensive coordinator
makes the calls; your gameplan sets the boundaries he works inside.

```
PlayCaller
├── Gameplan             your weekly constraints — the guardrails
├── CoordinatorProfile   his tendencies and quality — how he decides inside them
├── OpponentModel        what he believes about the other team
└── GameContext          down, distance, score, clock, field position, personnel
      ↓
   PlayCall              play + personnel + tempo
```

This turns the project's biggest technical risk into a mechanic. A great coordinator
makes simming ahead safe; a bad one is a reason to take the wheel yourself — and a
reason to go hire someone better in the offseason.

### Gameplan is constraints, not commands

Designed in full in [gameplan.md](gameplan.md). You never hand him a script. You set the
room he operates in:

- Run/pass lean as a **range**, not a number, varying by down and field position
- Fourth-down aggression, as a shift in the win-probability threshold
- Tempo preference
- Personnel and formation preferences
- Explicit rules — *never throw deep inside our own 10*, *attack their No. 2 corner*
- Things to avoid entirely this week

A good coordinator uses the room well. A bad one wastes it, or drifts to its edges.
"Overriding his tendencies" means tightening the guardrails until he has no choice.

### What makes a coordinator good

The critical rule, and the one that keeps the engine honest:

> **AI quality is decision quality. It never modifies outcomes.**

A bad coordinator does not roll worse dice. He makes *worse choices with the same
information* — runs on 3rd-and-8, abandons a working run game, kicks a field goal on
4th-and-1 from the 35. The play he calls then resolves through exactly the same physics
as anyone else's. This is the same principle as
[coach skills affecting information and staff but never the field](design-decisions.md).

```
CoordinatorProfile
  playCallingQuality    how close his choice sits to the WP-optimal one, given his info
  tendencyBias          personality: run-heavy, aggressive, conservative, gimmicky
  adaptability          how fast he updates his read of the opponent mid-game
  situational           strengths and weaknesses by phase — red zone, two-minute, short yardage
```

Personality here is a whimsy surface. A coordinator famous for going for it on fourth
down, one who abandons the run at the first sign of trouble, one who is brilliant in
the red zone and helpless in a two-minute drill — all of it is observable, commentable,
and something the news feed can needle him about.

## The opponent model

Each coordinator carries his own belief about the other team, built from what he could
actually have observed.

```
OpponentModel
  tendencies[situationBucket] → distribution over play families
  confidence[situationBucket] → grows with observation count
  personnelTells               what you run from 11 vs 21 vs heavy
  recencyWeighting             this drive ≫ this game > this season > last season
```

It is built from `PlayRecord` history — **another query over the event stream**
([ADR-0007](adr/0007-event-stream-contract.md)), so it costs almost nothing new. The
same tendency data serves three consumers: the AI's decisions, your self-scouting, and
the interrogation layer.

This is the same architecture as player evaluation
([decisions 36–37](design-decisions.md)): every team holds its own noisy model of
everyone else, derived from observable history rather than read from a global truth.
One idea, used twice.

### Adaptation is continuous but rate-limited

In-game observations update the model drive by drive. Run four screens and the defense
starts sitting on screens.

"Within limits" is the coordinator's `adaptability` rating capping how fast his beliefs
move, plus a floor on prior weight so he cannot overreact to a single play. A highly
adaptable coordinator punishes you for repeating yourself within a half; a rigid one
takes until next week.

This creates the loop that makes gameplanning worth doing: establish a tendency, notice
they've keyed on it, break it. That's football, it's measurable, and the interrogation
layer can say plainly *they were sitting on your screen game and you called four more.*

## What the defense knows pre-snap

The defense reads **formation, personnel, and motion** — everything physically
observable — plus **its tendency model's prediction** for this situation from this look.

It never sees the play. The defensive call is a bet, and it can be wrong.

This is deliberate and non-negotiable: if the AI could see your call, every causal
explanation the game offered would be a lie, and explanation is the entire product.

It also makes formation and personnel diversity mechanically valuable. Run everything
from 11 personnel in shotgun and your tendency model is razor sharp — the defense will
eat you, and the interrogation layer will tell you exactly why.

## Replay: snapshot the model

A subtle trap. The opponent model derives from prior games, so replaying game *N*
would need the model as it stood then — which derives from games 1…*N*−1, which would
have to be replayed first. Replaying one game would cascade through a whole season.

**The opponent model snapshot is therefore part of `GameSetup`**, and so part of
`initialState` in the replay tuple. It's a small tendency table. Every game replays
independently, and the cascade never exists.

Worth building this way from the start; discovering it later means reworking the replay
format after things depend on it.

## Benchmarking

"Is the AI good enough?" has to be a measurement, not a vibe. Three tests, all run
headless in `Tools/simharness`:

**Against an oracle.** Build a win-probability-optimal reference caller that searches
exhaustively. Far too slow for gameplay — but it never plays, it only benchmarks. The
EPA gap between a coordinator and the oracle is an absolute measure of quality, and the
spread of that gap across the league is what makes hiring matter.

**Against a baseline.** A naive caller (fixed run/pass split by down) is the floor.
Any coordinator who can't beat it comfortably is broken, not merely bad.

**Against a human.** The acceptance criterion for the whole feature:

> A good coordinator should finish within **~1 point per game** of a skilled human
> calling every snap.

Some gap is correct — the player's skill should matter, or taking control is pointless.
But beyond about a point a game, delegating becomes a tax and toggle-at-will collapses
into calling everything by hand. A *bad* coordinator should be visibly worse than that,
by three or four points; that spread is what gives coordinator hiring teeth.

## Cost

The caller runs once per play against a [1.5ms budget](match-engine.md#performance-budget)
that is dominated by the tick loop, so it needs to be in the tens of microseconds:

- Situation buckets are precomputed; plays are pre-indexed by bucket.
- Candidate evaluation considers a shortlist, not the whole playbook.
- **Opponent model updates are incremental** — running counts, never a recompute over
  history.

## Build order

1. A baseline caller (fixed distributions by down and distance) — enough for M1's crude
   engine to produce plausible games.
2. Gameplan constraints and the coordinator profile.
3. The opponent model from `PlayRecord` history, with recency weighting.
4. In-game adaptation, rate-limited.
5. The oracle and the benchmark harness.
6. Tuning until the human gap lands.
