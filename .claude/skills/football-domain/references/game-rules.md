# Game rules we model

**Rulebook: 2025 season.** Every rule below is a rule of that book. Where the code still
carries an older value, it is listed under [what the code carries
today](#what-the-code-carries-today) with the issue that fixes it — the book is the
target, the tree is the state.

Defaults for the `Rules` object. All of these are configurable so variants can be
tested; these are the values a generated league starts with.

## How to read the citations

`[2025 · 6]` is Rule 6 of the 2025 rulebook; `[2025 · 4-8-2-c]` is Rule 4, Section 8,
Article 2 (c). No rulebook text is reproduced here — the rules are in our own words and the
number is how you find the original. Citations stop at the rule where the section number
would be a guess: a number nobody checked is worse than a coarser one, which is the whole
reason this file has a season on it.

**Verification status of this pass.** The rulebook itself was not reachable from the
session that wrote it: the league's operations site and the rulebook PDF are both blocked
by this environment's network policy, and no mirror was readable. So the *substance* below
was checked against public reporting of the 2025 rule changes, and the *rule numbers* are
from memory. Each section says so on its cites line, and the phrase to grep for is
`unverified: cite on next pass`. One citation — the try after a touchdown on the last play
of a period — comes from a source that reproduced the article verbatim, and says so.

## Field and structure

- 100 yards between goal lines, plus two 10-yard end zones. `[2025 · 1]`
- 11 players per side on the field. `[2025 · 5]`
- Four downs to gain 10 yards. Gaining them resets to 1st and 10. Inside the
  opponent's 10, it's 1st and goal — distance is yards to the goal line. `[2025 · 7]`

*Cites Rule 1 (the field), Rule 5 (players) and Rule 7 (the series) of the 2025 book. The
rule numbers are from memory (unverified: cite on next pass).*

## Game length

- Four 15-minute quarters. Halftime after the second. `[2025 · 4]`
- Two-minute warning: an automatic stoppage at 2:00 remaining in each half. `[2025 · 4]`
- Play clock: 40 seconds from the end of the previous play; 25 seconds after certain
  administrative stoppages (change of possession, penalty enforcement, timeout).
  `[2025 · 4]`
- Three timeouts per team per half. They do not carry over. `[2025 · 4]`

*Cites Rule 4 (game timing) of the 2025 book. The rule number is from memory (unverified:
cite on next pass).*

## Clock stoppage

This is where accuracy matters most. The clock stops on:

| Event | Restarts on |
| --- | --- |
| Incomplete pass | Snap |
| Score | Snap (after the ensuing kickoff/try sequence) |
| Timeout | Snap |
| Change of possession | Snap |
| Penalty | Depends on enforcement; generally the ready-for-play signal |
| Two-minute warning | Snap |
| Runner out of bounds | **Ready for play**, except in the last 2 minutes of the first half and the last 5 minutes of the second half, when it restarts on the snap |
| First down gained | Does not stop (the clock runs while the chains move) |

The out-of-bounds rule is the one most often modeled wrong, and it's exactly the rule
that governs whether a two-minute drill works.

Live-play duration is roughly 4–7 seconds; the rest of the interval between snaps is
the offense's tempo choice against the play clock.

*Cites Rule 4 (game timing) of the 2025 book, which is where the clock stops and starts.
The rule number is from memory, and so is every row of the table (unverified: cite on next
pass).*

## The ten-second runoff

The clock penalty that makes the end of a half a rules problem rather than an arithmetic
one. In our own words:

- It applies after the two-minute warning of either half, and only when the game clock was
  running at the time of the foul. `[2025 · 4-7]`
- The fouls that carry it: an offensive foul that prevents the snap (a false start, say);
  an offensive foul during a dead-ball period that stops the clock, added in 2024;
  intentional grounding; an illegal forward pass; an illegal substitution; and any act
  that improperly conserves time. `[2025 · 4-7]`
- The offence may take a charged timeout instead of the runoff, if it has one left.
  `[2025 · 4-7]`
- The defence may keep the yardage and decline the runoff on its own; declining the
  penalty declines the runoff with it. Two decisions, not one, and a model that offers
  only the second gets the end of a half wrong. `[2025 · 4-7]`
- After a runoff the clock starts on the ready-for-play signal, not the snap.
  `[2025 · 4-7]`
- If less time than the runoff remains, the half is over. `[2025 · 4-7]`

An injury timeout inside two minutes and a replay reversal that would have left the clock
running carry runoffs of their own `[2025 · 5]`, `[2025 · 15]`. Neither is modelled and
neither needs to be before there is a replay system.

*Cites Rule 4, Section 7 of the 2025 book, which is the citation the backlog issue
supplied. The foul list, the timeout, the decline and the ready-for-play restart are
corroborated by public explanations of the rule; neither the section number nor any article
number has been checked against the book (unverified: cite on next pass).*

## Scoring

| Play | Points | Cite |
| --- | --- | --- |
| Touchdown | 6 | `[2025 · 11]` |
| Extra point (kick, snapped from the 15) | 1 | `[2025 · 11]` |
| Two-point conversion (from the 2) | 2 | `[2025 · 11]` |
| Field goal | 3 | `[2025 · 11]` |
| Safety | 2 | `[2025 · 11]` |

Field goal distance = yards to goal line + 10 (end zone) + 7 (snap depth). Ball on the
opponent's 30 is a 47-yard attempt. Get this formula right once, in one place. (Snap depth
is a modelling constant, not a rule.)

After a safety, the team that was scored upon puts the ball back in play with a free kick
from its own 20. It is the one free kick that may be punted. `[2025 · 11]`, `[2025 · 6]`

*Cites Rule 11 (scoring) of the 2025 book, and Rule 6 (free kicks) for the safety kick. The
rule numbers are from memory (unverified: cite on next pass).*

## The try

- After a touchdown the scoring team attempts one try. A kick is snapped from the 15; a
  two-point attempt is snapped from the 2. `[2025 · 11]`
- The defence can score two points on a try — a blocked kick, an interception or a fumble
  returned the length of the field. `[2025 · 11]`
- **A touchdown on the last play of a period still gets its try.** It is waived only
  during a sudden-death period, or when time in the fourth quarter has expired and a
  successful try could not change the outcome. `[2025 · 4-8-2-c]`

*Cites Rule 11 (scoring), from memory (unverified: cite on next pass), and Rule 4, Section
8, Article 2 (c), which a secondary source reproduced verbatim — that one is verified
against the source's quotation of the article, not against the book itself.*

## Overtime

**Regular season** `[2025 · 16]`

- One 10-minute period. Two timeouts per team.
- **Both teams get a possession even if the first possession ends in a touchdown.** This
  is the 2025 change: the regular season now possesses the ball the way the postseason
  does.
- The exception is a score by the defence on the first possession — a safety or a return
  — which ends the game at once.
- Once both teams have had a possession the game is sudden death: the next score wins.
  A turnover on the first possession gets there early — the team taking the ball away is
  thereby having its possession, so both have had one and sudden death starts.
- The period is never extended to finish a possession. If the ten minutes expire with the
  score level, the game is a tie.

**Postseason** `[2025 · 16]`

- 15-minute periods, as many as are needed; a postseason game cannot end level.
- Both teams get a possession in the first period, on the same terms as above, and it is
  sudden death from the moment both have had one.

*Cites Rule 16 (overtime) of the 2025 book. The 2025 alignment of regular-season possession
with the postseason, the ten minutes and the two timeouts are verified against public
reporting of the change; the rule number is from memory (unverified: cite on next pass).*

## Penalties

Common ones and their enforcement. Rates should be influenced by player `discipline`
and coaching, and the totals should land in the calibration range (10–14 per game
across both teams).

| Penalty | Yards | Notes |
| --- | --- | --- |
| False start | 5 | Pre-snap, offense, dead ball |
| Offside / encroachment | 5 | Pre-snap, defense; offense may get a free play |
| Delay of game | 5 | Play clock expired |
| Holding (offense) | 10 | From the spot of the foul, replay the down |
| Holding (defense) | 5 | Automatic first down |
| Pass interference (defense) | Spot foul | Automatic first down — the highest-variance penalty in the game |
| Pass interference (offense) | 10 | Replay the down |
| Illegal contact | 5 | Automatic first down |
| Roughing the passer | 15 | Automatic first down |
| Facemask | 15 | Automatic first down if by the defense |
| Unnecessary roughness | 15 | Automatic first down if by the defense |
| Illegal formation / motion | 5 | Pre-snap |

**Accept/decline:** simulate the play outcome and the penalty outcome, then let the
non-penalized team take whichever is better. Offsetting penalties replay the down.

**Where a foul is enforced from** is its own rule and is not in this table: a live-ball
foul is walked off from the spot the rule names, which for several of these is not the
previous spot. The engine gets some of them wrong today — that is issue #18.

*Cites Rule 12 (player conduct) of the 2025 book for the fouls and Rule 14 for where they
are enforced from. The rule numbers and every yardage in the table are from memory
(unverified: cite on next pass) — this table predates the audit and nothing in it has been
checked against the book.*

## Kickoffs

The dynamic kickoff, permanent from 2025. The play is a scrimmage play in disguise: the
two units line up five yards apart and nobody moves until the ball comes down.

- The kick is from the kicking team's 35. `[2025 · 6]`
- The other ten men of the kicking team line up with a foot on the receiving team's 40,
  and may not move until the ball is touched or hits the ground in the landing zone or
  the end zone. `[2025 · 6]`
- The receiving team puts at least nine men in a setup zone between its own 30 and 35,
  and may keep at most two returners back in the landing zone or the end zone.
  `[2025 · 6]`
- The **landing zone** is the receiving team's goal line to its 20. `[2025 · 6]`
- **A kick that comes down in the landing zone must be returned.** There is no fair catch
  on this play. `[2025 · 6]`
- **Short, or out of bounds:** a kick that comes down in the field of play short of the
  landing zone, or that goes out of bounds before the end zone, gives the receiving team
  the ball at its own 40. `[2025 · 6]`
- **Landing zone, then the end zone:** return it, or down it for a touchback at the own
  20. `[2025 · 6]`
- **Into the end zone in the air**, or out of the back of it: return it, or down it for a
  touchback at the own **35**. This is the 2025 change; it was the 30 in 2024, and the
  25 before the dynamic kickoff. `[2025 · 6]`
- After a safety the free kick is from the kicking team's own 20, and a touchback there is
  the receiving team's 20. `[2025 · 6]`

The two touchback spots are the point of the rule: a kicker who will not put the ball in
the landing zone hands over the 35, so the kicking team's leg strength is a decision
rather than a formality.

*Cites Rule 6 (free kicks) of the 2025 book. The landing zone, the two touchback spots and
the 2025 move to the 35 are verified against public reporting of the change; the alignment
numbers and the rule number are from memory (unverified: cite on next pass).*

## Onside kicks

- An onside kick must be **declared** to the officials before the play clock starts. There
  is no surprise onside kick. `[2025 · 6]`
- **Only a trailing team may declare one, and from 2025 it may do so at any point in the
  game.** In 2024 it was the fourth quarter only. `[2025 · 6]`
- The onside kick is taken from the kicking team's 34, with the rest of the unit on the
  35. The ball must travel ten yards, or be touched by the receiving team, before the
  kicking team may recover it. `[2025 · 6]`

*Cites Rule 6 (free kicks) of the 2025 book. The declaration, the trailing-team-at-any-time
rule and the 34 are verified against public reporting of the 2025 change; the rule number
is from memory (unverified: cite on next pass).*

## Punts

- Touchback to the 20; fair catch at the spot. `[2025 · 9]`, `[2025 · 10]`
- A ball downed inside the 10 is a significant field-position win and the AI should value
  it.
- Blocks and muffs are low-probability branches worth modeling — they're memorable and
  their absence is noticeable over a long career.

*Cites Rule 9 (scrimmage kicks) and Rule 10 (fair catch) of the 2025 book. The rule numbers
are from memory (unverified: cite on next pass).*

## Changes since 2024

What moved between the book the engine was first written from and the one we model.

| Rule | 2024 | 2025 | Touches |
| --- | --- | --- | --- |
| Kickoff touchback, ball reaching the end zone in the air | Receiving team's 30 | Receiving team's **35** | `Rules.kickoffTouchbackOwnYard` — #41, #46 |
| Dynamic kickoff | One-season trial | Permanent, with alignment tweaks | The kicking game — #46 |
| Onside kick | Fourth quarter only, from the 35 | Any point when trailing, from the 34, declared | `BaselineCaller.kicksOnside` — #41, #46 |
| Regular-season overtime | A first-possession touchdown ended it | Both teams possess, then sudden death; still 10 minutes, still may end in a tie | `GameState`, `Rules` — #15 |
| Replay assist, line-to-gain measurement | — | Expanded / virtual measurement | Officiating; not modelled |

The landing-zone touchback (the own 20) is unchanged from 2024; only the in-the-air
touchback moved.

*The four playing-rule rows are verified against public reporting of the 2025 changes. No
row is verified against the book itself (unverified: cite on next pass).*

## What the code carries today

The gap between this doc and the tree, as of the September 2026 audit. Each line is
somebody's issue; none of them are decided questions. The first three were read out of the
tree while this doc was written; the rest are the audit's findings, taken on its word.

- `Rules.kickoffTouchbackOwnYard` is 30 — the 2024 value. `Rules.swift`. #41.
- `BaselineCaller.kicksOnside` requires the fourth quarter — the 2024 rule.
  `PlayCaller.swift`. #41, #46.
- Regular-season overtime is never played: a level game ends a tie at the end of the
  fourth quarter, because `Rules.mayEndInATie` is asked before any extra period is
  reached. `GameState.swift`. #15.
- There is no ten-second runoff. #32.
- The team that gave up a safety does not kick off. #16.
- The clock does not stop on a change of possession. #17.
- A touchdown on the last play of a half gets no try. #31.
- Live-ball fouls are enforced from the wrong spot. #18.

## Injured reserve and game-day rules

Roster rules rather than playing rules; they live in the league's bylaws, not the rulebook,
and the money side of them is in [`salary-cap.md`](salary-cap.md).

- A player placed on IR misses a minimum number of games; teams have a limited number
  of return-from-IR designations per season.
- 53 on the active roster, 48 active on game day.
- Practice squad players can be elevated a limited number of times per season before
  they must be signed to the active roster.

*Not cited to the playing rules, because they are not in them (unverified: cite on next
pass — these belong to the bylaws and want their own reference).*
