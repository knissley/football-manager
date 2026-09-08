# Vision

## The pitch

You take over a struggling franchise. Over the next decade of in-game seasons you
rebuild it through the draft, free agency, and the cap — and every Sunday you find
out whether your plan survives contact with sixteen other plans. It runs on your
phone, offline, in sessions as short as five minutes or as long as you want.

## Who it's for

People who like the *between-games* part of sports games. The audience that reads
depth charts for fun, argues about cap structure, and would rather build a roster
than throw a spiral. Football Manager and Out of the Park Baseball players who
have never had a great American-football equivalent on iOS.

They are not looking for an arcade game. They want their decisions to be legible:
when the season goes badly, they want to be able to point at the choice that did it.

## Design pillars

**1. Decisions over dexterity.**
There is no gameplay input during a play. You choose personnel, scheme, gameplan,
and situational calls; the sim resolves the rest. Every interaction in the app is
a decision with a tradeoff, not a reflex test.

**2. A simulation you can interrogate.**
When a drive stalls, the app can tell you why — your right tackle lost four
consecutive reps, your third-down conversion rate against two-high is bottom five.
The engine produces structured play-by-play data, not a scoreline with flavor text,
and the UI surfaces the causal chain.

**3. Determinism you can trust.**
Same seed plus same inputs equals the same season, byte for byte. This is a
player-facing promise (no save-scumming ambiguity, replayable worlds, shareable
league seeds) and the foundation of how we test and balance. See
[ADR-0003](adr/0003-deterministic-seeded-simulation.md).

**4. Respect the commute.**
The core loop must be playable in five minutes: check news, handle the week's
decisions, sim the game, review. Long-form planning (draft boards, cap projections)
is available but never mandatory to advance.

**5. Fictional, generated, and yours.**
Every league is generated from a seed. That sidesteps licensing entirely, but it's
also a feature: a world nobody has played before, where scouting actually matters
because you can't look up the answer.

## The core loop

```
Week starts
  ├── News & inbox        (injuries, contract demands, league happenings)
  ├── Roster decisions    (promote from practice squad, sign a street free agent)
  ├── Depth chart         (who plays, and in which package)
  ├── Gameplan            (scheme emphasis, matchup targets, aggression sliders)
  ├── Simulate the game   (watch drive-by-drive, or quick-sim to the result)
  └── Review              (box score, snap counts, grades, what went wrong)
Advance week → repeat → playoffs → offseason
```

The offseason is its own loop: exit interviews, retirements, re-signings, franchise
tags, cap casualties, free agency, the combine, the draft, then camp battles.

## What this deliberately is not

- **Not a play-caller.** No Xs-and-Os play designer, no drawing routes. Scheme is
  chosen at a higher altitude. (Revisit post-1.0 if players ask for it.)
- **Not multiplayer.** Single-player career, on-device, offline. Online leagues are
  a plausible v2 and the architecture shouldn't preclude them, but nothing in v1
  requires a server. See [ADR-0002](adr/0002-swiftdata-offline-first.md).
- **Not licensed.** No real players, teams, logos, or league marks — ever. Generated
  content only.
- **Not free-to-play.** No energy timers, no gacha, no pack-opening. A premium app
  where the fun is the management, not the friction.

## What "good" looks like at 1.0

- A full 10-season career is playable end to end without a crash or a soft-lock.
- Simulated league stat lines land inside realistic ranges — passing yards, sack
  rates, scoring distribution, injury frequency (see
  [calibration targets](match-engine.md#calibration)).
- A week of decisions takes under five minutes; a full game watched drive-by-drive
  takes under fifteen.
- A player who finishes a season can explain, unprompted, why their team's run
  defense was bad.

## Open questions

Tracked here until they become ADRs or roadmap items.

- How much does the app show about hidden attributes? Scouting fog is core to the
  draft, but total opacity on your own roster is frustrating.
- Is there a coaching-carousel meta (you get fired, you apply elsewhere), or are
  you bound to one franchise for the career?
- Do we ship an in-game 2D field view of each play, or is structured text with
  good typography enough for 1.0?
