# Schemes and team identity

A team plays a certain way, players suit some ways better than others, and
changing identity costs something. The design problem is *which* something.

## The failure this exists to avoid

Tie schemes to coaches, and make coaches available only through a hiring
carousel, and you have gated a tactical decision behind a random market. Draft a
gifted passer onto a smashmouth team and the excitement dies immediately: his
formative years will be spent in an offence that does not throw, and the only
remedy is waiting for a name to appear on a list. Season after season can pass
without one.

That is frustration without agency, which is the worst kind.

## Scheme is yours; the coordinator is how well it is run

The [gameplan](gameplan.md) is guardrails you set, inside which your coordinator
works. **Scheme is the season-level version of exactly that.** You choose it.
Coach quality determines execution, not permission.

So the cost lives *inside* the decision rather than outside it, and there are two
of them behaving very differently.

### Familiarity, which decays

A coordinator who has run west coast for fifteen years runs an air raid worse.
But he can run it, and he gets better at it — 60% proficiency unfamiliar, full
command in four seasons. **A penalty that fades is a completely different thing
from a gate that never opens.**

Proficiency scales his *decision quality*, never his players' ability. A
coordinator out of his depth calls worse plays; he does not make anyone slower
([decision 40](design-decisions.md)).

Familiarity is tracked **per component** rather than per family, which is both
more accurate and more forgiving: a spread coach moving to air raid keeps his
zone-blocking background, while one moving to power run keeps nothing. Sharing
components means sharing familiarity.

### Fit, which does not

A scheme changes **what counts**. A 320-pound mauler guard is an 85 in a gap
scheme and a 72 in a zone one — the same player, differently useful. That cost is
immediate, permanent while he is on the roster, and fixable only by changing
personnel.

Which is the honest answer to the quarterback problem: you *can* switch to suit
him, today, and you can see exactly what it costs on the roster screen.

## How fit works

Schemes are composable — a run-blocking scheme and a passing identity on offence,
a front, coverage shell and pressure rate on defence — with named families as
combinations. Modifiers are defined per *component*, so six offensive families
are combinations rather than six eighteen-position tables. A deeper tier that
lets a coach mix components freely is additive.

Modifiers are **additive weight deltas, not multipliers**. This matters: a
scheme can make a rating *start* counting. A guard's agility carries no weight at
all in a gap scheme and is central in a zone one, and a multiplier on a zero
weight is silently nothing. That exact bug shipped once here before a test caught
it.

Weights are floored at zero and renormalised, so a scheme redistributes emphasis
rather than handing out points — a uniformly rated player scores the same in
every scheme, which is asserted.

**Every scheme de-emphasises something.** A modifier set that only adds emphasis
barely moves anybody once weights renormalise; air raid "wants receivers good at
receiving" is a shrug, not an identity. Air raid wants precision and volume and
actively does *not* want track speed, which is what makes it the opposite of a
vertical offence rather than a louder version of it.

## What it looks like

Two guards and a strong-armed passer, across the offensive families:

| Scheme | Mauler guard | Zone guard | Big-arm QB |
| --- | --- | --- | --- |
| Power run | **84** | 70 | 73 |
| Zone run | 72 | **77** | 73 |
| West coast | 82 | 71 | 69 |
| Spread | 72 | **77** | 68 |
| Air raid | 72 | **77** | 73 |
| Vertical shots | **84** | 70 | **77** |

There is a non-obvious lesson in that table, and it is the sort of thing the
design exists to produce. If you are a power-run team who has just drafted a
big-armed quarterback, the move is **vertical shots, not air raid** — it gains
the passer five points and costs the offensive line nothing, because it still
blocks gap. Switching to air raid would gain the quarterback nothing at all and
cost each lineman twelve.

The obvious change is the wrong one, the right one is cheaper than it looks, and
the roster screen tells you before you commit.

## When you can change

**Freely in the offseason**, with a one-season install cost on top of
familiarity — the transition year real teams visibly go through.

**Mid-season at a steep penalty**, because there is no camp to install it in.
Available, expensive, and occasionally the right desperate call.

## Generation

Generated teams have identities, and rosters are built to suit them: a power-run
club gets maulers and a game manager, not a 99-rated passer.

But only *mostly*. **Occasionally a team's identity clashes with its talent** — a
run-heavy club with a gifted young quarterback — because that mismatch is a
story. It is a team that ought to change, an AI worth anything will, and it puts
the trade market's logic into the world on day one. It is also the player's own
situation, arriving from the other side.

## Build order

1. ✅ Composable schemes with named families, in `FMCore`.
2. ✅ Fit as weight deltas, with `effectiveOverall` and a fit delta to display.
3. ✅ `SchemeExperience`: per-component familiarity, install and mid-season costs.
4. Team identity in generation, and rosters built to match it.
5. Proficiency feeding the AI play-caller's decision quality.
6. Scheme fit feeding play resolution.
7. AI teams choosing a scheme that suits their talent.
