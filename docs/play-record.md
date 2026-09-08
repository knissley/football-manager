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

Calls
  offensivePlay PlayID            into the play catalogue
  defensiveCall DefensiveCallID
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

## Sizing, and a revision it forces

Rough per-play budget: situation ~16 bytes, calls ~8, outcome ~24, decisions ~10 × 8 = 80.
Call it **~130 bytes per play**.

```
per game    150 plays × 130 B   ≈  20 KB
your season 17 games            ≈ 340 KB
whole league season 272 games   ≈ 5.4 MB
ten seasons, league-wide        ≈  54 MB
```

**Records are cheap. Trajectories are not:** ~1,300 ticks × 22 players × 4 bytes is
**~114 KB per game**, six times the record itself.

That refines the retention story in [ADR-0003](adr/0003-deterministic-seeded-simulation.md).
The thing that has to be replayed rather than stored is the **trajectory**, not the record.
Keeping `PlayRecord`s league-wide for a decade is affordable — and it's what makes
league-wide tendencies, historical Findings and cross-era comparisons cheap queries rather
than reconstruction jobs.

## Open questions for M1

- Exact `DecisionKind` case list. Certain to be wrong in its first version; the mitigation
  is building `FMAnalysis` in M2, early enough that the gaps are cheap to fix.
- Whether `Participation` needs an explicit assignment reference for grading, or whether
  the play catalogue plus player identity is enough to recover it.
- Penalty representation for accept/decline: store both branches, or the chosen branch
  plus enough to reconstruct the other.
