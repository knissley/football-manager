# Gameplan

**Status: designed.** No `Gameplan` type exists and no rule, tier, directive or
hypothesis is stored or read anywhere in the tree. What exists of the layer below it is
`SituationClass`, the shared situational vocabulary a gameplan rule would key off, and a
baseline caller with no gameplan at all. This arrives with the weekly loop at M4.

The head-coach half of the role, and the weekly decision surface. Gameplan sets the
guardrails your coordinator works inside ([play-calling.md](play-calling.md)) — you
never call plays from here, you decide the room he operates in.

It is also where the interrogation hook touches coaching: a gameplan is a set of
hypotheses about an opponent, and the game grades them.

## Structure

```
SeasonIdentity        your scheme. Set at season start, changes rarely.
      +
WeeklyDeltas          adjustments against this specific opponent.
      ↓
GameplanRuleSet       the canonical compiled form — the only thing the caller reads.
```

Identity plus deltas rather than a fresh plan each week: a light week is a couple of
tweaks, not a blank form, and self-scouting has something stable to measure drift
against.

## The rule set is canonical

Presets and dials are **rule generators**. The play-caller only ever consumes a
`GameplanRuleSet`; it has no idea whether a rule came from a preset, a dial, or was
hand-authored.

```
GameplanRule
  when      situation predicate — down, distance, field zone, score band,
            time band, personnel on the field
  then      effect — bias toward or away from a play family, tempo, protection,
            personnel preference, or a hard prohibition
  weight    soft preference … hard constraint
  source    .preset(name) | .dial(name) | .authored
```

Two things follow from this shape:

**The deep tier is additive.** A composable rule builder isn't a new system — it's an
authoring UI over a representation the caller already evaluates. Adding it later costs
UI work and nothing architectural.

**Presets become teaching.** `source` lets the UI say *this rule came from "Protect the
lead"*, and lets you promote a generated rule into an authored one by editing it. A
preset is a worked example rather than a black box, which is how fan-level literacy gets
taught without a tutorial.

## Tiers

**Tier 1 — presets and dials.** Named plans (*Protect the lead*, *Attack their weak
side*, *Establish the run*) plus a dozen dials: run/pass lean by down, tempo, fourth-down
aggression, blitz rate, coverage shell mix, protection priority.

**Tier 2 — the rule builder.** Direct authoring of `when → then` rules. Not in the first
version; the representation is built for it from day one.

**Your coordinator always proposes.** Each week he offers a plan based on his own
scouting read. The five-minute path is *review and accept*; the deep path is tearing it
apart. The player never faces a blank form, and the proposal itself is a signal — a good
coordinator's plan is worth reading.

## Directives — the keys of the week

Capped at about three, deliberately. These are the specific things you're trying to do to
this opponent.

```
Directive
  subject     your unit or player
  target      their player or unit
  action      attack · avoid · double · chip · shade coverage toward
  weight
  hypothesis  the claim being made, when the player states one
```

`Directive` is first-class so that a deeper per-matchup tier is additive later. The real
cost of that tier is not the schema — it is **conflict resolution** (three directives
weight cleanly into play selection; twenty contradict each other and need a resolution
policy) and **legibility** (three hypotheses make a report card; twenty make a wall). If
bulk directives arrive later, headline keys should stay a small distinct set.

## Hypothesis grading

The novel part, and the reason gameplan belongs to the interrogation hook.

Each key of the week is a claim — *their No. 2 corner is beatable*. After the game,
`FMAnalysis` measures it against the `PlayRecord` stream on two axes:

- **Was it executed?** How often did we actually attack him, versus what we said?
- **Did it work?** EPA and success rate on the plays where we did.

**Graded independently of the result.** You can be right and lose; you can win having
been wrong about everything. Separating "was your read correct" from "did you win" is
what makes this a scientific loop rather than a scoreboard, and it is the thing that
rewards a player for thinking rather than for winning.

## Plan versus execution

Gameplan changes are events ([ADR-0009](adr/0009-event-sourcing-by-default.md)), so
*what was our plan in Week 3* and *how has our identity drifted this season* are ordinary
queries.

Comparing the stated plan against the actual play distribution gives a first-class
readout: **you said run-heavy on early downs; he threw it 62% of the time.** That is
simultaneously self-scouting, evidence about your coordinator, and a reason to either
tighten the guardrails or go hire someone who follows the plan.

## Defensive gameplan

Structurally identical, and built at the same time — not after. Same `GameplanRuleSet`,
same `when situation → prefer/avoid` rule shape, same directives, same hypothesis
grading, same plan-versus-execution drift readout. The difference is vocabulary, and
what a rule is allowed to name.

Where an offensive rule names a play family, a defensive rule names the components of
`FMCore.DefensiveCall` ([play-calling.md](play-calling.md#a-defensive-call-is-data-not-a-label)):

- **Coverage mix** as a range by situation — *quarters or better on early downs*
- **Pressure rate**, and where the extra rusher comes from
- **Front alignment and run fit** — *two-gap on short yardage*, *slant to the tight end*
- **Package thresholds** — *nickel from 11 personnel*, *dime only on third and long*
- **Disguise frequency**, which trades reaction time for a worse quarterback read
- **Matchup assignments** — *travel our No. 1 corner with their No. 1 receiver*

The `when` clause on both sides is a `SituationClass`
([the shared vocabulary](play-calling.md#situational-football)), so *third and long* means
one thing across the whole game. An offensive rule and a defensive rule that both fire on
"late and trailing" are firing on the same snap by construction.

### Rules name a trade, not a best call

Because `CallVulnerability` has no `none` case, a defensive rule that says *never blitz*
is not caution — it is a standing decision to concede the quick game less often and the
run more. The grading layer reports that back as what it was: **you asked for two-high
on third down; they ran for 4.6 a carry on it.** Same readout the offense gets, same
evidence about your coordinator, same reason to tighten the guardrails or go hire
someone else.

## Build order

1. `GameplanRuleSet` and the rule representation — before any UI.
2. A dozen dials generating rules; the caller consuming only the rule set.
3. Named presets as rule generators, with `source` attribution.
4. Directives, capped, and coordinator-proposed plans.
5. Hypothesis grading in `FMAnalysis`.
6. Plan-versus-execution drift.
7. *Later:* the tier-2 rule builder, and bulk per-matchup directives.
