# [I9] Six sentences the pre-snap audit found stale, and the section nobody wrote

**Track:** Documentation truth · **Wave:** 4 · **Size:** small
**Depends on:** ADR-0015 accepted, for the last item only; the rest can land first.
**Where it fits:** docs lane. No engine code.
**Tracker:** #1
**Provenance:** §6 of `docs/audit-pre-snap-exchange.md` (C34, #229).

## Finding

Six places describe pre-snap behaviour the tree does not have, or omit behaviour it does.

1. `docs/play-calling.md:603-609` says *neither caller reads formation, personnel or motion
   off the other*. Since #226 the package draw reads personnel (`PlayCaller.swift:296-300`),
   which the same doc describes at `:380-395`.
2. `DefensiveCall.swift:32-34` documents `disguised` as costing a beat and buying a worse
   read; `:114-115` documents `.simulated` as the bluff. Neither is read by anything in
   `FMSimulation`. The comments read as behaviour and are intent.
3. `docs/roadmap.md:227-238` lists `CallVulnerability` as designed and not consulted. The
   list is short by six: `frontAlignment`, `disguised`, `usedMotion` (never set by any
   caller), `Coverage` beyond `isMan`, `PassRush.simulated`, `Tempo.slow` (never called).
4. `docs/audit-is-this-football.md:118-121` (S3) says three of six call dimensions are read.
   One of the three is read as one bit.
5. `docs/reference/playing-rules.md:85-87` (3-12-2) says nothing records which way a man
   moved. It should also say nobody moves: `usedMotion` is true on 0.0% of snaps.
6. `docs/match-engine.md` has no section on the moment before the snap; the order of the
   two benches' decisions is only in `GameSimulator.step`.

## Plan

1. Correct items 1, 3, 4 and 5 in place, each with the audit's citation.
2. Item 2 is a comment under `Packages/*/Sources` and so an engine-lane diff by preflight's
   rule even though it changes no behaviour. Land it in the same PR as 03 (the one-bit
   coverage fix), which rewrites those comments anyway, rather than paying an engine lane
   for two sentences.
3. Item 6: add a *Before the snap* section to `match-engine.md` carrying ADR-0015's five
   steps and, for each, the file and line that implements it today or the issue that will.
   The audit's §1 table is the draft.

## Done when

- [ ] Each of items 1, 3, 4, 5 and 6 reads true of the tree, with a citation.
- [ ] Item 2 is either landed with 03 or noted in the register (item 3) as intent.
- [ ] `preflight.sh --lane docs` green.

## Not in scope

- Any behaviour. Any file under `Packages/*/Sources` except as item 2 rides 03.
- `docs/design-decisions.md`: the designer's, and ADR-0015's line there is the designer's
  to add when it is accepted.

## Not checked when filing

Whether other docs carry the pre-#226 sentence; the audit grepped `play-calling.md`,
`match-engine.md`, `roadmap.md`, `gameplan.md` and the reference only.
