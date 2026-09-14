# Game rules we model — the index by area

**Every rule statement in this project has one home: `docs/reference/playing-rules.md`,
indexed by article number.** This file is the way in by *area* — you know you are working
on the clock, or the try, or where a foul is enforced from, and you want the article
numbers that govern it. Follow them into the reference and read the rule there.

It carries no paraphrase of its own, on purpose. It used to: 74 of the 75 articles it
cited were also in the reference, in a second set of words, and a branch that corrected an
article in the reference shipped the correction's opposite in the copy here, in one commit
set, through review. Two paraphrases of one rule are two things to keep true, and the
cheapest way to keep them agreeing is to have one.

**Rulebook: 2025 season.** CLAUDE.md pins the engine to that book. A 2026 book exists and
has moved some of this again; a 2026 rule is out of scope here, and reporting that
describes one is not evidence about this one. `Rules.rulebookSeason` records the target.

## What is where

| File | What it is |
| --- | --- |
| `docs/reference/playing-rules.md` | **the rules**, by article, in our own words, each naming the test that checks it or saying the engine does not implement it yet |
| `docs/invariants.md` | **the promise**: what must be true of a game, numbered, each naming its test or harness row |
| `docs/reference/calibration-sources.md` | **the rates**: every band, the season it came from and how it was derived |
| this file | the index by area, plus the modelling conventions and roster rules that are not playing rules at all |
| [`salary-cap.md`](salary-cap.md) | contracts, proration, dead money, tags |

A claim about the sport cites an article and a season (CLAUDE.md rule 10). If the article
you need is in neither this project's reference nor the book itself, say so and stop — do
not cite from memory. `scripts/lint-reference.sh --show <article>` prints the article
beside the citation, which is the only thing that catches a citation that resolves but
says something else.

## The index

Article numbers below are pointers into `docs/reference/playing-rules.md`, which is in rule
order, so a number is found by reading down. `4-3-2-a-1` is Rule 4, Section 3, Article 2,
clause (a), item (1).

### Field and structure

| Area | Articles |
| --- | --- |
| The field, the goal lines, the end zones | `1-1-1` |
| Eleven a side | `5-1-1` |
| A series, and the line to gain | `3-8-2`, `3-8-3`, `7-3-1` |
| Forward progress, and where the next snap comes from | `3-12-1`, `3-12-2`, `7-3-3`, `7-6-1` |
| A charged down | `3-8-4` |
| Definitions the clock rules lean on: time in, the try, the T-formation quarterback | `3-36-3`, `3-40`, `3-42` |

### Game length and the clock

| Area | Articles |
| --- | --- |
| Four periods, the intermissions, overtime | `4-1-1`, `4-1-2`, `4-1-3` |
| The coin toss and its elections; changing ends | `4-2-2`, `4-2-2-a`, `4-2-3` |
| What starts the clock | `4-3-1` and its clauses, `4-3-2` and its clauses |
| What stops it | `4-4-a` through `4-4-j` |
| The two-minute warning | `3-41`, `4-4-h` |
| Charged timeouts, and the injury timeout | `4-5-1`, `4-5-3`, `4-5-4` with its Notes |
| The play clock, and delay of game | `4-6-1` through `4-6-4` |
| Extending a period for an untimed down | `4-8-1`, `4-8-2` and its clauses |

**The out-of-bounds rule (`4-3-2-a` and its items) is the one most often modelled wrong**,
and it is exactly the rule that decides whether a two-minute drill works. The window is
judged where the runner stepped out, not at the previous whistle.

### The ten-second runoff

| Area | Articles |
| --- | --- |
| The six acts that cannot buy time, and the runoff itself | `4-7-1` and its Items |
| Illegal substitution after the warning | `4-7-2` |
| The last forty seconds of a half | `4-7-3` |
| A replay reversal's runoff — not modelled, there is no replay system | `4-7-4` |
| The excess injury timeout's runoff | `4-5-4 Note 3` |
| The clock after a runoff | `4-3-2-g` |

This is the clock penalty that makes the end of a half a rules problem rather than an
arithmetic one, and the decision easiest to model as one decision is two: the defence may
decline the runoff and keep the yardage, and declining the yardage declines the runoff
with it.

### Scoring, the try, and field goals

| Area | Articles |
| --- | --- |
| What each score is worth | `11-1-2-a` to `11-1-2-d`, `11-2-1` |
| The try: the down, the spots, who may score, when it is waived | `11-3-1`, `11-3-2-b`, `11-3-2-c`, `4-8-2-b`, `4-8-2-c` |
| A foul on the try | `11-3-3` and its Items |
| Who kicks off after a try or a field goal | `11-3-4`, `11-4-6` |
| A legal field goal, and a missed one | `11-4-1`, `11-4-2` |
| The free kick after a safety | `11-5-2`, `6-1-1-b` |
| A touchback, and the spot it is put in play from | `11-6-2-a`, `11-6-2-c`, `11-6-3` |

### Free kicks — kickoffs, safety kicks, onside kicks

| Area | Articles |
| --- | --- |
| When a half or a possession opens with one | `6-1-1-a`, `6-1-1-b` |
| Where the two units line up; the setup zone and the landing zone | `6-1-2-a` to `6-1-2-e`, `6-1-3-a` to `6-1-3-c` |
| A kick that lands in the landing zone; who may recover | `6-1-4`, `6-1-4-c`, `6-1-4-d` |
| The two touchback spots | `6-1-5`, `6-1-5-a` |
| The onside kick: declaring it, the alignment, recovering it | `6-1-1-c`, `6-1-6` and its clauses |
| A fouled free kick, and the free kicker's own protection | `6-1-7`, `6-2-3` |
| Short, or out of bounds: the receivers' choice of spots | `6-2-4` |
| The fair catch, and the fair catch kick it buys | `10-2-1`, `10-2-4` |

**The two touchback spots are the point of the rule**: a kicker who will not put the ball
in the landing zone hands over the 35, so leg strength is a decision rather than a
formality.

**Not this book.** Reporting that puts the onside kick's restraining line at the 34, or
that lets a team which is *not* trailing declare one, is describing later rule-making.
Rule 6 has three 2025 modifications and only three — the setup-zone alignment (`6-1-3-b`
Item 2), the touchback spot (`6-1-5`), and declaring at any point when trailing (`6-1-6`).
Those three are also where the 2025 and 2026 books differ, so read
`docs/reference/rulebook-acquisition.md` before verifying any of them against a downloaded
copy.

### The passing game

| Area | Articles |
| --- | --- |
| A legal forward pass; intentional grounding and the spike | `8-1-3`, `8-2-1` and its Items, `8-2-Penalty` |
| An ineligible player downfield | `8-3-1` |
| Contact with a receiver: illegal contact, defensive holding | `8-4-2` to `8-4-7` |
| Pass interference, both ways | `8-5-1`, `8-5-4`, `8-5-Penalty` |
| Where a foul during a pass play is enforced from | `8-6-1`, `8-6-1-b`, `8-6-1-d` |
| A loose ball recovered and carried in | `8-7-3 Item 1` |

### Fouls and what they cost

| Area | Articles |
| --- | --- |
| Pre-snap: false start, encroachment, offside, illegal motion, illegal formation | `7-4-2`, `7-4-3`, `7-4-5`, `7-4-8`, `7-5-1` |
| Use of hands, blocks, holding | `12-1-3-a` to `12-1-3-c`, `12-1-6`, `12-2-7` |
| Personal fouls: roughness, the helmet, the passer, the facemask, the horse collar | `12-2-8`, `12-2-10`, `12-2-11`, `12-2-15`, `12-2-16` |
| The kicker's protection, and the marking the enforcement turns on | `12-2-12` |
| Unsportsmanlike conduct after the play | `12-3-1` |

### Where a foul is enforced from

| Area | Articles |
| --- | --- |
| The half-distance ceiling, which overrides every other enforcement | `14-2-1` |
| A foul on a scoring play; a foul with the opponent holding the ball | `14-2-3`, `14-2-4` |
| The spots a penalty can be enforced from | `14-3-4` |
| The basic spot, and the three-and-one method | `14-3-5`, `14-3-6` |
| A flag before the snap, and a flag as it is snapped | `14-4-1` |
| A run followed by a change of possession | `14-4-3`, `14-4-5`, `14-4-5-d`, `14-4-6-b` |
| Offsetting fouls | `14-5-1` |

`14-2-1` bites well short of a goal line, so a walk-off that stops inside the field of play
is no evidence the ceiling is idle.

### Overtime

| Area | Articles |
| --- | --- |
| Regular season: one period, both teams owed a possession, never extended | `16-1-3` and its clauses |
| Postseason: as many periods as it takes, the halves they pair into, the fresh toss | `16-1-4` and its clauses |
| What counts as having possessed, and the kicking plays | `16-1-5-b`, `16-1-5-c` |
| The approved rulings on a kickoff during overtime | `A.R. 16.1`, `A.R. 16.2`, `A.R. 16.4` |

### Officiating

| Area | Articles |
| --- | --- |
| Replay assist — a 2025 modification, not modelled | `15-9` |

## Modelling conventions, which are not rules

These have no article and never will. Each says which it is, so nothing here can be
mistaken for the book.

- **Field goal distance** = yards to the goal line + 10 (the end zone) + 7 (snap depth).
  The ball on the opponent's 30 is a 47-yard attempt. The snap depth is a modelling
  constant; get the formula right once, in one place.
- **Live-play duration** of roughly 4–7 seconds is a modelling convention. The rest of the
  interval between snaps is the offence's tempo choice against the play clock — and the
  play clock in force *is* a rule the engine counts (`4-6-1`, `4-6-2`), so a delay of game
  is that clock expiring rather than a rate drawn beside it.
- **Accept or decline**: simulate the play outcome and the penalty outcome, then let the
  non-penalised team take whichever is better. A declined penalty that still applies is a
  classic bug.
- **A ball downed inside the 10** is a significant field-position win and the AI should
  value it.
- **Blocks and muffs** are low-probability branches worth modelling: they are memorable,
  and their absence is noticeable over a long career.
- **Penalty rates per game** are a calibration band, not a rule. Bands live in
  `docs/reference/calibration-sources.md` with the season each came from; never assert one
  from memory and never retune one inside a fix.

## What the engine does not implement yet

Not a separate list, on purpose: every article the engine does not enforce says so in its
own entry in `docs/reference/playing-rules.md`, naming the issue that will enforce it or
saying in as many words that no issue carries it. `InvariantsTraceabilityTests` fails if an
entry there names neither a test nor an admission, so the gap list cannot go stale in place
the way a hand-kept one does.

The largest of those gaps, for orientation: the dynamic kickoff is in the engine as far as
the *aiming points* go and no further. Nobody lines up for a free kick, so the setup zone,
the restraining lines and every alignment foul are absent — and so is the landing-zone
touchback, which needs a kick to come down in the landing zone and then reach the end zone.

## Injured reserve and game-day rules

Roster rules rather than playing rules: they are in the league's constitution and bylaws,
not the rulebook, so they carry no article number and none of them is in the reference. The
money side of them is in [`salary-cap.md`](salary-cap.md).

- A player placed on IR misses a minimum number of games; teams have a limited number of
  return-from-IR designations per season.
- 53 on the active roster, 48 active on game day.
- Practice squad players can be elevated a limited number of times per season before they
  must be signed to the active roster.

*None of the three has been checked against the bylaws by anybody here (unverified: cite on
next pass).* The 2025 amendments to Article XVII, Section 17.16 are the return-from-IR
designations above, and the bylaws want a reference of their own.
