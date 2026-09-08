# Game rules we model

Defaults for the `Rules` object. All of these are configurable so variants can be
tested; these are the values a generated league starts with.

## Field and structure

- 100 yards between goal lines, plus two 10-yard end zones.
- 11 players per side on the field.
- Four downs to gain 10 yards. Gaining them resets to 1st and 10. Inside the
  opponent's 10, it's 1st and goal — distance is yards to the goal line.

## Game length

- Four 15-minute quarters. Halftime after the second.
- Two-minute warning: an automatic stoppage at 2:00 remaining in each half.
- Play clock: 40 seconds from the end of the previous play; 25 seconds after certain
  administrative stoppages (change of possession, penalty enforcement, timeout).
- Three timeouts per team per half. They do not carry over.

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

## Scoring

| Play | Points |
| --- | --- |
| Touchdown | 6 |
| Extra point (kick, snapped from the 15) | 1 |
| Two-point conversion (from the 2) | 2 |
| Field goal | 3 |
| Safety | 2 |

Field goal distance = yards to goal line + 10 (end zone) + 7 (snap depth). Ball on the
opponent's 30 is a 47-yard attempt. Get this formula right once, in one place.

After a safety, the team that was scored upon kicks off from its own 20.

## Overtime

- Regular season: one 10-minute period. Both teams get a possession unless the
  defense scores. If still tied when time expires, the game is a tie.
- Postseason: 15-minute periods, played until someone wins. Both teams get a
  possession in the first period.

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

## Kickoffs and punts

- Kickoff from the kicking team's 35. A touchback places the ball at the receiving
  team's 30 (this yardage is a rules-variant knob and should stay in `Rules`).
- Punts: touchback to the 20; fair catch at the spot; a ball downed inside the 10 is a
  significant field-position win and the AI should value it.
- Onside kicks are permitted only when trailing in the fourth quarter, and are declared.
- Blocks and muffs are low-probability branches worth modeling — they're memorable and
  their absence is noticeable over a long career.

## Injured reserve and game-day rules

- A player placed on IR misses a minimum number of games; teams have a limited number
  of return-from-IR designations per season.
- 53 on the active roster, 48 active on game day.
- Practice squad players can be elevated a limited number of times per season before
  they must be signed to the active roster.
