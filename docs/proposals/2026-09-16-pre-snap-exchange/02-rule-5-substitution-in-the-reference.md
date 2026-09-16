# [D9] Rule 5 Section 2, substitution, is not in the reference

**Track:** Rulebook 2025 · **Wave:** 4 · **Size:** small
**Depends on:** nothing.
**Where it fits:** docs lane; `docs/reference/playing-rules.md` and, if any article is
found the engine contradicts, `docs/invariants.md`.
**Tracker:** #1
**Provenance:** §3 row b of `docs/audit-pre-snap-exchange.md` (C34, #229). The audit could
not say whether the book constrains a defence substituting against tempo, because the
reference has one Rule 5 entry, 5-1-1 (`playing-rules.md:369`).

## Finding

The engine redraws the defensive package on every snap whatever the offence's tempo: the
package changes between consecutive snaps of a drive on 43.2% of hurry-up snaps and 47.3%
of normal-tempo ones (audit §4, table 6, 400 games at seed 7; 43.4 / 47.1 at seed 11). In
the sport the offence at tempo holds the defence's eleven on the field. Whether that is
the book or practice, and exactly what the book says, is not in the reference, so 04
cannot be written as a `.football` test and ADR-0015's step 2 cites practice where it
may be able to cite an article.

## Plan

1. `scripts/fetch-rulebook.sh <dir outside the repo>` and confirm the edition is 2025.
2. Read Rule 5 Section 2 in full. Write each article into `playing-rules.md` in our own
   words, by number, in rule order, under a Rule 5 heading that says what the section
   governs. Name the test that checks each, or say *not modelled* and name the issue (04).
3. Where an article constrains the defence's substitution against the offence's — timing,
   the officials' hold, what the offence must do to trigger it — say so plainly and say
   what the engine does today (§4, table 6) against it.
4. `FM_RULEBOOK_TEXT=<path> scripts/lint-reference.sh` before pushing; no book text.

## Done when

- [ ] Every article of Rule 5 Section 2 has an entry, in our own words, with its status.
- [ ] The entry names whether the engine's per-snap redraw contradicts an article, and
      which.
- [ ] `lint-reference` green at head and on `origin/main`.

## Not in scope

- Building 04. This issue says what the book says; 04 makes the engine do it.
- Rule 5 Section 1 beyond 5-1-1, unless an article there bears on substitution.

## Not checked when filing

Whether the 2025 and 2026 editions differ on this section; `scripts/fetch-rulebook.sh`
prints which edition it got and the four articles known to differ are elsewhere.
