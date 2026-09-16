# Audit: chess, not checkers — the pre-snap exchange

**Status: an investigation, built on the tree at `79e7a6c` (2026-09-15). It changed no
engine code.** Every claim below cites a file and line at that commit, a harness row from
`simharness --games 400` at seeds 7 and 11 on it, a line of `gamelog --seed 7 --home 3
--away 11`, or the query in the [appendix](#appendix--the-query-behind-sections-4-and-5),
which reads the same four hundred games the harness plays. Nothing about the sport is
asserted from memory: where a rule governs it is cited by article and season, and where
none does the text says *coaching practice*. This is C34,
[#229](https://github.com/knissley/football-manager/issues/229), filed out of
[ADR-0014](adr/0014-decide-from-what-the-decider-can-see.md) (PR #228, in flight when this
was written): having decided that the defence may not see the play call, *what may it
see, and when?*

## The short answer

**The engine plays one exchange, and it is one-way.** The offence draws its concept, then
its grouping; the defence draws its package having seen the grouping; and that is the whole
of what passes between the two benches before the ball is snapped. The defensive *call* —
coverage, rush, front, run fit, disguise — is drawn from the down, the distance, the score
and the clock, and reads neither the grouping on the field nor the package the defence
itself has just sent out. The offence never looks at anything: the concept is fixed before
the defence answers, and no check, audible, motion or pre-snap read exists under any name.

Measured, on the snaps where neither caller takes a situational branch, the two calls carry
**no information about each other**: the run share is the same against every coverage, the
coverage mix is the same against every grouping, and the offence hits the call's own
vulnerability exactly as often as chance ([§4](#4-measured-how-far-apart-the-two-are)).

**There is a fan-visible symptom, and it is already graded.** The sport's run share on
first and ten from eleven personnel swings **seventeen points** with the box it faces —
58.7% against a four-back front, 41.9% against five or more, from ADR-0014's own counts —
and the engine's swings **zero**. That gap is what `row:ypcOutnumberedByOne` (3.1 / 3.2
against 3.9–5.1) and the eleven-against-base carry share (13.8 / 14.6% against 18.8 /
18.3%) are reading, and ADR-0014 already names it "anticipation the engine does not
model". This audit names the mechanisms behind that word and prices them.

**A second symptom is visible in a printed game.** Play 69 of the seed-7 game: second and
goal from the one, the offence in 22 personnel, the defence in *nickel* under a *run
blitz* — a sell-out call the resolver plays as ordinary zone coverage — and a quick pass
for the touchdown. The package and the call are two draws that do not know about each
other, and the resolver reads the coverage as one bit.

The proposals are in [§8](#8-proposals). None is built. The decisions only the owner can
make are in [§9](#9-decisions-for-the-owner).

## 1. The sequence as the code executes it

From the end of one play to the snap of the next, in `GameSimulator.step`. Every step
names the file and line, who decides, and what the decision reads.

| # | Step | Where | Decider | Reads |
|---|---|---|---|---|
| 1 | The toss and its elections, if a half is opening | `GameSimulator.swift:267-286` | rules, then each captain | the situation |
| 2 | **Timeouts**, defence asked first, then offence | `GameSimulator.swift:298-306` | each bench | the situation, its class, the play clock |
| 3 | The try decision, if a try is owed | `GameSimulator.swift:321` | the offence | the situation |
| 4 | **The offence calls its concept and tempo** | `GameSimulator.swift:337`, `PlayCaller.swift:507-521` | the offence | the situation, its class, the play clock in force. **Not** the package on the field: `situation.defensePackage` at this moment is the *previous* snap's, and nothing reads it |
| 5 | **The offence sends out its grouping** | `GameSimulator.swift:340`, `PlayCaller.swift:184-236` | the offence | the class and the yard line. **Not the concept** — `personnel(for concept:…)` takes the concept and never reads it |
| 6 | **The defence substitutes**, and the answer goes on the record | `GameSimulator.swift:345-353`, `PlayCaller.swift:285-308`, `PackageConditional.swift:111` | the defence | `situation.offensePersonnel`, the down, the distance, the yard line, the clock and the score. The one exchange, and it is inside ADR-0014's boundary |
| 7 | **The defence calls** coverage, rush, front, run fit, disguise | `GameSimulator.swift:414`, `PlayCaller.swift:950-993` | the defence | **the class alone** (`defensiveCall(for: classified…)` at `:954` discards the situation). Not the grouping it is facing, not the package it just chose |
| 8 | The call's package is overwritten with the substituted one | `GameSimulator.swift:416` | the simulator | — |
| 9 | The two-minute warning, if the interval reaches it | `GameSimulator.swift:438` | rules | the tempo |
| 10 | The play clock: does the offence beat it, and does it spend a timeout | `GameSimulator.swift:456-468`, `Penalties.swift:77` | rules, then the offence | the tempo, the crowd, the clock in force |
| 11 | **The eleven are drawn** from both rotations | `GameSimulator.swift:476`, `Lineup.swift:497` | the game | the grouping, the package, the rotations |
| 12 | Pre-snap fouls | `CrudeResolver.swift:45`, `Penalties.swift:90-180` | rules | `usedMotion` (`:135`), tempo (`:120, :136, :173`), `rush.isBlitz` (`:155`), discipline, noise |
| 13 | **The snap.** The rush is the call's count out of the eleven (`Lineup.swift:133`), protection answers the count (`:193`), coverage is who is left (`:208`), the box is the front plus the linebackers (`:216`) | `CrudeResolver.swift:321-440` | the resolver | the call's `rush`; `coverage.isMan` and nothing else of the coverage (`:447`, `:465`); `runFit` (`:1028`) |
| 14 | Post-snap: the quarterback works the family's read order at the breaks | `CrudeResolver.swift:504-585`, `ReadProgression.swift:81` | the resolver | the family, the separations, his awareness. No pre-snap read exists; the first look he takes is at the first break |

Three facts about the order, each load-bearing:

- **Steps 4 and 5 are the offence deciding twice from the same information**, and the second
  decision does not read the first. The grouping is a function of the class, not of the
  concept, so a deep pass is as likely to go out in 22 personnel as an inside run is on the
  same down.
- **Steps 6 and 7 are the defence deciding twice from different information**, and the
  second does not read the first. The package is drawn from the grouping; the call is drawn
  from the class. So the eleven on the field and the call they are executing are
  independent given the class, which is how a nickel package plays `goalLineStop` (§5).
- **The offence's concept (step 4) is settled before the defence's package (step 6)
  exists**, and nothing after step 6 lets the offence revisit it. ADR-0014's second
  alternative — *let the offence re-check its concept against the box it sees* — is not
  rejected on principle there; it is rejected because this step is absent.

## 2. What each side could see, and what it reads

The inventory the issue asks for. *Could see* is what ADR-0014 allows the decider at that
moment; *reads* is what the code reads; the last column says whether the gap matters.

### The offence, before it calls (step 4)

| Field | Exists | Could see | Reads | Verdict |
|---|---|---|---|---|
| down, distance, yard line, clock, score, timeouts | `Situation.swift` | yes | yes (`PlayCaller.swift:507-521, :614-670`) | — |
| the package on the field | `Situation.swift:139` | **yes, once the defence has substituted** — but at step 4 the defence has not, so the value is last snap's | no | **The check is missing.** Not a violation; an absence. The offence decides before the information it is entitled to exists |
| the defence's declared front (`frontAlignment`) | `DefensiveCall.swift:27` | yes, once shown, unless disguised (coaching practice) | no | nothing to read: the front is drawn at step 7, after the offence has called |
| the shell (`coverage`) | `DefensiveCall.swift:55-100` | the pre-snap picture only, and disguise degrades it (coaching practice; `play-calling.md:617-618` says so) | no | as above |

### The defence, before it substitutes (step 6)

| Field | Could see | Reads | Verdict |
|---|---|---|---|
| `situation.offensePersonnel` | yes — declared by substituting | **yes** (`PlayCaller.swift:296-300`) | the one exchange, correct and sourced |
| down, distance, yard line, clock, score | yes | yes (`:296-307`) | — |
| the offence's tempo | yes, once the offence shows it | no | matters: a defence that cannot substitute against tempo is coaching practice **and possibly a rule** — Rule 5 Section 2 is absent from `docs/reference/playing-rules.md` (§3) |
| the concept | **no** (ADR-0014) | no | correct |

### The defence, before it calls (step 7)

| Field | Could see | Reads | Verdict |
|---|---|---|---|
| `situation.offensePersonnel` | yes | **no** — `defensiveCall(for:)` reads `classified` only (`PlayCaller.swift:954, :957-993`) | **Unread and should be read.** The grouping is the sport's first tell, and the defence is allowed it |
| its own package | yes | **no** — the call's `package` is overwritten afterwards (`GameSimulator.swift:416`) | a call and an eleven that disagree, e.g. a run blitz from dime (§5) |
| the concept | no | no | correct |

### What the resolver reads of the calls (step 13)

| Field | Read | Where | Verdict |
|---|---|---|---|
| `OffensiveCall.concept` | yes | `CrudeResolver.swift:38` | — |
| `OffensiveCall.tempo` | yes | `Penalties.swift:77, :120, :136, :173`; `GameClock` | — |
| `OffensiveCall.usedMotion` | yes, as a penalty term | `Penalties.swift:135` | **never true.** No caller sets it: the only writes are the initialiser's default (`OffensiveCall.swift:41-46`). The term at `:135` has never fired in a game. `playing-rules.md:85-87` (3-12-2) already records that nothing says which way a man moved; it does not say nobody moves |
| `DefensiveCall.rush` | yes | `Lineup.swift:133`, `Penalties.swift:155` | `.simulated` is sent as four rushers and is otherwise identical to `.fourMan` (`Lineup.swift:145` returns before any exchange): "the bluff" (`DefensiveCall.swift:114-115`) bluffs nobody, because there is no protection identification to fool (`match-engine.md:255-262` says so of the zone blitz; the same is true here). `.sixManBlitz` and `.simulated` are called on 0.0% of snaps (§4, table 1) — #225's finding, restated |
| `DefensiveCall.coverage` | **one bit** | `CrudeResolver.swift:447, :465` — `coverage.isMan` picks the rating and the technique label; nothing else of the nine-case enum is read. `deepDefenders` (`DefensiveCall.swift:85`) has no reader in `FMSimulation` | **Cover 2, cover 3, quarters, match quarters and prevent resolve identically**, and so do man free, two-man and cover zero. **`Coverage.runBlitz`** — documented as *no coverage call, everyone is playing the run* (`:72-73`) — has `isMan == false` and so is resolved as **zone coverage with the defender's zone rating**, the same contest as cover 3. A sell-out costs the defence nothing against the pass. The `.disguised` field cannot degrade a read of a shell the resolver does not have |
| `DefensiveCall.frontAlignment` | no | — | unread. Takes only `.even` (82.5%) and `.bear` (17.5%) in play; `over`, `under` and `slanted` are never called (§4, table 1). `vulnerability`'s `.runAwayFromStrength` (`DefensiveCall.swift:196`) can therefore never be produced |
| `DefensiveCall.runFit` | yes | `CrudeResolver.swift:1028-1030` | `.aggressive` and `.sellOut` move the block contest; `.balanced`, `.twoGap`, `.spill` are the same zero. Three of five values are one value |
| `DefensiveCall.disguised` | no | — | unread. True on 2.9% of snaps, all of them `manFreeBlitz` (`DefensiveCall.swift:243-244`). The doc comment at `:32-34` describes a cost and a benefit; neither exists. #45's note that it is unread (its Problem section) is **still true** |
| `DefensiveCall.vulnerability` / `CallVulnerability` | no | — | unread in `FMSimulation` and in `Tools/`; the only reader outside its own file is a comment in `Lineup.swift:150`. Still true from #45. `roadmap.md:230` defers it to M5, correctly: a soft spot cannot be soft without geometry. But two of its seven cases are unreachable today for a different reason — `.runAwayFromStrength` needs a declared front nobody calls, and `.playAction` needs a `runBlitz` or `sellOut` call the resolver plays as zone |
| `Tempo.slow` | — | `GameClock.swift:190` | never called: `PlayCaller.swift:690-694` returns only hurry-up, fast, normal and bleed-clock (§4, table 1). Registered here so the next person does not infer it from the enum |

### What `ReadProgression` covers, and does not

The issue asked whether the read progression already models part of this. It models the
**post-snap** half only: the passer's first judgement is at the first read's break
(`CrudeResolver.swift:551-585`), on a perceived separation that carries his own error
(`:516`). There is no pre-snap judgement of the shell, no hot route against a blitz, and
no read that changes because of what the defence showed — because the defence shows
nothing. So the question this audit narrows to is the pre-snap half, and the whole of it.

## 3. The sport's sequence, beside it

From the reference and the `/football-domain` skill. **Most of this is coaching practice
rather than the book**, and saying so is more useful than a forced citation. Where a rule
governs, it is cited; where the reference has no entry, that is a finding on the reference.

| # | The sport | Rule, or practice | The engine |
|---|---|---|---|
| a | The offence's call comes with a personnel grouping; it substitutes, and the grouping is public the moment it jogs on | Practice. 5-1-1 (eleven a side) is the only Rule 5 article in `playing-rules.md:369` | Steps 4–5. Built, except that the grouping does not follow from the concept |
| b | The defence matches personnel — or chooses not to — and may substitute only when the offence has (the offence at tempo can hold the defence's eleven on the field) | **Rule 5 Section 2 governs substitution and is absent from the reference.** Whether the book constrains the defence against tempo, and how, is not established here and must be read before anything is built on it | Step 6 draws a fresh package on **every** snap, whatever the tempo: the package changes between consecutive snaps of a drive on 43.2% of hurry-up snaps and 47.3% of normal-tempo ones (§4, table 6). No memory of the previous snap's eleven exists in the caller |
| c | The offence breaks the huddle and shows a formation; motion and shifts follow | 7-4-8 (illegal motion), 7-5-1 (illegal formation), 3-12-2 (which way a man is moving at the snap) — `playing-rules.md:76-87, :491-492` | No formation. Motion is a Bool nobody sets. The fouls are drawn from a rate |
| d | The defence aligns to what it sees: a front, a shell, a box count — or shows one thing and plays another | Practice. Disguise is the deliberate degradation of the offence's read (`play-calling.md:617-618`, `gameplan.md:130`) | Step 7 draws the call from the class alone. `frontAlignment` and `disguised` are on the call and read by nothing |
| e | The quarterback reads the picture — the box, the safeties, the leverage — and may check out of the play, change the protection, or run it | Practice. This is the *check* ADR-0014's second alternative names | **Absent.** The concept is fixed at step 4 |
| f | Motion asks a question; how the defence moves with it answers | Practice | Absent (c) |
| g | The defence may rotate after the motion, or on the quarterback's cadence | Practice | Absent (d) |
| h | The snap, inside the play clock | 4-6-1, 4-6-2 (`playing-rules.md:253-292`) | Built (step 10) |
| i | After the snap the quarterback works his reads against the coverage that is actually there | Practice; the read order is authored coaching design (decision 222) | Built for the crude engine's five families (step 14) |

Rows b, d, e, f and g are the exchange. The engine has the first half of a, all of h, and
i. **Of the five rows that make it chess, it has none.**

## 4. Measured: how far apart the two are

The query in the appendix plays the harness's four hundred games at seed 7 and again at
seed 11 and reads 53,194 scrimmage snaps a seed (kneels, spikes, tries and flag-only snaps
out). **Ordinary snaps** are those on which neither caller takes a situational branch —
not must-pass, not clock-burn, not desperation, not two-minute, not short yardage, not
goal-to-go, not inside the three, and the game within one score — 24,074 at seed 7. They
are the population on which the two callers' base tables face each other with no shared
cause, so any correlation left would be information passing between them.

**Table 1 — what the calls carry**, all scrimmage snaps, seed 7.

| Field | Values in play |
|---|---|
| `disguised` | true 2.9% (1,555 snaps, every one `manFreeBlitz`) |
| `usedMotion` | true **0.0%** (0 snaps) |
| `frontAlignment` | even 82.5%, bear 17.5%, over / under / slanted **0.0%** |
| `rush` | four-man 76.6%, five-man 9.5%, zone blitz 8.5%, three-man 5.4%, six-man **0.0%**, simulated **0.0%** |
| `coverage` | cover 3 30.7%, match quarters 17.4%, man free 13.8%, cover 2 12.4%, two-man 11.4%, run blitz 6.6%, prevent 5.4%, quarters 2.3%, cover zero **0.0%** |
| `tempo` | normal 85.3%, hurry-up 7.7%, fast 3.5%, bleed-clock 3.5%, slow **0.0%** |

**Table 2 — run share by the coverage called against it**, ordinary snaps. If the defence
knew anything about the concept, the rows would differ.

| Class | Snaps | Run share | vs man free | vs two-man | vs cover 3 | vs cover 2 | vs match quarters |
|---|---:|---:|---:|---:|---:|---:|---:|
| first down, seed 7 | 12,696 | 61.6% | 60.4 | 65.1 | 61.7 | 60.8 | 60.5 |
| first down, seed 11 | 12,531 | 61.2% | 59.9 | 62.4 | 61.3 | 60.9 | 61.2 |
| second and long, seed 7 | 6,145 | 22.0% | 22.9 | 22.5 | 22.0 | 23.7 | 20.2 |
| second and long, seed 11 | 6,062 | 21.0% | 19.9 | 20.8 | 21.0 | 21.2 | 21.4 |

Flat, at both seeds, inside the binomial noise of each cell (the smallest cell above is
477 snaps, where one standard error is about two points). **By construction:** the offence's
run share is a function of the class (`PlayCaller.swift:648-670`) and the defensive call is
a function of the class (`:957-993`), and neither reads the other.

**Table 3 — the coverage called, by the grouping on the field**, ordinary first downs. If
the defensive call read the grouping, the rows would differ.

| Grouping | Snaps (seed 7) | man free | two-man | cover 3 | cover 2 | match quarters |
|---|---:|---:|---:|---:|---:|---:|
| 11 | 9,084 | 7.5 | 12.5 | 41.6 | 16.0 | 22.4 |
| 12 | 2,716 | 7.5 | 12.8 | 41.8 | 15.4 | 22.5 |
| 21 | 896 | 6.5 | 12.6 | 42.6 | 16.5 | 21.8 |

Seed 11 reads the same to within a point in every cell. **The defence calls the same
coverage mix against two backs as against three receivers.** This one is *not* the
boundary: ADR-0014 allows the defence the grouping, and `package(for:)` reads it; the call
simply was never written to.

**Table 4 — run share by the package on the field**, eleven personnel, first and ten. This
is the row the sport can be put beside, because ADR-0014 printed the counts.

| Population | vs base (four backs) | vs nickel or more | Swing |
|---|---:|---:|---:|
| the feed, 2023: 710 of 3,769 carries and 499 of 4,747 dropbacks met base | **58.7%** (710 of 1,209) | **41.9%** (3,059 of 7,307) | 16.8 points |
| the feed, 2024: 646 of 3,530 and 460 of 4,371 | **58.4%** (646 of 1,106) | **42.4%** (2,884 of 6,795) | 16.0 points |
| engine, seed 7, every such snap | 56.1% (2,039 snaps) | 58.8% nickel (11,251), 59.3% dime (882) | −2.7 points |
| engine, seed 7, ordinary snaps only | 58.1% (1,220) | 62.4% nickel (6,714), 61.6% dime (547) | −4.3 points |
| engine, seed 11, ordinary snaps only | 60.5% (1,248) | 61.2% nickel (6,647), 57.9% dime (475) | −0.7 points |

The feed's rows are Bayes over the table in ADR-0014's Context (P(run | base) =
P(base | run)·P(run) / P(base)), and the counts are the ADR's, re-stated so a reader can
check the arithmetic. The engine's base cell holds 1,200–2,000 snaps, so one standard
error is 1.1–1.4 points; a sixteen-point swing is more than ten of them away. **In the
sport an offence in eleven personnel on first and ten runs more often into a heavy box
than into a light one. In the engine it runs the same into both**, because the concept is
drawn before the box exists.

What produces the sport's swing is not established here, and matters for what to build.
Two mechanisms are consistent with it and they pull the same way: the defence *anticipates*
— loads the box on the downs, scripts and looks it expects a run from (practice; decision
42's "tendency") — and the offence *selects* — keeps the run on when the box is light and
checks out when it is not, which would pull the other way and is evidently smaller. A
third is that the feed's four-back snaps include base fronts the defence was simply in.
The direction says anticipation dominates; the split between the three is a question for
the feed, not for this audit.

**Table 5 — the offence against the call's own vulnerability**, ordinary snaps. *Hit* is the
share of snaps on which the concept called is the one `vulnerability` says the call is weak
to; *chance* is the class's share of that concept regardless of call.

| Class, seed | weak to the run: hit / chance | weak to seams: hit / chance | weak to crossers: hit / chance | weak to the hot throw: hit / chance |
|---|---:|---:|---:|---:|
| first down, 7 | 60.5 / 61.6 | 15.2 / 15.3 | 15.2 / 15.3 | 19.8 / 19.5 |
| first down, 11 | 61.2 / 61.2 | 14.6 / 14.8 | 14.9 / 14.8 | 20.1 / 20.1 |

Chance, to the decimal. The offence exploits nothing, because it sees nothing.
`CallVulnerability`'s doc comment says it exists so that "a coordinator choosing between
these is choosing what to give up" (`DefensiveCall.swift:202-207`); today nobody is on the
other side of the trade.

**Table 6 — the package changing between consecutive snaps of one drive, by the offence's
tempo**, all scrimmage snaps.

| Tempo | Snaps (seed 7) | Package changed | Seed 11 |
|---|---:|---:|---:|
| hurry-up | 3,233 | 43.2% | 43.4% |
| fast | 1,430 | 44.3% | 44.7% |
| normal | 34,502 | 47.3% | 47.1% |
| bleed-clock | 1,752 | 45.0% | 47.3% |

The defence substitutes on nearly half of all consecutive snaps and tempo does not move it.
The three or four points between hurry-up and normal are the class (the two-minute
groupings are steadier), not the tempo. In the sport the offence at tempo is holding the
defence's eleven on the field; that is the point of tempo, beyond the clock. What the book
says about it is the Rule 5 Section 2 gap in §3.

## 5. Is there a fan-visible symptom today?

**Yes, two, and one of them is on the harness already.**

**In the harness.** `row:ypcOutnumberedByOne` reads 3.1 / 3.2 against 3.9–5.1, `OFF` at
both seeds, and eleven personnel meets a four-back front on 13.8 / 14.6% of its
first-and-ten designed carries against the feed's 18.8 / 18.3% (harness, *grouping against
package* block, seeds 7 and 11; the ratio is the `11 / base` count over the four `11 /`
rows). ADR-0014 accepted the second as the honest reading of a draw that cannot see the
concept, and named the residual "anticipation". Table 4 is that residual measured as a
swing rather than as a share: the sport's run share responds to the box by sixteen or
seventeen points and the engine's by nothing. **The two rows are the symptom of a missing
exchange, not of a wrong constant**, which bears on #227 (§8, proposal 8).

**In a printed game.** `gamelog --seed 7 --home 3 --away 11` prints the grouping, the
package and the coverage on every scrimmage line (`Tools/gamelog/main.swift:926-928`) and
nothing else about the moment before the snap, because nothing else happens. Thirteen of
its snaps are labelled *run blitz* — five from nickel, five from base, two from dime, one
from the goal-line eleven — and play 69 is the one a fan would stop on:

```
  69  Q2 2:09  WRN  2nd & goal opp 1     quick pass     C. Benavides complete to B. Blakemore for 1 yard — TOUCHDOWN — his 2nd read  · 22 vs nickel, run blitz
```

Second and goal from the one, 22 personnel, the defence in nickel playing a sell-out run
call, and a throw. Three things a fan cannot see are wrong with it. The package was drawn
from the yard-line row (`PackageConditional.swift:74`, nickel 43.2% inside the three) and
the call from the short-yardage branch (`PlayCaller.swift:977-978`, `goalLineStop` 62%), so
five defensive backs are executing a bear front with everybody in the box, which the sport
does not show and the record cannot notice. The call's coverage is `runBlitz`, "no coverage
call", and the resolver played it as zone (`CrudeResolver.swift:447`), so the sell-out cost
the defence nothing on the throw — the touchdown came off a coverage contest, not off a
defence caught selling out. And the offence, in a grouping the sport sends out to run, threw
without ever having seen the front it was throwing into. None of that is a symptom the log
can print; the symptom is that the log has nothing to print.

**What is not a symptom today**, stated so it is not inferred: no row measures a check, an
audible, motion or disguise, and no row can, because none occurs. "The quarterback never
checks out of a doomed play" is true and invisible; "the defence never shows two-high and
plays one" is true, and would be invisible even if it did, because the resolver plays all
shells alike.

## 6. Where the docs and the tree disagree

- **`play-calling.md:603-609`** says *neither caller reads formation, personnel or motion
  off the other*. Since #226 the package draw reads personnel (`PlayCaller.swift:307`),
  which the same doc's own nickel section describes at `:380-395`. The sentence is stale
  by one merge.
- **`DefensiveCall.swift:32-34`** documents `disguised` as costing a beat of reaction time
  and buying a worse quarterback read; **`:114-115`** documents `.simulated` as "the
  bluff". Neither does anything (§2). The comments read as behaviour and are design intent;
  they should say so, or the register should carry them.
- **`roadmap.md:227-238`** lists `CallVulnerability` as designed and not consulted, and
  says the audit "found it reads `runFit` and the weather on a kick, and nothing else".
  The list is short by six: `frontAlignment`, `disguised`, `usedMotion` (never set),
  `Coverage` beyond one bit, `PassRush.simulated`, `Tempo.slow`.
- **`match-engine.md`** has no section on the moment before the snap. It describes the seam
  (`:134-172`), the pocket (`:188-262`) and the clock; the order in which the two benches
  decide, which §1 had to be read out of `GameSimulator.step`, is not written anywhere.
- **`audit-is-this-football.md:118-121`** (S3) says three of the six call dimensions are
  read and three ignored. Still true, and now it should say that one of the three read is
  read as one bit.
- **`docs/reference/playing-rules.md`** has one entry under Rule 5. The substitution rules
  a defence plays under against tempo are not in the reference, so this audit could not
  cite them and nothing built on them can either.

## 7. What closing a gap costs

The price list the proposals are marked against. Each item is a measured precedent, not an
estimate.

- **Any new pre-snap decision is a draw**, and a draw in a play's stream reorders every
  draw after it in that play (`GameSimulator.swift:240`: one stream per play, split by
  index). Precedent: #97 added one draw per half and 205 of 400 games differed from their
  first snap at seed 7 (PR #221); #218 added one per snap and 21 rows flipped standing
  inside the noise floor with none moving beyond it (PR #226). So: `GoldenSeedTests`
  regenerated in the behaviour commit, both seeds re-taken, every moved row reported
  against `harness-noise-sweep.tsv`'s floor, and a preflight engine lane of four to seven
  minutes (250 s and 416 s on those two PRs). **A pre-snap draw is cheaper in one way**:
  taken before `Lineup.onField` (`:476`) it moves every downstream draw, but taken from a
  separate labelled stream — as the toss is (`:221-228`) — it moves none, at the price of
  a second stream per play.
- **A caller decision goes in the decision log** (rule 4). A new `DecisionKind` costs a case
  with its contract stated (`PlayRecord.swift:57-260`), a factory that is the only way to
  build it (#177, `:595`), an arm in `DecisionContractTests` (`:111-113, :195-198,
  :247-249`), a line in `play-record.md`'s register, the gamelog printer, and the footprint
  check. #226's `.substitution` is the worked example: one kind, one afternoon.
- **The sim stays pure and the tick loop never allocates** (rules 1 and 5). There is no
  tick loop at M1, so the second rule binds only in that a check must be a flat draw over
  the situation and the package — no per-snap table, no string, no lookup keyed by
  anything unordered. Every proposal below is an integer comparison over values already on
  `Situation` and `Calls`.
- **A rate needs a source** (rule 10). The feed carries P(package | grouping, down) and,
  by Bayes over ADR-0014's counts, P(run | box); it carries nothing about disguise,
  motion or audibles as such. Anything drawn from those is coaching practice, named as
  modelling in `calibration-sources.md`'s *nothing sources* section, and graded by what it
  produces.
- **A doc-only change costs the docs lane**: 18 steps, about three minutes (PR #226's
  `55c82e2`).

## 8. Proposals

Each is checked against ADR-0014, priced from §7, and placed at a milestone. **Nothing here
is built, and none of it gates #49** unless the owner puts it there.

### ADR-0015 — the order of the exchange, and what each step may read

**Decide:** the sequence in §1 becomes a stated contract with one step added. (1) The
offence calls a concept, a tempo and a grouping, and the grouping *follows from* the
concept. (2) The defence substitutes on the grouping, the down, the distance, the yard line,
the clock and the score, **and only when the offence has substituted or a series has
begun**. (3) The defence calls on all of that plus its own package, never the concept. (4)
**The offence may check**: re-draw its concept having seen the package and the front, never
the coverage or the rush. (5) The snap. Disguise, when built, is the defence withholding
the front and the shell from step 4 at a cost; motion, when built, is the offence forcing
the defence to show them.

**ADR-0014:** inside it by construction — each step names what its decider can see, and
step 4 is the ADR's own second alternative, taken up. **Rejects:** the status quo (no
check, per-snap substitution), and a check that sees the coverage. **Cost:** a doc. Writing
it before any of the issues below is what keeps them from each deciding the order
separately. **M1.** Recommended.

### Doc corrections (one docs-lane issue, track I)

The six items in §6, plus a *Before the snap* section in `match-engine.md` that carries §1's
table once ADR-0015 fixes it. **ADR-0014:** n/a. **Cost:** three minutes. **M1.**
Recommended; can go with the ADR.

### D-track: Rule 5 Section 2 into the reference

**Finding:** the reference has no entry for substitution beyond 5-1-1 (§3 b), and this audit
could not say whether the book constrains a defence substituting against tempo. **Plan:**
fetch the 2025 book (`scripts/fetch-rulebook.sh`), read Rule 5 Section 2 in full, write the
entries in our own words by article, and name which are modelled, which are not, and which
the engine contradicts today (§4, table 6). **ADR-0014:** n/a. **Cost:** a docs lane;
`lint-reference` must stay green. **M1, before proposal 4.** Recommended.

### C-track: a defence substitutes when the offence does

**Finding:** the package is redrawn on every snap regardless of tempo (table 6), so the
offence at tempo holds nobody on the field. **Plan:** carry the previous snap's package in
`State`; draw a new one only when the grouping changed, a series began, or the interval was
a stoppage; otherwise keep it and write a `.substitution` point saying so (a new `detail`
value on the existing kind, or a second kind — the contract test decides). **ADR-0014:**
inside; it *narrows* what the defence may do, on information it has. **Cost:** a
behaviour commit, goldens, both seeds; **it will move `packageBase` and `packageNickel`**,
because the feed's per-snap conditional already contains the sport's substitution
constraint and applying the conditional per *substitution* rather than per snap changes
the marginal — the owner should expect those two rows to need re-reading rather than
retuning. Depends on the D-track entry above saying what the book allows. **M1 if the
book supports it; otherwise it is practice and the owner decides.** Recommended, second.

### C-track: the defensive call reads the grouping

**Finding:** table 3. The call is a function of the class alone and the grouping is
information ADR-0014 grants it. **Plan:** `defensiveCall(for:)` takes the situation it
already receives and conditions on `offensePersonnel` where the feed supports it — the
participation feed pairs the grouping with the package; whether it pairs it with a
coverage or a rush count is #225's plan item 2 to find out. **This is #225's territory**
(it rewrites the defensive caller's tendencies) and should be a constraint in #225's plan
rather than a fourth issue in the same function. **ADR-0014:** inside. **Cost:** #225's.
**M1, inside #225.** Recommended; the owner decides whether #225 absorbs it.

### C-track: the offence checks against the box

**Finding:** table 4 — the sport's run share responds to the box by sixteen points, the
engine's by none, and ADR-0014 names the mechanism and says the engine does not have it.
**Plan:** after step 6, one draw: given the package on the field and the class, the offence
keeps its concept or re-draws it from P(concept | package, class). The rate is derivable
from the feed by Bayes (table 4's arithmetic) for the run/pass split; the split within pass
families is practice. The check goes on the record as a `DecisionKind` — *checked, from X
to Y* — so a fan can be told *he saw the light box and handed it off*. **ADR-0014:** inside
— the package is observable; the ADR's own text says a check "moves the boundary rather
than crossing it". **The risk, stated:** table 4's swing is mostly the defence's
anticipation, and reproducing it wholly through the offence's check makes the engine's
causal account say the offence chose what in the sport the defence mostly forced. That is
not a lie about the engine, which would then work that way; it is the wrong mechanism
carrying a right number, which is the shape #227 warns about. **Cost:** a draw per snap,
goldens, both seeds, one kind; it will move `runShare.*`, both ypc-by-box rows and the
eleven-against-base share, and it should. **M1 or M2 — the owner's call (§9, Q1).** My
recommendation is below.

### M2: the defence anticipates from the opponent model

**Finding:** the larger half of table 4's swing is the defence loading the box on what it
expects, and expectation is decision 43's tendency table, which is M2's *team tendencies*
and decision 44's snapshot in `GameSetup`. **Plan:** none now; a line in M2's stream list
that the package and the call condition on the tendency prediction for this situation from
this grouping. **ADR-0014:** inside — the ADR generalises decision 42, which is exactly
this. **M2.** Not M1.

### A comment on #227, not an issue

**Finding:** #227 reads the engine's ypc response to the box as a slope nine to fourteen
times too steep. Part of the sport's small gap between boxes is *selection*: in the sport
the runs that meet a loaded box are the ones the offence chose to keep on against it, and
the ones it checked out of are not in the carries row at all. Table 4 says the engine
chooses nothing. So some of the slope #227 measures may be the check that is missing rather
than a constant that is wrong, and #227 should re-measure after the check exists — or
accept that its band is partly a selection effect the engine cannot reach without one.
**ADR-0014:** n/a. **Cost:** a comment. **Recommended now.**

### C-track: the coverage is read as one bit, and a run blitz covers like cover 3

**Finding:** §2, the `coverage` row. Not a pre-snap defect, but it is what makes disguise,
the shell and the pre-snap read impossible to build on top of: there is no shell to show or
hide. **Plan:** the resolver reads `deepDefenders` and `isPressureCoverage`; a `runBlitz`
or `coverZero` call has no deep help and the deep read's contest says so; the coverage
contest reads the shell. **A `.football` test first**, from the feed's pressure-coverage
rows if it has them, else named as modelling. **ADR-0014:** n/a. **Cost:** a behaviour
commit that moves the pass rows; **after #39 lands**, which is rewriting the technique
vocabulary on the same points. **M1, on #49's gate, after #39 and before #224** — the
owner's decision of 2026-09-16 (§9, Q4). The resolver code is deleted at M5; the test, the
rows and the shell's definition are not, and M2 reads the stream this makes true.

### E-track: the harness carries the exchange

**Finding:** the numbers in §4 live in a scratch query. **Plan:** tables 2, 3, 4 and 6 as
ungraded rows in `UngradedRows.swift`, so the ADR-0015 order is measurable on every run and
a check, once built, prints its swing beside the feed's. **ADR-0014:** n/a. **Cost:** a
tools lane. **M1.** Recommended.

### Deferred, and why

- **Disguise** (`disguised` reaching the read): M5 at the earliest, and only after the
  shell is more than one bit. Until then there is nothing to disguise.
- **Motion** as an offensive decision: M6, where a design says who moves and where; the
  penalty term can stay dead until then, and the register should say it is.
- **Post-motion rotation** and the quarterback's pre-snap read of the shell: M5, geometry.
- **Protection identification**, which is what `.simulated` and the zone blitz exist to
  beat: #224's question, and M6's play format.
- **`frontAlignment`'s three unreached values**: nothing calls them and nothing reads them;
  register as unreached with their milestone rather than wire them in.

## 9. Decisions for the owner

Each with the choices, what each trades, and a recommendation. None is decided here.

**Q1 — Does the offensive check land at M1 or wait for M2's tendency model?**
*Build it now:* a crude complete exchange, the ypc-by-box rows become honestly reachable,
#227 gets its confound measured, and it is one draw. *Wait:* the swing is mostly the
defence's anticipation, and a check alone reproduces the number with the wrong mechanism.
*Both at M2:* correct, and the whole of M1 keeps a run game that cannot see the box.
**Recommendation: build it now, and say on the record and in the ADR that it carries the
swing alone until M2's anticipation takes its share.** The rows stay honest because the
draw is over a population the offence can see, and a wrong-shaped number is better
reported by a row that exists than by one that cannot.

**Q2 — Does "the defence substitutes when the offence does" wait for the rulebook entry,
or go in as practice?** *Wait:* rule 10; the book may constrain it exactly, and building
practice where an article exists is the mistake #186 was. *Practice now:* the mechanism is
the same either way. **Recommendation: wait — the D-track entry is a docs lane and a day,
and it decides whether the test is `.football` or `.pin`.**

**Q3 — Does the defensive call reading the grouping fold into #225, or file separately?**
*Fold:* one caller rewrite, one derivation, one set of moved rows. *Separate:* #225 is
already large. **Recommendation: fold, as a plan constraint on #225's item 4, since a
defensive caller rewritten without it would be rewritten twice.**

**Q4 — Does the one-bit coverage defect gate anything?** It is not pre-snap and it is not
on #49's gate. *Gate it on #49:* every pass row the retune will set a level against comes
out of a coverage contest that cannot tell prevent from cover 3, so the retune would be
done twice — #224's argument, and it is the same argument. *Leave it off:* #49 is already
eight items, and the crude resolver dies at M5. **Decided by the owner on 2026-09-16:
gated.** It runs after #39 and before #224 in the resolver region. What survives M5 either
way is the football test, the rows, the shell's definition on `Coverage`, and the promise
that the coverage the record names is the coverage the field played — which M2 is built
against.

**Q5 — Who owns ADR-0015?** It is a resolver-semantics decision and a design decision at
once — decision 42's successor. **Recommendation: the owner writes it or has it written
via `/adr`, and it lands before proposals 4, 5 and 6 are filed, so they cite it rather
than each re-deciding the order.**

## Appendix — the query behind sections 4 and 5

A scratch executable, not in the tree, depending on the four packages by path and playing
the harness's schedule (`simharness/main.swift:212-249`: same world, same weather draw,
same seeds). It is reproduced here so the numbers can be re-taken; proposal 10 is what
would make it unnecessary.

```swift
// presnap/Sources/presnap/main.swift — build with the four FM packages as path deps.
import Foundation
import FMCore
import FMGeneration
import FMRandom
import FMSimulation

let games = 400
let seed: UInt64 = CommandLine.arguments.count > 1 ? UInt64(CommandLine.arguments[1])! : 7
guard case .success(let world) = WorldGenerator.generate(
    seed: seed, shape: .standard, season: 2030, parts: .teamsAndRosters,
    collegeCount: 80, strengthSpread: WorldGenerator.strengthSpread)
else { fatalError("no world") }

let simulator = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
var plays: [PlayRecord] = []
let teams = world.teams
for index in 0..<games {
    let home = teams[index % teams.count]
    let away = teams[(index + 1 + index / teams.count) % teams.count]
    guard home.id != away.id else { continue }
    var weatherRandom = SplittableRandom(seed: seed &+ UInt64(index) &* 104_729)
    let weather = WeatherGenerator.forGame(
        stadium: home.stadium, week: index % 18 + 1, using: &weatherRandom)
    let setup = GameSetup(
        game: GameID(UInt64(index + 1)),
        home: GameTeam(id: home.id, depthChart: world.depthChart(of: home.id), scheme: home.scheme),
        away: GameTeam(id: away.id, depthChart: world.depthChart(of: away.id), scheme: away.scheme),
        players: world.players, stadium: home.stadium, weather: weather, rules: .standard,
        seed: seed &+ UInt64(index) &* 7919)
    plays += simulator.simulate(setup).plays
}

let excluded: Set<PlayConcept> = [.kneel, .spike, .twoPointPass, .twoPointRun]
let scrimmage = plays.filter {
    $0.outcome.kind.isScrimmagePlay && $0.outcome.kind != .penaltyOnly
        && !excluded.contains($0.calls.offense.concept)
}
func isRun(_ p: PlayRecord) -> Bool {
    p.calls.offense.concept == .insideRun || p.calls.offense.concept == .outsideRun
}
/// No situational branch in either caller: the two base tables face each other.
func isOrdinary(_ p: PlayRecord) -> Bool {
    let c = SituationClass(p.situation)
    if c.isMustPass || c.isClockBurn || c.isDesperation || c.time.isTwoMinute { return false }
    if c.downAndDistance.isShortYardage || c.downAndDistance == .goalToGo { return false }
    if p.situation.ballOn <= 3 { return false }
    return c.score.isOneScoreGame || c.score == .tied
}
let ordinary = scrimmage.filter(isOrdinary)
func pct(_ n: Int, _ d: Int) -> String { String(format: "%5.1f%%", Double(n) / Double(d) * 100) }

// Table 1: values in play.
print(pct(scrimmage.count { $0.calls.defense.disguised }, scrimmage.count), "disguised")
print(pct(scrimmage.count { $0.calls.offense.usedMotion }, scrimmage.count), "usedMotion")
// … and the same over frontAlignment, rush, coverage and tempo.

// Table 2: run share by coverage, within a class, ordinary snaps.
for cls in [DownAndDistanceClass.firstDown, .secondLong] {
    let inClass = ordinary.filter { SituationClass($0.situation).downAndDistance == cls }
    for cov in Coverage.allCases {
        let snaps = inClass.filter { $0.calls.defense.coverage == cov }
        if snaps.count >= 100 { print(cls, cov, snaps.count, pct(snaps.count(where: isRun), snaps.count)) }
    }
}
// Table 3: coverage by grouping, ordinary first downs — group `firstDown` by
// `situation.offensePersonnel.code`, then by `calls.defense.coverage`.
// Table 4: run share by package, eleven personnel, first and ten — filter on
// `offensePersonnel == .eleven && distance == 10`, group by `situation.defensePackage`.
// Table 5: for each `calls.defense.vulnerability`, the share of snaps whose concept is
// the one it names (playAction → .playAction; quickGame/hotThrow → .quickPass/.screen;
// theRun/runAwayFromStrength → a run; crossers/seams → .mediumPass/.deepPass), against
// the class's share of that concept over every call.
// Table 6: walk `plays` in order; on consecutive scrimmage snaps of one possession that
// did not start a new series, count `situation.defensePackage` changing, keyed by
// `calls.offense.tempo`.
```
