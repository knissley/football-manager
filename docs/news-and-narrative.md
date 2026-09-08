# News and narrative

Where the league feels alive, and the fastest way to make the whole game feel cheap if
it's wrong. Generated news goes stale around week six of season one unless the design
attacks that directly.

## Two stages, and the split is the point

```
Stage 1 — Detection        FMAnalysis
  Queries over the event streams produce Findings, each scored for newsworthiness.
  Objective, testable: "did we find the interesting things?"

Stage 2 — Rendering        FMNarrative
  A writer, with a voice and biases and memory, turns a Finding into copy.
  Subjective, swappable, improvable on its own schedule.
```

Keeping these apart matters more than it looks:

- **The hard problem is selection, not prose.** Ten thousand true statements exist each
  week; the craft is choosing the twenty worth reading. That's a scoring function, and
  it's testable in a way prose isn't.
- **Findings are the same objects the interrogation layer produces.** The news feed and
  the "why did we lose" screen are one system with two presentations.
- **The same Finding rendered by two writers reads differently.** That's the variety
  engine, and it costs nothing per story.

### Newsworthiness

Scored from things we already compute:

| Input | Source |
| --- | --- |
| Leverage — how much it moved win probability | [ADR-0008](adr/0008-win-probability-keystone.md) |
| Surprise — distance from expectation | Team ratings vs. result |
| Record proximity — two games from a franchise mark | Career/season stat projections |
| Personal relevance — you, your rivals, your former players | Rivalry state, transaction history |
| Rarity — a safety, a 99-yard drive, a kicker fumble | Play type frequency |
| Novelty — have we said this recently? | The writer's own memory |

## Writers are persistent entities

```
Writer
  identity      generated name, outlet, portrait
  beat          national · your team · a rival · statistical · tabloid
  biases        favoured teams, pet theories, blind spots
  voice         vocabulary, rhythm, hedging versus certainty
  memory        claims made, predictions on record, running feuds
  credibility   accuracy of past predictions — computed, and visible to you
```

**Memory is the strongest anti-fatigue mechanism available.** A writer who remembers his
own past claims produces contextual copy rather than standalone copy: *last month I
called their run defence a mirage; twelve carries for 94 yards later, I'd like my apology
now.* No template does that.

**Credibility is computed, not authored.** Pundits make falsifiable predictions and the
game grades them against what actually happened. The man who picks you to finish last
every season accumulates a visible record of being wrong about it.

That's the third use of one idiom, and it's becoming the game's signature move:

> **State a claim. Measure it against the event stream. Show the result.**
>
> Gameplan hypotheses · scouting evaluations · pundit predictions

## Whimsy: odd things are true, and reported straight

The playfulness lives in the world's *facts*, not in the prose winking at you. A punter
with a cult following, a mascot situation that becomes a season-long saga, a rookie who
is implausibly old, a quarterback whose superstition the media insists is working.

These are **generated world events**, not authored news items
([ADR-0009](adr/0009-event-sourcing-by-default.md)) — so they persist, compound, and can
be referred back to years later.

**The line they never cross:** odd facts influence the narrative layer and fan and owner
perception. They never reach play resolution. A punter's cult following is real, is
reported, and does not make him punt further. Pillar 1 holds — the engine doesn't wink,
the world does.

The superstition case is the best of these, because the analytics layer can *disprove* the
media's story. Whimsy and the hook reinforcing each other.

## Harshness, and why credibility is its safety valve

Coverage gets brutal. Two rules keep that from being merely unpleasant:

**Criticism is specific and evidence-backed, even at its harshest.** *31st against play
action on third down* cuts deeper than *the Kestrels look lost*, and it's fair — you can
go look.

**Harshness tracks expectation, not record.** A three-win team projected to win three gets
patience; a nine-win team projected for twelve gets savaged. This is realistic, and it's
what stops a deliberate rebuild from being punished for going according to plan.

And the release valve: because pundit credibility is tracked, being doubted is the setup
for being vindicated. Harsh coverage with no route to proving anyone wrong is just abuse;
with a visible scoreboard on the people doubting you, it's a story.

## Media pressure feeds owner expectations, carefully

One feedback edge into the simulation, and it needs a specific shape to avoid a problem.

**`MediaPressure` is a metric computed in `FMAnalysis`, not an artifact of
`FMNarrative`.** It is a measurement over events — results against expectation, narrative
momentum, streak state — and the owner and carousel systems read *that*. `FMNarrative`
stays a pure leaf: it renders, and nothing depends on it.

Otherwise `FMSimulation` would have to depend on prose generation to decide whether you
get fired, which is both architecturally wrong and impossible to test.

Pressure is lagging and aggregated, never per-article, and it is one input among several
(record, expectation delta, finances, tenure) into an `ownerPatience` projection.

## Anti-fatigue checklist

Things that must be true or the feed feels generated:

- Writer memory suppresses repetition and enables callbacks.
- Recency penalties in newsworthiness — the same *kind* of story can't run weekly.
- Findings are specific and numeric, not adjectival. Generated *findings* beat generated
  *prose* every time.
- A story about you and a story about a team you've never played should not read the same.
- Volume is bounded. Twenty good items beat two hundred true ones.

## Build order

1. `Finding` and the newsworthiness score in `FMAnalysis` — before any prose.
2. A single neutral renderer. Prove the *selection* is good with boring copy.
3. Writers: identity, voice, beat.
4. Writer memory and callbacks.
5. Predictions and computed credibility.
6. Odd world events as generated facts.
7. `MediaPressure` into `ownerPatience`.
