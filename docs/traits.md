# Traits

The most personality per line of code in the project, and the place where being playful
and being rigorous point the same direction: **the names are funny, the effects are
honest.**

## What earns a trait its place

> **A trait must do something a rating cannot.**

If *Rocket Arm* is +8 throw power, it should have been +8 throw power — you've given a
number a nickname. A trait justifies itself by being one of four things:

| Kind | Does | Example |
| --- | --- | --- |
| **Conditional** | Active only in a nameable situation | *Clutch* on high-leverage snaps; *Mudder* in the rain |
| **Branch-selecting** | Changes which resolution path runs | *Swim Master* — a different rush move, different timing |
| **Distribution-shaping** | Changes variance, not the mean | *Gunslinger* — same average, wilder tails |
| **Threshold-changing** | Moves a cutoff in the physics | *Sticky Hands* — a wider catch radius |

Every one of those needs a *simulated moment* to attach to. Traits are where the spatial
engine ([ADR-0006](adr/0006-spatial-simulation.md)) pays its rent in fun.

## Weight and scale

Ratings say how good he is. **Traits say what kind of player he is.** Two 78-rated
receivers should play noticeably differently.

- Catalogue of roughly 60–100 traits.
- Most players carry one to three; some carry none, a few carry four.
- Bad traits are as common as good ones, and just as mechanical.
- Rarity tiers, so a genuinely unusual trait is a thing you notice on a scouting report.

## Discovery

Traits are hidden and revealed through play, by **inference from the event stream with the
evidence attached** — *he's caught 8 of 9 contested targets.* The fifth use of the game's
signature idiom, and nearly free given the analysis layer already exists.

### Belief is per observer

Every team keeps its own `TraitBelief` per player and trait: **unknown → suspected →
confirmed**, from evidence it could actually have seen.

That's what grounds the trade asymmetry ([decision 36](design-decisions.md)) in something
concrete. You see your own players in practice every day, so you confirm faster. A
division rival who plays you twice a year learns from game tape alone — but over years, he
learns. Sometimes before you do.

### Staff suspect before the maths confirms

A position coach or scout with the right specialty can flag a hunch ahead of statistical
confirmation. **Their hunches are graded like everything else**, so a coach who keeps
saying *this kid has it* and keeps being right becomes someone you learn to trust — and
one who doesn't, doesn't.

### A trait that never fires stays hidden

Your backup quarterback's *Ice in the Veins* is unknown because he has never taken a
high-leverage snap. Playing him is how you find out, and that is a real football decision
with a real cost.

## Traits change

Through the `DevelopmentEvent` stream ([ADR-0009](adr/0009-event-sourcing-by-default.md)),
so ageing is transformation rather than only decline:

- A burner loses *Track Speed* at 31 and gains *Savvy Route Runner* at 33.
- Coaching can add technique traits — a rusher who finally learns the counter.
- **Injury can add negative traits.** He was never quite the same after the knee. Brutal,
  true, and dramatic.

This is also the obvious job for the deferred development currency: adding, honing, or
buying out traits.

## Starter catalogue

Names are football vernacular played for laughs, never random-generator whimsy. Effects
are the four kinds above.

**Quarterback**
*Rocket Arm* (threshold — shorter ball flight, shrinks the coverage window) ·
*Quick Release* (threshold — decision to release, beats pressure by fractions) ·
*Gunslinger* (distribution — more big plays and more interceptions, same mean) ·
*Field General* (conditional — faster pre-snap read against disguise) ·
*Escape Artist* (branch — scramble path where others take the sack) ·
*Ice in the Veins* / *Deer in Headlights* (conditional — high leverage) ·
*Happy Feet* (bad, conditional — accuracy collapses on a short pressure clock) ·
*Checkdown Charlie* (bad, conditional — bails early) ·
*Statue* (bad, threshold — scramble effectively unavailable)

**Running back**
*Hurdler* · *Jump Cut* (branch — distinct tackle-break paths) ·
*One Cut* (conditional — thrives in zone, ordinary in gap) ·
*Human Bowling Ball* (branch — short-yardage contact) ·
*Third Down Back* (conditional — protection and receiving) ·
*Butter Fingers* (bad, threshold — fumble on contact) ·
*Dancer* (bad, distribution — dances behind the line, more negative plays)

**Receiver and tight end**
*Sticky Hands* (threshold — catch radius) · *Separator* (threshold — sharper breaks) ·
*Boxer* (conditional — contested catches) · *Slippery* (branch — yards after catch) ·
*Chain Mover* (conditional — third down) ·
*Alligator Arms* (bad, conditional — shrinks over the middle with a defender closing) ·
*Body Catcher* (bad, threshold — narrower effective radius) ·
*Diva* (bad — targets and morale, not physics)

**Offensive line**
*Anchor* (threshold — resists bull rush) · *Quick Feet* (conditional — versus speed) ·
*Mauler* (conditional — gap-scheme run blocking) · *Pancake Artist* (branch) ·
*Whiff Prone* (bad, distribution — wild variance in pass sets) ·
*False Start Merchant* (bad, conditional — discipline in loud stadiums)

**Pass rush**
*Swim Master* · *Bull Rusher* · *Spin Doctor* (branch — distinct moves and timings) ·
*Motor* (conditional — no late-game decay) ·
*Jump the Snap* (distribution — earlier get-off, more offsides) ·
*One Trick* (bad, conditional — **effectiveness drops once the tackle has seen the move
twice**, which plugs straight into in-game opponent adaptation)

**Coverage**
*Mirror* (threshold — man separation) · *Ball Hawk* (conditional — interception threshold) ·
*Zone Eyes* (conditional) · *Press Specialist* (conditional) ·
*Grabby* (bad, distribution — pass interference and holding) ·
*Toast* (bad, distribution — occasionally, spectacularly beaten)

**Linebacker and front seven**
*Sideline to Sideline* (threshold — pursuit) · *Thumper* (conditional — short yardage) ·
*Green Dog* (branch) · *Missed Tackle Machine* (bad, distribution)

**Universal**
*Iron Man* / *Glass* (threshold — injury) · *Gym Rat* (development rate) ·
*Mentor* (development — lifts young players at his position, feeding the
[mentorship lever](design-decisions.md)) · *Big Game Hunter* (conditional — playoffs) ·
*Slow Starter* (conditional — early season) · *Homebody* (bad, conditional — road games) ·
*Cheap Shot Artist* (distribution — penalties) ·
*Coach Killer* (bad — locker room, not physics)

## Rules that keep it honest

- **Effects are seeded and deterministic**, like everything else in the sim.
- **A trait never modifies an outcome after the fact.** It changes an input, a branch, or
  a threshold *before* resolution. No fudge factors.
- **Every trait is testable in isolation**: same seed, same situation, trait on versus
  off, with the difference showing up where the trait claims it should.
- **Bad traits are never hidden from the engine**, only from observers. The physics always
  knows.
- **A trait reveal is a `Finding`**, so the news layer can run with it: *the league has
  figured out that their rookie corner cannot tackle.*

## Build order

1. The `Trait` type and the four hook kinds, wired into resolution.
2. Ten traits, one of each kind across a few positions — enough to prove the hooks.
3. `TraitBelief` per observer, with evidence-based confirmation.
4. Staff hunches, with tracked accuracy.
5. The full catalogue.
6. Gain and loss through `DevelopmentEvent`.
