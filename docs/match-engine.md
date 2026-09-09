# Match engine

Lives in `FMSimulation`. Pure, synchronous, deterministic, spatial.

Given a `GameSetup` — two teams, gameplans, sliders, weather, seed — it returns a
`GameResult`: the event stream, the box score derived from it, and per-player grades.

## The engine is spatial

Twenty-two players exist as positions and velocities on a field, updated on a fixed
tick. Outcomes are not drawn from outcome distributions; they **emerge from geometry**.

- Separation is the actual distance between a receiver and a defender.
- Pressure is a rusher actually reaching the quarterback's position.
- A tackle happens when bodies converge and a tackle attempt resolves.
- A catch depends on where the ball arrives relative to where the receiver is.

This is the expensive choice and the reason the rest of the product works
([ADR-0006](adr/0006-spatial-simulation.md)). The 2D field view is a direct render of
engine state — the dots are the simulation, not an animator's guess at what a dice roll
meant. And the causal breakdown is a *readout* of what happened rather than a story
told about a number.

Player ratings and traits are **inputs to the physics**: `speed` sets a top velocity,
`routeRunning` sets how sharply a cut can be made without losing ground, "swim master"
selects a different pass-rush move resolution with different timing. Traits are engine
hooks, not cosmetic modifiers.

## The event stream is the contract

The engine's public output is an ordered stream of typed events
([ADR-0007](adr/0007-event-stream-contract.md)), specified in
[play-record.md](play-record.md). Everything downstream — box scores,
grades, news, highlights, tendencies, the causal breakdown — is a **query over that
stream**, never a parallel accumulation.

```
PlayRecord
  situation      down, distance, ball position, clock, score, personnel
  calls          the offensive and defensive calls, held by value, and who chose
                 each (AI or player) — a design edited later cannot rewrite history
                 ([ADR-0010](adr/0010-plays-designs-and-calls.md))
  decisions      the engine's own branch points, recorded as data
                 ("pressure at 2.1s", "progression read 2 of 3", "checkdown covered")
  outcome        yards, result, participants, penalty
  trajectory     per-tick positions — retained only where the game is retained
```

This is what makes the engine safe to deepen. A crude engine and a full spatial engine
emit the same event shapes, so the analysis layer, the UI, and the news system are
written once, against a stable contract, before the engine is any good.

## Determinism and replay

A game is a pure function of `(initialState, seed, sliderConfig, decisionLog)`.

The `decisionLog` matters because of toggle-at-will play calling: a game where the
player took over some snaps is not reproducible from a seed alone. Every player
decision is recorded in order, so the game replays exactly.

That tuple *is* the storage format for games we don't retain in full. Fifteen of
sixteen games each week keep a box score and their replay tuple; ask to watch one and
it re-simulates identically. Storage stays bounded across a decade-long career, and
determinism stops being a testing convenience and becomes a player-facing feature.

**Banned in `FMSimulation` and `FMGeneration`** (CI-enforced): `Int.random`,
`Double.random`, `SystemRandomNumberGenerator`, `.shuffled()`, `.randomElement()`,
`UUID()`, `Date()`, and any clock or environment read. Iteration order over unordered
collections must never reach output — sort by a stable ID first.

Floating-point determinism across architectures is a real risk here in a way it wasn't
for an abstract engine. Golden tests run on both arm64 and x86_64 in CI, and hot paths
avoid transcendental functions where a cheaper formulation exists.

## Performance budget

**A season simulates in about 60 seconds.** That is the constraint, and it is
architectural rather than a tuning target.

```
272 games / 60s          ≈  220 ms per game
220ms / ~150 plays       ≈  1.5 ms per play
1.5ms / (60 ticks × 22)  ≈  1.1 µs per entity-tick
```

A tight entity update — integrate velocity, steer toward a target, test a few
proximities — should run in 50–200ns, which leaves 5–20× headroom for a richer per-tick
model. That headroom exists **only if the hot loop never allocates**:

- Flat arrays of `struct`, indexed by slot. No per-tick object churn, no dictionaries.
- No string construction during simulation. Events carry IDs and enums; text is
  rendered later, by the narrative layer.
- No `Array` growth inside a play. Buffers are sized once and reused.
- Trajectory capture is opt-in per game, not always-on.

Build this in from the first line. Retrofitting it is a rewrite, not an optimization
pass.

## The resolver seam

The engine splits in two ([ADR-0012](adr/0012-play-resolver-seam.md)):

```
GameSimulator     the sport's rules — clock, downs, possession, scoring,
                  penalties, timeouts, overtime. Written once, never rewritten.
   ↓ asks, per snap
PlayResolver      what happened on this snap.
   ├── CrudeResolver     M1. Named matchups, no geometry. Deleted at M5.
   └── SpatialResolver   M5. Twenty-two entities on a tick clock.
```

Most of what an engine does is not physics. A wrong ten-second runoff is wrong in both
resolvers, and it is wrong exactly where players are paying the most attention. Writing
those rules once means M5 replaces one component into a harness that already sims a
season, rather than rewriting the clock and its tests along with everything else.

### The crude resolver

Matchup-lite: no positions and no tick loop, but **real named matchups** — this rusher
beat this tackle at this time, this corner was covering this receiver. It emits genuine
`Participation` and `DecisionPoint` data, because a resolver that returned empty
`decisions` would leave the interrogation layer unbuildable until M5, which is the exact
risk [ADR-0007](adr/0007-event-stream-contract.md) exists to remove.

Its decision points must be **consistent with its own outcome**. If it reports pressure
at 2.1 seconds and a sack, the sack is by that rusher. A fabricated causal chain that
merely looks plausible would let the analysis layer appear to work while reading noise —
the real risk of building M2 against scaffolding.

What it does *not* do: geometry, trajectories, or anything requiring a position. It hits
the parametric calibration rows because they are inputs at this fidelity, and it takes
the spread of team win totals seriously because that one is emergent.

It is scaffolding, and it is deleted at M5 rather than kept as a fast-sim path. Career
fast-forward runs at the spatial engine's speed; unwatched games are already stored as
replay tuples and reproduce exactly.

## Play resolution

### Plays are data

A play is a formation plus a per-player assignment: a route with landmarks and timing,
a blocking rule, a coverage responsibility. The engine reads that format; the play
designer edits it; the premade concept library is authored in it.

Because assignments are data, a designed play needs **validation** — eleven players,
legal formation, every assignment executable — before it reaches the engine. That's a
constraint checker, not a drawing tool, and it's the real cost of the play designer.

### Pass play

Pressure, routes, and the read happen concurrently on the tick clock rather than as
sequential dice rolls:

1. Rushers and blockers engage; each matchup resolves as a physical contest whose
   result is *when* and *where* the rusher gets past, not a binary win.
2. Receivers run their assigned routes; defenders play their assigned technique.
   Separation is measured, not drawn.
3. The quarterback progresses through his reads on a timing schedule, gated by
   `awareness` and by what the pocket is actually doing around him. He throws, checks
   down, scrambles, throws it away, or takes the sack.
4. Ball flight has a duration. The catch resolves on arrival, against the defender's
   actual position and the receiver's `catching` and hands traits.
5. Yards after catch is pursuit geometry and tackle attempts.

Each of those steps writes a decision record. That's where "your right tackle lost his
rep in 2.1 seconds and the checkdown was covered" comes from — it's logged, not inferred.

### Run play

Blocking assignments resolve into actual displacement; the hole is a real gap between
bodies. The back's vision trait affects which gap he attacks and how quickly he commits.
Tacklers pursue on real angles. Broken tackles chain.

### Special teams

Kick distance and accuracy from ratings, wind, and precipitation; returns resolve as
pursuit geometry like any other play. Blocks and muffs are low-probability branches and
worth keeping — they're memorable.

## Injuries

Availability in M1; severity, rehabilitation and reaggravation in M3.

Injuries are drawn from a play's **participants** rather than inside the resolver,
because an injury is about who was involved and not about how the contact was modelled —
so the model survives the spatial resolver replacing the crude one, at which point real
contact severity can feed it instead of the play kind.

Two causes, and they are genuinely different events rather than two sizes of the same
one:

**Contact.** Somebody was hit. Weighted toward the ball carrier and the men who brought
him down, scaled by how much contact the play involved.

**Non-contact.** A cut, a plant, a landing. Drawn from who was *moving hard* rather than
who was hit, so it is uncorrelated with how the play went and can happen on a snap where
nobody was touched at all. It has no walk-it-off branch: an achilles is most of a season
and a hamstring is still weeks. About a sixth of injuries and well over a third of the
games lost, which is the relationship the sport actually has.

A linemen in a phone booth does not tear a knee coming out of a break, so only explosive
roles are exposed — and a quarterback is exposed when he scrambles and not when he stands
in the pocket.

## Clock, penalties, and AI

- **Clock** rules are explicit states, not approximations. Two-minute warning, spikes,
  kneels, the out-of-bounds rule, and the ten-second runoff all matter most exactly
  where players pay the most attention.
- **Penalties** are drawn per matchup from player `discipline` and coaching, then
  applied with correct accept/decline logic — the engine evaluates both branches and
  takes the better one for the non-penalized team.
- **AI play calling**, on both sides of the ball, keys off `SituationClass` and the
  opponent's tendencies, modulated by coach ratings and gameplan. Fourth-down decisions
  run on expected points, with coach aggression shifting the threshold.

Because play calling can be toggled at will, the AI caller is a **headline system** and
has its own design doc: [play-calling.md](play-calling.md). In short — your offensive
coordinator makes the calls inside guardrails your gameplan sets, both sides carry noisy
tendency models of each other built from `PlayRecord` history, the defense never sees
the call, and caller quality is benchmarked against an oracle and against human play
rather than assessed by feel.

## Variance, and why records have to be reachable

Means are the easy part. A league tuned only to its averages produces a distribution that
is *narrower than chance*, and in one a record is not merely unlikely — it is impossible.
An early crude resolver managed a maximum of three passing touchdowns in four hundred
team-games and could never have produced four. A Poisson process with the same mean would
have produced four in one game in twenty-five.

Two mechanisms fix that, and neither is "more randomness":

**Form.** A rating is a central tendency, not a constant. Each player draws a day once per
game, seeded from the game and his identifier, applied to every rep he takes. This is what
*correlates* a player's plays within a game — and correlation, not magnitude, is what
gives a distribution tails. Independent per-play noise averages out over a hundred snaps;
a day does not. Ordinary days stay within a few rating points so talent still decides a
season; a rare day well outside that is what lets a generational player in the right
situation chase a number nobody should reach.

Form sits on a different timescale from everything else that moves a player, and the
three should never be confused:

| | Timescale | Reverts | Answers |
| --- | --- | --- | --- |
| **Trait** | A career | No | What kind of player is he |
| **Development** | Season to season | No | Who is he becoming |
| **Form** | One game | Completely | Who was he on Sunday |

Two things it deliberately is not. It is **not a hot hand**: form is drawn before kickoff
and never reacts to what happens in the game, because a model that noticed a player was
having a good day and made him better would be the engine authoring a narrative. And it is
variance in *capability*, not in *outcomes* — every play still resolves through identical
physics, and form only changes what a player brings to it.

**Form is visible after the fact, never before.** The analysis layer can say *he was off
all day* as an observation drawn from the stream, the same way it reports pressure or
separation, because a performance nobody can account for is exactly what the interrogation
hook promises not to produce. It is not visible before kickoff, where it would become a
lineup cheat and tell the player the answer before asking the question.

**Teams have days too, and they have reasons.** Part of each player's day comes from a
team-wide component, so a squad can be collectively flat or collectively electric — which
is real, and is a direct lever on the spread of team win totals, the row the calibration
table calls the most important number. That component is driven by things with causes:
travel, a short week, a hostile crowd, the game before. A shared draw with no reason
behind it would be indistinguishable from an excuse.

**Explosive plays.** A receiver who beats every defender with an angle on him is in open
field, not three yards further on. The run game had a burst through the hole from the
start and the passing game had no equivalent, which is precisely why one had a tail and
the other did not.

The test of this is not the mean. It is whether, over a long enough career, somebody
breaks a record that looked unattainable — and `Tools/simharness` reports the tails
alongside the means for exactly that reason.

## Sliders

Sliders are **league-wide world tuning**, not a personal difficulty dial. Pass
difficulty, injury frequency, pass rush intensity and the rest apply to every team, so
stat leaders, records and the Hall of Fame stay comparable within a career.

Sliders are part of the replay tuple. Calibration targets below are valid **at default
settings only**.

*Open:* whether sliders lock at career creation or records carry their config. See
[design-decisions.md](design-decisions.md#open-questions).

## Calibration

Tuned against `Tools/simharness` — never by playing the app. The harness sims N games
headless and prints each metric against its target range, marking the row `ok` or `OFF`.

CI runs it at 400 games on seed 7 on both architectures, uploads the output as an
artifact and puts the table in the job summary — but the job **reports, it does not
gate**: an `OFF` row is a finding to read, not a red build. *Intent, not yet built:* the
ranges live in the harness source rather than a checked-in target file, and no row fails
CI yet. Making a row gating is a per-row decision, taken in a retune issue.

| Metric (per team per season) | Target range |
| --- | --- |
| Points per game | 20–26 |
| Passing yards per game | 200–260 |
| Rushing yards per game | 95–140 |
| Yards per carry | 4.0–4.8 |
| Completion percentage | 61–68% |
| Sack rate (per dropback) | 5.5–8.0% |
| Interception rate (per attempt) | 1.8–2.8% |
| Third-down conversion rate | 36–43% |
| Red zone TD rate | 52–62% |
| Penalties per game (both teams) | 10–14 |
| Turnovers per game (both teams) | 2.2–3.2 |
| Player-games lost to injury | 40–90 |
| **Spread of team win totals (σ)** | **2.6–3.2** |

The last row is the one that encodes "upsets happen and dominant teams dominate." Too
low and the league feels random; too high and every season is decided in August. It is
the single most important number in this table.

### The shape of a game, not only of a play

Everything above measures the passing and running game. None of it measures *football*,
and the [is-this-football audit](audit-is-this-football.md) is what that omission cost:
the engine hit "points per game" for months while paying three points for an extra point,
because no row asked where the points came from.

These rows are what a game is made of, and they are checked in the harness under **Is this
football?**:

| Metric | Target |
| --- | --- |
| Share of points from touchdowns | 60–68% |
| Share of points from field goals | 20–26% |
| Drives per team per game | 10.5–12.0 |
| Drives ending in a punt | 36–42% |
| Drives ending in a touchdown | 19–24% |
| Drives ending on downs | 4–7% |
| Average drive start (own yard line) | 27–30 |
| Drives starting in own half | 75–82% |
| Carries stuffed (0 yards or fewer) | 17–22% |
| Carries of 10+ yards | 9–13% |
| Carries of 20+ yards | 2–4% |
| Field goals made, 30–39 yards | 89–93% |
| Field goals made, 40–49 yards | 79–85% |
| Field goals made, 50+ yards | 60–70% |
| Extra points made | 93–97% |
| Games decided by 3 or fewer | 25–31% |
| Fumbles lost per team per game | 0.5–0.8 |
| Turnovers per team per game | 1.1–1.6 |
| Touchdowns not scored by the offence | 0.15–0.28 |
| Kickoffs returned | 30–40% |
| Punts returned | 33–42% |
| Yards per pass attempt | 6.6–7.6 |
| Yards per play | 5.2–5.9 |
| Dropbacks gaining 20+ | 8–12% |
| Dropbacks gaining 40+ | 1.5–3.0% |
| Fourth downs gone for | 12–20% |
| Fourth-and-ones gone for | 55–75% |
| Fourth-down conversion rate | 45–58% |
| Two-point attempts per team per game | 0.15–0.30 |
| Drives per team per game | 10.5–12.0 |
| Three-and-out rate | 20–27% |
| Snaps in 11 personnel | 60–72% |
| Snaps against nickel | 50–65% |
| Snaps against base | 22–32% |
| Yards per carry, even count, first and ten | 4.6–5.4 |
| Yards per carry, outnumbered by one | 3.0–4.0 |
| Pre-snap fouls, road vs home | 1.15–1.35× |
| Combined points, heavy rain vs dry | 2–4 lower |

Home win rate and the home scoring edge are printed **without** a target. Real home-field
advantage is about two points and 56%, and most of it is travel, rest and short weeks —
none of which exists before there is a schedule to travel on (M3). What the engine models
is the crowd, so the mechanism gets the target and the aggregate gets a note.

The weather rows need a large sample: at 400 games there are only twenty-odd heavy-rain
games and the row is noise. Run `--games 1000` before reading them.

A mean is not a distribution. An engine can hit 4.3 yards a carry by giving everybody four
and a half yards every time, and that would be nothing like the sport — which is why the
carry rows measure the shape and not the average.

Also checked: the best players lead the league most seasons, and no scheme dominates —
equal-talent rosters built differently should win the same number of games within noise.

## Build order

Deepen behind the event contract rather than building depth first. See the
[roadmap](roadmap.md).

1. Event stream shape and a deliberately crude outcome engine behind it.
2. The analysis and narrative layers, proving the contract carries what they need.
3. Spatial engine: dropback passing with real geometry, same events out.
4. Run game, special teams, penalties, injuries, fatigue.
5. Play format and designer.
6. AI play calling benchmarked against the player.
7. Calibration.
