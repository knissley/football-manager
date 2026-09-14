<!--
This body IS the report. The reviewer and the orchestrator read it instead of a separate
message, so a fact that is only in a chat message is a fact that is lost.

CAP: 500 words outside the preflight block. Evidence is a line — the command and what it
printed — not the story of running it. Delete a heading that does not apply to this branch
rather than writing "n/a" under it.

No model identifiers anywhere in this body beyond the attribution trailer the tooling
appends. Rulebook citations by article number and season; never rulebook text.
-->

Closes #<!-- the issue this PR completes. Use `Refs #N` instead when it satisfies only part
of an issue: the issue then stays open with a comment naming which Done-when items are met. -->

## What changed

One paragraph: what the branch does and **the mechanism**, not the narrative of building it.

## Done when

<!-- One line per Done-when item of every issue this PR closes, quoted from the issue, each
with its evidence: the test name, the command, the file, the number it printed. -->

- [ ] <item, quoted from the issue> — <evidence>
- [ ] <item, quoted from the issue> — <evidence>

## Measured

<!-- Only what you ran and read yourself, on this head. -->

-

## Assumed

<!-- Anything taken on trust, including every place the issue's plan was silent and you
filled the gap by judgment — say what you filled it with. -->

-

## Not checked

<!-- Everything you did not verify, stated plainly. A body missing Assumed or Not checked
goes back before it is reviewed. -->

-

## preflight

<!-- Paste `./scripts/preflight.sh --report` whole. It prints its own fenced block and
carries the lane, the base sha, the harness-reach verdict, the Targets.swift checksum at
HEAD and at the merge base, and every step with its seconds and result. -->

## Harness

<!-- Either the rows that moved, one line of mechanism each and the noise floor you read
them against (say which floor: one seed before-and-after, or across two seeds), or:

  none moved — `scripts/harness-reach.sh origin/main` says `skip`: <its reason>

"Noise" and "resampled" are mechanisms only with a count of differing games and a mechanism
per differing game. -->
