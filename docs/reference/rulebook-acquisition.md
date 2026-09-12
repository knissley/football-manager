# Getting the rulebook, and which edition you have

The playing rules are **not in this repository and never will be**: they are a copyrighted
document, and CLAUDE.md rule 8 allows a citation and forbids a copy. But rule 10 says every
football claim is verified against the book rather than against somebody's memory, so each
session needs a copy *somewhere* — outside the tree, for verification only.

Getting one used to cost an hour, three times over: the link is unguessable, the extraction
fails in a way that does not say what is wrong, and the document you end up with is **not the
edition this project targets**. This page and `scripts/fetch-rulebook.sh` exist so that never
costs an hour again.

    scripts/fetch-rulebook.sh /some/path/outside/the/repo

Sixteen seconds, from nothing to a text file and the `export FM_RULEBOOK_TEXT=…` line that
`scripts/lint-reference.sh` wants. The script refuses to write inside any checkout of this
repository — **linked worktrees included**, since agents dispatched here each get one — and
if it cannot work out where those checkouts are, it refuses to run at all rather than run
unguarded.

## The three things that cost the time

**The link is a content-delivery asset with an opaque id.** It encodes nothing about the
season and is not guessable; it has to be scraped off the league's rules page. The script
scrapes it and keeps the last known link only as a fallback.

**`import pypdf` fails on this image's system Python** with a missing `_cffi_backend` and a
Rust panic, because its `cryptography` is broken. Nothing in that error suggests the fix,
which is a virtual environment. The script makes one.

**The asset behind that link has been replaced in place.** The same URL that served the 2025
edition now serves 2026. A session that downloads without checking gets a rulebook for a
season this project does not target, and every citation it then "verifies" is verified
against the wrong book. **This is the one that matters**, because nothing about it looks like
an error.

## Telling the editions apart

| | md5 | pages |
|---|---|---|
| 2025 — **the season this project targets** | `883457f1f405bb4a4c78234941a23af2` | 243 |
| 2026 — what the link serves today | `02dc74eecd96472eae1957b9917ad267` | 91 |

The page counts differ far more than the text does, for editions this doc measures as
word-identical outside four articles: the 2025 copy is simply a differently produced PDF.
**Identify on the checksum, never on the size or the page count** — and rule out a truncated
download before concluding you have found a new edition, because that looks identical to one.

The script identifies the edition by checksum. **On an unrecognised checksum it stops rather
than guessing** — most likely the asset has rolled again. Identify it (page 1 names the
season, page 2 lists that year's changes), confirm it, and add the checksum to the script.

The 2025 PDF has not been retrievable from a session container by any route tried. Which is
why the section below exists.

## The 2025 ↔ 2026 delta — measured, and it is exactly four articles

Everywhere outside these four the editions are word-identical, so the 2026 text can be cited
freely and the shingle in `lint-reference.sh` works against it unchanged. Inside them it is
wrong for our purposes.

**Provenance.** Measured twice, in separate sessions, by word-level diff of the genuine 2025
text — supplied by the owner, since it cannot be downloaded or committed — against the same
articles extracted from the 2026 PDF. Both measurements agree. The summaries below are in our
own words; the book's own change list is *not* sufficient, for the reason under 6-1-3.

### 6-1-3 — kickoff and safety-kick formation

| | 2025 — **implement this** | 2026 |
|---|---|---|
| The formation requirements start when | the kicker begins moving toward the ball | the Referee signals the ball ready |
| Receiving players required to have a foot on the restraining line | **six**, or **seven** when more than nine are in the setup zone | five, or six |
| Receiving players allowed in the setup zone but *off* the restraining line | **at most three**, and **at most one** in each of the three lateral areas | at most four, at most two per area |
| Extra proviso when four are off the line | **does not arise — 2025 permits at most three** | one on each side of the field has to be between the sideline and the inbounds line |

**The book's own change list understates this one.** It describes the change as affecting
receiving-team alignment in the setup zone, and says nothing about the trigger moving from
the kicker's approach to the ready signal. A session trusting the change list would miss it.
That is why the table above was measured rather than copied.

Unchanged between editions: every kicking-team requirement, the allowance for the kicker to
be past his own restraining line so long as his kicking foot is not, the bar on his crossing
midfield before the ball comes down, the nine-player minimum in the setup zone, the holding
lines for receivers outside the setup zone, and the five-yard penalty.

### 6-1-5 — kickoff or safety kick crossing the goal line

**2025 and 2026 are identical except that 2026 adds one sentence**, creating a special case:
a kick taken from midfield that ends in a touchback is spotted at the 20 regardless of which
branch it came through. **2025 has no such case.**

Either way the spot turns on **whether the ball ever came down in the landing zone**:

- **it did** — turf or a player there — and the ball afterwards died in the end zone, the
  receivers having downed it there, or it having gone out of bounds behind their own goal
  line: spot it at the **20**;
- **it did not** — the kick reached the goal line without ever coming down in the landing
  zone, and then went out of bounds behind that line, hit the receivers' goal post, an
  upright or the crossbar, or came down at or past the goal line and was downed in the end
  zone by the receivers: spot it at the **35**.

Note which way the ball leaves: **out of bounds behind the goal line** is the condition on
both branches, and it covers the sides of the end zone, not only the end line.

A kick into the end zone that stays inbounds is live either way.

### 6-1-6 — declaring an onside kick

| | 2025 — **implement this** | 2026 |
|---|---|---|
| Who may declare | the kicking team, **only while it is behind** | the kicking team, unconditionally |
| When | any point in the game | any point in the game — **unchanged** |

**This is the sharpest trap in the book and it does not read like one.** Both editions permit
the declaration at any point in the game, so the phrase about timing is *not* the change —
what 2026 removed is the requirement that the declaring team be trailing. An implementer
reading the 2026 text sees an unconditional right and codes it, and the result looks like a
rule correctly implemented rather than a wrong edition.

Minor and without engine effect: which official hands the kicker the ball before the play
clock starts, the holder being named in two alignment clauses, and an added
unsportsmanlike-conduct penalty. Everything else in the article is unchanged.

### 19-2

Officiating administration — who may be consulted about a possible disqualification. **No
engine effect.**

## Two things this does not give you

**A stable text file.** Two extractions of the same PDF differed by 91 bytes — one blank line
per page, from a different `pypdf` version. They are **identical after whitespace is
collapsed**, which is how the shingle compares, so a citation verified against either is
verified against both. Do not treat a checksum of the *text* as meaningful; checksum the PDF.

**Any assurance that a citation is right.** `lint-reference.sh` checks that a cited article
*exists* and that no run of the book's prose has been copied. It cannot tell that a correct
paraphrase carries the wrong number beside it — that has happened, more than once, and each
time it was caught by a person reading the article. The lint is a floor, not a check.
