# A back you drafted to catch passes plays the downs you drafted him for

**Status:** accepted in part — items 1, 3 and 4 accepted; item 2 parked
**Milestone:** M3.5 · **Size:** medium · **Written:** 2026-09-15, from a `/design-grill`
session · **Designer's verdict:** 2026-09-15, [below](#designers-verdict--2026-09-15) ·
**Tracker:** [#183](https://github.com/knissley/football-manager/issues/183)

## The player's decision

Who is on the field, in which situation — assigned by job rather than inherited from a
single ranking.

Today a position group is one ordered list and `RotationProfile` turns the index into a
snap share, so "who plays" and "who is best" are the same fact. The player decides to
break that: the back on a pass concept is not the back on a run concept; the receiver in
the slot is not necessarily the receiver you'd list first.

**Before choosing** they see each role, who fills it, and a projection — *~250 snaps, 38%
of offensive downs* — computed from their own package and concept mix, with the line
naming its own source (this season / last season / scheme baseline). **After choosing**
they see the snap count come true or not. **They can be wrong and know it**: assign a man
to a role your caller rarely reaches and the projection says 140 snaps before the season
rather than after it.

Four things, of which the roster screen is the smallest:

1. **The caller distinguishes the back by concept family.** A pass concept can field a
   different back than a run concept. *(caller)*
2. **The coverage contest reads the rating the alignment asks for** — inside rewards
   `routeRunning`/`agility`/`acceleration`, outside rewards
   `releaseVsPress`/`catchInTraffic`/`strength`. *(resolver)*
3. **The defence can travel its best cover man** with the offence's best receiver,
   sometimes. *(caller)*
4. **The depth chart assigns men to alignments and roles.** *(roster, riding M3.5's
   rekeying)*

**Items 2, 3 and 4 are one indivisible landing.** Item 4 is what creates the ability to
move a receiver inside; without 2 and 3 that is a dominant strategy with no counter. Item
1 is independent and lands on its own.

> **The verdict overturns this paragraph.** The exploit item 4 unlocks is real, but its
> mechanism is an ordering artifact that item 3 fixes on its own; item 2 is neither
> necessary to it nor sufficient for it. The landing is **3+4**, and item 2 parks.
> See [*The bundle does not hold*](#the-bundle-does-not-hold--items-3-and-4-land-without-item-2).

## The moment

Draft day, round four. You take a 78-overall receiving back over an 84-overall early-down
back, with a 90-overall starter already on the roster, and you say out loud *"he'll play
third downs."* Week 8, you open the roster and he has 250 snaps and 31 catches. The 90 is
still your back on first and ten and nothing was taken from him.

## Prototype

`role-chart-sketch.md`, carried beside this brief — a text wireframe in
`docs/weekly-loop.md`'s idiom, two versions. The owner reacted to two things. **First**,
"preseason" was wrong: the chart is editable year-round, which turned the projection's
denominator into a design question, resolved as a three-source table where the line names
its source. **Second**, and more damaging: four of the six proposed roles (second tight
end, second back, base linebacker, dime corner) are `order[position][n]` with a new label.
v2 keeps only the rows where a different man than depth order would pick is a real choice.

## The football truth

**Cited.** Nickel is on the field 61.6–69.2% of snaps and base 20.2–25.0% (2023-24, S2,
`docs/match-engine.md` calibration; `docs/reference/calibration-sources.md`). Player-snaps
per team-game by group are banded for all seven groups (same source) — these are the
guardrail every item must stay inside. Eleven personnel is 62.3–71.9% of offensive snaps.
The engine currently measures nickel 54% / base 30% / dime 12%
(`docs/audit-is-this-football.md`), below band, which means the projection would
under-promise until that is retuned.

**Cited, supporting.** The defence reads formation, personnel, motion and tendency and
never the call (decision 42) — item 3 is that decision applied to coverage assignment.
Development follows role and playing time (decision 21) — this brief is that lever.

**Unverified.** That the slot and the boundary reward different traits is true of the
sport and **uncited anywhere in this repo** — `docs/reference/` has nothing on it and
neither does the `football-domain` skill. Item 2 rests on it. Also unverified: any effect
size for how much separation an alignment is worth. I invented no number and the brief
proposes none.

**Unsourced, and worth the designer knowing.** `RotationProfile.shares(for:)` — the
75/62/44/19 curve — carries no citation in `docs/reference/`. The audit's own words: *"a
rotation curve written for a substitution system that did not exist."*

## Systems touched

Read, not run — **no Swift toolchain in this session**.

| Change | File | Layer |
|---|---|---|
| Back by concept family | `FMSimulation/PlayCaller.swift`, `Lineup.onField(_:concept:situation:)` | caller |
| Alignment-dependent rating in the coverage contest | `FMSimulation/CrudeResolver.swift:428-439` (`let route = rating(.routeRunning, …)` — one key for every receiver today) | resolver |
| Travel the cover man | `Lineup.coverageDefenders` ordering becomes a caller decision, not a fixed slot order | caller |
| Roles on the chart | `FMCore/DepthChart.swift`, `SlotLayout.offense/defense`, `Lineup.fill` | rules + seam |
| Charts generated with roles | `FMGeneration/RosterGenerator.swift:229` — **moves `WorldChecksum.swift:184`; every golden world regenerates** | generation |
| The projection | new query in `FMAnalysis` | analysis |
| The screen | M4 depth chart | UI |

**Unchanged, deliberately:** `PersonnelGroup`, `DefensivePackage`, `DefensiveCall`. The
caller stays the only decider of who is on the field — `GameSimulator.swift:291-301`
orders concept → offensive personnel → defensive package, and `Lineup.onField` is handed
the concept, so every role binding is a pure function of decisions already made. One
decider, one explanation chain.

**The seam holds.** ADR-0013 says the seam is `Lineup.fill`, not the tick loop; M5 is
unaffected by item 4.

## What the record must carry

Checked against `docs/play-record.md`. **Nothing is missing** — the rare case.

| Fact | Status |
|---|---|
| Personnel grouping and defensive package, per play | **present** — `Situation.personnel` |
| Who was on the field | **present** — `onField`, 22 roster indices in slot order (#21) |
| Where a man lined up | **derivable** — slot index plus the grouping reproduce the alignment; the slot *is* the alignment |
| Snaps per player | **present** — `snapCounts(rosters:)` |
| Package/concept mix for the projection | **derivable** — a query over `Situation.personnel` and `Calls.offense.concept` |
| Who covered whom, and by how much | **present** — `.coverageAssignment(defender, receiver, technique, separationCm)` |

That last row is why this shape is right: *"you moved him inside and they travelled
Okonkwo with him anyway, and his separation went 140cm → 85cm"* is answerable from the
stream on day one, with no new fact. The interrogation hook lands on this feature for
free.

## The fun test

A draft, with a control. Give a playtester a board carrying a 78-overall receiving back
and an 84-overall early-down back, with a 90-overall starter already rostered. **The
question:** which do you take, and why? **The thing they do:** play the season, check him
in week 8. **The number:** his snap count, against what they said they expected.

**Passes** if a tester takes the 78 on purpose, says *"he'll play third downs"*
beforehand, and finds it true. **Fails** if they take the 84 because the number is bigger,
or take the 78 and he plays 40 snaps anyway.

**Exploit check, same session:** if every tester puts their best receiver in the slot,
items 2 and 3 failed. Three testers and a survey question, no instrumentation.

**Correctness floor, not a fun test:** the seven `snaps.*` bands stay green through all
four items, or something broke.

## Cost and home

**Item 1 — small.** Caller plus `Lineup.fill`. Regenerates game goldens, **not**
`WorldChecksum`. Could be an issue on the current audit backlog; no dependency beyond the
baseline caller.

**Items 2+3+4 — large, one landing, M3.5.** Item 4 needs M3.5's role rekeying, which needs
M3's season loop. Regenerates every golden world and moves passing and coverage harness
rows; each needs a measured noise floor, and the M3.5 brief should say which rows it
expects to move before the work starts.

**The trade the designer must make consciously:** items 2 and 3 modify the crude resolver,
which M5 replaces. That is code with a known expiry of one milestone. The case for paying
it: M4 is the first playable build, and shipping it with a dominant strategy poisons a
milestone of playtest data. The case against: do items 2 and 3 at M5 instead, and hold
item 4 with them — which means the roster screen at M4 cannot assign receiver alignments.

## The cut

**Item 1 alone.** The passing-down back, and nothing about receivers. It is the owner's
stated motivation in one sentence, it keeps the moment exactly (draft day, week 8, the
snap count), it touches two files, it regenerates no world golden, and it creates no
exploit because nobody can move a receiver anywhere. Recorded as the template's required
cut — **the brief recommends all four**, not this.

## Contradictions

Searched `design-decisions.md`, all fourteen ADRs, the roadmap, the parking lot and
`briefs/` for *rotation, snap share, substitution, personnel, package, nickel, depth
chart, playing time, snap count, role, alignment, slot*.

- **Decision 177 is amended, not contradicted.** It says every position but the
  starter-only ones "splits its snaps against the curve." This brief keeps that for
  **attrition** positions (edge, defensive tackle, back — the sport rotates these by
  fatigue) and replaces it with role assignment for **situational** ones. 177 earns an
  `Amended` note. **The load-bearing warning:** the engine's third edge plays ~47% of
  snaps today *because of* that curve, and there are exactly two edges in every
  `SlotLayout` package. If M3.5's rekeying drops the attrition draw, the third edge goes
  to zero and the project ships the Madden bug this session started out to avoid. That
  sentence belongs in the M3.5 issue.
- **ADR-0013** — this brief specifies its first M3.5 bullet rather than competing with it.
  Its "no unfamiliarity cost" clause is what makes mid-season reassignment free and
  instant, so the projection is the only friction on the decision. Deliberate; say it out
  loud rather than let playtest find it.
- **ADR-0012** — tension, not contradiction: items 2 and 3 invest in a resolver the seam
  exists to replace. Named above as the designer's call.
- **Decision 42** — item 3 is supported by it. One shortfall recorded: `PersonnelGroup`
  counts positions, so swapping in the receiving back leaks no tell the defence can read.
  Real football charges for that; this engine does not. Its home is M2 tendencies.
- **Decision 137** — item 3 is caller behaviour, adding no field to `DefensiveCall`, so
  the composed-call decision stands.
- **Parking lot** — no entry on rotation, roles or substitution. Nothing to promote or
  contradict.
- **Briefs** — none exist but the template, so no prior brief to conflict with.

## Open questions

| Question | Session's recommendation | Owner said |
|---|---|---|
| Assign a man to a situation, or set a number? | Situation; reject the share dial | Situation. "I'm not thinking 'give him X snaps'" |
| A separate `when → then` usage tier? | Recommended it at rung 1 | Rejected — the role name carries the situation; some of it belongs in gameplan |
| Is a slot corner a different job, needing role-relative ratings? | Same job for now; role-relative is unfalsifiable before M5 | Same job for now |
| How big is the role list? | Six, derived from where `SlotLayout` fields different counts | Small — then correctly cut four of the six as depth order in disguise |
| Is "best receiver in the slot" an acceptable crude-engine artifact? | No; items 2 and 3 are the price of item 4 | "I do think it would suck if the answer is always best receiver in the slot" |
| Scope: all four, or item 1 now? | Sequenced 1 now, 2+3+4 together | All four |

## What was not checked

- **Nothing was compiled or run.** `command -v swift` returns nothing in this environment;
  every engine claim is from reading source, and no harness row was measured.
- **The realised-share table shown during the session** (edge 75/62/44/19 nominal →
  69/62/47/22 realised) is a standalone Python Monte Carlo of the draw in `Lineup.fill` at
  a **fixed slot count**, not the harness and not the real package mix. Directionally
  right — the draw compresses toward equality — and wrong in magnitude, especially for
  cornerback, where slot count varies by package. **Nobody has measured the real realised
  curve**, and the claim that per-player shares diverge from the table is therefore
  unproven.
  > **The verdict tightens this for edge.** Every `SlotLayout` package fields exactly two
  > edges, so the slot count does not vary and the figure is exact rather than
  > approximate: 68.9 / 61.6 / 47.4 / 22.1. The caveat stands for cornerback. See
  > [*What the designer checked*](#what-the-designer-checked).
- **No harness row was predicted for any of the four items.** Item 2 will move passing
  rows and item 3 coverage rows; by how much is unknown and no noise floor was measured.
- **Not read:** `FMAnalysis` or `FMNarrative` (neither exists in the form the projection
  needs), `SchemeFit`, the traits system, or `docs/development.md` beyond its Role line —
  so how role assignment feeds development is assumed from ADR-0013 and decision 21, not
  verified.
- **Not checked:** whether `RosterGenerator` produces rosters with enough bodies at each
  role, nor what the legality checker M3.5 builds would say about any of these alignments.
- **The AI half is untouched.** ADR-0013 makes it non-optional that the other thirty-one
  teams can do this. No mechanism was proposed for an AI coach to assign roles, and its
  open question ("how does an AI identify a move worth making?") is still open and still
  scheduled at M3.5.

---

## The three things to push back on hardest

1. **Items 2 and 3 are throwaway work with a one-milestone expiry, and the brief still
   recommends them.** ADR-0012 exists precisely so the crude resolver can be discarded. If
   the designer decides M4 can ship with the slot exploit and a note, the whole receiver
   half moves to M5 and this brief shrinks to item 1 plus a paragraph. That is a defensible
   call and the session did not make it.
2. **The unverified football claim is load-bearing, and it is the only one.** Item 2 rests
   entirely on "the slot and the boundary reward different traits," which nothing in
   `docs/reference/` says. Rule 10 says a claim about the sport cites a rule number or a
   real-league season and source. This one cites neither. If the designer cannot source
   it, item 2 should not be built and items 3 and 4 fall with it.
3. **The role list shrank from six to two under pressure, and may shrink again.** The
   owner correctly found that four of six were depth order relabelled. The two survivors —
   passing-down back and receiver alignment — survive on different grounds, and only the
   first is certain. If receiver alignment also proves to be depth order with extra steps
   once someone reads `Lineup.fill` harder than this session did, this brief is item 1,
   and item 1 is small.

## AFK questions — for the designer, by reading

- **Cite or refute:** do the slot and the boundary reward different traits, and is there a
  public season-level source for it? `docs/reference/` needs the line either way.
- **Cite:** free substitution between downs. `docs/reference/playing-rules.md` covers Rule
  5 with **5-1-1 alone**; the substitution articles are not written up, and every item
  here assumes them.
- **Read and rule:** does `RotationProfile`'s uncited curve need a source, a retune issue,
  or an explicit "unsourced by design" note? The audit already called it a curve written
  for a system that did not exist.
- **Check the tree:** does `RosterGenerator` produce enough bodies per role, and does
  M3.5's legality checker permit these alignments? Not looked at.
- **Decide:** whether decision 177 takes an `Amended` note now or when M3.5's issue lands
  — and either way, whether the third-edge warning goes in the decision or only in the
  issue.

---

# Designer's verdict — 2026-09-15

`main` at `63f6430`. **Read, not run** — `command -v swift` returns nothing here, so
nothing below was compiled, no harness row was measured, and no game was printed. Where a
number appears it is **computed** from the draw in `Lineup.fill` by exact enumeration, and
it says so. *Measured*, *read* and *computed* are three different words in this section.

## The verdict

| Item | Verdict | Home |
|---|---|---|
| 1 — the caller distinguishes the back by concept family | **accepted** | M3.5 |
| 2 — alignment-dependent rating in the coverage contest | **parked** | [parking lot](../parking-lot.md), pending a citation |
| 3 — the defence travels its best cover man | **accepted**, and promoted | M3.5, with item 4 |
| 4 — the depth chart assigns men to alignments and roles | **accepted** | M3.5, with item 3 |

The brief is a good one: its football is cited where it can be, it says plainly where it
cannot be, the moment is a real moment, and the record check is honest and correct. Three
findings below change what gets built, and all three make the work **smaller**.

## The bundle does not hold — items 3 and 4 land without item 2

The brief's central structural claim is that items 2, 3 and 4 are one indivisible landing,
because item 4 creates a dominant strategy that only 2 and 3 can counter. The exploit is
real. Its mechanism is not the one the brief names, and once the real mechanism is on the
table the bundle comes apart.

**The exploit is an ordering artifact, not a missing rating model.** Two independent
orderings collide. `Lineup.fill` walks the layout in slot order and draws each slot from
the remaining candidates weighted by snap share, so the first cornerback slot is biased
toward the top of the chart and each later one toward the bottom. `Lineup.coverageDefenders`
then returns corners in ascending *defensive* slot order, and the matchup loop in
`CrudeResolver.swift:430` pairs them against `routeRunners()` by index — receivers in
ascending *offensive* slot order, which `SlotLayout.offense` fills outside-in.

The net, computed by exact enumeration over the draw for nickel with the shipped
cornerback curve `[0.94, 0.88, 0.60, 0.20]` — the mean chart depth of the corner each
receiver draws:

| Receiver | Slot | Covered by | Mean chart depth of that corner |
|---|---|---|---|
| widest | 2 | def. slot 17 | 1.02 |
| middle | 3 | def. slot 18 | 1.15 |
| **inside (the slot)** | **4** | **def. slot 19** | **1.44** |

So the inside receiver already draws a corner four-tenths of a chart place worse than the
widest one does, before anybody assigns anything. That is the whole exploit, and it is
**an artifact of two sort orders, not a claim about the sport**. Computed, not measured:
it assumes chart order tracks coverage rating, which `RosterGenerator.depthChart(from:)`
makes true at generation — the chart is ordered by `overall`, ties on identifier.

Three consequences:

1. **Item 3 is the counter, and it counters this on its own.** Making
   `coverageDefenders` ordering a caller decision is precisely the fix for a coverage
   assignment that falls out of a slot sort. It needs nothing from item 2.
2. **Item 2 is neither necessary nor sufficient here.** Rewarding different rating keys by
   alignment does not touch which corner the inside receiver draws. It is a separate,
   football-motivated idea that happens to have been bundled with the fix.
3. **The brief's own Systems-touched table already says item 3 is not resolver work.** It
   files item 3 under `Lineup.coverageDefenders`, layer *caller*, and only item 2 under
   `CrudeResolver.swift`, layer *resolver*. The paragraph headed *the trade the designer
   must make consciously* then says "items 2 and 3 modify the crude resolver", which
   contradicts the table two sections above it. The table is right.

**So the designer's hard trade mostly evaporates.** The brief asks me to choose between
paying for throwaway resolver work and shipping M4 with an exploit. I am choosing neither.
Item 3 is caller state — *which defender travels with which receiver* is a decision the
spatial resolver needs too, so the decision and its plumbing survive M5 and only the crude
resolver's way of consuming the ordering is thrown away. Item 2 is the genuinely
throwaway part, and it is the one with the uncited premise. Parking it costs the design
nothing it can currently justify.

## Item 2 parks, and rule 10 is why

Item 2 rests entirely on "the slot and the boundary reward different traits." The brief
says, correctly and without being asked, that this is **uncited anywhere in this
repository** — `docs/reference/` has nothing on it and neither does the `football-domain`
skill. CLAUDE.md rule 10 says a claim about the sport cites a rule number and rulebook
season, or a real-league season and its source. This one cites neither, and no effect size
exists for it either. It cannot be built on that.

The brief's own third push-back says so and then recommends it anyway. I am taking the
push-back. Parked, with two triggers, and **the second one probably fires first**: a
sourced line in `docs/reference/`, *or* M5, where the spatial engine derives separation
from geometry and alignment stops needing a rating key at all. If M5 arrives first, item 2
is never built as written, which is the correct outcome for a rating model invented to
stand in for geometry that is one milestone away.

## Item 1 does not go on the audit backlog

The brief offers item 1 as a candidate for the current audit backlog. It is not one. The
process rule is that an idea arriving mid-milestone does not enter that milestone unless it
is a football defect, and item 1 is not a defect: nothing measures a passing-down back's
share, the `row:snaps.backfield` band is a position-group aggregate that stays green either
way, and no cited band moves. It is a feature, it is a good one, and its home is M3.5 with
the rest. It keeps its independence there — it regenerates game goldens and not
`WorldChecksum`, so it can land first within the milestone.

## What the designer checked

**Read and confirmed.** Nickel 61.6–69.2%, base 20.2–25.0% and eleven personnel 62.3–71.9%
are in the calibration table (`docs/match-engine.md`, S2, 2023-24) exactly as the brief
cites them. The engine's measured nickel 54% / base 30% / dime 12% is
`docs/audit-is-this-football.md`. The seven `snaps.*` bands exist. Every row of the brief's
*What the record must carry* table is correct: `onField`, `snapCounts(rosters:)`,
`Situation.personnel` and `.coverageAssignment(defender, receiver, technique, separationCm)`
are all on the record contract in `docs/play-record.md` today.

**Computed, not measured.** The realised edge curve, by exact enumeration over the two-slot
weighted draw in `Lineup.fill` against the shipped `[0.75, 0.62, 0.44, 0.19]`:
**68.9 / 61.6 / 47.4 / 22.1**. This confirms the brief's third-edge figure of ~47% and
**upgrades its own caveat**: the brief calls its realised table "directionally right and
wrong in magnitude", but every `SlotLayout` package — base, nickel, dime, quarter, prevent,
goal-line — fields exactly two edges, so for edge the slot count does not vary and the
figure is exact. The caveat stands for cornerback, whose slot count runs from one to four
by package. The coverage-ordering table above is computed the same way.

**Found, and the brief did not have it.** The `snaps.*` bands **cannot see the third edge
go to zero.** All seven are position-group aggregates — `row:snaps.frontSeven` is edge,
interior and linebacker together — and two edges stand on the field on every defensive snap
whichever two they are. The brief offers those bands as its correctness floor for all four
items. They are a real floor for the group totals and **no floor at all** for who inside
the group takes the snaps, which is the thing this design moves. The only guard that exists
today is `RotationProfileTests.rotationDepthVaries`, one `#expect(... .edge, depth: 2) > 0.3`
tagged `.unit`, asserting the *table* rather than a realised share — and it lives in a
suite for a type M3.5 rekeys, so it is rewritten by the same change it would have caught.
**The guard disappears exactly when the risk arrives.** That is the strongest argument for
the warning living in a decision, and it is now in one.

**A gap in the record contract, small and cheap now.** The brief marks *where a man lined
up* **derivable** — "the slot *is* the alignment" — and that is true of
`SlotLayout.offense`, which fills the eligibles outside-in. It is **not written down**.
`docs/play-record.md` documents the slot convention only as offence 0–10 / defence 11–21,
for deriving which team a man was on; nothing states that eligible slot 2 is the widest
receiver and slot 4 the inside one. Today that is harmless. Under item 4 the alignment
becomes the thing the player assigns and the thing the projection is about, so the
derivation rule becomes load-bearing and belongs in the contract. Added to M3.5's stream
list as a documentation fact, not a new field — the record stores nothing extra.

**Not checked.** Whether `RosterGenerator` produces enough bodies per role, and what
M3.5's legality checker would say about these alignments: the brief did not look and
neither did I. No harness row is predicted for any item and no noise floor is measured;
that stays the M3.5 issue's job, as the brief says. I did not read `SchemeFit`, the traits
system, or `docs/development.md` beyond its Role line, so how role assignment feeds
development is still assumed from ADR-0013 and decision 21 rather than verified. The AI
half is untouched here too — ADR-0013's open question is still open and still scheduled at
M3.5.

## What this brief settled, and where it now lives

Two things, and neither of them stays in this file.

- **Substitution is two mechanisms, not one** — attrition rotates, situation assigns.
  [Decision 224](../../design-decisions.md#situational-football-and-defense).
- **Decision 177 is amended**, and the amendment carries the third-edge warning with the
  computed numbers and the reason the bands cannot catch it.
  [Decision 177](../../design-decisions.md#the-crude-engine).

The warning is also on the rekeying bullet in
[M3.5's roadmap section](../../roadmap.md#m35--roles-and-a-lineup-you-can-move-players-around-in),
where the author of the M3.5 issue will read it, and it is named in that milestone's cut
line. It does not live only in this brief.

## For the owner

- **ADR-0013 and the roadmap both name a role list this brief disproves.** The ADR's
  Decision section and M3.5's first bullet each give "third-down back, nickel corner, dime
  corner" as the example roles. The owner's own finding in this session — that four of six
  proposed roles were `order[position][n]` relabelled — kills two of those three: the
  nickel corner is the third corner by construction of `SlotLayout.defense`, and the dime
  corner the fourth. **Reported, not resolved.** My recommendation: the ADR's list is
  illustrative rather than load-bearing, so it yields, and it takes a dated amendment note
  when M3.5 opens and the real role list is fixed — not now, when the list would only have
  to be amended twice. The roadmap is mine and is corrected in this pass.
- **Free substitution between downs is uncited**, and every item here assumes it.
  `docs/reference/playing-rules.md` covers Rule 5 with 5-1-1 alone; the substitution
  articles are not written up. Recommendation: it joins the citation backlog (#80) rather
  than becoming its own issue.
- **`RotationProfile`'s curve is still unsourced**, as the audit said. Recommendation:
  leave it unsourced and say so in the decision rather than open a retune — decision 224
  now records that the curve's *shape* is uncited while its *sum* is the invariant that is
  checked, which is the honest description of what it is.
