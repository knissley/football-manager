# [C37] The offence never sees the box it is running into

**Track:** Crude resolver semantics · **Wave:** 4 · **Size:** large
**Depends on:** ADR-0015 accepted; 04 first, so the box the offence reads is one the
defence was allowed to have. **Owner decision Q1 open**: this is M1 or it waits for M2's
opponent model; the audit's recommendation is M1, stated on the record.
**Where it fits:** `GameSimulator.step` between steps 3 and 5, the `PlayCaller` protocol,
`PlayRecord`'s `DecisionKind`. The caller region, after #225 and 04.
**Tracker:** #1 · likely a line on **#183** too, since M2's anticipation is the other half.
**Provenance:** §4 table 4 and §8 of `docs/audit-pre-snap-exchange.md` (C34, #229);
ADR-0014's second alternative, taken up by ADR-0015 step 4.

## Finding

The offence's concept is drawn (`GameSimulator.swift:337`) before the defence's package
exists (`:345`), and nothing after that lets the offence revisit it. So the run share does
not respond to the box:

| Eleven personnel, first and ten | vs four backs | vs five or more | swing |
|---|---:|---:|---:|
| the feed, 2023 (ADR-0014's counts, by Bayes) | 58.7% | 41.9% | 16.8 |
| the feed, 2024 | 58.4% | 42.4% | 16.0 |
| engine, seed 7, all such snaps | 56.1% (2,039) | 58.8% nickel, 59.3% dime | −2.7 |
| engine, seeds 7 / 11, ordinary snaps | 58.1 / 60.5% | 62.4 / 61.2% nickel | −4.3 / −0.7 |

The engine's base cell holds 1,200–2,000 snaps; one standard error is 1.1–1.4 points. This
is what `row:ypcOutnumberedByOne` (3.1 / 3.2 against 3.9–5.1) and the eleven-against-base
carry share (13.8 / 14.6% against 18.8 / 18.3%) are reading, and what ADR-0014 called
*anticipation the engine does not model*.

**The swing has two mechanisms and this issue builds one.** The defence loads the box on
what it expects (anticipation; M2's opponent model, decision 43), and the offence keeps or
changes its call on what it sees (the check). The direction of the feed's swing says
anticipation dominates. Building the check alone reproduces the number through the
smaller mechanism, and the record will say the offence chose what the defence mostly
forced. ADR-0015 accepts that on condition it is written down; this issue writes it down.

## Plan

1. **Re-measure table 4 on the `main` you start from**, both seeds, and write it here.
2. **Derive P(run | package, class) from the feed** for the classes the feed can support,
   with `scripts/calibration-sources.py`, citing the MANIFEST line; the arithmetic is
   ADR-0014's table by Bayes. The split *within* the pass families is practice, named as
   such.
3. **One draw after the package**: given the package on the field and the class, the
   offence keeps its concept or re-draws it so that the run share lands on the derived
   conditional. Reads `situation.defensePackage` and, when 03 has made the front mean
   something, `frontAlignment` unless `disguised`. **Never the coverage, the rush or the
   run fit** (ADR-0015 step 4). The grouping does not change: a check is a call at the
   line, not a substitution.
4. **On the record.** A `DecisionKind` — *checked, from concept X to Y, having seen
   package P* — through a factory and a `DecisionContractTests` arm (#177); a line in
   `play-record.md`'s register; the gamelog prints it above the snap it preceded. A snap
   with no check writes no point.
5. **A `.football` test from the derivation, committed red**: eleven personnel on first and
   ten runs more often into a four-back front than into nickel, at the derived rates.
   Verify it can fail by removing the draw.
6. **Say what the swing is carried by.** The row's note and `calibration-sources.md` say
   the offence's check carries the whole of it until M2's anticipation takes its share.
7. Every moved row with its mechanism against its measured floor. Expect `runShare.*`,
   both ypc-by-box rows, the eleven-against-base share and `ypcEvenCount` to move.

## Done when

- [ ] Table 4 before and after at both seeds.
- [ ] The engine's swing is inside the feed's, with the derivation cited.
- [ ] The check is on the record through a factory, and every check point names a package
      the record's `situation.defensePackage` agrees with.
- [ ] `row:ypcOutnumberedByOne` reported before and after; **its level is #49's**, not
      this issue's, and a value still under band is reported, not tuned.
- [ ] The note in item 6 exists.

## Not in scope

- **Anticipation.** The defence's package and call conditioning on a tendency is M2's, 09.
- **Audibles as designs**, hot routes, protection changes: M6, plays as data.
- **Retuning** any constant. Residuals to #49 by comment.
- **#227's slope.** This issue may change what #227 measures (08); it does not fix it.

## Not checked when filing

Whether the feed's four-back share by grouping is stable enough by class to derive more
than the first-and-ten row. Whether a check should cost the offence anything — a beat of
play clock, a procedural-foul term — which is practice and not in the feed. Whether
`row:ypcOutnumberedByOne` moves toward band when the runs into a loaded box become chosen
runs (08's confound), which is the reason 05 runs before #227 re-measures.
