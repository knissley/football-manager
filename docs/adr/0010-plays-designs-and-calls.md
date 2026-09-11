# 0010. Distinguish play designs, calls, and plays

**Status:** Accepted
**Date:** 2026-09-08

## Context

`PlayID` was used for two disjoint identifier spaces: `PlayRecord.id`, identifying a
down that occurred, and `Calls.offensivePlay`, identifying an entry in a playbook. Both
are `Identifier<PlaySubject>`, so nothing stops one being assigned where the other
belongs — the exact class of mistake typed identifiers exist to prevent. A single test
constructs `id: PlayID(1)` and `offensivePlay: PlayID(100)` two lines apart and compiles.

Underneath the collision is a modelling error. Three things were being called a play:

- The **authored artifact** — formation, routes, blocking rules, assignments. It lives
  in a playbook, is reused across seasons, and is editable in the play designer (M6).
- The **per-snap choice** — that artifact plus personnel, tempo, motion, protection; on
  defence, coverage, rush, front, package, run fit and disguise. It exists for one snap.
- The **collision** — both choices meeting, resolving, and producing a result. It is
  permanent history in the event log.

Different lifetimes, and the difference is load-bearing rather than pedantic. A
`PlayRecord` holding only a reference to a design describes a play that never happened
as soon as that design is edited — a career-long problem, because the play designer is
a shipped feature and history is the product ([ADR-0009](0009-event-sourcing-by-default.md)).

`DefensiveCall` landed in this muddle too: its fields are call-level selections, but it
was documented as a playbook entry and referenced through a `DefensiveCallID` catalogue.

## Decision

**A play is the collision.** The word is reserved for what occurred on a down.

Three levels, named for what they are:

```
PlayDesign     authored, in a playbook, lives across seasons, editable   (M6)
   ↓ selected, plus the per-snap wrapper
OffensiveCall / DefensiveCall     what each side chose this snap
   ↓ collide and resolve
PlayRecord     what occurred — immutable history
```

Both calls are stored **by value** in the record. A call carries a `PlayDesignID` so the
concept remains queryable, but the choices that defined the snap are captured, not
pointed at. Editing a design changes the playbook; it never rewrites what happened.

`PlayID` is retired rather than renamed, so it cannot mean two things again.
`PlayDesignID` names the playbook entry; `DefensiveCallID` is deleted, the call being
held by value. `Calls` becomes exactly what it says: the two calls that clashed, and who
made each.

## Consequences

- The compiler now separates the two identifier spaces that were silently
  interchangeable.
- History is durable against playbook editing. This is the same guarantee
  [ADR-0009](0009-event-sourcing-by-default.md) makes for gear and appearance, applied
  one level down.
- Records barely move in size. Measured, `Calls` goes from 43 to 41 bytes — tempo and
  motion drop into `OffensiveCall` where they belong, and the 8-byte `DefensiveCallID`
  becomes a 6-byte value held inline — and a realistic play is two bytes smaller. The
  durability guarantee is close to free.
- `DefensiveCall.package` duplicates `Situation.defensePackage` — the call selects it,
  the situation observes it. Kept, because a call must be meaningful standing alone in a
  playbook or a gameplan rule, and the redundancy is one byte and a testable invariant.
- Asymmetry remains and is deliberate: `OffensiveCall` references a design, and
  `DefensiveCall` does not, because no defensive design format exists yet. M6 adds one
  and the shapes converge. Adding a field now that is always zero would be worse.
- The play designer's output has a defined home. A designed play is a `PlayDesign`; the
  engine consumes calls, and never needs a new case per authored play.

## Alternatives considered

**Rename only — `PlayRecordID` alongside `PlayID`.** Minimal, and it fixes the type
collision, which was the concrete bug. Rejected because the collision was a symptom: it
leaves designs and calls conflated, so the play-designer problem arrives untouched at M6
when the shape is far more expensive to change.

**Keep identifier references and version designs.** Make playbook edits append-only, so
a record referencing design version 4 always resolves to what was actually run. Genuinely
appealing: records stay small, and *show me every snap of this concept* is a trivial
query. Rejected because the record must then store the version as well as the design, so
the bytes come back, and every playbook edit spawns a version with its own retention
question — more machinery for the same guarantee that storing the call outright provides
directly.

**One `Play` type covering all three levels, with optional fields.** Fewer types, and it
matches the loose way the sport uses the word. Rejected because the three have different
lifetimes — seasons, one snap, forever — and a type whose fields are meaningful only in
certain combinations pushes that distinction into every call site.

## Amendment 2026-09-10 — the concept is stored by value beside the design reference

The decision above keeps the concept queryable through the `PlayDesignID` a call carries.
For the first months no playbook existed, and the reference was filled from a stand-in:
`CrudePlaybook` in `FMSimulation` minted an identifier from `PlayFamily.rawValue + 1`, so
every record in the M1 stream pointed at a design that did not exist, in an identifier
space that would have dangled — or resolved to the wrong design — the day a real playbook
was authored. The contract that is supposed not to move would have moved with M6.

So a call now carries what the reference always stood for: `OffensiveCall.concept`, a
`PlayConcept` in `FMCore`, held by value, and `OffensiveCall.design` is `PlayDesignID?`,
`nil` until there is a playbook to name a design in. The concept is the coarse vocabulary
a caller decides on and a resolver acts on — the kinds of snap the crude engine resolves,
sixteen of them when this amendment was written, the sixteenth being the two-point run
that 11-3-1 makes a different play from the two-point pass, and seventeen since the
dynamic kickoff gave the kick struck through the end zone a case of its own — and it is
what a tendency table, a box score and a gameplan rule key off; the design is the authored
artifact the concept was run from. Both stay on the call
once designs exist: editing a design changes the playbook, and the record still says what
kind of play was called. `PlayRecord.schemaVersion`, set to 1, landed alongside so that a
reader can tell the shapes apart when the record moves again.

The consequence that landed differently is the size. The body says storing the calls by
value was close to free — two bytes smaller. Measured, an optional eight-byte identifier
is nine bytes aligned to eight: `OffensiveCall` goes 10 → 17 bytes, `Calls` 41 → 49, the
record's fixed part 136 → 144, and a realistic play 494 → 502. The version byte is
absorbed by padding after the index; the design reference's optionality is not. Eight
bytes a play for a record that no longer names a design nobody wrote.

Those four numbers are what this amendment measured when it landed, and the eight bytes
it cost are still the eight bytes it cost. The absolute figures have moved on: the record
has gained fields since — the possession-loss spot and the kicking-team kickoff touchdown
that [#58](https://github.com/knissley/football-manager/issues/58) put in it — and
`swift run --package-path Tools/playsize` now prints a **152-byte fixed part and 510 bytes
for a realistic play**. Read them off the tool rather than off this paragraph; the tool is
the measurement and this is a record of one moment of it.
