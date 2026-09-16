# [E12] The harness cannot see whether the two callers know anything about each other

**Track:** Calibration and measurement · **Wave:** 4 · **Size:** small
**Depends on:** nothing.
**Where it fits:** `Tools/simharness` — `StreamQueries.swift`, `UngradedRows.swift`,
`main.swift`. Tools lane. No engine code.
**Tracker:** #1
**Provenance:** §4 of `docs/audit-pre-snap-exchange.md` (C34, #229), whose numbers live in a
scratch query reproduced in its appendix and nowhere in the tree.

## Finding

The audit measured four things the harness does not print: the run share by the coverage
called against it within a class (table 2), the coverage mix by the grouping faced (table
3), the run share by the package on the field for eleven personnel on first and ten (table
4), and the package changing between consecutive snaps of a drive by tempo (table 6). Each
is a query over the record; none has a row. So ADR-0015's order — and 03, 04 and 05 as
they land — can be checked only by re-running a query that is not in the tree.

## Plan

1. **Tables 2, 3, 4 and 6 as ungraded rows**, printed under *Who is on the field*, each with
   the audit's population definition — *ordinary snaps* is the population on which neither
   caller takes a situational branch, and the harness should define it once in
   `StreamQueries` rather than each row re-deriving it.
2. Table 4 carries the feed's derived figures beside it (58.7 / 41.9 and 58.4 / 42.4) with
   the ADR-0014 counts they come from, **as a note and not a target**: a target would need
   a band the derivation has not been given yet, and 05 is what would earn it.
3. The `UngradedRows` self-check names each row and the issue that will grade it.
4. `simharness --games 400 --seed 7` output is byte-identical above the new block; the
   world checksum is unchanged.

## Done when

- [ ] Four rows print at both seeds and reproduce the audit's tables on `79e7a6c`'s
      successor within the noise the audit states.
- [ ] Each row names its population and the issue that will grade it.
- [ ] `preflight.sh` tools lane green; `harness-reach.sh` says `skip`.

## Not in scope

- Grading any of them. A band is 05's or M2's to earn.
- Changing any existing row or `Targets.swift`.

## Not checked when filing

Whether *ordinary snaps* as the audit defined it is the population the eventual bands
will want; it was chosen to remove shared causes, not to match a feed population.
