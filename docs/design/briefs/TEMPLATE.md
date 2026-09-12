# <The idea, as the football sentence it makes true>

**Status:** proposed | accepted | parked | rejected
**Milestone:** M<n> · **Size:** small | medium | large · **Written:** <date>, from a
`/design-grill` session · **Designer's verdict:** <filled in by the designer, with date>

## The player's decision

What the player chooses, what they see before choosing, what they see after, and how they
could choose wrongly and know it. If there is no decision, say what the player watches
and why that is worth a milestone's room.

## The moment

One scene. The down, the screen, the week. "The player will remember the time when..."

## The football truth

Which rule, which real rate, which real behaviour of coaches and players this rests on.
Cite each by rulebook article and season, or by real-league season and source. Anything
not cited is marked **unverified**.

## Systems touched

Types, modules and files, from reading the code, not from memory. Which layer each change
lives in (rules layer, resolver, caller, record, generation, analysis, UI).

## What the record must carry

The facts a `PlayRecord`, an `InjuryEvent`, a `DevelopmentEvent` or another stream must
carry for this to work, checked against `docs/play-record.md`. For each: **present**,
**derivable**, or **missing**. A missing fact is the most important line in the brief.

## The fun test

How a playtester proves this is fun, or proves it is not: the question they answer, the
thing they do, the number that moves.

## Cost and home

Size, milestone by the roadmap's dependency order, and what it depends on.

## The cut

The version half the size that keeps the moment.

## Contradictions

Decisions by number, ADRs, other briefs. "None found, having searched for <terms>" is an
acceptable answer; "none" alone is not.

## Open questions

Each with the recommendation the session gave and what the owner said.

## What was not checked

Required.
