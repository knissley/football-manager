# 0015. Order the pre-snap exchange, and say what each step may read

**Status:** Proposed
**Date:** 2026-09-16

## Context

[ADR-0014](0014-decide-from-what-the-decider-can-see.md) decided that a decision may not
read what its real-world decider could not know at that moment, and settled the one case
that forced it: the defensive package may not see the play call. It left open the question
it raised — what the defence *may* see, and when, and what the offence may see back.

[#229](https://github.com/knissley/football-manager/issues/229) measured the exchange the
engine plays today, in [audit-pre-snap-exchange.md](../audit-pre-snap-exchange.md). It is
one-way and it is one step: the offence draws a concept, then a grouping that does not
follow from the concept; the defence draws a package from the grouping; the defence then
draws its call from the down, distance, score and clock, reading neither the grouping nor
its own package; and the offence never looks at anything. On the snaps where neither
caller takes a situational branch, the two calls carry no information about each other.
The sport's run share on first and ten from eleven personnel swings sixteen to seventeen
points with the box it faces, from ADR-0014's own counts; the engine's swings zero. The
package is redrawn on every snap whatever the offence's tempo.

Four issues in the report would each build one step of the exchange. Filed without a
stated order, each decides the order for itself and the next reader of `GameSimulator.step`
has to reconstruct it from the code again, as the audit did. And a step built out of order
can be a violation of ADR-0014 that looks like a feature: a check that reads the coverage
is clairvoyance with a football name.

## Decision

**The moment before the snap is an ordered exchange, and every step says what its decider
may read.** The order is the sport's, and it binds every caller — the baseline one now, a
coordinator with a gameplan later.

1. **The offence declares.** One decision: a concept, a tempo, and the grouping that runs
   the concept. The grouping follows from the concept, because the play call in the huddle
   is one call. Reads the situation and the class. Reads no defensive value.
2. **The defence substitutes**, as an answer to the offence's substitution rather than as a
   fresh draw on every snap. Reads the grouping, the down, the distance, the yard line, the
   clock and the score. Never the concept (ADR-0014). When the book constrains a defence
   substituting against tempo, that constraint lives here, cited; until the reference
   carries Rule 5 Section 2 it is stated as practice.
3. **The defence calls** coverage, rush, front, run fit and disguise. Reads everything step
   2 read, plus the package it has just chosen. Never the concept.
4. **The offence may check.** Having seen the eleven on the field and what the defence
   shows, it keeps its concept or re-draws it. Reads the package, and the declared front
   unless the call is disguised. **Never the coverage, the rush, or the run fit**: those are
   what the defence is hiding until the snap, and a check that reads them has read the
   call. A check is a caller decision and goes on the record as one.
5. **The snap.** The resolver reads both calls whole.

Two things are placed by this order without being built by it. **Disguise** is the defence
withholding the front, and later the shell, from step 4 at a cost the resolver charges.
**Motion** is the offence forcing the defence to show them, at the cost the penalty model
already charges. Both plug into step 4 when they exist and change nothing above it.

The test a reader applies is ADR-0014's, one step at a time: at this step, would this
decider know this? A value the engine has already drawn is not knowable because it has
been drawn.

## Consequences

- **Every step is a draw**, so building any one of them regenerates the goldens and
  resamples every row; #218's substitution moved twenty-one verdicts inside the noise
  floor and none beyond it, which is the expected cost per step. The check should draw from
  the play's own stream after the package, so a change to it moves nothing before it.
- **The carries figure becomes honestly reachable.** ADR-0014 left eleven personnel's
  four-back carry share at 13.8 / 14.6% against the sport's 18.8 / 18.3% because a draw
  over snaps cannot see the concept. A check at step 4 reads the box, which the offence
  can see, and moves the run share with it. Until M2's opponent model lets the defence
  anticipate at steps 2 and 3, **the whole of that swing is carried by the offence's
  check**, and the record will say the offence chose what in the sport the defence mostly
  forced. That is the wrong mechanism carrying a right number, and it is accepted here on
  the condition that the ADR and the row's note say so, and that M2's anticipation takes
  its share when it lands.
- The `PlayCaller` protocol grows a method for step 4, and the record grows a
  `DecisionKind` for the check, through a factory and a contract-test arm (#177).
- Step 2 as an answer rather than a per-snap draw **moves `packageBase` and
  `packageNickel`**: the feed's per-snap conditional already contains the sport's
  substitution constraint, and applying it per substitution changes the marginal. Those
  rows are re-read after that lands, not retuned before it.
- `defensiveCall(for:)` at step 3 gets the grouping and the package it discards today. That
  is #225's rewrite of the defensive caller, and this order is a constraint on it.
- What each step may read is now written down, so a future caller with a gameplan or a
  tendency model is checked against a list rather than against the previous implementer's
  reading of the code.

## Alternatives considered

**Leave it as it is: one concept, one package draw per snap, no check.** Simplest, and
the three marginal rows sit in band. Rejected because the run share cannot respond to the
box at all, tempo holds nobody on the field, and every later step would be built against
an order nobody wrote down.

**Let the check see the coverage.** It closes the vulnerability model at once — the offence
attacks what the call concedes — and `CallVulnerability` was written for exactly that
reader. Rejected as clairvoyance: the shell is what the defence hides until the snap, and
an explanation that the quarterback checked into the seam because the call was cover 3 is
a lie with a citation. The front is different, because it is shown; disguise is the dial
that hides it.

**Condition the package draw on the concept.** Rejected by ADR-0014; recorded here only
because it is the alternative each new step will be tempted by.

**The defence calls first, or both call simultaneously.** Symmetrical and easy to
implement. Rejected because the sport's order is the offence's: the grouping is declared
by jogging on, and the defence answers it. A simultaneous draw is the checkers the audit
measured.

**Build the exchange as one draw of a joint (concept, package) from the feed's joint
distribution.** Reproduces every cross-tabulation at once. Rejected because a joint draw
has no decider, so nothing in it can be explained, and ADR-0007 makes the explanation the
product.
