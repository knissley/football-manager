# Roadmap

Milestones are ordered by dependency, not by calendar. Each has an exit criterion
that can be checked rather than argued about. The guiding principle: **get a playable
end-to-end skeleton early, then deepen.**

## M0 — Repo and design foundation ✅

Docs, CLAUDE.md, project skills, ADR practice, .gitignore.

*Exit:* a new contributor (human or Claude) can read the docs and know where code goes.

## M1 — Core domain and world generation

`FMCore`, `FMRandom`, `FMGeneration`. No UI, no persistence.

- Typed IDs, `Player`, `Team`, `League`, `Contract`, `Ratings`, `DepthChart`.
- `SplittableRandom` with known-answer tests.
- Cap math with a thorough unit test suite (proration, dead money, post-June-1).
- Generator: names, 32 franchises, plausible rosters, a draft class.
- Invariant checkers from [domain-model.md](domain-model.md#invariants-worth-enforcing-in-code).

*Exit:* `generateWorld(seed: 42)` twice produces byte-identical worlds, rosters have a
believable talent distribution, and the cap test suite passes.

## M2 — Match engine v1

`FMSimulation`, plus the `Tools/simharness` CLI.

- Game loop, clock, downs, scoring, possession changes.
- Run and pass resolution from matchups; special teams.
- Play-by-play log and box score, reconciled.
- Harness sims 10,000 games and emits the calibration JSON.

*Exit:* league-wide stats land inside the [calibration table](match-engine.md#calibration),
a golden-seed game's box score is checked in, and 16 games sim in under 2s on device.

## M3 — Season engine

- Schedule generation with correct byes and division home-and-away.
- Week advance, standings with tiebreakers, playoff seeding and bracket.
- Injuries across a season; fatigue and rest.
- Offseason skeleton: retirements, progression at camp.

*Exit:* a full season sims to a champion; 100 simulated seasons produce a believable
spread of win totals and no invariant violations.

## M4 — The app, first playable

App target, `FMUI`, `FMPersistence`. This is the first build that's a *game*.

- Team hub, roster list, player detail, depth chart editor, schedule, standings.
- Watch-a-game view: drive-by-drive with a play log.
- Week advance from the UI.
- SwiftData save/load of a career, with round-trip tests.

*Exit:* install on a phone, start a career, play a full season, background and resume
the app without losing progress.

## M5 — Roster management

The meta layer that makes the career interesting.

- Contracts UI: extensions, restructures, cuts with dead-money preview.
- Free agency with AI bidding over multiple days.
- The draft: scouting with fog, a draft board, AI teams that pick sensibly.
- Practice squad, waivers, trades with cap and pick validation.
- Player progression and regression driven by development traits and playing time.

*Exit:* three consecutive AI-only offseasons produce rosters that stay cap-legal, and
teams that draft well get better.

## M6 — Coaching and tactics

- Scheme selection and scheme-fit effects on player performance.
- Weekly gameplan: tempo, aggression, blitz rate, coverage mix, matchup targeting.
- Coaching staff hiring, coordinators, their effect on progression and play calling.
- In-game adjustments at halftime.

*Exit:* two identical rosters with different schemes and gameplans produce measurably
different results over 1,000 games, in the direction you'd expect.

## M7 — Career texture

The things that make a decade of seasons feel like a story.

- News feed and inbox; press conferences or owner expectations.
- Awards, records, league leaders, Hall of Fame.
- Franchise history: past seasons, retired numbers, rivalries.
- Player narratives — holdouts, breakouts, decline.

*Exit:* a 10-season career review screen reads like a history worth screenshotting.

## M8 — Polish

- Onboarding and new-career flow.
- Full VoiceOver and Dynamic Type support; the roster table is the hard part.
- Haptics on key game moments.
- Performance pass: launch time, week-advance time, memory over a long career.
- Save file size audit over a 10-season career.

*Exit:* accessibility audit clean, no frame drops on the roster and game screens, a
10-season save loads in under 2 seconds.

## M9 — Beta

- TestFlight, crash reporting, opt-in analytics on where careers stall.
- Balance pass driven by real player data.
- App Store listing, screenshots, privacy nutrition label.

*Exit:* 50 testers, 10 completed seasons each, no P0 bugs open for a week.

## Explicitly deferred

Not in 1.0, not being designed around, but the architecture shouldn't make them
impossible:

- Online leagues and multiplayer
- iPad-optimized layouts and Mac Catalyst
- A play designer or Xs-and-Os editor
- Custom league import / roster sharing
- 2D or 3D animated play visualization
