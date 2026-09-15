# Prototype — the role depth chart (sketch)

Made during the `/design-grill` session of 2026-09-15, in the idiom
`docs/weekly-loop.md` uses for its wireframes. **Sketch, not a commitment.**

## v1 — what the owner reacted to

```
┌─────────────────────────────────┐
│ DEFENSE · SECONDARY             │
├─────────────────────────────────┤
│ BOUNDARY CB    Okonkwo      84  │
│                  ~1010 snaps 94% │
│ FIELD CB       Vance        79  │
│                  ~ 940 snaps 88% │
│ NICKEL CB      Reyes        81  │
│                  ~ 680 snaps 63% │
│                  base: off field │
│ DIME CB        Reyes        81  │
│                  (also dime)     │
├─────────────────────────────────┤
│ You ran nickel on 63% of downs  │
│ last season. Reyes at NICKEL     │
│ projects 680 snaps — 4th most on │
│ the defense.                     │
└─────────────────────────────────┘
```

The load-bearing element is the **projection line, not the assignment row**.
Assigning a man to a role is a form. Being told what the assignment is worth in
snaps, and why, is a decision you can be wrong about and know it.

## What changed because of the reaction

**1. "Preseason" was wrong.** The owner pointed out the chart is editable in the
preseason, the season and the offseason alike, which makes the projection's
denominator a design question rather than a detail. Resolved as: the line names
its own source, and the source changes as the season fills in.

| When | Reads | Line says |
|---|---|---|
| Mid-season, enough games | this season's package mix, from the stream | `~640 snaps · your nickel rate, 6 games` |
| Season start, same coordinator and scheme | last completed season | `~680 snaps · last season's mix` |
| New coordinator or scheme, week 1 of a career | the scheme's own baseline (`FMCore.DefensiveScheme`) | `~700 snaps · scheme baseline, no games yet` |

Blend across the seam; label by whichever source dominates.

**2. Four of the six rows turned out to be depth order in disguise.** Second
tight end, second back, base linebacker and dime corner are `order[position][n]`
with a new label. The chart above survives only for the rows where a *different*
man than the depth order would pick is a real choice — which, in the crude
engine, is the receiver alignments and the passing-down back.

## v2 — the row that actually earns its place

```
┌─────────────────────────────────┐
│ OFFENSE · BACKFIELD             │
├─────────────────────────────────┤
│ EARLY-DOWN BACK  Mensah     90  │
│                  ~410 snaps 62% │
│ PASSING-DOWN BACK  Ruiz     78  │
│                  ~250 snaps 38% │
│                  run concepts:  │
│                  off the field  │
├─────────────────────────────────┤
│ Ruiz plays the down you drafted │
│ him for. Mensah is still your   │
│ back on 1st and 10.             │
└─────────────────────────────────┘
```
