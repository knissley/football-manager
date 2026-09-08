# 0002. SwiftData, offline-first, no backend

**Status:** Accepted
**Date:** 2026-09-08

## Context

A career is a large, highly relational, long-lived dataset: thousands of players,
their contracts, a decade of statistics, and a season's play-by-play. It needs to
persist across app launches, load fast, and survive schema changes as the game grows.

The product is single-player ([vision](../vision.md#what-this-is-not)),
which means nothing about the core experience requires a network. Building a backend
anyway would add accounts, sync conflict resolution, server cost, an API surface,
and a privacy policy — before the game is fun.

## Decision

We will persist careers with **SwiftData in a local on-device store**, and ship no
backend in 1.0. The app works fully offline, with no account and no network calls.

The SwiftData layer is confined to `FMPersistence`, which maps explicitly between
`@Model` classes and `FMCore` value types. Nothing else in the codebase imports
SwiftData.

## Consequences

- No accounts, no server bill, no sync bugs, no privacy policy beyond "we collect
  nothing." App Store review and the privacy nutrition label get much simpler.
- Careers live on one device. Losing the phone loses the career — mitigated later by
  optional CloudKit sync, which SwiftData supports without restructuring, provided we
  keep the model CloudKit-compatible (no unique constraints, all attributes optional
  or defaulted). We will keep it compatible even though we aren't enabling it.
- Explicit struct↔model mapping is real boilerplate, paid on every domain type. In
  exchange the domain model changes freely without a migration on every milestone,
  and the sim stays framework-free ([ADR-0004](0004-pure-swift-domain-core.md)).
- SwiftData is comparatively young; if we hit a wall on performance with large object
  graphs, the mapping boundary means we can swap `FMPersistence` for GRDB or raw
  SQLite without touching the game.
- iOS 18+ minimum deployment target.

## Alternatives considered

**Core Data.** More mature, better-documented performance characteristics at scale,
and a real consideration given the object-graph size. Rejected because SwiftData's
value-type-friendly API fits the codegen-free style we want, and the `FMPersistence`
boundary makes this a reversible decision rather than a permanent one.

**Codable JSON files.** Trivially simple and fully deterministic, which is appealing.
Rejected on load time and memory: reading a whole 10-season career into memory to show
one roster screen doesn't scale, and we'd end up writing an index — i.e. a database.

**A cloud backend from day one.** Only justified by multiplayer, which is explicitly
out of scope. Every hour spent on it in 1.0 is an hour not spent on the match engine.
