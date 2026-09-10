# The `PlayRecord` event stream

**Status: built.** `PlayRecord` and the types around it live in `FMCore`, the engine
fills them on every snap, and `Tools/playsize` measures the footprint this doc quotes.
Two caveats a reader needs: the record is not yet versioned and the play concept is
stored by reference rather than by value (#33), and one fact the doc implies is derivable
is not on the record yet — where a kick was fielded (#58). Who was on the field, whether
a pass was completed and the points a play scored are on the record
([below](#who-was-on-the-field)).

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
  onField       [UInt8]         the 22 men on the field, as roster indices in slot order
  trajectory    TrajectoryRef?  opt-in, usually absent   ← designed, not built
```

*Designed, not built:* the record has the first seven fields and no `trajectory`. There is
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
  passResult    .complete .incomplete .intercepted   on a pass, a two-point pass
                                                     or a spike; nil otherwise
  participants  [Participation]    (player, role, result)
  penalties     [PenaltyRecord]    including declined ones, and both branches
  clockRunoff   UInt16
  pointsScored  UInt8              what this play put on the board
  scoring       Scoring?           what kind of score, which says who scored it
```

**A completion is a fact, not an inference.** `PlayEnding` cannot say a pass was caught:
a ball caught for a loss ends `.tackled` exactly as a run does. `passResult` says it
(2025 rulebook, 8-1-3), `PlayRecord.isCompletion` reads it, and the harness's completion
row reads that rather than counting the passes that gained — which is how it read three
points low while showing green (S14 in the [audit](audit-is-this-football.md)).

**The points are on the play.** The game writes `pointsScored` and `scoring` once the
rules have read the outcome and before the record is appended, so a scoreboard is the
stream summed and never the rules run a second time; `scoring` says who — a touchdown,
field goal or try pays the side that had the ball, a safety or a defensive touchdown the
side that did not. Both are the rules' verdict on the play, not the resolver's, and the
game overwrites whatever a resolver wrote there.

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

### Who was on the field

Credit and presence are two different facts, and the record carries both. `participants`
is sparse by design ([decision 97](design-decisions.md#foundational)) — only the men who
did something the play names — which is right for credit and useless for the question a
box score asks first: who took the snap. A lineman who blocked nobody worth naming was
credited on three to five snaps in five; a safety on a sixth of run plays; and a snap
count, the development model's main lever
([ADR-0013](adr/0013-fluid-positions.md)), was whatever the credits added up to.

So every play carries `onField`: twenty-two roster indices in slot order, one byte each,
offence in 0 through 10 and defence in 11 through 21 — the same convention `PlayerSlot`
fixes, so on a kickoff the kicking team is the offence. The index points into
`GameResult.rosters`, each team's roster for the game in depth-chart order: every man on
the chart who was available at kickoff, once, at the first position he appears. The table
is fixed before the first snap, so a man who leaves hurt keeps his index and an early play
still means what it meant. `PlayRecord.vacant` (255) marks a slot nobody stood in, which
only happens when a position has run out of men.

`PlayRecord.player(at:rosters:)` resolves a slot, and `snapCounts(rosters:)` over a
game's plays is the snap count. Both are queries; the record stores the index and nothing
else. The contract — twenty-two entries on every play including kicks, tries and flag-only
snaps, every index inside its roster, every credit the same man the slot resolves to,
nobody twice, nobody after he left hurt, and a team's quarterback snaps summing to its
plays from scrimmage — is `OnFieldTests`, and the harness reads player-snaps per position
group off it (`snaps.*` in the [calibration table](match-engine.md#calibration)).

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
PlayRef        10 B     PlayRecord     144 B  (fixed part)
```

A realistic play — twelve decision points, ten credited participants, and the twenty-two
men on the field — is **502 bytes** in Swift's in-memory layout:

```
per game (150 plays)          73 KB
your season (17 games)      1,250 KB
league season (272 games)      19 MB
ten seasons, league-wide      195 MB
```

**Presence costs thirty-three bytes a play.** Twenty-two of them are the roster indices
themselves and eleven are the third array's pointer with the padding it brings, which
took the fixed part from 133 to 144. Credits stay sparse; what was added is the one fact
the sparse credits could not carry. (The 133 was itself two bytes over the 131 this doc
used to quote: `Outcome.finalSpot` was not absorbed by padding as
[decision 179](design-decisions.md#the-crude-engine) supposed, and the tool has measured
133 since it landed.)

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
game against ~73 KB of records — 1.5×, not the 6× asserted before. Records and
trajectories are the same order of magnitude.

So the retention story reverts to roughly where
[ADR-0003](adr/0003-deterministic-seeded-simulation.md) had it: **retain your own games
in full; replay everything else from its seed.** 195 MB of league-wide history for a
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
