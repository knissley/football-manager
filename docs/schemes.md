# Schemes and team identity

**Status: partly built, sections marked.** `Scheme`, `SchemeFit` and generation's
`SchemeIdentity` are built, teams are generated with an identity and rosters are built
for it, and the resolver reads fit. **Familiarity is not built**: `SchemeExperience`
exists as a type and nothing reads it, because a decay-and-rebuild mechanic needs a
season loop (M3) to mean anything. Changing identity, and what it costs, is M7.

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

**Designed, not built.** `SchemeExperience` is a type nothing reads. It needs a season
loop (M3) before decay and rebuild mean anything.


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

Identity shapes a generated roster in **two separate ways**, and conflating them
would be wrong.

**Where the talent went.** A power-run club has invested in its line and its back
and not in a quarterback. This moves the *ceiling* a position generates at, by a
few points either way — enough that identity is legible on a roster, not so much
that a run-heavy team cannot employ a competent passer at all.

**What kind of player.** Within a position, a gap team's guards are maulers and a
zone team's are athletes. This biases the *shape* of the ratings, and the overall
is still corrected to its target afterwards — so fitting the scheme shows up as a
bonus in that scheme rather than as free rating points.

A thirty-two team league at seed 67, four rows picked out of it:

```
TEAM OFFENSE     DEFENSE          STR  MEAN   QB   RB    OL   WR   FIT
12   vertical    press blitz     -2.3  64.4   81   72  67.0   70   1.1   off built for west coast
14   air raid    bend/break      +3.0  65.6   78   72  75.7   74  -2.4   off built for vertical, def built for press blitz
24   air raid    3-4 okie        +6.0  69.1   94   79  72.3   90   1.0
25   power run   3-4 okie        +4.1  66.6   81   81  76.2   79   1.6
```

Regenerate the whole table with `swift run worldgen --seed 67 --teams 32 --show league`.
`STR` is the strength offset the club was drawn at, in overall points either side of the
league's middle; `FIT` is the mean scheme fit of its roster.

Team 25 is a power-run club: a back and a line, and a quarterback who is merely
adequate — nothing about it was assembled to throw. Team 24 runs an air raid: a
94-rated passer and a 90 receiver, a thinner line, and a fit of 1.0 saying the
roster suits what the club does with it. Same league, same generator,
recognisably different clubs.

Teams 12 and 14 are **deliberate mismatches** — five of the thirty-two here,
against a design rate of twelve percent. Team 12's is the mild kind: vertical
shots run by a roster built for a west-coast offence, both of them
quarterback-led, and its fit is unremarkable at 1.1. Team 14 is the interesting
one. It is an air raid whose offence was assembled to take vertical shots and
whose defence was built to blitz, now playing a soft two-high shell, and its fit
of -2.4 is the worst in the league and the only negative one in it.

That mismatch is a story rather than a generation flaw. It is a team that ought
to change, a good AI will, and it puts the trade market's logic into the world on
day one — as well as being the player's own situation, arriving from the other
side.

## Build order

1. ✅ Composable schemes with named families, in `FMCore`.
2. ✅ Fit as weight deltas, with `effectiveOverall` and a fit delta to display.
3. ✅ `SchemeExperience`: per-component familiarity, install and mid-season costs.
4. ✅ Team identity in generation, and rosters built to match it.
5. Proficiency feeding the AI play-caller's decision quality.
6. Scheme fit feeding play resolution.
7. AI teams choosing a scheme that suits their talent.
