# Game rules we model

**Rulebook: 2025 season.** Every rule below is a rule of that book, read in it. A 2026
book exists and has moved some of this again — CLAUDE.md pins the target at 2025, so a
2026 rule is out of scope here and reporting that describes one is not evidence about this
book. Where the code still carries an older value, it is listed under [what the code
carries today](#what-the-code-carries-today) with the issue that fixes it — the book is
the target, the tree is the state.

Defaults for the `Rules` object. All of these are configurable so variants can be
tested; these are the values a generated league starts with.

## How to read the citations

`[2025 · 6-1-5]` is Rule 6, Section 1, Article 5 of the 2025 rulebook; a fourth part is
the clause, so `[2025 · 4-7-1-b]` is that article's (b). No rulebook text is reproduced
here — the rules are in our own words and the number is how you find the original.

Every rule statement below was checked against the 2025 book itself. A line that is not a
rule — a modelling convention, a calibration band, a fact about our engine — says which it
is instead and cites that. Anything still marked `(unverified: cite on next pass)` is a
line nobody has checked; grep for that phrase before trusting a number.

## Field and structure

- The field is 360 feet by 160 feet, with goal lines 10 yards in from each end line: 100
  yards between goal lines and two 10-yard end zones. `[2025 · 1-1-1]`
- 11 players a side. Twelve in the formation is a foul before the snap and a foul on the
  snap. `[2025 · 5-1-1]`
- A series is four scrimmage downs to reach the line to gain. `[2025 · 3-8-2]`,
  `[2025 · 7-3-1]`
- The line to gain is 10 yards in advance of the spot of the snap that started the series,
  **or the goal line if that is nearer** — which is what first and goal is.
  `[2025 · 3-8-3]`

## Game length

- Four 15-minute periods. A tie at the end of them goes to overtime under Rule 16.
  `[2025 · 4-1-1]`
- Halftime is 13 minutes; the other intermissions are at least two. `[2025 · 4-1-2]`,
  `[2025 · 4-1-3]`
- The two-minute warning is an automatic timeout taken at the end of the last down snapped
  or kicked before two minutes remain — in the **second and fourth periods**, not every
  half of every kind of period. `[2025 · 3-41]`
- Play clock: 40 seconds from the end of the previous play; 25 seconds after an
  administrative stoppage — change of possession, charged timeout, two-minute warning, end
  of a period, penalty enforcement, a free kick. `[2025 · 4-6-1]`, `[2025 · 4-6-2]`
- Three charged timeouts per team per half. They do not carry over. `[2025 · 4-5-1]`

## Clock stoppage

This is where accuracy matters most. The clock stops at the end of a down in which any of
these happens, and starts again as the second column says. `[2025 · 4-4]`, `[2025 · 4-3]`

| Event | Restarts on | Cite |
| --- | --- | --- |
| Incomplete pass | Snap | `4-4-f`, `4-3-2` |
| Ball dead on or behind a goal line | Snap | `4-4-d` |
| Free kick or fair catch kick down | Legal touching in the field of play, with exceptions | `4-4-a`, `4-3-1` |
| Charged timeout | Snap | `4-4-j`, `4-3-2` |
| **Change of possession** | Snap | `4-4-i`, `4-3-2-a-1` |
| Foul | Generally as if the foul had not occurred; on the snap in the listed late-game cases | `4-4-e`, `4-3-2-e` |
| Two-minute warning | Snap | `4-4-h` |
| Runner out of bounds | **Ready for play**, except on the snap after a change of possession, after the two-minute warning of the first half, or inside the last five minutes of the second half | `4-4-c`, `4-3-2-a` |
| After a 10-second runoff | Ready for play | `4-3-2-g` |
| During the Try | The Try is untimed | `4-3-2-h`, `11-3-1` |
| First down gained | Does not stop the clock | — |

The out-of-bounds rule is the one most often modeled wrong, and it's exactly the rule
that governs whether a two-minute drill works.

Live-play duration of roughly 4–7 seconds is a modelling convention, not a rule; the rest
of the interval between snaps is the offense's tempo choice against the play clock.

## The ten-second runoff

The clock penalty that makes the end of a half a rules problem rather than an arithmetic
one. In our own words:

- After the two-minute warning of either half a team may not conserve time by: a foul by
  either team that stops the clock during a dead-ball period; intentional grounding; an
  illegal forward pass; throwing a backward pass out of bounds; spiking or throwing the
  ball in the field of play after a down has ended, other than after a touchdown; or
  illegally batting or kicking the ball out of bounds. Five yards, unless a larger
  distance penalty applies. `[2025 · 4-7-1]`
- **When the offence does one of them while the clock is running, ten seconds come off**,
  the play clock is reset to 30, and the game clock starts on the ready-for-play signal.
  `[2025 · 4-7-1]` Item 1
- The offence may use a charged timeout instead of the runoff, and then the clock starts
  on the snap. `[2025 · 4-7-1]` Item 1
- **The defence may always decline the runoff and keep the yardage. Declining the yardage
  declines the runoff with it** — two decisions, not one, and a model that offers only the
  second gets the end of a half wrong. `[2025 · 4-7-1]` Item 1
- An illegal substitution after the two-minute warning, while the ball is dead and the
  clock running, is five yards **and** a runoff. `[2025 · 4-7-2]`
- The same act by the defence is not a runoff: the play clock resets to 40 and the clock
  starts on the ready signal unless the offence wants the snap. There is never a runoff
  against the defence. `[2025 · 4-7-1]` Item 2, `[2025 · 4-5-4]` Note 9
- A half can end on a runoff. `[2025 · 4-5-4]` Note 4
- A replay reversal or a nullified foul after the two-minute warning that leaves the clock
  where a correct ruling would not have stopped it also runs ten seconds off; neither team
  may decline that one, but either may spend a timeout to stop it. `[2025 · 4-7-4]`
- An excess timeout for injury against the team in possession carries a runoff at the
  defence's choice. `[2025 · 4-5-4]` Note 3

## Scoring

| Play | Points | Cite |
| --- | --- | --- |
| Touchdown | 6 | `[2025 · 11-1-2-a]` |
| Field goal | 3 | `[2025 · 11-1-2-b]` |
| Safety | 2 | `[2025 · 11-1-2-c]` |
| Try by kick | 1 | `[2025 · 11-1-2-d]` |
| Try by pass or run | 2 | `[2025 · 11-1-2-d]` |

A field goal must be a place kick or drop kick from on or behind the line of scrimmage,
and must not touch the ground or a teammate before it passes through the goal.
`[2025 · 11-4-1]`

Field goal distance = yards to goal line + 10 (end zone) + 7 (snap depth). Ball on the
opponent's 30 is a 47-yard attempt. Get this formula right once, in one place. The snap
depth is a modelling constant, not a rule.

**A miss is a field-position event.** If a missed field goal crosses the line and the
receivers do not touch it, they take the ball at the spot of the kick — or at their 20 if
the kick came from inside the 20. `[2025 · 11-4-2]`

**After a safety, the team that was scored upon puts the ball in play with a free kick
from its own 20**, and that kick alone may be a punt as well as a drop kick or place kick.
`[2025 · 11-5-2]`, `[2025 · 6-1-1-b]`

## The try

- After a touchdown the scoring team gets one untimed scrimmage down. The game clock does
  not run during it. `[2025 · 11-3-1]`
- The snap is 15 yards from the defence's goal line for a kick, two yards from it for a
  pass or run — the offence's choice, changeable after a penalty or a timeout.
  `[2025 · 11-3-1]`
- **Either team can score on a try.** A try that ends in a touchdown is two points whoever
  scores it; what would be a safety on a try is one point to the opponent.
  `[2025 · 11-3-2-b]`, `[2025 · 11-3-2-c]`
- **A touchdown on the last play of a period still gets its try.** It is waived only
  during sudden-death overtime, or when time in the fourth period has expired and a
  successful try could not affect the outcome. `[2025 · 4-8-2-c]`
- After the try, the team that was on defence for it receives the kickoff.
  `[2025 · 11-3-4]` The same is true after a successful field goal. `[2025 · 11-4-6]`

## Overtime

**Regular season** — one 10-minute period after an intermission of no more than three
minutes. `[2025 · 16-1-3]`

- **Both teams must have the opportunity to possess the ball**, whatever the first
  possession produced. The one exception in the article: if the team that kicked off
  scores a safety on the receiving team's first possession, it has won. `[2025 · 16-1-3-a]`
- Once both have had that opportunity, whoever has more points has won. `[2025 · 16-1-3-b]`
- If the first team does not score on its initial possession, or the score is level after
  both have possessed, **the next score by any method wins**. `[2025 · 16-1-3-c]`
- A defence that takes the ball away has thereby had its possession — possession is gained
  by catching, intercepting or recovering a loose ball — so a first-possession turnover
  puts the game into sudden death, and a defensive touchdown on the first possession ends
  it under (b). `[2025 · 16-1-5-b]`
- **The period is never extended**, not even for a second team that has not possessed or a
  possession still running. Level at the end is a tie. `[2025 · 16-1-3-d]`
- Two timeouts each; fourth-quarter timing rules otherwise apply. `[2025 · 16-1-3-e]`

**Postseason** — 15-minute periods, as many as it takes. `[2025 · 16-1-4]`

- The possession rules are the same. `[2025 · 16-1-4-a]` to `[2025 · 16-1-4-c]`
- Level at the end of a period, or a second team's initial possession unfinished, means
  another period. `[2025 · 16-1-4-d]`
- Three timeouts per half, two-minute intermissions between periods, and a fresh coin toss
  after the fourth. `[2025 · 16-1-4-e]`, `[2025 · 16-1-4-g]`, `[2025 · 16-1-4-i]`

On kicking plays the opportunity to possess is defined for you: a kickoff is the receiving
team's opportunity, and if the kicking team legally recovers it the receiving team is
still deemed to have had it. `[2025 · 16-1-5-c]`

## Penalties

Common ones, with what the book says they cost.

| Penalty | Yards | Notes | Cite |
| --- | --- | --- | --- |
| False start | 5 | Enforced before the snap | `7-4-2` |
| Encroachment | 5 | Pre-snap, defense | `7-4-3` |
| Offside | 5 | The offense may get a free play | `7-4-5` |
| Delay of game | 5 | Play clock expired, and the other listed delays | `4-6` |
| Illegal formation (offense) | 5 | | `7-5-1` |
| Illegal motion | 5 | | `7-4-8` |
| Holding (offense) | 10 | Replay the down | `12-1-3-c` |
| Illegal use of hands (offense) | 10 | | `12-1-3-a` |
| Illegal block in the back | 10 | | `12-1-3-b` |
| Holding (defense) | 5 | Automatic first down | `8-4-6`, `12-1-6` |
| Illegal contact | 5 | Automatic first down | `8-4-4` |
| Pass interference (defense) | Spot foul | First down at the spot of the foul. In the end zone it is first down at the 1, or half the distance to the goal when the previous spot was inside the 2 | `8-5-4` |
| Pass interference (offense) | 10 from the previous spot | Replay the down | `8-5-4` |
| Roughing the passer | 15 | Automatic first down | `12-2-11` |
| Unnecessary roughness | 15 | Automatic first down if by the defense | `12-2-8` |
| Facemask | 15 | Automatic first down if by the defense | `12-2-15` |

All cites are the 2025 book.

**Accept/decline:** simulate the play outcome and the penalty outcome, then let the
non-penalized team take whichever is better. Offsetting penalties replay the down.

**Where a foul is enforced from** is its own rule — Rule 14 `[2025 · 14-4]` for the spots,
`[2025 · 8-6]` for the passing game — and is not in this table. The engine gets some of
them wrong today; that is issue #18.

The 10–14 penalties per game the harness aims at is a calibration band, not a rule, and
its season and source belong to issue #2.

## Kickoffs

The dynamic kickoff, made permanent for 2025. The two units line up five yards apart and
nobody moves until the ball comes down.

- **The kick is from the kicking team's 35** — its 20 for a safety kick — and the other
  ten of the kicking team line up on the **receiving team's 40**. `[2025 · 6-1-2-a]`,
  `[2025 · 6-1-2-b]`
- The receiving team's restraining line is its own 35, and the **setup zone** is the five
  yards between its 35 and its 30. `[2025 · 6-1-2-c]`, `[2025 · 6-1-2-d]`
- The **landing zone** is the receiving team's 20 out to its goal line. `[2025 · 6-1-2-e]`
- **At least nine receiving players must be in the setup zone**, at least six of them with
  a foot on the restraining line — seven if the team puts more than nine in the zone. That
  leaves at most two returners deep. `[2025 · 6-1-3-b]`
- **At most three of those players may be off the restraining line, and never more than
  one in each of the three areas the sidelines and the inbounds lines cut the setup zone
  into.** This is the 2025 modification to the formation. `[2025 · 6-1-3-b]` Item 2
- The kicking team's ten line up with their front foot on their restraining line, feet on
  the ground, and nobody but the kicker and the men deep may move until the ball touches
  the ground or a player in the landing zone or the end zone. `[2025 · 6-1-3-a]`,
  `[2025 · 6-1-3-c]`
- **A kick that comes down in the landing zone is live and gets returned.** There is no
  fair catch available: a fair catch is defined only on a scrimmage kick.
  `[2025 · 6-1-4]`, `[2025 · 10-2-1]`
- **Short, or out of bounds:** if the kick goes out of bounds between the goal lines, or
  first touches the ground or a player short of the landing zone, the receiving team may
  take the ball **25 yards from the spot of the kick** — its own 40 when the kick was from
  the 35 — or at the out-of-bounds spot, or where the ball came down, whichever it
  prefers. From a safety kick the distance is 30 yards. `[2025 · 6-2-4]`
- **Landing zone, then the end zone:** the ball is live; downed there or out of bounds
  behind the goal line, it is a touchback at the **20**. `[2025 · 6-1-5-a]`
- **Into the end zone without touching down in the landing zone first** — downed there,
  out of bounds behind the goal line, or off the goal post — it is a touchback at the
  **35**. This is the 2025 change; it was the 30 in 2024. `[2025 · 6-1-5]`
- A kickoff or safety kick that reaches the end zone and stays inbounds is a live ball and
  must be returned or downed. `[2025 · 6-1-5]`
- The kicking team may recover the ball once it has touched the ground or a player in the
  landing zone or the end zone; a recovery there is the kicking team's ball at the dead
  ball spot. `[2025 · 6-1-4-c]`, `[2025 · 6-1-4-d]`

The two touchback spots are the point of the rule: a kicker who will not put the ball in
the landing zone hands over the 35, so leg strength is a decision rather than a formality.

## Onside kicks

- **Only a trailing team may attempt one, and it must declare it** to the Referee before
  the play clock starts; the Referee then tells the receiving team. There is no surprise
  onside kick. `[2025 · 6-1-1-c]`, `[2025 · 6-1-6]`
- **It may be declared at any point in the game.** Fourth quarter only was the 2024 rule.
  `[2025 · 6-1-6]`
- The kicking team's restraining line is still its **35** (its 20 on a safety kick), with
  the rest of the unit's front feet on that line and no more than five players either side
  of the ball. `[2025 · 6-1-6-b]`, `[2025 · 6-1-6-c]`
- The kicking team may recover only after the ball **reaches the receiving team's
  restraining line** — ten yards in advance of its own — or is touched by a receiving team
  player first. `[2025 · 6-1-6-e]`, `[2025 · 6-1-6-g]`
- The receiving team puts eight or nine players between its restraining line and 15 yards
  behind it, the onside kick setup zone. A kick that goes untouched beyond that zone is
  dead and the receiving team's, and costs the kicking team 15 yards.
  `[2025 · 6-1-6-h]`, `[2025 · 6-1-6-k]`

**Not this book:** reporting that puts the onside kick at the 34, or lets a team that is
*not* trailing declare one, is describing later rule-making. In the 2025 book the
restraining line is the 35 and only a trailing team may declare. Rule 6 has three 2025
modifications and only three — the setup-zone alignment, the touchback spot, and
declaring at any point when trailing.

## Punts

- A punt that reaches the end zone untouched by the receivers is a touchback, and the
  receiving team snaps at its own 20. `[2025 · 11-6-2-c]`, `[2025 · 11-6-3]`
- A fair catch is an unhindered catch of a scrimmage kick beyond the line after a valid
  signal; the receiving team then snaps from the spot, or may take a fair catch kick.
  `[2025 · 10-2-1]`, `[2025 · 10-2-4]`
- A ball downed inside the 10 is a significant field-position win and the AI should value
  it. Modelling, not a rule.
- Blocks and muffs are low-probability branches worth modeling — they're memorable and
  their absence is noticeable over a long career.

## Changes since 2024

The book's own list of what changed for 2025, with what it touches here.

| Rule | What changed | Touches |
| --- | --- | --- |
| `6` | The 2024 form of the kickoff is made permanent | The kicking game — #46 |
| `6-1-3` | Alignment for receiving-team players in the setup zone, on a kickoff or a safety kick: at most three of them off the restraining line, and never more than one in each of the three areas bordered by the sidelines and the inbounds lines | #46 |
| `6-1-5` | **Touchback spot moves to the 35** when the kick reaches the end zone without touching down in the landing zone first — downed there, out of bounds behind the goal line, or off the goal post | `Rules.kickoffTouchbackOwnYard` — #41, #46 |
| `6-1-6` | Alignment for the kicking team on an onside kick, **and an onside kick may be declared at any time when trailing** | `PlayCaller.kicksOnside` — #41, #46 |
| `15-9` | Replay assist may advise the on-field crew on more objective aspects of a play | Officiating; not modelled |
| `16-1-3` | **Regular-season overtime gives both teams a possession** whatever the first one produced, within one 10-minute period | `GameState`, `Rules` — #15 |

The landing-zone touchback (the 20) did not move, and neither did the onside kick's
restraining line: it is still the 35.

## What the code carries today

The gap between this doc and the tree, as of the September 2026 audit. Each line is
somebody's issue; none of them are decided questions. The first three were read out of the
tree while this doc was written; the rest are the audit's findings, taken on its word.

- `Rules.kickoffTouchbackOwnYard` is 30 — the 2024 value. `Rules.swift`. #41.
- `kicksOnside` requires the fourth quarter — the 2024 rule. It is the default in the
  `PlayCaller` protocol extension, not a method on one caller: `BaselineCaller` and every
  other caller inherit it, so changing that guard changes them all. `PlayCaller.swift`.
  #41, #46.
- Regular-season overtime is never played: a level game ends a tie at the end of the
  fourth quarter, because `Rules.mayEndInATie` is asked before any extra period is
  reached. `GameState.swift`. #15.
- There is no ten-second runoff. #32.
- The team that gave up a safety does not kick off. #16.
- The clock does not stop on a change of possession. #17.
- A touchdown on the last play of a half gets no try. #31.
- Live-ball fouls are enforced from the wrong spot. #18.

The dynamic kickoff is not in the engine at all: `Rules` carries one
`kickoffTouchbackOwnYard` and `Advancement` has one kickoff touchback spot, so there is no
landing zone, no second touchback spot and no short-kick or out-of-bounds spot. That is
#46's problem, and this section is what it is being held to.

## Injured reserve and game-day rules

Roster rules rather than playing rules; they are in the league's bylaws, not the rulebook,
and the money side of them is in [`salary-cap.md`](salary-cap.md).

- A player placed on IR misses a minimum number of games; teams have a limited number
  of return-from-IR designations per season.
- 53 on the active roster, 48 active on game day.
- Practice squad players can be elevated a limited number of times per season before
  they must be signed to the active roster.

*None of the three carries a rule number because none of them is in the playing rules
(unverified: cite on next pass).* They live in the constitution and bylaws — the 2025
amendments to Article XVII, Section 17.16 are the return-from-IR designations above — and
those want a reference of their own.
