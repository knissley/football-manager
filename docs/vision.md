# Vision

## The pitch

You take a head coach and general manager job with a franchise that needs rebuilding.
Over a decade of seasons you draft, develop, negotiate, and scheme — and every week
the simulation tells you, in detail, whether it worked. You can blow through a
rebuilding year in a minute or call every snap of a playoff game. When your
third-round quarterback wins a title, the game can show you the exact play, and prove
it wasn't scripted.

## The hook

**A simulation you can interrogate.**

Every football game ever made hands you a result. This one hands you the reasoning:
which lineman lost his rep, how long the pocket held, why the AI called what it called,
what your third-down defense actually does against a spread formation. Not narration
over a dice roll — a spatial simulation where the explanation is the thing that
actually happened.

The narrative payoff — the rivalries, the highlight reel, the Hall of Fame ceremony —
is what makes the sim *worth* interrogating. But the sim comes first. A league that
generates good stories out of a shallow engine is a story generator; a league that
generates them out of an honest one is a sport.

## Design pillars

**1. The engine is honest. The world is playful.**
The physics never wink. Nothing in the simulation is fudged for drama, and no outcome
is authored. Everything *around* it — trait names, the news voice, draft storylines,
mascots with agendas — is allowed to have a sense of humor. "Swim master" and "butter
fingers" are funny names for real mechanical hooks into how a play resolves.

**2. Nothing is unexplainable.**
Every result decomposes. A season record decomposes into games, a game into drives, a
drive into plays, a play into matchups and decisions — and at each level the app can
say what mattered. If the game can't explain something, that's a bug in the engine's
instrumentation, not an acceptable mystery.

**3. Determinism you can trust.**
Same world, same seed, same slider config, same decisions ⇒ the same season, forever.
This is a player promise, the foundation of testing, *and* the storage strategy: the
other fifteen games each week aren't stored, they're replayable.
([ADR-0003](adr/0003-deterministic-seeded-simulation.md))

**4. Depth exactly when you want it.**
Sim three seasons in three minutes while you rebuild; drop into a single snap in Week
18 and call it yourself. The player sets the resolution moment to moment, and the game
never punishes them for delegating — which means the AI coach has to be genuinely good.

**5. Generated, seeded, and yours.**
Every league is generated. Rivalries start with plausible invented history and then
grow from what actually happens to you. Nobody else's league has your grudges.

## The core loop

```
Week
  ├── News          league-wide happenings, your inbox, what the media thinks
  ├── Prepare       depth chart, gameplan, practice emphasis, roster moves
  ├── Play          watch, sim, or take control snap by snap — switch at will
  ├── Review        why it went the way it did: grades, leverage, causal breakdown
  └── Advance
Season → playoffs → offseason → repeat, or get fired and start somewhere else
```

## What this is not

- **Not multiplayer.** Single-player, on-device, offline.
  ([ADR-0002](adr/0002-swiftdata-offline-first.md))
- **Not licensed.** No real players, teams, marks, or likenesses, ever.
  ([ADR-0005](adr/0005-generated-fictional-content.md))
- **Not free-to-play.** No energy timers, no gacha, no pack-opening.
- **Not an arcade game.** You never control a player. You control decisions.

## What "good" looks like

- A ten-season career completes without a crash, a soft-lock, or an unexplainable result.
- Simulating a season takes about a minute; watching one game takes about fifteen.
- League statistics land in realistic ranges at default sliders
  ([calibration](match-engine.md#calibration)).
- Upsets happen and dominant teams still dominate — the spread of team win totals is
  the metric that proves it.
- A player who has just lost a game can find out why in under thirty seconds.
- Someone who finishes a career has a favorite player, and can tell you why.

## Open questions

Tracked in [design-decisions.md](design-decisions.md#open-questions). The load-bearing
ones right now: how sliders interact with career records, how much authorship the
player gets over development, and how the trade AI avoids feeling exploitable.
