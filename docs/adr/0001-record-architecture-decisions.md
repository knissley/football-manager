# 0001. Record architecture decisions

**Status:** Accepted
**Date:** 2026-09-08

## Context

This project will be built over a long stretch, in sessions separated by days or
weeks, by a human and by Claude — which starts each session with no memory of the last
one. A design conversation that isn't written down did not happen. The specific
failure mode we're avoiding: re-deciding the same question differently each time and
ending up with a codebase whose parts disagree about their own premises.

## Decision

We will keep architecture decision records in `docs/adr/`, numbered sequentially,
using the template in this directory. ADRs are immutable once accepted; a reversal is
a new ADR that supersedes the old one.

The bar is the one in [the README](README.md#when-to-write-one): hard to reverse,
non-obvious, or the result of choosing between real alternatives.

## Consequences

- Design intent survives across sessions and contributors, which matters much more
  here than in a project with a continuously present team.
- Some decisions get written up that turn out not to have mattered. Acceptable — the
  cost of an unnecessary ADR is ten minutes; the cost of a missing one is a rewrite.
- The index in the README must be updated with each new ADR, which is a small
  maintenance burden and the thing most likely to be forgotten.

## Alternatives considered

**Design docs only.** The `docs/` files describe how things *are*, which is what a
newcomer needs, but they don't preserve why alternatives were rejected — so rejected
options keep coming back.

**Commit messages and PR descriptions.** The rationale exists but isn't findable. Nobody
greps six months of history before making a design call.

## Amendment 2026-09-09 — the body is what is immutable

The decision above says ADRs are immutable once accepted. In practice one was not:
[ADR-0003](0003-deterministic-seeded-simulation.md) grew a whole section after acceptance,
recording how the determinism guarantee actually got broken — a thing the original could
not have known and that would have been lost if the only options were to rewrite the body
or to write a reversal of a decision nobody wanted reversed.

The rule is therefore narrower than this ADR states it, and [README.md](README.md) carries
the current wording: the **body** of an accepted ADR is immutable, a dated `Amendment`
section may be appended, and a reversal is still a new ADR that supersedes the old one.
This ADR's body is left as it was written, which is the rule demonstrating itself.
