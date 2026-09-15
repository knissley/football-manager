# The pre-snap exchange: how far from a reactive contest?

**Status: an investigation, not a design doc and not a fix.** It measures one thing — how
much of the sport's pre-snap conversation the engine plays. Every measurement in it was
taken on `79e7a6c3a7313fc915fb0cd615ba03fb42d62477`, and `d95de59` — which added ADR-0014 —
changed no source under `Packages/` or `Tools/`, so they stand. Every claim below names a file and line, a
harness row, or a printed `gamelog` observation. Nothing here changes engine behaviour, and
the proposals at the end are proposals: none of them has been built.

**Why it is its own file.** [`audit-is-this-football.md`](audit-is-this-football.md) is
fifteen findings of twenty to sixty lines each, and this is three hundred. A section that
long would be the document rather than an entry in it, so the audit carries a pointer and
the work lives here. The audit's [S3](audit-is-this-football.md#s3--one-personnel-grouping-one-defensive-package-all-game--fixed)
is this file's direct ancestor: S3 built the substitution, and this asks what the
substitution is allowed to know.

**The constraint every proposal works inside.**
[ADR-0014](adr/0014-decide-from-what-the-decider-can-see.md), accepted 2026-09-15: *the
engine may not let a decision depend on information the real-world decider would not have at
the moment it decides.* Three parts of it are load-bearing here and are applied throughout,
rather than the summary of it:

- **The test is the decider's, not the compiler's**: *at the moment this decision is made,
  would the real decider know this?* A defensive coordinator substituting knows the personnel
  that jogged on, the down, the distance, the yard line and the clock. He does not know the
  call.
- **A drawn value is information.** That the engine has already drawn the concept, and holds
  it where a caller could reach it, does not make it knowable; order of evaluation inside a
  snap is an implementation detail and confers nothing. **§2's inventory applies that test and
  not reachability** — a field a decider would genuinely know, left unread, is a gap; a field
  he would not, left unread, is the boundary working.
- **Where a sourced rate is measured on a population the decider cannot identify, the engine
  draws over the population he can and *reports* the subset.** Any proposal below that would
  introduce a sourced rate takes that shape and says so.

The ADR also records, in its Alternatives, that letting the offence re-check its concept
against the box it sees is **not rejected on principle** — the box is observable, so a check
at the line moves the boundary rather than crossing it — and was set aside only because the
engine does not model it. That is this file's territory and it is P5.

**This file does not reopen ADR-0014.**

**What it does not touch.** How often a defence blitzes is
[#225](https://github.com/knissley/football-manager/issues/225). What a zone blitz is worth
is [#224](https://github.com/knissley/football-manager/issues/224). The slope of yards per
carry against a blocking advantage is
[#227](https://github.com/knissley/football-manager/issues/227). Those are filed, owned and
referenced here, never re-decided.

---

## 1. The sequence, as the code executes it

From the end of one play to the snap of the next, `GameSimulator.step(_:random:tosses:)`
(`Packages/FMSimulation/Sources/FMSimulation/GameSimulator.swift:250`). The order below is
the order the source runs in, read from the source rather than from
[`match-engine.md`](match-engine.md).

| # | Step | Where | Who decides | What it is handed | What it actually reads |
| --- | --- | --- | --- | --- | --- |
| 1 | Coin toss and the two elections | `GameSimulator.swift:267–286` | both captains | `Situation`, `SituationClass` | quarter, possession, score |
| 2 | Timeouts, both benches | `:296–307` | both | `Situation`, `SituationClass`, `PlayContext` | clock, score, timeouts |
| 3 | Two-point decision, when a try is pending | `:319–324` | offence | `Situation`, `SituationClass` | score, quarter |
| 4 | **The offensive concept and tempo** | `:336–339` | offence | `Situation`, `SituationClass`, `PlayContext` | down, distance, ball, clock, score, timeouts |
| 5 | **The offensive grouping** | `:340–342` | offence | the concept from 4, plus `Situation`, `SituationClass` | down-and-distance class, `ballOn`, must-pass, clock-burn |
| 6 | **The defensive package** | `:344–346` | defence | `Situation` **with the grouping now set**, `SituationClass` | `offensePersonnel`, `down`, `distance`, `ballOn`, time, score |
| 7 | The substitution goes on the record | `:353` | — | — | `DecisionKind.substitution` |
| 8 | Free kick or try overrides the package | `:382–386` | the rules | — | — |
| 9 | `situation` and `classified` rebuilt | `:388–389` | — | — | — |
| 10 | **The defensive call** | `:414–415` | defence | `Situation`, `SituationClass`, `PlayContext` | **`SituationClass` only** — see below |
| 11 | The package is stamped onto the call | `:416` | — | — | `state.defensePackage` |
| 12 | Two-minute warning | `:438` | the rules | — | tempo |
| 13 | Play clock, and the timeout that beats it | `:456–468` | offence | `Situation`, `calls`, `PlayContext` | tempo, clock |
| 14 | The twenty-two bodies | `:476–477` | — | `situation` | `offensePersonnel`, `defensePackage` |
| 15 | The snap | `:479–481` | the resolver | `calls`, `onField`, `PlayContext` | see §2 |

**The whole exchange is steps 4, 5, 6 and 10, and only one of them is reactive.** Step 6
reads what step 5 produced. Nothing else on this list reads anything the other side did.

Two things in that table are worth stating flatly, because they are the finding.

**The defensive call is blind to the defence's own substitution.** Step 10 hands
`BaselineCaller.defensiveCall` the full `Situation` and the full `PlayContext`, and the
implementation discards both:

```swift
// PlayCaller.swift:950–955
public func defensiveCall(
    for situation: Situation, classified: SituationClass, context: PlayContext,
    random: inout SplittableRandom
) -> DefensiveCall {
    defensiveCall(for: classified, random: &random)
}
```

The private method it forwards to (`PlayCaller.swift:957–994`) reads
`SituationClass` alone, and `SituationClass` carries four fields —
`downAndDistance`, `field`, `score`, `time` (`SituationClass.swift:24–29`). It holds nothing
about personnel, nothing about the package, nothing about the yard line in yards. So the
coordinator who has just sent his nickel onto the field picks his coverage and his pressure
without knowing he did it.

**The offence is never asked a second question.** There is no step between 6 and 15 that
puts anything back to the offence. No audible, no check, no motion, no re-read. Steps 4 and
5 are settled before the defence has answered, and the answer never travels back.

### The stale carry-over

`state.offensePersonnel` and `state.defensePackage` (`GameState.swift:137–138`) are written
in exactly three places — `GameSimulator.swift:340`, `:345`, and `GameState.chooseTryPlay`
at `GameState.swift:490` — and **never reset**. So the `Situation` built at
`GameSimulator.swift:336` and handed to the *offensive* caller carries the **previous**
snap's grouping and the previous snap's defensive package, across possession changes and
across kickoffs.

**This has no symptom today**, and the reasons are worth writing down because they are the
only thing holding it:

- `BaselineCaller.offensiveCall` reads neither field (the full list of what it reads is in
  §2).
- The harness folds over `isScrimmagePlay` only (`PlayOutcome.swift:65–70`;
  `simharness/main.swift:998–1001`), and a kickoff is not one.
- `gamelog` prints the pairing under the same guard (`gamelog/main.swift:924–928`).

It is a trap rather than a defect: the first caller that reads `situation.defensePackage` in
`offensiveCall` — which is the natural thing to reach for when writing an audible — will
silently be reading last play's defence. Proposal P1 closes it by construction.

---

## 2. What each side could see, and what it reads

### The defence, at step 6 (the package)

Everything on `Situation` is available. What `BaselineCaller.package` reads
(`PlayCaller.swift:285–309`): `situation.offensePersonnel`, `situation.down`,
`situation.distance`, `situation.ballOn`, `classified.time`, `classified.score`,
`classified.isMustPass`. That is a genuine, sourced conditional — `PackageConditional` holds
P(package | grouping, down) from the participation feed — and it is the one place in the
engine where one side answers the other.

### The defence, at step 10 (the call)

Available: the whole `Situation`, including the grouping it just answered and the package it
just chose, plus the whole `PlayContext` including `defenseScheme`. Read: `downAndDistance`,
`field`, `score`, `time`. **Everything else is discarded at the call boundary.**

### The offence, at steps 4 and 5

Available: the whole `Situation` and the whole `PlayContext`. Read, across the entire
`BaselineCaller` offensive half (`PlayCaller.swift:507–946`): `down`, `distance`, `ballOn`,
`clockRemaining`, `scoreDifferential`, `offenseTimeouts`, `defenseTimeouts`, and from the
context `clockIsRunning`, `playClock`, `playClockExpired`, `rules.fieldGoalDistance`,
`rules.playClockAfterAPlay`. It reads neither `offensePersonnel` nor `defensePackage`, and
neither scheme.

### The boundary that already holds, by signature

Before the gaps: **the defensive caller cannot reach the offensive concept at all.** Step 4
stores it in a local (`declared`, `GameSimulator.swift:334, 354`); `PlayCaller.defensiveCall`
takes `Situation`, `SituationClass`, `PlayContext` and a stream (`PlayCaller.swift:24–27`),
and none of the three carries a `PlayConcept`. ADR-0014's first consequence — that a drawn
value is information, and that the engine holding it confers nothing — is satisfied here not
by discipline but because there is no member to read. That is worth recording as a positive
result, and it is the shape P1 proposes for everything else.

### The register of fields that exist and are read by nothing

Measured by grepping `Packages/*/Sources` and `Tools/*/Sources` for each member outside the
file that declares it. `#45`'s filing said `CallVulnerability`, `frontAlignment` and
`disguised` were unread; **that is still true at `79e7a6c`, and the list is longer than
three.**

`play-calling.md` already records the reason for one of them — `CallVulnerability` exists in
`FMCore` and the resolver never asks what a call concedes, because a soft spot cannot honestly
be soft before the spatial engine. Re-checked here and it still holds.

| Member | Declared | Read in `Packages/*/Sources`? | Note |
| --- | --- | --- | --- |
| `DefensiveCall.coverage` | `DefensiveCall.swift:25` | **only as `.isMan`** | `CrudeResolver.swift:447, 465`. Nine coverages, two behaviours. |
| `DefensiveCall.rush` | `:26` | yes | `CrudeResolver.swift:321`; `Penalties.swift:155` |
| `DefensiveCall.runFit` | `:31` | yes | `CrudeResolver.swift:1028–1030`, two of five cases |
| `DefensiveCall.frontAlignment` | `:27` | **no** | read only by `vulnerability`, `:196` |
| `DefensiveCall.package` | `:28` | **no** | overwritten at `GameSimulator.swift:416`; the live value is `situation.defensePackage` |
| `DefensiveCall.disguised` | `:35` | **no** | nothing anywhere reads it |
| `DefensiveCall.vulnerability` | `:190` | **no** | `DefensiveCallTests` only |
| `CallVulnerability` | `:208` | **no** | all seven cases unreachable in the sim |
| `DefensiveCall.isAllOut` | `:171` | **no** | `vulnerability` only |
| `DefensiveCall.concedesUnderneath` | `:177` | **no** | — |
| `DefensiveCall.isTwoMinuteSound` | `:183` | **no** | — |
| `Coverage.deepDefenders` | `:85` | **no** | so prevent, quarters and cover two are one thing |
| `Coverage.isPressureCoverage` | `:97` | **no** | — |
| `FrontAlignment.isDeclared` | `:147` | **no** | `vulnerability` only |
| `OffensiveCall.usedMotion` | `OffensiveCall.swift:33` | **read, never written** | see below |
| `OffensiveCall.tempo` | `:32` | yes | `Penalties.swift:120, 136`; the play clock; the clock rules |
| `PlayContext.offenseScheme` / `.defenseScheme` | `PlayResolver.swift:18–19` | not by any caller | `SchemeFit` reads them elsewhere |

**Whether each is unread because nothing needs it, or because something should.** The test
is ADR-0014's — *would the decider know it at that moment?* — rather than whether the field
can be reached. Every member in the table above is one the decider **would** know: a
coordinator knows his own front, his own coverage's structure, his own package, and whether
he intends to disguise; a quarterback knows whether his offence motioned. None of them is a
boundary case. So every "no" below is a gap, not the rule working.

- `frontAlignment`, `vulnerability`, `CallVulnerability`, `isAllOut`, `concedesUnderneath`,
  `deepDefenders`, `isPressureCoverage`: **something should**, but not yet. These are
  soft-spot vocabulary, and a soft spot cannot honestly be soft without geometry — which is
  [`roadmap.md`](roadmap.md)'s own reason for deferring them to M5, and
  [`play-calling.md`](play-calling.md)'s "Designed, not built". The register is correct; the
  entry is that the register is *long*, and that it caps what any pre-snap proposal can be
  worth (§5).
- `isTwoMinuteSound`: **something should, and cheaply** — it is a property of the call and
  the caller has the clock. Not this issue's; it is a tendency, which is
  [#225](https://github.com/knissley/football-manager/issues/225)'s.
- `DefensiveCall.package`: **nothing needs it**, and it is worse than unread — it is
  actively overwritten (§4).
- `disguised`: **something should**, and it is precisely this issue's. It is inert because
  there is no offensive pre-snap read for a disguise to degrade. P6.
- `usedMotion`: **a defect.** `Penalties.swift:135` adds 0.4 percentage points of procedural
  foul probability when it is true. Every `OffensiveCall` the engine constructs —
  `PlayCaller.swift:512, 515, 518, 520`; `GameSimulator.swift:406, 418, 579`;
  `ScriptedGame.swift:487` — leaves it at its `false` default. **The branch cannot fire in a
  simulated game.** Only `VocabularyCoverageTests.swift:250` ever sets it.

---

## 3. The sport's sequence beside it

**Most of this is coaching practice, not rules.** The rulebook governs *when* substitutions
may happen and *what the formation must look like at the snap*; it says almost nothing about
who may look at whom. Where an article genuinely governs a step it is cited below; where none
does, that is stated rather than papered over with a nearby number. The edition read is the
**2026** book (`FM_RULEBOOK_TEXT`), which differs from the 2025 book this project targets in
exactly four articles — 6-1-3, 6-1-5, 6-1-6 and 19-2 — none of which appears here.

| # | The sport | Governed by a rule? | The engine |
| --- | --- | --- | --- |
| 1 | The offence decides a play | no — coaching | step 4 |
| 2 | The offence substitutes; no more than eleven in the huddle | **5-2-1**, **5-2-3** | step 5 |
| 3 | **The defence is given the chance to match**, before the two-minute warning of either half; the ball is held until it has had reasonable time; a play clock that expires while it substitutes is on the offence | **5-2-10**, and **5-2-9** after a timeout or a change of possession; **5-2-10-c** extends it to a fourth-down punt all game; **5-2-10-d** the delay | step 6 — but see below |
| 4 | Using substitutions to fool the other side is unsportsmanlike | **5-2-11** (and 12-3-1-k) | not modelled; nothing simulates one |
| 5 | Both sides line up; the offence must be legally formed at the snap | **7-5-1** | not modelled — there are no formations, only groupings |
| 6 | The defence shows a look, which may not be the one it intends | **no rule** — nothing in the book restricts what a defence shows or when it rotates | `disguised` exists and is read by nothing |
| 7 | The quarterback reads the look | **no rule** | does not exist |
| 8 | He may change the call | **no rule** | does not exist |
| 9 | Motion or a shift asks a question, and the answer is information | **7-4-7** permits shifting and repeated motion; **7-4-8** allows one backfield man moving at the snap, not toward the line; **7-4-6** requires the one-second set after the last shift | `usedMotion` exists, is read by `Penalties`, and is never set |
| 10 | The defence may rotate after the motion or after the eyes | **no rule** | does not exist |
| 11 | The snap, inside the play clock | **4-6-1**, **4-6-2** | steps 12–15 |

**Three observations from that table.**

**First, the engine's one reactive step is the one the rulebook actually protects.**
5-2-10 exists precisely so that personnel is a public declaration the defence gets to answer.
The engine models that and models it from the source's own conditional. That is not a small
thing and the report should not bury it: *the step the book cares about is the step that
works.*

**Second, 5-2-10's protection lapses after the two-minute warning of either half, and the
engine never notices.** The article conditions the matching opportunity on the substitution
being made before the warning. After it, an offence can line up and snap without the defence
having completed its answer. The engine asks `caller.package(for:)` on every scrimmage snap
identically — `GameSimulator.swift:344–346` has no tempo term, no two-minute term, and the
offence's `Tempo` is not passed to it at all. A hurry-up offence inside two minutes gets the
same matched defence as a huddled one on first and ten in the first quarter. This is the one
place in the whole pre-snap picture where a **rule** is unmodelled rather than a coaching
practice.

**Third, everything from step 6 to step 10 of the sport's column is coaching, and none of it
is in the book.** There is no article about disguise, no article about an audible, no article
about a post-motion rotation. Anyone writing these later should not go looking for one; the
reference for them is [`calibration-sources.md`](reference/calibration-sources.md)'s
"what a test claims about a game and nothing sources" register, the way `ReadProgression`
already is.

---

## 4. The symptom: what a fan sees today

**Yes, there is a fan-visible symptom, and it is not the one the issue expected.** It is not
the missing audible. It is that **the defence's call and the defence's personnel are decided
independently and then declared to be the same eleven.**

`GameSimulator.swift:416` is the mechanism:

```swift
var defense = caller.defensiveCall(for: situation, classified: classified, ...)
defense.package = state.defensePackage
```

The call arrives carrying a package its own preset chose — `preventShell` names `.prevent`,
`goalLineStop` names `.goalLine`, `dimeRush` names `.dime`
(`DefensiveCall.swift:245–253`) — and the substitution's answer is written over the top of
it. The comment above it (`:373–381`) argues, correctly, that the substitution should win.
What it does not do is send the rest of the call back to be re-drawn against the bodies that
are actually out there.

### Measured

Four printed games, `gamelog --seed 7` with `--home/--away` at `3/11`, `5/9`, `1/7` and
`2/14`; **522 scrimmage snaps**, each printing `<grouping> vs <package>, <coverage>`.

| The call | Snaps | Played by the package its own preset names |
| --- | --- | --- |
| `preventShell` (printed *prevent*) | 19 | **0** — 16 nickel, 2 base, 1 dime |
| `goalLineStop` (printed *run blitz*) | 62 | **2** — 28 nickel, 25 base, 7 dime |
| `dimeRush` (printed *quarters*) | 7 | **0** — 4 nickel, 3 base |

And the line that says it best: **the prevent package reached the field once in four games,
and the call on it was man free.** Likewise the goal-line package was out there four times,
and on two of those the call was man free rather than the goal-line stop.

Not all eighty-eight of those are wrong football. A cover-3 shell from nickel personnel is
ordinary; so is a run blitz from a four-back front on third and one. The subset a fan would
actually flinch at is narrower and still real:

- **A goal-line sell-out from dime — 7 snaps in four games.** `goalLineStop` carries
  `frontAlignment: .bear` and `runFit: .sellOut`, and `runFit == .sellOut` is worth `0.3` of
  block-contest edge to the defence (`CrudeResolver.swift:1028–1030`). The engine hands that
  edge to a personnel group with five men in the box.
- **A prevent shell from base — 2 snaps.** Three rushers and a four-deep zone, played by four
  defensive backs.
- **A six-defensive-back quarters call from base — 3 snaps.**

About **three flinch-worthy printed lines a game**, out of roughly 130.

### The graded harness: nothing demonstrably moves

`simharness --games 400 --seed 7` at `79e7a6c`. No graded row is demonstrably a symptom of
the pre-snap gap, and the honest statement is that the gap is real and, on the rows, invisible.

The nearest candidates, and why each is somebody else's:

- `yards per carry, outnumbered by one` **3.1** against 3.9–5.1, and `outnumbering by one`
  **5.2** against 4.0–4.9. The engine's count advantage is worth about 2.1 yards where the
  sport's is worth about half a yard. That is
  [#227](https://github.com/knissley/football-manager/issues/227), explicitly, and the
  mechanism there is the block-count slope rather than the exchange. It is also **not**
  contaminated by the incoherence above: both rows are read on first-and-ten designed
  carries, and `goalLineStop` is drawn only on `isShortYardage`
  (`SituationClass.swift:108`), which first and ten never is.
- `pressure rate per dropback` **26.6%** against 27.8–32.3, `sack rate per dropback` **3.5**
  against 6.1–7.2, `pressures ending in a sack` **13.4%** against 20.0–24.2. A defence that
  never pressures what it has diagnosed would show here — but so would half a dozen other
  things, and how often the defence blitzes at all is
  [#225](https://github.com/knissley/football-manager/issues/225)'s and what a zone blitz
  collects is [#224](https://github.com/knissley/football-manager/issues/224)'s. Attributing
  these rows to the pre-snap exchange would be a guess.
- `runs called, third and 1 to 3` **93.7%** against 44.5–51.7. An offensive tendency, and
  #225's.

**There is no row that measures the exchange itself.** The harness prints the joint —
`grouping against package, first-and-ten designed carries` — ungraded and for reading, and
that is the only thing in the whole output that would notice if step 6 stopped reading step
5. Nothing at all would notice if step 10 started reading step 6.

---

## 5. What it costs to close any of this

The prices below apply to every proposal in §6 and are stated once.

**A new pre-snap decision is a draw, and a draw re-streams the game.** Every play draws from
its own stream split by index (`GameSimulator.swift:240`), so a change *within* a play does
not shift later plays — but it shifts everything after it *in that play*, which is the whole
play. Adding or moving one `random.next` in the pre-snap block changes every subsequent draw
on that snap and therefore the snap's outcome, the clock, the next situation, and the rest of
the game. [#97](https://github.com/knissley/football-manager/issues/97) is the worked example:
one changed draw resampled 205 of 400 games at one seed. **Every golden regenerates and every
harness row resamples.** A branch that does this must carry a before-and-after at seeds 7 and
11 and read each moved row against its measured noise floor.

**Changing which branch an existing draw lands in costs the same.** Filtering a menu before
drawing from it is not cheaper than adding a draw; the integer comes out the same and lands
somewhere else.

**Purity and the tick loop.** `FMSimulation` imports no platform API and does no I/O
(rule 1, ADR-0004); the tick loop allocates nothing (rule 5, ADR-0006). A pre-snap
negotiation is flat structs on the stack, drawn once before the snap, never per tick. None of
the proposals below needs a dictionary or a string.

**A caller decision must reach the decision log.** Rule 4 and ADR-0007: a substitution is
already a `DecisionPoint` (`GameSimulator.swift:353`,
`DecisionKind.substitution` at `PlayRecord.swift:246`). A new kind costs: an enum case with a
doc comment that *states its contract*, a factory (`PlayRecord.swift:430–654`), an accessor
for whatever it packs into `detail`, and an arm in
`DecisionContractTests.throughItsFactory` — which is a compile error if omitted, by design —
plus the corpus must actually produce it, since the suite asserts
`seen == Set(DecisionKind.allCases)` (`DecisionContractTests.swift:146`).

**Record bytes are not free either.** Changing a value recorded on `Situation` — even one no
draw depends on — changes `PlayRecord` bytes and therefore any golden that hashes a record,
while leaving the harness rows alone. Do not assume; measure.

---

## 6. Proposals

Seven, in the order they should be considered. **Nothing here is built.** Each carries what
it would decide, where it sits against ADR-0014, and what it costs. P6 is the recommendation
over the whole set.

### P1 — ADR: give each pre-snap question a narrowed view

**Finding.** The one thing ADR-0014 names explicitly — the play call — is already out of the
defence's reach, and by signature rather than by discipline (§2). **Nothing else is.**
`defensiveCall` is handed the whole `Situation` and the whole `PlayContext`
(`PlayCaller.swift:24–27`), and `offensiveCall` is handed a `Situation` whose
`defensePackage` holds the *previous* snap's answer (§1). So the boundary holds today by
accident of what `PlayCaller`'s signatures happen to carry, and the next member added to
`Situation` or `PlayContext` extends every caller's reach without anyone deciding to. The
agent who writes an audible will reach for `situation.defensePackage` and read stale data
that looks live.

**Plan.** An ADR proposing that each pre-snap question take a view built at the moment it is
asked — `PreSnapView.forOffense` and `PreSnapView.forDefense` — carrying only what that
decider may have then. The defence's view carries the declared grouping, down, distance,
yard line, clock, score and its own package; it has no member for the offensive call. The
offence's view has no member for the defensive package until a step exists that legitimately
gives it one. Plus one `.contract` test that the views are total and disjoint from the call.

**Against ADR-0014.** This *is* ADR-0014, made structural — it turns "no member to read" from
a property of today's signatures into a decision the types record. The ADR says explicitly
that it is not an audit and asserts nothing about what current decisions read; this is the
seam that would make a future sweep unnecessary.

**Cost.** No new draw, so **no stream shift and no golden moves** — a signature change and
two value types in `FMCore`/`FMSimulation`, plus updating `ScriptedGame` and the caller
tests. `Targets.swift` untouched. The one thing to measure rather than assume: whether
removing the stale fields from the offence's view changes any recorded `Situation` byte (it
should not — the fields stay on `Situation`; only the caller's view narrows).

**Milestone.** M1. It is the cheapest proposal here and it is what makes the rest safe.

---

### P2 — Issue: the defensive call is drawn blind to the defence's own substitution

**Finding.** Step 6 draws the package from the grouping; step 10 draws the call from
`SituationClass` alone and step 11 stamps the package over whatever the call named
(`GameSimulator.swift:414–416`). Measured over 522 printed scrimmage snaps (§4): the prevent
shell was called 19 times and played by the prevent package 0 times; the goal-line stop 62
times and played by its own eleven twice; `dimeRush` 7 times and never from dime. Three
printed lines a game contradict themselves outright, and one of them hands a sell-out run
front's block-contest edge to a five-man box.

**Plan.** Condition step 10 on the package already on the field. Two shapes, and the first is
recommended:

1. **Filter the menu.** Keep #218's ordering. Before drawing, restrict the preset list to
   calls the package on the field can execute — no goal-line sell-out from dime, no prevent
   shell without the prevent eleven — and draw from what is left. Cheap, local to
   `BaselineCaller.defensiveCall`, and it makes `DefensiveCall.package` meaningful again
   instead of overwritten.
2. **Invert the order**: draw the call first and let the package follow it. Rejected: it
   undoes #218, and it makes the package a function of the call rather than an answer to the
   grouping, which is exactly the joint that #218 replaced with the source's conditional.

**Against ADR-0014.** Inside it, and worth being explicit: the defence conditions on *its own
personnel*, the declared offensive grouping, the down, the distance, the yard line and the
clock. It is told nothing about the concept. A real coordinator knows which eleven he just
sent out; withholding that is not a boundary, it is an omission.

**Cost.** **Large.** It changes which branch an existing draw lands in, so every golden
regenerates and every harness row resamples at both seeds (§5). No new `DecisionKind`. Does
not need `Targets.swift`. Whoever takes it must paste every moved row with a mechanism and a
named noise floor, and must expect the pressure and sack rows to move — which is where it
collides with #224 and #225, so it should land **after** both, not before. It is also the
natural partner of P5, and the two should be sequenced rather than merged: one is the defence
learning to look at itself, the other is the offence learning to look at the defence.

**Milestone.** M1, but last in its wave.

---

### P3 — Issue: `usedMotion` is read and never written

**Finding.** `Penalties.swift:135` reads it; no `OffensiveCall` constructed anywhere in
`Packages/*/Sources` sets it. The illegal-motion and illegal-shift share of the procedural
foul draw is therefore a constant. 7-4-7 and 7-4-8 permit motion and shifts; nothing requires
them, so this is a modelling gap rather than a rules one.

**Plan.** Do **not** file this as a one-line fix. Deciding when an offence motions is a new
pre-snap decision — which concepts motion, how often, and whether tempo suppresses it — and
that is a draw. The honest shapes are: (a) fold it into whatever wave opens the pre-snap
negotiation, so the stream moves once; or (b) if nothing is going to open that soon, delete
the dead term from `Penalties` and record in the register that motion is unmodelled, so the
next reader is not misled into thinking it is wired.

**Against ADR-0014.** Motion is a public act. A defence that reacts to it is reading the
field, not the call. Inside the boundary, and one of the few places where giving the defence
*more* information is unambiguously correct.

**Cost.** (a) is a draw and moves everything (§5). (b) removes a branch that never fires:
**no draw moves, no golden moves** — worth confirming with a run rather than assuming, since
`max(0.001, procedural)` means the arithmetic is reachable only through the term. Prefer (a)
if the wave is close.

---

### P4 — Issue: a defence may not get to match after the two-minute warning

**Finding.** 5-2-10 conditions the defence's matching opportunity on the offence substituting
*before* the two-minute warning of either half. The engine asks `caller.package(for:)`
identically on every scrimmage snap (`GameSimulator.swift:344–346`) with no tempo term and no
two-minute term, and the offence's `Tempo` is not even passed to it. **This is the only place
in the pre-snap picture where a rule is unmodelled rather than a coaching habit**, which
makes it the one item here that can be asserted from the book rather than from taste.

**Plan.** Under `Tempo.hurryUp` inside two minutes, the defence answers from what it already
had on the field rather than from the conditional — or answers from a degraded conditional.
Which of the two is a design question the owner should settle; the shape of the finding does
not depend on it.

**Against ADR-0014.** Inside it. It *removes* information from the defence in a situation
where the rules remove it, which is the boundary working in the direction it was written for.

**Cost.** Changes what step 6 draws in a narrow slice of snaps, so the stream shifts on those
snaps and the game diverges after them: **every golden regenerates, the rows resample**, but
the affected population is small and a before-and-after should show most rows inside their
floors. Needs a `.football` test written from 5-2-10 and committed red. No `Targets.swift`.

**Milestone.** M1. It is small, it is cited, and it is independent of P2.

---

### P5 — Issue: let the offence check its concept against the box it sees

**The most sanctioned direction here, and the ADR says so.**
[ADR-0014](adr/0014-decide-from-what-the-decider-can-see.md)'s Alternatives record this one
as *not rejected on principle*: the box is observable, so a check at the line **moves the
boundary rather than crossing it**, and it is plausibly the mechanism that produces the
carries-versus-dropbacks spread in the first place. It was set aside only because the engine
does not model it — one call per snap, no check, no audible — and the ADR says that if it is
built, the carry rate becomes reachable honestly.

**Finding.** §1, step by step: the concept is settled at `GameSimulator.swift:337–339` and
nothing puts it back to the offence after the defence has answered at `:345`. A quarterback
who has drawn an inside run and is looking at a four-back front with an extra hat in the box
runs it anyway, every time. The engine has the two facts it would need — `state.defensePackage`
is set by then, and `Lineup.boxCount` (`Lineup.swift:224–226`) already counts the box — and no
step that consults them.

**Plan.** A third pre-snap question, asked of the offence between steps 6 and 10: given the
concept already called and the package now on the field, does the offence keep it or check
out of it? Crude is correct here (breadth before depth): a check between run and pass
families, bounded by tempo — an offence in `hurryUp` has no time to check — and by the
concept (a kneel, a spike and a kick do not check). The result goes on the record as a
decision, not as a silently different call.

**Against ADR-0014.** Inside it, and the ADR names it as such. The offence reads the *box* —
who is on the field and how many are near the line — which is physically observable. It must
not read the defensive **call**: today's `DefensiveCall` does not exist yet at that point in
the step (it is drawn at `:414`), and any implementation must keep that ordering rather than
move the call earlier for convenience. **That ordering is the whole safety property of this
proposal** and a reviewer should check it first.

**The shape any rate here must take.** ADR-0014's second consequence binds: the offence's
check may be drawn over a population the *offence* can identify at the line — the box it is
looking at — and the run/pass mixture that falls out of it in any post-hoc population is
**reported, not targeted**. Concretely, if this is built, the sport's 18.8 / 18.3% of eleven
personnel's first-and-ten designed carries meeting a four-back front (ADR-0014's re-derived
table, 2023-24) becomes something the engine can approach as an *emergent* figure; it must
not become a `Targets.swift` band that the check is then tuned against. That would be the
same error one layer along.

**Cost.** **Large, and it is a new draw**: every golden regenerates, every harness row
resamples at both seeds (§5). A new `DecisionKind` — call it the check — with a doc comment
stating its contract, a factory, an accessor and an arm in
`DecisionContractTests.throughItsFactory`, plus the corpus must produce it or
`seen == Set(DecisionKind.allCases)` fails. A `.football` test cannot cite an article,
because no article governs an audible; it is a scenario test, registered where
`ReadProgression` is registered. No `Targets.swift` edit, by the paragraph above.

**Milestone.** The mechanism is M1-shaped — one bounded question, flat structs, one draw —
but its *value* is capped by P6 and it reshapes the run game, so it should not land in the
same wave as [#227](https://github.com/knissley/football-manager/issues/227). Recommend:
open it, hold it behind #227 and #225.

---

### P6 — Recommendation: do not build the defence a brain the resolver cannot hear

**Finding.** `Coverage` has nine cases; the resolver reads it through `.isMan` and nothing
else (`CrudeResolver.swift:447, 465`). Cover two, cover three, quarters, match quarters and
prevent are one defence to the engine. `deepDefenders` is never read. `frontAlignment`,
`disguised`, `vulnerability`, `isAllOut`, `concedesUnderneath` and `isTwoMinuteSound` are read
by nothing. The register in §2 is the shape of the ceiling.

**This is not a proposal to fix it** — it is a proposal about ordering. Every pre-snap
improvement is bounded by what the post-snap engine can tell apart. Making the defence choose
its coverage more cleverly buys nothing while the resolver's only question about a coverage is
whether it is man. [#39](https://github.com/knissley/football-manager/issues/39) is in flight
filling `coverageAssignment`'s technique vocabulary — `press`, `zoneFlat`, `bracket`, `spy` —
which is the first step of the other half, and the coverage picture will be richer by the time
anything here is dispatched.

**Recommendation, as a whole.** Take **P1** and **P4** now: both are small, neither moves a
graded row's mechanism, and P1 is what makes every later proposal safe to write. Hold **P2**
and **P5** until after #224, #225, #39 and #227 — each of those moves the goldens once, and
these two should not each move them again. Take **P3(b)** if no pre-snap wave is close, P3(a)
if one is. Do not open disguise, or a post-motion rotation, until a coverage is more than a
boolean; [`roadmap.md`](roadmap.md) already says M5 for the geometry and this is agreement
with it, measured.

**Against ADR-0014.** Nothing to check — it proposes no behaviour.

**Cost.** Free.

---

### P7 — The design questions this cannot answer, for the design tracker

Two of them are not defects and belong to
[#183](https://github.com/knissley/football-manager/issues/183) rather than to #1. Each is
stated as a question, with the ADR-0014 line already drawn, so the owner can judge it without
re-deriving any of this.

1. **What is a disguise worth, and to whom?** `disguised` degrades the offence's read at a
   cost to the defence. With no offensive read, it has nothing to degrade, so today it can
   only be a flat penalty on the defence — which is worse than leaving it inert. **ADR-0014:**
   symmetrical and safe; the offence never sees the call either way, and a disguise operates
   on what it *does* see. **Cost:** meaningless before P5, since P5's box read is the thing a
   disguise would degrade. Sequence it after.
2. **Should `CallVulnerability` grade a play before the geometry exists?** It is the one piece
   of vocabulary already complete and reachable in one line from the resolver, and the
   analysis layer wants it more than the sim does — a completion underneath against prevent is
   the defence winning, and nothing downstream can currently say so. **ADR-0014:** it is a
   post-hoc *label*, not an input; reading it to explain a play crosses no line, reading it to
   decide one does. **Cost:** as a label on the record, one field and no draw — **no golden
   moves**. As a resolver input, everything moves.

---

## 7. Doc corrections this investigation found

Both are corrected in the commit that adds this file.

- [`play-calling.md`](play-calling.md):606–610, *What each side knows pre-snap*, said neither
  caller reads formation, personnel or motion off the other. Since #218 the defence's package
  **does** read `situation.offensePersonnel` (`PlayCaller.swift:300`), which is the one half
  of the exchange that is built. The commitment is unchanged and ADR-0014 is now cited
  underneath it; the description of the tree was stale.
- [`match-engine.md`](match-engine.md)'s `yards per carry, outnumbered by one` row said the
  engine reaches that box on 0.2% of first-and-ten designed carries and the row reads `n/a`.
  At `79e7a6c` it reaches it on 9.7% — 1,175 carries — and grades 3.1 against 3.9–5.1.
  [`play-calling.md`](play-calling.md) already carried the corrected figures; this table did
  not.

## 8. What was not checked

- **Nothing was measured at seed 11.** The harness numbers are one run at seed 7 and the
  printed games are four at seed 7. No noise floor was taken, because nothing here moves a
  row; a proposal that does must take its own.
- **No claim is made about *why* any OFF row is off.** §4 says which rows could plausibly
  respond to a reactive exchange and says explicitly that attributing them would be a guess.
- **`ScriptedGame`'s caller was read but not exercised.** It is the scenario harness's, not
  the game's, and its `offensiveCall`/`defensiveCall` (`ScriptedGame.swift:483–495`) follow
  the same shape.
- **The `disguised` draw rate was not measured empirically.** `manFreeBlitz` is the only
  preset carrying it (`DefensiveCall.swift:244`) and is drawn on 16% of must-pass downs and
  50% of clock-burn downs (`PlayCaller.swift:972, 983`); the printed coverage name does not
  distinguish it from `runStuff`, so no count was taken from the gamelog.
- **Whether P1's narrowed view changes a recorded byte** was reasoned about, not measured.
- **`play-calling.md`:418–419's dropback and union shares were not used and not re-derived.**
  They do not reproduce from the release and are filed as
  [#231](https://github.com/knissley/football-manager/issues/231). Where a
  carries-versus-dropbacks figure was needed, ADR-0014's own re-derived table was used, which
  prints its counts.
- **The 2026 book was read for every article cited.** The four articles where the 2025 and
  2026 editions differ were checked against
  [`rulebook-acquisition.md`](reference/rulebook-acquisition.md) and none is cited here — but
  no 2025 copy was consulted, because none is available in this environment.
