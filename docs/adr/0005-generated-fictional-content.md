# 0005. Generated fictional players and teams

**Status:** Accepted
**Date:** 2026-09-08

## Context

A football management game needs leagues, teams, and thousands of players. There are
three ways to get them: license real ones, hand-author fictional ones, or generate
them.

Real names and likenesses are the genre norm and the thing players ask for first.
They are also licensed by the league and the players' association, unavailable at any
price to an indie developer, and a takedown risk if used without permission — including
via "community roster" workarounds, which shift the liability but don't remove it.

Hand-authoring 1,700 players is weeks of content work that has to be redone every time
the ratings schema changes, and it's static: everyone who plays gets the same world.

## Decision

All content is **fictional and procedurally generated from a seed**: player names,
biographies, colleges, ratings, teams, cities, colors, and stadiums. We will not ship
real names, marks, or likenesses, and we will not build an import path for them.

## Consequences

- No licensing exposure, no legal review, no takedown risk. For a solo-scale project
  this is the difference between shipping and not.
- Scouting becomes a real mechanic. In a licensed game everyone knows the top draft
  pick before the draft; in a generated world the fog is genuine and the draft is the
  most interesting part of the offseason.
- Infinite replayability. A new seed is a genuinely new world.
- Content scales with the ratings schema for free — add a rating, regenerate.
- **The cost is the cold start.** A generated roster has no emotional hook; nobody
  cares about a player they've never heard of. This is the real risk of the decision,
  and it's addressed with craft rather than licensing: names must sound plausible
  rather than randomly assembled, generated players need distinguishing traits and
  narratives, and the game must surface storylines (a late-round pick breaking out, a
  rivalry, a decline) so attachment forms through play.
- Some portion of the potential audience will bounce off the absence of real teams.
  Accepted.

## Alternatives considered

**Licensed real content.** Not available to us. Not a real option.

**Ship fictional, support community roster imports.** Gets real names in front of
players while keeping them out of our binary. Rejected: it's a thin liability shield
we'd be knowingly building for that purpose, and it undercuts scouting — the whole
draft loop assumes the player can't look up the answer.

**Hand-authored fictional leagues.** More control over flavor and a curated,
memorable starting world. Rejected on cost and on replayability; a fixed world is
played once. We may hand-tune the *generator's* name pools and archetypes, which gets
much of the flavor benefit at a fraction of the cost.
