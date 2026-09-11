# Reference

**Status: built.** Two files, both of them hand-entered and both of them checked.

This directory is the external truth an agent verifies against **instead of its own
memory**. CLAUDE.md's rule 10 says a claim about the sport cites a rule number and a
rulebook season, and a claim about a rate cites a real-league season and the source the
number came from. This is where both live.

- [`playing-rules.md`](playing-rules.md) — the rules the engine implements, one entry per
  article of the **2025** rulebook, paraphrased in our own words. Look a number up here.
- [`calibration-sources.md`](calibration-sources.md) — where every calibration band came
  from: the real-league season, the data set, and the figures the tree states in words.

## Why it exists

The engine was first written from somebody's memory of the sport, and the code carried that
memory's errors for weeks. A table in the football-domain skill said the opposite of the
code and nothing connected the two, so nothing noticed. The September 2026 audit found
fifteen findings that way, seven of them in the rules layer.

The fix is not a better memory. It is that every football claim in this repository points
at something outside it — an article number, or a season and a data set — and that the
pointing is checked by a test.

## What is not here

**No rulebook text.** The rulebook is a copyrighted document; a citation is what we need
from it, not a copy. Every rule below is in our own words, and the number is how you find
the original. Terms of art are the exception and have to be: a *free kick*, the *line to
gain*, *half the distance to the goal* have no synonyms worth having.

**No data sets.** The calibration bands are aggregates typed in by hand, with the season
and the source named per row. No play-by-play file is checked in, and neither is any real
player, team or league name ([ADR-0005](../adr/0005-generated-fictional-content.md)).

## How this relates to everything else

| File | What it is | Who reads it |
| --- | --- | --- |
| `reference/playing-rules.md` | the article index: look up a number | anybody checking a citation |
| `.claude/skills/football-domain/references/game-rules.md` | the same rules read by area, with what the tree carries today | an agent about to write sim logic |
| [`../invariants.md`](../invariants.md) | what must be true, and the test that checks each | a reviewer, and a rules PR |
| `reference/calibration-sources.md` | where each band came from | anybody about to move a band |
| [`../match-engine.md#calibration`](../match-engine.md#calibration) | the bands themselves, generated from `Targets.swift` | anybody reading harness output |

Where two of them disagree, that is a bug in the docs and not a decision.
`InvariantsTraceabilityTests` in the FMSimulation test target binds them together: every
test named in `invariants.md`, in `playing-rules.md` and in `game-rules.md` has to exist,
every calibration row named has to exist, every rules-conformance scenario has to be
covered by an invariant, and every sourced row has to appear in `calibration-sources.md`.

## Policing this directory

That suite checks **names**. It has never seen the rulebook, so it cannot tell that an
entry has copied the book's words, or that the number beside a correct paraphrase is the
wrong article. Both happened, and both were found by a person reading with the book open.

[`scripts/lint-reference.sh`](../../scripts/lint-reference.sh) is the mechanical half:

```bash
FM_RULEBOOK_TEXT=/path/to/rulebook.txt scripts/lint-reference.sh
scripts/lint-reference.sh --self-test     # needs no corpus; CI runs this one
```

It reports ten-word runs the tree and the book have in common, and any
`rule-section-article` number in the four documents above that names no article. What it
cannot do is tell whether a cited article *supports* the claim beside it — `8-5-4` exists,
so a citation to it passes, and it was still the wrong article in six entries for weeks.
It prints that limitation on every run so a clean one cannot be read as more than it is.
[tools.md](../tools.md#lint-reference--reproduced-rulebook-text-and-citations-that-resolve)
is the full description, including why twenty-three runs are carried in a baseline rather
than reworded.

### Getting a corpus

**There is none in the repository and there will not be.** The rulebook is the copyrighted
document this whole directory exists to avoid copying, so the lint takes it from outside:

- `FM_RULEBOOK_TEXT=<path>`, or
- a file at `.rulebook.txt` in the repository root, which `.gitignore` keeps untracked.

Any plain-text extraction of the book works — the lint only tokenises words and reads
`RULE`/`SECTION`/`ARTICLE` headings, and it repairs a heading a PDF extractor has broken
across a line. Get the official PDF from the league's own rules page and extract it
locally; do not commit either the PDF or the text.

**Mind the edition.** This project targets the **2025** book. A 2026 extraction is
identical outside four articles — 6-1-3, 6-1-5, 6-1-6 and 19-2 — so it is fine for the
lint and fine for citations elsewhere, but taking a 2026 rule into the engine is a defect
and not an improvement. With no corpus the lint prints why and exits 0.
