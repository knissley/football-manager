# Contracts and the salary cap

The cap is the central constraint of the management game. Model it properly — every
arithmetic error here is visible on a contract screen, and the meta collapses if teams
can escape the cap by accident.

## Contract anatomy

A contract has a term (years) and, per year:

- **Base salary** — paid during the season, counts fully in that year.
- **Roster bonus** — paid on a date if the player is on the roster; counts in that year.
- **Incentives** — split into *likely to be earned* (counts against the cap now, based
  on last season's production) and *not likely to be earned* (doesn't, but reconciles
  the following year).

Plus, paid once at signing:

- **Signing bonus** — cash paid up front, but **prorated evenly across the contract
  years for cap purposes, up to a maximum of 5 years**.

And per year:

- **Guarantees** — how much of that year's money is owed regardless of release.

## Cap hit

```
capHit(year) = baseSalary(year)
             + rosterBonus(year)
             + signingBonus / min(contractYears, 5)
             + likelyToBeEarnedIncentives(year)
```

## Dead money

When a player is released or traded, all **remaining unamortized signing bonus
proration accelerates into the current year**. Guaranteed base salary still owed also
counts.

```
deadMoney = remainingProration + guaranteedSalaryStillOwed
capSavings = capHit − deadMoney          // can be negative
```

A **post-June-1 designation** splits it: the current year keeps only this year's
proration share, and *all* remaining proration hits the following year. Teams get a
limited number of these per year, and the cap relief doesn't arrive until June 1 —
which is a real strategic tradeoff, not a free option.

## Team cap space

```
capSpace = leagueCap
         + carryoverFromLastYear
         − Σ capHit(activeContracts)
         − Σ deadMoney
         − practiceSquadCharges
```

Teams must be cap-compliant at the start of the regular season. This is a `FMCore`
invariant with a checker; the AI roster manager must be able to get compliant by
cutting, restructuring, or extending.

## Restructures

Converting base salary into a signing bonus lowers the current year's hit by spreading
the converted amount over the remaining years (max 5). It creates cap room now and more
dead money later. The AI should use it, and overusing it should produce the classic
cap-hell death spiral — that's a feature, and a good teacher.

## Player movement

- **Rookie contracts** — 4 years, slotted by draft position. First-rounders carry a
  fifth-year team option.
- **Unrestricted free agent (UFA)** — 4+ accrued seasons and an expired contract. Free
  to sign anywhere.
- **Restricted free agent (RFA)** — 3 accrued seasons. The original team can tender at
  one of several levels, each with a matching right and, at higher tenders, draft-pick
  compensation.
- **Franchise tag** — one per team per year. A one-year deal at roughly the average of
  the top five salaries at the position, or 120% of the player's prior cap hit,
  whichever is greater.
- **Waivers** — released players with fewer than 4 accrued seasons pass through
  waivers; claiming priority runs in reverse standings order.
- **Trades** — must leave both teams cap-legal. Trading a player accelerates his
  proration onto the *trading* team, which is why big contracts are hard to move.

## Rookie draft

7 rounds. Order is reverse standings, with playoff results breaking out the back end,
plus compensatory picks awarded for net free-agent losses. Picks are tradeable assets
and the AI needs a pick-value chart to evaluate trades — a smooth, steeply decreasing
curve where the top of the first round is worth several times the bottom of it.

## Test this hard

Cap math is rule-based, deterministic, and easy to get subtly wrong — the ideal unit
test target. Cover at minimum:

- Proration with contracts of 1, 3, 5, and 7 years (the 5-year cap is the trap).
- Dead money on release in year 1, a middle year, and the final year.
- Post-June-1 split across both affected years.
- Restructure math, including a restructure of an already-restructured deal.
- Trade acceleration onto the correct team.
- Cap space going negative and the compliance checker catching it.
- Franchise tag valuation when the top-5 average and the 120% rule disagree.
