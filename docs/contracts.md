# Contracts and negotiation

**Status: partly built, sections marked.** The *structures* are built: `Contract`,
`ContractYear`, `ProratedBonus`, `DeadMoney` and the cap arithmetic live in `FMCore` with
their own tests, and generation writes real contracts. **Negotiation is not built at
all** — no agent, no offer, no counter, no probing. Everything from
[You negotiate a structure](#you-negotiate-a-structure-not-a-number) onwards that
describes a conversation with an agent is M7.

The cap is the game's central constraint, and negotiation is how you fight it. The
failure mode to avoid is the genre standard: a slider where more money means yes, or a
minigame with a sweet spot you learn once and never think about again.

## You negotiate a structure, not a number

**Designed, not built** — and so is every section below it. The structures exist as types
in `FMCore`; the negotiation is M7.


The same total value can be built a dozen ways, and players want different ones.

| He is | He wants |
| --- | --- |
| 32 and declining | **Guarantees** — he may never see year three |
| 25 and ascending | A **short deal**, so he hits the market again in his prime |
| Leveraged, with a family | **Cash now** — signing bonus over base salary |
| Chasing a ring | To **stay somewhere good**, at a discount |
| Proud | The **headline number**, even structured badly |

So the real problem is *find the structure that satisfies him at the least cap pain to
you*. That's an optimization against hidden preferences, it's specific to football rather
than a generic haggle, and it puts your interests in direct opposition to his: you want
cap-friendly, he wants guaranteed. Restructures, proration, and the slow walk into cap
hell all fall out of that tension
([salary cap reference](../.claude/skills/football-domain/references/salary-cap.md)).

```
ContractPreferences        hidden, seeded per player, fixed
  security      guaranteed money over total value
  cashNow       signing bonus weighting
  term          long-term security vs. a prove-it deal
  winning       willingness to discount for a contender
  role          starting job, touches, a specific job description
  loyalty       discount for staying
  ego           headline number, being top-N at his position
  marketAnchor  how hard he holds to comparable deals
```

## Counters leak preferences

The agent evaluates your offer against a utility function over those weights. His counter
is roughly the nearest structure that clears his reservation utility — which means **the
delta between your offer and his counter points along his preference gradient.**

Move guarantees but not total, and he accepts: security was the axis. Shorten the term and
he counters longer: he wants safety, not a bet on himself.

That makes a negotiation readable, and it's the same information game as scouting and
gameplan hypotheses. It's also cheap to compute — a utility function plus a small
constrained search over structure space.

**But the counter is distorted by the agent's style.** An aggressive agent asks for more
than he needs; a pragmatic one negotiates close to true. So you're reading a signal
through a *systematic* bias, exactly as with scouts ([decision 64](design-decisions.md)),
and learning your league's agents is the same multi-season meta-game.

### Staff intelligence

Your negotiator gives you a partial read before you open — *he wants three years, not
five* — from his relationship with that agent. Rewards staff investment and stops the
information game being pure trial and error for a player who hasn't learned to read
counters yet.

## Probing has to cost something

Without friction, you binary-search the reservation value and it's a slider again.

- **Preferences are seeded per player and fixed.** No re-rolling by reopening talks.
- **Agents have finite patience.** Every round spends some.
- **Lowballs insult.** An offer far under market costs patience and damages the
  relationship, sometimes permanently.
- **The market moves under you.** A comparable player signing elsewhere shifts his anchor,
  so stalling carries real risk.
- **Counters are noisy**, not a precise reveal.

## Agents are characters

Named, persistent, with styles and memory — the same machinery as writers and scouts, used
a third time.

An agent represents multiple players across the league. Lowball him and his other clients
are harder to sign. An agent holding three of your starters has genuine leverage over you
in a way no single negotiation does. **Who represents a player is real information**, and
worth checking before you open.

## Building an offer

Two tiers, the same pattern as [gameplan](gameplan.md):

- **Presets generate structures** — *market deal*, *front-loaded*, *prove-it*,
  *team-friendly with guarantees*. Enough for most negotiations, and each one is readable,
  so it teaches what the levers do.
- **The full structure underneath** — years, base by year, signing bonus, guarantees,
  incentives, options.

The canonical representation is the structure; presets are generators over it. A deeper
authoring surface later is additive.

**Delegation:** hand your negotiator a mandate — *get it done under 18 a year, no more
than 40 guaranteed* — and he executes. A good negotiator lands nearer the reservation
value with less relationship damage. Every deep system in this game has a delegate, and
this is the one that keeps the five-minute path alive when you don't care about this
particular deal.

## Contexts

| Context | Dynamic |
| --- | --- |
| **Extension** | Exclusive window, but free agency looms as his leverage |
| **Free agency** | Competitive bidding; rival offers partially visible |
| **Franchise tag** | The nuclear option. One a year, and it costs the relationship |
| **RFA tender** | Tender level versus matching risk and compensation |
| **Rookie deal** | Slotted. Nothing to negotiate, which keeps draft day clean |
| **Restructure** | You're asking a favour. Cash now for him, future pain for you, and agents remember being asked |

## When it goes wrong

All four consequences are live, and they escalate.

**He walks.** Signs elsewhere, and the cap space doesn't help you this season. Without a
real chance of losing him nothing else has weight.

**Holdout or trade demand.** An unhappy player under contract — usually one whose deal has
fallen below market — can miss camp, sulk through a season, or demand out. Missed camp
costs development and continuity, so a stale contract becomes an ongoing problem rather
than a one-time loss.

**League-wide relationship damage.** An `AgentRelationship` per agent affects starting
patience and willingness to deal. A reputation for fair dealing is a real asset.

**Locker room effects.** A badly handled contract sours teammates, especially around a
leader. This is the one most at risk of feeling mysterious, so it must be **legible** —
the interrogation layer surfaces *three players' morale dropped after the Hendricks
release*, with the evidence attached, exactly like any other Finding.

## Everything is an event

Every offer, counter, signing, restructure, tag and release is a `ContractEvent`
([ADR-0009](adr/0009-event-sourcing-by-default.md)).

Which buys the thing that isn't possible under current-state models: **"how did our cap get
like this?"** walks the actual history — the restructure in year two that bought a playoff
run and the dead money in year five that paid for it. Plus *what did we offer him in
2029*, and every agent relationship's full history.

## Build order

1. Contract structure, cap math, and `ContractEvent` — cap arithmetic is the most
   test-worthy code in `FMCore`.
2. `ContractPreferences` and the agent utility function.
3. The offer/counter loop with patience and insult costs.
4. Presets as structure generators.
5. Agents: identity, style, `AgentRelationship` memory.
6. Delegation by mandate.
7. Free agency bidding, tags, tenders, restructures.
8. Holdouts, trade demands, and legible morale effects.
