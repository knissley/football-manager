# A comment for #225, not an issue: the defensive call reads the class alone

**Owner decision Q3**: fold into #225 as a constraint on its plan item 4, or file
separately. The audit recommends folding. If folded, post this as a comment on #225 and
add one sentence to its plan; if filed, the body below is the Finding and Plan.

---

Filed from `docs/audit-pre-snap-exchange.md` (C34, #229), §2 and §4 table 3, as a
constraint on this issue's plan item 4 rather than a fourth issue in the same function.

**Finding.** `BaselineCaller.defensiveCall` (`PlayCaller.swift:950-993`) discards the
situation at `:954` and draws from the class alone. So the coverage mix is identical
against every grouping — on ordinary first downs at seed 7: man free 7.5 / 7.5 / 6.5%,
cover 3 41.6 / 41.8 / 42.6%, match quarters 22.4 / 22.5 / 21.8% against 11 / 12 / 21
personnel, and the same to a point at seed 11. It also does not read the package the
defence has just substituted to, which `GameSimulator.swift:416` overwrites onto the call
afterwards, so a nickel eleven executes `goalLineStop` on 43% of goal-line snaps and a dime
eleven executes a bear front (`gamelog --seed 7 --home 3 --away 11`, plays 34 and 69).

**The grouping and the package are both information ADR-0014 grants the defence at this
step**, and ADR-0015 step 3 says the call reads them. This issue is rewriting the defensive
caller's tendencies from the feed; a caller rewritten without them is rewritten twice.

**Ask.** Plan item 4 conditions the coverage and rush draw on `situation.offensePersonnel`
and on the package where the feed supports it — the participation release pairs the
grouping with the package; whether it pairs either with a coverage or a rusher count is
this issue's item 2 to find out, and "it does not" leaves the conditioning as modelling,
named. Not in scope stays as written: `Lineup`, the rush construction, the run path.
