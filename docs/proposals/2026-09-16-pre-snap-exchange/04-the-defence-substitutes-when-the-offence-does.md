# [C36] The defence substitutes on every snap, whatever the offence's tempo

**Track:** Crude resolver semantics · **Wave:** 4 · **Size:** medium
**Depends on:** 02 (the reference says what the book allows) and ADR-0015 accepted.
**Where it fits:** `GameSimulator.step` and `State` (`GameState.swift`), the caller's
`package(for:)` — the caller region, after #225. **Not on #49's gate** unless the owner
puts it there; it moves two graded rows, see below.
**Tracker:** #1
**Provenance:** §4 table 6 of `docs/audit-pre-snap-exchange.md` (C34, #229); ADR-0015
step 2.

## Finding

`caller.package(for:)` is asked on every scrimmage snap (`GameSimulator.swift:345`) and
draws from `PackageConditional` with no memory of the eleven already on the field. So the
package changes between consecutive snaps of one drive on **43.2% of hurry-up snaps and
47.3% of normal-tempo ones** at seed 7 (43.4 / 47.1 at seed 11; 400 games each). Tempo
does not move it. In the sport the offence at tempo holds the defence's eleven on the
field; that is what tempo is for, beyond the clock. What the book says is 02's job.

## Plan

1. **Re-measure on the `main` you start from** and write table 6 on this issue.
2. **Carry the previous snap's package in `State`.** Draw a new one only when the
   offence's grouping changed from the previous snap, a series began, the interval was an
   administrative stoppage (a change of possession, a timeout, the two-minute warning —
   the 4-6-2 list, which is already on `PlayContext.playClock`), or the book's rule from
   02 says the defence may. Otherwise keep it.
3. **The record says which.** A `.substitution` point today means *the question was put
   and answered from a distribution*. A snap where the defence held its eleven writes
   either no point or a point whose `detail` says *held*; `DecisionContractTests` and
   `play-record.md`'s register decide which, and the factory is the only way to build it
   (#177).
4. **A `.football` test if 02 found an article, else `.pin` with the practice named**: on
   consecutive hurry-up snaps with the grouping unchanged, the package does not change.
   Verify it can fail by restoring the per-snap draw.
5. **Expect `packageBase` and `packageNickel` to move**, and say by how much before
   deciding anything. The feed's per-snap conditional already contains the sport's
   substitution constraint; applying it per *substitution* instead of per snap changes the
   marginal the two rows grade. If they leave band, report the mechanism and the floor
   and leave them to #49 — do not re-derive the table to put them back.

## Done when

- [ ] Table 6 before and after at both seeds, with the floor named.
- [ ] The package does not change between consecutive snaps of a drive when the offence
      did not substitute and no stoppage intervened; demonstrated by the test in item 4.
- [ ] The record distinguishes a substitution from a held eleven.
- [ ] `packageBase`, `packageNickel`, the ungraded dime share and `ypcOutnumberedByOne` reported
      before and after; nothing retuned.

## Not in scope

- **The offence's side**: whether the offence substitutes is `personnel(for:)`'s, and
  ADR-0015 step 1 (the grouping follows from the concept) is 05's or #225's, not this.
- **The defensive call** holding or changing with the package — #225's caller rewrite.
- **Moving any band.** Residuals to #49 by comment.

## Not checked when filing

Whether the feed can separate first-snap-of-a-series packages from later ones, which would
let item 5's expected movement be derived rather than measured. Whether the offence's
`tempo` today ever differs within a drive enough for the constraint to bind often.
