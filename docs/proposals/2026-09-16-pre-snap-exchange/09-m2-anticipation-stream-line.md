# A line for M2's stream list, not an issue: the defence anticipates

For the designer, to carry into M2's depth on #183 when M2 is deepened. Not filed on #1.

---

**From** `docs/audit-pre-snap-exchange.md` (C34, #229), §4 table 4 and §8; ADR-0015 steps
2 and 3; decisions 42, 43 and 44.

The sport's run share on first and ten from eleven personnel swings sixteen points with
the box, and the direction says the larger mechanism is the defence loading the box on
what it expects, not the offence checking. Expectation is the opponent model — decision
43's tendency table, built from `PlayRecord` history, snapshotted into `GameSetup` per
decision 44.

**The stream fact M2 must carry:** the defence's package (ADR-0015 step 2) and call (step
3) may condition on the tendency model's prediction for this situation from this grouping
— and on nothing the model could not have been built from before the snap. When it lands,
05's note that the offence's check carries the whole swing is retired, and the split
between anticipation and the check is measured on 06's rows rather than assumed.

**Cost, so the designer can place it:** a draw per snap in each of two callers, the model
snapshot in `GameSetup` and therefore in the replay tuple, goldens, and both ypc-by-box
rows and `runShare.*` moving again. It is not M1.
