# The draft and scouting

**Status: partly built, sections marked.** Class generation is built and inspectable —
`DraftClassGenerator` produces a three-year pipeline with hidden ceilings, production
carrying independent error, red flags, early declarations and mean-reverting class
strength, and `worldgen --show class` prints it. Everything about *scouting* — biased
observers, the fog, budgets, boards, draft day, retrospectives — is M7 and is labelled
`Designed, not built`.

The most interesting decision in the game, because it's the one where you act on
information you know is wrong.

## What makes it work

Generated worlds make scouting *real*. In a licensed game everyone knows who the best
prospect is before the draft; here nobody does, including you, including the AI, and
including the media. The fog isn't a UI convention — it's the actual state of knowledge.

Three properties hold it together:

1. **You never see truth.** You see estimates, from observers with names and flaws.
2. **Investment narrows uncertainty; it never removes it.**
3. **Your scouts are wrong in *patterns*, not at random** — and the patterns are learnable.

## Where a class comes from

Prospects exist **three years before their draft**, which is what makes multi-year
scouting possible: this year's seniors were watchable as sophomores. A prospect is a
`Player` — the same identifier he carries into the Hall of Fame — with a `Prospect`
record holding the college half. There is no separate prospect type, for the same
reason there is no separate franchise type ([decision 156](design-decisions.md)).

**A cohort is not a draft class.** A cohort is a year group; a class is who is actually
available. A junior who declares leaves next year's cohort and joins this year's draft,
which is what coming out early means. Conflating the two leaves the current draft
missing its best young players.

### Classes are not interchangeable

Some years are loaded, some are barren, and a year can be deep at quarterback and empty
at edge. That is what makes *this is the year to trade up* a real thought, and a
quarterback run a real event.

The variation is **mean-reverting**: a loaded class makes the next few likelier to be
thin, so league talent oscillates visibly and returns to its mean over a decade rather
than drifting somewhere records stop being comparable. Reversion is spread over a window
rather than landing on the following year, because a tidy annual alternation is not
something anybody would believe.

Class *shape* — which positions a year is rich at — is zero-sum, so only overall strength
moves the total. Keeping those separable is what lets
[the conservation law](development.md) be asserted on one number.

### Production is evidence, not a restatement

A prospect's college numbers carry **independent error**. Three things pull them away
from the truth: the team around him, how much he played, and whether the system flatters
him. So a good player on a bad team looks ordinary and a limited one in the right system
looks better than he is.

Context does not overturn a twenty-point ability gap, and should not. What it overturns
is a close call — which is exactly where scouting happens. Without independent error,
production is ability wearing a hat, and the scout who "distrusts small-school
production" has nothing to be wrong about.

### Red flags

Concerns are hidden truth carrying two independent numbers: **severity**, how much it
actually matters, and **visibility**, how readily anybody finds it.

The independence is the design. Correlating them would mean a serious problem is always
an obvious one, and the player who slides for no visible reason would stop existing. The
interesting tail is the real concern nobody has surfaced — knowable years later through
the retrospective.

Character concerns are **football-professional only**: work ethic, coachability, film
study, maturity, scheme buy-in. Everything is about the job. The game invents people, and
inventing conduct allegations about them would buy a more realistic draft broadcast at a
price the rest of the design is not willing to pay ([decision 160](design-decisions.md)).
Medical is the other half, and it is the one that produces the classic late slide.

### Declaring

A projected high pick comes out; a fringe junior goes back for another year and arrives
next season as a different prospect — another year of tape, and a stock that has moved
either way. Seniors never had the choice.

## Scouts are biased observers

**Designed, not built** — and so is every section below it. `Prospect` carries the true
values and the noisy production; nothing observes them through a scout. M7.

Named characters, like the writers ([news-and-narrative.md](news-and-narrative.md)), and
built on the same machinery.

```
Scout
  identity      generated name, background, portrait
  specialty     position groups and regions where his read is sharper
  biases        systematic, not random — overrates athleticism, distrusts
                small-school production, falls for high-motor players
  accuracy      computed from EvaluationEvent history, and visible to you
```

**Bias being systematic is the whole design.** A scout who overrates speed over-grades
fast players *consistently*. Which means, over seasons, you can learn to correct for
him — mentally discount his grades on burners, trust him on technique. Learning your own
staff is a meta-game that takes years to master and costs nothing to implement beyond
being honest about how the noise is generated.

It also makes disagreement content. Two scouts with different biases return different
grades on the same prospect, and adjudicating that is a decision with real texture.

Same signature idiom as everywhere else: **they state claims, the game grades them
against what happened, and you can see the pattern.**

## Investment narrows, but can't be farmed

Estimates are seeded per `(scout, player, depth, collegeSeason)` and fixed
([decision 37](design-decisions.md)). Going deeper doesn't re-roll the noise — it draws
from a distribution with *smaller variance* at the next depth.

So more scouting genuinely tightens the picture, and re-running the same depth on the
same player **within a season** returns the same answer. Without that rule, players
grind re-evaluations and average the error away to find truth, and the entire fog
collapses.

The season is in the key because prospects develop. A grade from his sophomore year has
to be allowed to be wrong about the player he has since become, or a riser could never
be seen and a scout would be stuck forever with his first impression. Across seasons
there is genuinely new tape, so a new draw is honest rather than exploitable
([decision 157](design-decisions.md)).

This does mean watching a player for three years tightens your read on **current
ability** — which is right, and is not a hole. The thing the draft actually gambles on
is hidden on a different axis entirely: [decision 34](design-decisions.md) keeps the
ceiling and the development trait fogged no matter how long you watch. What you can
learn is who he is. What you cannot learn is who he will become.

## Two budgets

**Staff coverage** is automatic. Your scouting department produces baseline grades across
its assigned regions and position groups — this is the org infrastructure you inherit,
build, and leave behind when you take another job
([decision 24](design-decisions.md)).

**Focused spend** is discretionary. You point resources at specific prospects for deep
dives. This is triage: depth on a shortlist versus breadth across the class, decided
before you know which choice was right.

## What you see

Three layers, so the skimmer and the obsessive are both served:

| Layer | Content |
| --- | --- |
| **Card** | Round grade with a confidence band — *2nd–4th, medium confidence*. The decision-relevant summary, and how the job actually talks |
| **Detail** | Attribute ranges that tighten with investment |
| **Report** | Scout prose, attributed to the scout, carrying his voice and his bias |

Measurables from the combine sit outside the fog: a 40 time is *known*, precisely, by
everyone. That's the counterweight that keeps the class navigable — some things you know
exactly, and the things you don't know are the things that decide careers.

## Your board versus consensus

There is a public consensus board — media and league-wide opinion — and your own.

**The gap between them is where the value is.** If your staff has a player two rounds
above consensus, you can wait on him. If consensus is high on someone your scouts dislike,
you can trade down and let someone else take him. Every draft decision is really a
decision about that gap, and about how much you trust the people who produced it.

A combine riser is exactly this in motion: measurables land above expectation, consensus
moves, and a player you planned to get in the third is gone in the first.

## Draft day

A live event. Picks land one at a time on a clock, the board thins, and trade offers
arrive while you're sitting on your pick.

The moments worth building for:

- **The slide.** A player falls well past his consensus grade. Do you take him, or is
  everyone else seeing something you aren't? Occasionally they are.
- **The run.** Four quarterbacks in six picks and your board is suddenly wrong.
- **The offer.** Someone wants to jump you, and their price reflects *their* board, not a
  universal chart — AI teams value picks by their own needs and their own estimates
  ([decision 36](design-decisions.md)), so this is a negotiation rather than a lookup.
- **Your scouts, in your ear, disagreeing.**

Rookie contracts are slotted, so nothing has to be negotiated on the clock.

**The five-minute path:** set your board, delegate, review the results. A rebuild that
takes four minutes a season is a stated requirement, and auto-draft from your own board
is how draft day honours it.

## Retrospectives

Every grade is an `EvaluationEvent` ([ADR-0009](adr/0009-event-sourcing-by-default.md)),
stamped with who said it, when, and at what confidence.

Which makes the payoff possible years later: *your staff had him as a fourth-round grade;
he's a two-time All-Pro, and the scout who liked him was the one everybody else in the
building ignored.* Scout accuracy is computed from exactly this history, so the
retrospective and the staff evaluation are the same query.

## Storylines

Where the draft's whimsy lives ([decision 59](design-decisions.md) — odd things are true
and reported straight):

- The small-school prospect nobody has tape on
- A late medical flag that moves him down everyone's board
- The scout who is obsessed with one player and will not shut up about him
- The riser, the faller, and the player who slides for no visible reason — a reason that
  becomes knowable years later through the retrospective

## Build order

0. ✅ Class generation: the three-year pipeline, hidden ceilings, production with
   independent error, red flags, declarations, and mean-reverting class strength
   (`Packages/FMGeneration/DraftClassGenerator.swift`). Year-over-year rating movement
   rides on the development stream rather than a second progression mechanism built here
   ([decision 125](design-decisions.md)) — the pipeline is shaped for it and it is not
   wired up yet.
1. `EvaluationEvent` and the seeded `(scout, player, depth, collegeSeason)` estimate model.
2. Scouts: specialty, systematic bias, prose voice.
3. The three presentation layers and the consensus board.
4. Staff coverage and focused spend.
5. Auto-draft from a board — the five-minute path first, deliberately.
6. Live draft day, trade offers, the clock.
7. Computed scout accuracy and retrospectives.
8. Storylines.
