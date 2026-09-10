# The `PlayRecord` event stream

**Status: built.** `PlayRecord` and the types around it live in `FMCore`, the engine
fills them on every snap, and `Tools/playsize` measures the footprint this doc quotes.
Who was on the field, whether a pass was completed and the points a play scored are on
the record ([below](#who-was-on-the-field)); the record is versioned and the concept
called is on it by value ([below](#what-was-called)); where a kick was fielded, where
possession was lost on a takeaway, and what happened while the ball was dead before a
snap are on it too ([below](#kicks-takeaways-and-the-dead-ball)).

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
  schemaVersion UInt8           the shape this record was written under; 1 today

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
  quarter, clockRemaining              the play clock is a decision point, below
  down, distance, ballOn            yards from the opponent's goal line
  possession    TeamID
  scoreDiff     Int16              from the possessing team's view
  timeouts      (off: UInt8, def: UInt8)
  personnel     (off: PersonnelGroup, def: DefensivePackage)

The down, and nothing about the afternoon. The weather is a fact about the game: it is
on `GameResult.weather` once, the resolver reads it from its `PlayContext`, and no
situation carries it. It sat on every situation for a while — about a hundred and fifty
copies a game — and nothing that reads a situation ever looked at it.

`SituationClass(situation)` derives the shared situational buckets — down-and-distance,
field, score and time — used by both callers, gameplan rules, tendency tables and
analysis. It is derived, never stored: a bucket boundary can change without rewriting
history.


Calls
  offense       OffensiveCall     concept by value; design reference, nil until M6;
                                  tempo + motion
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
  finalSpot     UInt8?             where the ball came to rest, on a play that changed hands
  fieldedAt     Int8?              where a kick was fielded; negative in the end zone
  possessionLostAt UInt8?          where a takeaway was, in the offence's frame like
                                   every other spot here
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

Four more are the rules layer's rather than the resolver's, and name no player:

```
.playClock(seconds, remaining)     which play clock the snap was taken against (4-6) and
                                   what it read; zero is an expired one, a delay of game
.clockElection(election)           a choice one side made about the clock between downs,
                                   as the referee announces it: the runoff and its
                                   alternatives (4-7-1), the last forty seconds (4-7-3),
                                   an injury timeout (4-5-4)
.timeout(byOffense)                a charged timeout taken before this snap (4-5-1), by
                                   the side in possession at it or by the other
.twoMinuteWarning                  the warning was taken before this snap (3-41)
```

All four exist so that the clock explains itself from the stream — which clock a snap
faced, why ten seconds came off, why a half ended on a flag, who stopped it and when the
warning came — instead of being inferred from two consecutive situations. The first two
sit on the play they are about; the last two sit at the front of the *next* snap's chain,
because the ball was dead when they happened and the next snap is the first thing they
are before ([below](#kicks-takeaways-and-the-dead-ball)).

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

**Every flag names a player the record identifies.** A `PenaltyRecord` names the
offender by slot, and the slot resolves through `onField` whether or not the play
credited him — a receiver running a decoy route, a rusher who never reached the kicker, a
blocker on a return. Before presence was on the record the only way to resolve a slot was
the credits, and one flag in forty named nobody a reader could identify. The contract is
`PenaltyTests.offendersAreReal`: the offender resolves, he is on the offending team's
roster, and the slot is on the side of the ball his team was.

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

## What was called

`OffensiveCall.concept` is a `PlayConcept`, held by value on every record: the kind of
snap at the coarsest grain that is still useful — inside run, outside run, quick, medium
and deep pass, screen, play action, punt, field goal, kneel, spike, kickoff, onside kick,
extra point, two-point conversion. Fifteen cases, because that is how many kinds of snap
the crude engine resolves; a play format with routes in it does not retire them, because
a concept is what a tendency table, a box score and a gameplan rule key off, and none of
them wants a route tree.

`OffensiveCall.design` is the `PlayDesignID` the concept was run from, and it is `nil`
until M6 gives it a playbook to point into. For a while it was not: the engine filled it
from a stand-in whose identifiers were the concept's raw value plus one, so every record
named a design that did not exist in an identifier space that would have dangled — or
resolved to the wrong design — the day a real one was authored. A record now says what
was called whatever becomes of the playbook it was called from
([ADR-0010](adr/0010-plays-designs-and-calls.md), amended).

The concept's kind is a contract: a snap of it produces a play of `PlayConcept.kind`
unless a flag before the snap wiped it out, where a called pass is a dropback and a
dropback may end as a sack or a scramble. `SchemaAndConceptTests` checks it over twenty
games, and that no record names a design.

## Kicks, takeaways, and the dead ball

**A kick has three spots, and the record carries all three.** Where it was kicked from is
`Situation.ballOn`; where it came to rest is `Outcome.finalSpot`; and `Outcome.fieldedAt`
is where it was fielded — all in the kicking team's frame, yards from the receiving team's
goal line, `fieldedAt` negative for a kick caught in the end zone. On a fair catch, a
downed punt or one run out of bounds the fielding spot and the resting spot are the same
number; on a touchback it is `nil`, because nobody fielded it. Gross, return and net are
queries: `kickDistance` is the line to the fielding spot, or to the goal line on a
touchback, which is how the league measures one; `returnYards` is the fielding spot to
the resting spot, zero on a kick fielded and not run; `netPuntDistance(rules:)` is the
gross less the return, or the line to the touchback spot on a touchback. With only the
resting spot, the gross of a returned punt and its return could not be told apart and the
harness's net punt row spotted a touchback at the goal line — `KickRecordTests` holds the
identities over forty games, and `grossPunt`, `puntReturnYards`, `kickoffReturnYards` and
`netPunt` in the [calibration table](match-engine.md#calibration) read off the record.

**A kickoff touchdown says who scored it.** The resting spot of a returned kick that
scores is 100, the kicking team's goal line; a kick the returner fumbled and the kicking
team carried in comes to rest at 0, the receivers' goal line, and `Rules.advance` reads
that as the kicking team's touchdown, its try, and its kickoff after it (8-7-3 Item 1,
11-2-1, 11-3-1, 11-3-4). `isKickingTeamTouchdown` is the query. The crude resolver never
fumbles a kick — a muff is not modelled — so only a scripted game reaches it today.

**A takeaway says where possession was lost.** `Outcome.possessionLostAt` is where the
pass was intercepted or where the ball came loose, and `nil` on every other play. It is
in the **offence's frame** — the frame of the team that snapped, the same as
`Situation.ballOn`, `Outcome.finalSpot`, `Outcome.fieldedAt` and a penalty's
`enforcementSpot`. Every spot on the record is in that one frame, and the new possessor's
frame was the alternative and was rejected for that reason: one frame per record is a
rule a reader can hold, and two would mean asking which field a number belongs to before
reading it. A reader who wants the takeaway in the new possessor's frame subtracts it
from 100, exactly as the rules layer does with `finalSpot`.

**What it is the spot *for* is a rule, not a fact about the record.** It is the basic
spot for a foul during a **run** followed by a change of possession (14-3-5-b), so a
defensive personal foul on a run that ends in a fumble lost downfield is walked off from
the fumble once the ball reverts to the offence (14-4-3-a). It stops being the spot the
moment the ball comes loose **behind the line of scrimmage**: a basic spot behind the line
puts a defensive foul — behind the line or beyond it — back on the previous spot (14-3-6,
the exception for fouls by the defence, and 14-4-6-b for a foul during the fumble itself).
That is the strip sack, and it is the common half of the field's use rather than the rare
one.

It is **not** the spot for a foul on a pass that was intercepted: until a forward pass
from behind the line is over, a flag on either side comes off the previous spot, and the
down turns into a running play only once somebody catches the ball (14-4-5); a defensive
personal foul before the catch takes the better of two spots for the offence — where it
snapped, or where the ball was dead (14-4-5-d) — and neither of those is this field.
`Rules.enforce` reads the field only on a fumble lost for that reason. The record carries
the spot on every takeaway either way, because where a pass was picked off is worth
knowing whether or not a flag was thrown on the play.

The record carries no time within a down, so a foul by the intercepting team during its
own return is the same record as a foul before the catch, and is walked off the same way:
right for the second, wrong for the first. The same silence covers a pass **completed and
then fumbled away**, which is enforced from the fumble where 14-4-5-d gives the previous
spot if the foul preceded the catch. The crude resolver reaches neither today, and
[#58](https://github.com/knissley/football-manager/issues/58) is where both are tracked.

**What happened while the ball was dead is on the next snap.** A charged timeout is not a
play and produces no record of its own ([decision 192](design-decisions.md)), but it is
no longer an inference from two consecutive situations either — one taken with the ball
about to change hands could not be charged to a team that way, and the printer could not
show it. A timeout the callers take before a snap is a `.timeout` decision point at the
front of that snap's chain, with the side that took it; the two-minute warning, taken at
the end of the last down snapped before 2:00 (3-41), is a `.twoMinuteWarning` on the first
snap after it. `timeoutsBeforeTheSnap` and `hasTwoMinuteWarningBeforeTheSnap` read them. A
timeout the rules charged as the consequence of a play — the offence's alternative to a
runoff, an injury timeout — stays a `.clockElection` on that play, where the referee
announces it; a reader counting timeouts counts both, which is what the harness does. Rows
of their own kind were the alternative — a `DeadBallEvent` stream beside the plays — and
were rejected because everything downstream walks one stream, and a between-downs event is
exactly the thing the next snap's causal chain begins with.

## Constraints from the rest of the design

- **No strings, ever.** IDs and enums only; text is rendered later by `FMNarrative`
  ([performance budget](match-engine.md#performance-budget)).
- **Fixed-size where possible.** `DecisionPoint` is 8 bytes; `decisions` is the only
  variable-length part of a record.
- **Append-only, ordered by `index` within a game.** No mutation after the whistle. There
  is no global play order: a week's games are concurrent, so ordering across games comes
  from the schedule ([ADR-0011](adr/0011-derived-identity-for-regenerable-streams.md)).
- **Versioned from day one** — old events must still fold correctly
  ([ADR-0009](adr/0009-event-sourcing-by-default.md)). `PlayRecord.schemaVersion` says
  which shape a record was written under, and is bumped when the layout or the meaning
  of a field changes. It is 1: the day one this doc promised arrived late, and every
  record written before it is a version-0 record that nothing needs to read.
- **Derived values are not stored.** Win probability, leverage and grades are computed by
  `FMAnalysis`, not written into the record, so improving those models improves history
  retroactively.

## Sizing — measured, not estimated

An earlier draft of this document estimated ~130 bytes per play and concluded that
records were cheap enough to keep league-wide for a decade. **That estimate was wrong**:
it omitted the participant list entirely, which turned out to dominate.

Measured against the real types (`swift run --package-path Tools/playsize`):

```
Situation      23 B     OffensiveCall   17 B     DecisionPoint    8 B
Calls          49 B     DefensiveCall    6 B     Participation   24 B
PlayRef        10 B     PlayRecord     152 B  (fixed part)
```

A realistic play — twelve decision points, ten credited participants, and the twenty-two
men on the field — is **510 bytes** in Swift's in-memory layout:

```
per game (150 plays)          74 KB
your season (17 games)      1,270 KB
league season (272 games)      19 MB
ten seasons, league-wide      198 MB
```

**Presence costs thirty-three bytes a play.** Twenty-two of them are the roster indices
themselves and eleven are the third array's pointer with the padding it brings, which
took the fixed part from 133 to 144. Credits stay sparse; what was added is the one fact
the sparse credits could not carry. (The 133 was itself two bytes over the 131 this doc
used to quote: `Outcome.finalSpot` was not absorbed by padding as
[decision 179](design-decisions.md#the-crude-engine) supposed, and the tool has measured
133 since it landed.)

**The weather gave eight of them back.** `Situation` went from 29 bytes to 23 when the
`WeatherState` it carried on every play moved to the game's result, and the fixed part
from 144 to 136 with it. A fact about the afternoon was being written a hundred and fifty
times a game for nothing that reads a situation to look at.

**The concept took eight of them back.** `OffensiveCall` went from 10 bytes to 17 when
the concept went on it by value and the design reference became optional: an optional
eight-byte identifier is nine bytes aligned to eight. `Calls` went 41 → 49 and the fixed
part 136 → 144. The version byte that landed with it cost nothing — it sits in the padding
after the index. Eight bytes a play for a record that no longer points at a design nobody
wrote ([ADR-0010](adr/0010-plays-designs-and-calls.md), amended).

**Two more spots cost eight more.** `Outcome.fieldedAt` and `Outcome.possessionLostAt`
are an optional byte each, and with the padding they bring the fixed part went 144 → 152.
The dead-ball decision points cost nothing on a play that has none, and eight bytes each
on the hundred and fifty or so snaps a season that follow a timeout or the warning.

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
value, so a playbook edit cannot rewrite history, was close to free — until the concept
went on the call by value as well, which is the eight bytes above.

**The claim that trajectories dwarf records does not hold.** A trajectory is ~111 KB per
game against ~74 KB of records — 1.4×, not the 6× asserted before. Records and
trajectories are the same order of magnitude.

So the retention story reverts to roughly where
[ADR-0003](adr/0003-deterministic-seeded-simulation.md) had it: **retain your own games
in full; replay everything else from its seed.** 198 MB of league-wide history for a
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
