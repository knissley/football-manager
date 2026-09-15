# 0014. Decide from what the decider can see

**Status:** Accepted
**Date:** 2026-09-15

## Context

[#218](https://github.com/knissley/football-manager/issues/218) made the defensive
package a **draw** from the participation feed's own P(package | grouping, down) instead
of a function of the receiver count. Its *Done when* named a target measured on
**carries**: eleven personnel meets a four-back front on 18.8% (2023) and 18.3% (2024) of
its first-and-ten designed carries, against the engine's 0.3%.

The feed answers the same grouping differently depending on what the snap turned out to
be. Both seasons, first and ten, eleven personnel against a four-back front:

| population | 2023 | 2024 |
| --- | ---: | ---: |
| designed carries | 18.8% | 18.3% |
| dropbacks | 10.8% | 11.0% |
| all snaps | 14.5% | 14.2% |

Those are one defence substituting once, sorted afterwards by an observer who has seen the
snap. The defence chose before that sort existed.

In the engine the caller is asked for the package **after** the offensive concept has been
drawn. So the carries figure was *available*: condition the draw on the concept and the
row closes at the number the issue wrote down. Nothing in the tree stopped it, and the
constant would have carried a real citation to a real release.

The question nobody had answered in general is whether that is allowed. It recurs on every
caller issue, with the easiest-to-reach target arguing for itself each time.

## Decision

**The engine may not let a decision depend on information the real-world decider would not
have at the moment it decides.** It binds both sides of the ball and every layer that
decides anything — the play callers, substitution, protection, a coach's roster move.

The test a reader can apply, before writing the input into a decision: **at the moment
this decision is made, would the real decider know this?** A defensive coordinator
substituting a package knows the personnel that jogged on, the down, the distance, the
yard line and the clock. He does not know the play call, because it has not happened yet.

Two consequences of the rule, both load-bearing:

- **A drawn value is information.** That the engine has already drawn the concept, and
  holds it where the caller could read it, does not make it knowable. Order of evaluation
  inside a snap is an implementation detail and confers nothing.
- **Where a sourced rate is measured on a population the decider cannot identify at
  decision time, the engine draws over the population he can identify**, and the subset's
  realised rate is *reported* rather than targeted. For the package that is the snap
  marginal, 14.5 / 14.2%: the engine lands at 13.8 / 14.6% on carries, and P(package |
  snap) is by construction the run/pass mixture. The residual is anticipation the engine
  does not model, named as a gap rather than closed by a number.

This generalises [decision 42](../design-decisions.md#ai-play-calling) — the defence never
sees the call — from the tendency model, which does not exist yet, to every draw the
engine already makes.

## Consequences

- **A target derived from a post-hoc population can become unreachable, and a *Done when*
  written against one is wrong rather than merely missed.** #218's second item was exactly
  that. The cost was real and was paid in process: a merge as `Refs` rather than `Closes`,
  a reopened issue, a question written up, and an owner decision — for a row whose
  mechanism was never in dispute.
- **The engine will sometimes read `OFF` on a row it could trivially close.** When the row
  is measured on a subset the decider cannot see, the honest move is to report the value
  against the population the caller draws over, leave the row out of band, and say why.
  That is a verdict the harness prints and nobody gets to fix.
- Filing gets a new obligation: a target names the **population** it was measured on, and
  a reviewer checks that the decider can identify that population before the snap.
- Every causal account the interrogation layer gives is structurally honest, which is the
  product ([ADR-0007](0007-event-stream-contract.md)). An explanation assembled from a
  decision that read the other side's call would be fiction with a citation on it.
- **This is not an audit.** No sweep for existing violations has been done, and this record
  asserts nothing about what any current decision reads. Where it binds next is known:
  [#225](https://github.com/knissley/football-manager/issues/225) sets how often a defence
  blitzes, and the same boundary governs what that may condition on;
  [#224](https://github.com/knissley/football-manager/issues/224) concerns what a zone
  blitz is worth.

## Alternatives considered

**Condition the defensive draw on the offensive concept.** The appeal is genuine: it
closes #218's *Done when* as literally written, it reaches a rate derived from the release
rather than chosen, and the code would read like the derivation it came from. Rejected as
clairvoyance. The rate is real and the only way to reproduce it is to hand the defence the
play call, which makes every later explanation of why the box was light a lie.

**Let the offence re-check its concept against the box it sees.** Not rejected on
principle — the box is observable, so a check at the line *moves the boundary rather than
crossing it*, and it is plausibly the mechanism that produces the carries-versus-dropbacks
spread in the first place. Rejected for now because the engine does not model it: one call
per snap, no check, no audible. If it is ever built, the carry rate becomes reachable
honestly, and this ADR is what says the difference matters.

**Leave the pairing computed from the receiver count, as it was.** No table, no draw, and
the three marginal rows — `personnel11`, `packageNickel`, `packageBase` — were already
`ok`. Rejected: that is #218's whole finding. Eleven personnel met a four-back front on
0.2% of first-and-ten designed carries against the sport's 11.0 / 9.8%, three graded yards
per carry rows sat behind a joint that did not exist, and correct marginals over a wrong
joint is the shape of a bug that grades green.
