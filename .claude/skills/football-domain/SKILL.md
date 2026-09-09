---
name: football-domain
description: Reference for American football rules, terminology, roster construction, and salary cap mechanics as this project models them. Load before writing or reviewing simulation logic, naming domain types, designing screens that show football concepts, or whenever unsure of a term of art like proration, dead money, nickel, or down and distance.
---

# Football domain reference

The game models modern American professional football. Rules are **data**, not
hardcoded — the world's `Rules` object carries them so we can test variants — but
these are the defaults, and the vocabulary here is the vocabulary the code should use.

**The rulebook we model is the 2025 season.** Every rule statement in
[`references/game-rules.md`](references/game-rules.md) carries a rule, section and article
number from that book, in our own words, and was read there. A claim about the sport that
cannot cite one does not go in a doc, a test name or a PR — and a later book, or reporting
about one, is not evidence about this one.

Deeper references:
- [`references/game-rules.md`](references/game-rules.md) — clock, scoring, penalties, overtime
- [`references/salary-cap.md`](references/salary-cap.md) — contracts, proration, dead money, tags

The sections of the rules reference that other work cites:
[the ten-second runoff](references/game-rules.md#the-ten-second-runoff),
[the try](references/game-rules.md#the-try),
[overtime](references/game-rules.md#overtime),
[kickoffs](references/game-rules.md#kickoffs),
[onside kicks](references/game-rules.md#onside-kicks),
[what changed since 2024](references/game-rules.md#changes-since-2024), and
[what the code carries today](references/game-rules.md#what-the-code-carries-today) — the
2024 values and rules gaps still in the tree, each with its issue.

## Getting the vocabulary right

Use terms of art. Don't invent generic synonyms — `deadMoney`, not `wastedSalary`;
`downAndDistance`, not `attemptState`; `redZone`, not `nearGoalArea`. Players know
these words, and code that uses them reads correctly to anyone who knows the sport.

Some that are easy to get subtly wrong:

| Term | Means |
| --- | --- |
| **Down and distance** | Which of four attempts (`1st`–`4th`) and yards needed for a new set |
| **Series / set of downs** | Four downs to gain 10 yards; gaining them resets to 1st and 10 |
| **Drive** | One team's possession, from gaining the ball to giving it up or scoring |
| **Snap** | The play's start; also the unit of playing time (`snapCount`) |
| **Dropback** | A pass attempt, sack, or scramble — the denominator for sack rate |
| **Red zone** | Inside the opponent's 20-yard line |
| **Box** | Defenders near the line of scrimmage; "eight in the box" = run commitment |
| **Personnel** | Skill-position grouping by digits: `11` = 1 RB, 1 TE, 3 WR; `21` = 2 RB, 1 TE |
| **Base / nickel / dime** | Defensive packages: 4 DB / 5 DB / 6 DB |
| **Shell** | The deep coverage structure: single-high, two-high, quarters |
| **Man / zone** | Coverage assigned to a receiver vs to an area |
| **Line of scrimmage** | Where the ball is spotted; the yard line the play starts from |
| **Field position** | Where the ball is; expressed as own-N or opponent-N, never 0–100 in UI |
| **Turnover on downs** | Failing to gain the distance on 4th down; possession changes |
| **Three-and-out** | A drive of three plays gaining fewer than 10 yards, then a punt |

## Positions

```
Offense (11 on the field)
  QB    Quarterback           1
  RB    Running back          1     (FB fullback in heavy personnel)
  WR    Wide receiver         2–4
  TE    Tight end             1–2
  OL    LT LG C RG RT         5     (always exactly five)

Defense (11 on the field)
  EDGE  Edge rusher           2     (4-3 DE and 3-4 OLB — same position, different front)
  DT    Defensive tackle      1–2   (nose tackle is a DT archetype)
  LB    Off-ball linebacker   2–4
  CB    Cornerback            2–4
  S     Safety                2–3   (free/strong is usage, not a position)

Special teams
  K     Kicker      P  Punter      LS  Long snapper
```

`EDGE`, `LB`, and `S` are single positions in the model. Whether a given EDGE fits
your front, or a safety plays deep or in the box, is a **scheme fit** question resolved
by ratings — not a separate position enum case. This keeps the position list short and
puts the interesting variation in ratings and scheme.

## Roster construction

| Group | Size | Notes |
| --- | --- | --- |
| Active roster | 53 | Hard limit at every phase boundary |
| Game-day active | 48 | The rest are inactive that week |
| Practice squad | 16 | Can be elevated for a game; poachable by other teams |
| Injured reserve | — | Off the active roster; minimum absence before return |

A plausible 53 looks roughly like: 3 QB, 4 RB, 6 WR, 4 TE, 9 OL, 5 EDGE, 5 DT, 5 LB,
6 CB, 4 S, 3 specialists. The generator should hit this shape with variance, and the
AI roster manager should treat large deviations as a need.

**Positional value is not uniform.** QB is worth several times any other position;
premium positions (QB, EDGE, LT, CB, WR) command more than off-ball LB, RB, S, or
interior OL. The AI's contract and draft valuation must reflect this or the trade and
free agency markets will be nonsense.

## The season

```
Preseason → 17 games over 18 weeks (one bye per team) → Playoffs → Offseason
```

Playoffs: 7 teams per conference — 4 division winners seeded 1–4 by record, 3 wild
cards. The 1 seed gets a bye. Wild card round, divisional, conference championship,
then the championship game at a neutral site.

Seeding tiebreakers, in order: head-to-head, division record, common games, conference
record, strength of victory. Implement them properly and test them — a wrong tiebreaker
is player-visible and infuriating.

Offseason order matters and drives the whole meta: retirements → contract decisions
(cuts, restructures, franchise tags) → free agency → combine and scouting → draft →
undrafted free agents → training camp, where progression resolves.

## Where things usually go wrong

Things to be careful about when writing sim code:

- **Clock management.** Late-game situations are where players pay the most attention
  and where an approximation reads as fake. Two-minute drills, spikes, kneel-downs,
  and the timeout/out-of-bounds interaction need to be explicit states.
- **Cap arithmetic.** Proration and dead money are the easiest thing in the project to
  get subtly wrong, and every wrong answer is visible on a contract screen. Test
  exhaustively; see the cap reference.
- **Penalty accept/decline.** Evaluate both branches and take the better one for the
  non-penalized team. A "declined" penalty that still applies is a classic bug.
- **Yards-to-goal vs yards-to-first-down.** Two different distances. Inside the 10,
  they interact — you can't have 1st and 10 from the opponent's 6; it's 1st and goal.
- **Field position representation.** Store as yards from the opponent's goal line
  (0–100) internally; format as "own 35" / "opponent 20" for display. Mixing the two
  is a recurring source of off-by-a-lot bugs.
- **Sack yardage** counts against passing yards, and a sack is not a pass attempt but
  is a dropback. Stat denominators are specific; get them right or calibration lies.
