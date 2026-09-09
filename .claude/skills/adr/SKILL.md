---
name: adr
description: Write an architecture decision record for this project. Use when a design decision has been made that is hard to reverse, non-obvious, or chosen over a real alternative — or when the user says "write an ADR", "record this decision", or asks to document why something is built the way it is.
---

# Writing an ADR

An ADR records a decision and, more importantly, **why the alternatives lost**. The
docs in `docs/` describe how things are; ADRs preserve the reasoning so nobody
re-litigates a settled question — or reverses it without knowing what they're giving up.

## Steps

1. **Check it needs one.** The bar is in `docs/adr/README.md`: hard to undo, confusing
   to a newcomer, chose between real alternatives, or overturns a prior ADR. A naming
   choice or a version bump does not need an ADR. If it doesn't clear the bar, say so
   and offer to note it in the relevant doc instead.

2. **Find the next number.** `ls docs/adr/` — take the highest and add one. Zero-padded
   to four digits.

3. **Read the neighbours.** Skim two existing ADRs for voice and length. They are
   direct, specific, and admit costs.

4. **Write it** to `docs/adr/NNNN-short-imperative-title.md`, following
   `docs/adr/TEMPLATE.md`. Status `Accepted` if the decision is made; `Proposed` if
   you're writing it to have the argument.

5. **Update the index table** in `docs/adr/README.md`. This is the step that gets
   forgotten.

6. **Cross-link.** If the decision is described in `docs/architecture.md`,
   `docs/domain-model.md`, or `docs/match-engine.md`, add a link from there to the ADR.

## What makes these good

- **Context is facts, not preference.** What situation forces a decision? What breaks
  if we don't make one? If the context section reads like an argument for the decision,
  it's the wrong section.

- **Consequences are honest.** Every real decision costs something. An ADR listing only
  benefits isn't recording a decision, it's recording enthusiasm. Name the ongoing tax
  explicitly — "the cost is the mapping layer, and it will feel tedious" is the kind of
  sentence that makes an ADR worth having later.

- **Alternatives get a fair hearing.** State each alternative's genuine appeal before
  the reason it lost. "Rejected because it's bad" is not a reason. If you can't
  articulate why someone reasonable would have chosen the alternative, you haven't
  thought about it enough.

- **Specific over general.** "Doesn't scale" is nothing. "Reading a whole 10-season
  career into memory to show one roster screen doesn't scale" is a reason.

- **Short.** One page. If it's longer, the decision probably contains several decisions.

## Amending

The **body** of an accepted ADR is immutable — context, decision, consequences and
alternatives are the record of what was decided and what it was weighed against. When
practice teaches something the original could not have known (a way the decision got
broken, a case it did not cover, a consequence that landed differently), **append a dated
amendment** rather than editing the body:

1. Add a section at the end of the file headed `## Amendment YYYY-MM-DD`, optionally with
   a short title after an em dash.
2. Say what it adds and why the body could not have said it. Name what was measured.
3. Leave the body exactly as it was, even where the amendment contradicts it. The
   contradiction is the point: it shows what we learned.

`docs/adr/0003-deterministic-seeded-simulation.md` is the worked example.

An amendment is not a reversal. If the decision itself changes, supersede instead.

## Superseding

To reverse a decision:

1. Write a new ADR whose context explains what changed since the original.
2. Set the old ADR's status to `Superseded by [ADR-NNNN](NNNN-....md)`.
3. Update both rows in the index.

The status line and an appended `Amendment` section are the only permitted edits to an
accepted ADR. The rule is stated in `docs/adr/README.md`; keep the two in step.
