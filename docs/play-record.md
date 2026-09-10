# The `PlayRecord` event stream

**Status: built.** `PlayRecord` and the types around it live in `FMCore`, the engine
fills them on every snap, and `Tools/playsize` measures the footprint this doc quotes.
Two caveats a reader needs: the record is not yet versioned and the play concept is
stored by reference rather than by value (#33), and several facts the doc implies are
derivable are not on the record yet — who was on the field (#21), whether a pass was
completed and where the points came from (#22), and where a kick was fielded (#58).

The highest-stakes artifact in the project. Everything downstream is a query over it
([ADR-0007](adr/0007-event-stream-contract.md)), and it gets designed before the engine
that fills it exists — so the guesses here are the expensive ones.

## What it must carry

Nine consumers, all reading the same stream:

| Consumer | Needs |
| --- | --- |
| Box score | Participants, yards, outcome kinds |
| Player grades | Per-snap involvement and result, by assignment |
| Causal breakdown | The engine's own observable decision points |
| Win probability & leverage | Situation before and after |
| Highlights | Leverage, plus outcome rarity |
| News Findings | All of the above, aggregated |
| Tendencies & opponent models | Situation → call, by team |
| Trait inference | Repeated observable outcomes in specific contexts |
| Replay | Nothing — replay rebuilds from seed and decision log |

## The layering rule

**A `PlayRecord` contains what a very good film-study analyst could determine.**

Not what the engine knows. The engine knows that *Sticky Hands* widened a catch radius by
four centimetres; film study knows he caught a contested ball. So:

- **Observable decisions go in the record** — pressure timing, target selection,
  separation at the throw, who made the tackle.
- **Engine internals stay out** — which trait modified which threshold, the underlying
  attribute rolls, the true values behind any estimate.

This is what preserves the fog. Trait belief is inferred per observer from *aggregated
observable outcomes* ([decision 85](design-decisions.md)) — a contested-catch rate, not an
announcement that a trait fired. If the record said "trait fired", every observer would
see it and the discovery loop would collapse.

Engine internals remain re-derivable on demand: replay the play from its seed with
instrumentation on. Debuggable without being visible.

## Shape

```
PlayRecord
  game          GameID
  index         UInt16          monotonic within the game; also the seed-split label

  situation     Situation       state before the snap
  calls         Calls           what each side chose, and who chose it
  decisions     [DecisionPoint] the observable causal chain
  outcome       Outcome         what happened
  trajectory    TrajectoryRef?  opt-in, usually absent   ← designed, not built
```

*Designed, not built:* the record has the first six fields and no `trajectory`. There is
no `TrajectoryRef` type and nothing to point it at — trajectories are per-tick positions,
and they arrive with the spatial engine at M5. The sizing section below costs a trajectory
anyway, because whether records or trajectories dominate storage is a decision that has
to be made before M5 rather than after.

```
Situation
  quarter, clockRemaining, playClock
  down, distance, ballOn            yards from the opponent's goal line
  possession    TeamID
  scoreDiff     Int16              from the possessing team's view
  timeouts      (off: UInt8, def: UInt8)
  personnel     (off: PersonnelGroup, def: DefensivePackage)
  weather       WeatherState

`SituationClass(situation)` derives the shared situational buckets — down-and-distance,
field, score and time — used by both callers, gameplan rules, tendency tables and
analysis. It is derived, never stored: a bucket boundary can change without rewriting
history.


Calls
  offense       OffensiveCall     design + tempo + motion, by value
  defense       DefensiveCall     coverage, rush, front, package, run fit, by value
  offensiveCaller  .coordinator(PersonnelID) | .player | .automatic
  defensiveCaller  .coordinator(PersonnelID) | .player | .automatic

Outcome
  kind          .rush .pass .sack .scramble .punt .fieldGoal .kickoff .kneel
                .spike .penaltyOnly
  yards         Int16
  endedIn       .tackle .outOfBounds .touchdown .incomplete .interception
                .fumbleLost .fumbleRecovered .touchback .safety .firstDown
  participants  [Participation]    (player, role, result)
  penalties     [PenaltyRecord]    including declined ones, and both branches
  clockRunoff   UInt16
```

### `DecisionPoint` is the causal chain

The part that makes the game's pitch work. *Your right tackle lost his rep in 2.1 seconds
and the checkdown was covered* is **logged, not inferred**.

```
DecisionPoint
  tick     UInt16          when in the play
  kind     DecisionKind
  actors   (PlayerID, PlayerID?)
  value    Int16           metres, milliseconds, or an index — per kind
```

`DecisionKind` cases, all film-observable:

```
.pressureAllowed(rusher, blocker, ms)     .pressureHeld(blocker, rusher, ms)
.readProgression(index, receiver, separationCm)
.throwDecision(.primary | .checkdown | .throwaway | .scramble | .sack)
.ballArrival(receiver, separationCm, placement)
.catchAttempt(receiver, defender, result) .tackleAttempt(defender, carrier, result)
.blockResult(blocker, defender, result)   .holeQuality(gap, quality)
.coverageAssignment(defender, receiver, technique)
```

A crude engine emits a handful of these per play; the spatial engine emits many. **Same
cases, same meaning** — which is exactly what lets the engine be replaced without touching
anything above it.

## Identity

A play is addressed by `PlayRef` — `(game, index)` — and nothing is stored for it. The
record already carries both fields, so the reference is computed
([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)).

There is no allocated play identifier, and that is deliberate rather than frugal. Most
games are never retained; they are replayed from a seed on demand. An allocated
identifier would have to be recovered on replay, which means storing the allocator's
state per game — a snapshot justified by nothing but the identifier itself, and the same
replay cascade the design removes everywhere else. A derived reference resolves by
replaying the game and indexing into it.

Nothing queries a play by reference in any case. The real queries are *this game's
plays*, *every third-and-long this season*, *this player's snaps* — keyed off `game`,
`SituationClass` and participant slots. References exist for pointing *in* from outside:
a highlight, a news item, a bookmark.

## Constraints from the rest of the design

- **No strings, ever.** IDs and enums only; text is rendered later by `FMNarrative`
  ([performance budget](match-engine.md#performance-budget)).
- **Fixed-size where possible.** `DecisionPoint` is 8 bytes; `decisions` is the only
  variable-length part of a record.
- **Append-only, ordered by `index` within a game.** No mutation after the whistle. There
  is no global play order: a week's games are concurrent, so ordering across games comes
  from the schedule ([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)).
- **Versioned from day one** — old events must still fold correctly
  ([ADR-0009](adr/0009-event-sourcing-by-default.md)).
- **Derived values are not stored.** Win probability, leverage and grades are computed by
  `FMAnalysis`, not written into the record, so improving those models improves history
  retroactively.

## Sizing — measured, not estimated

An earlier draft of this document estimated ~130 bytes per play and concluded that
records were cheap enough to keep league-wide for a decade. **That estimate was wrong**:
it omitted the participant list entirely, which turned out to dominate.

Measured against the real types (`swift run --package-path Tools/playsize`):

```
Situation      29 B     OffensiveCall   10 B     DecisionPoint    8 B
Calls          41 B     DefensiveCall    6 B     Participation   24 B
PlayRef        10 B     PlayRecord     131 B  (fixed part)
```

A realistic play — twelve decision points, ten credited participants — is **467 bytes**
in Swift's in-memory layout:

```
per game (150 plays)          68 KB
your season (17 games)      1,162 KB
league season (272 games)      18 MB
ten seasons, league-wide      181 MB
```

Three things changed as a result of measuring.

**Participants are only the players who did something.** Crediting all twenty-two made
participants roughly three-quarters of a record for no analytical gain, and the team is
now derived from the slot convention (0–10 offence, 11–21 defence) rather than stored.
Together those cut a play from 756 bytes to 424.

**The 424 figure was itself an underestimate.** It hand-counted the record's fixed fields
at 16 bytes. Measuring `MemoryLayout<PlayRecord>.size` directly gives 131 — the
hand-count omitted Swift's padding and the pointer each of the two arrays carries. The
tool now measures the struct instead of adding up its parts, which is why the number rose
to 467 without the type ever growing.

For the record, the type changes from
[ADR-0010](adr/0010-plays-designs-and-calls.md) made a play *two bytes smaller*
like-for-like: `Calls` went 43 → 41 as tempo and motion moved into `OffensiveCall` and
the 8-byte `DefensiveCallID` became a 6-byte value stored inline. Storing both calls by
value, so a playbook edit cannot rewrite history, was close to free.

**The claim that trajectories dwarf records does not hold.** A trajectory is ~111 KB per
game against ~68 KB of records — 1.6×, not the 6× asserted before. Records and
trajectories are the same order of magnitude.

So the retention story reverts to roughly where
[ADR-0003](adr/0003-deterministic-seeded-simulation.md) had it: **retain your own games
in full; replay everything else from its seed.** 181 MB of league-wide history for a
ten-season career is not something to put on a phone casually.

One caveat in the other direction: these are *in-memory* sizes with Swift's padding, not
a wire format. A packed encoding — no padding, no eight-byte identifiers where an index
would do — should roughly halve them. The retention policy can be revisited once
`FMPersistence` exists and the real encoded size is known. Until then, plan for the
measured figure rather than the hoped-for one.

## Open questions for M1

- Exact `DecisionKind` case list. Certain to be wrong in its first version; the mitigation
  is building `FMAnalysis` in M2, early enough that the gaps are cheap to fix.
- Whether `Participation` needs an explicit assignment reference for grading, or whether
  the play catalogue plus player identity is enough to recover it.
- Penalty representation for accept/decline: store both branches, or the chosen branch
  plus enough to reconstruct the other.
