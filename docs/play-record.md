# The `PlayRecord` event stream

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
  id            PlayID          monotonic within game
  gameID        GameID

  situation     Situation       state before the snap
  calls         Calls           what each side chose, and who chose it
  decisions     [DecisionPoint] the observable causal chain
  outcome       Outcome         what happened
  trajectory    TrajectoryRef?  opt-in, usually absent
```

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
  offensivePlay PlayID            into the play catalogue
  defensiveCall DefensiveCallID   into the defensive catalogue, entries shaped
                                  as FMCore.DefensiveCall
  offensiveCaller  .coordinator(StaffID) | .player
  defensiveCaller  .coordinator(StaffID) | .player
  tempo, formation, motion

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

## Constraints from the rest of the design

- **No strings, ever.** IDs and enums only; text is rendered later by `FMNarrative`
  ([performance budget](match-engine.md#performance-budget)).
- **Fixed-size where possible.** `DecisionPoint` is 8 bytes; `decisions` is the only
  variable-length part of a record.
- **Append-only, ordered by `PlayID`.** No mutation after the whistle.
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
Situation      29 B     DecisionPoint    8 B
Calls          43 B     Participation   24 B
```

A realistic play — twelve decision points, ten credited participants — is **424 bytes**
in Swift's in-memory layout:

```
per game (150 plays)          62 KB
your season (17 games)      1,055 KB
league season (272 games)      16 MB
ten seasons, league-wide      164 MB
```

Two things changed as a result of measuring.

**Participants are only the players who did something.** Crediting all twenty-two made
participants roughly three-quarters of a record for no analytical gain, and the team is
now derived from the slot convention (0–10 offence, 11–21 defence) rather than stored.
Together those cut a play from 756 bytes to 424.

**The claim that trajectories dwarf records does not hold.** A trajectory is ~111 KB per
game against ~62 KB of records — under 2×, not the 6× asserted before. Records and
trajectories are the same order of magnitude.

So the retention story reverts to roughly where
[ADR-0003](adr/0003-deterministic-seeded-simulation.md) had it: **retain your own games
in full; replay everything else from its seed.** 164 MB of league-wide history for a
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
