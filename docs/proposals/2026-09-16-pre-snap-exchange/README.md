# The pre-snap exchange: issue bodies, not yet filed

**Status: drafted 2026-09-16 from [audit-pre-snap-exchange.md](../../audit-pre-snap-exchange.md)
(C34, #229) and [ADR-0015](../../adr/0015-order-the-pre-snap-exchange.md); nothing here is
filed and nothing is built.** Each file is one issue in the standard body — Finding, Plan,
Done when, Not in scope, Not checked when filing — ready to paste. The owner files them;
this page says in what order and what each waits on. Delete the directory once they are
filed and the tracker carries them.

| File | Track | Lane | Waits on | Owner decision |
|---|---|---|---|---|
| [01-docs-corrections.md](01-docs-corrections.md) | I | docs | ADR-0015 accepted | — |
| [02-rule-5-substitution-in-the-reference.md](02-rule-5-substitution-in-the-reference.md) | D | docs | nothing | — |
| [03-coverage-is-read-as-one-bit.md](03-coverage-is-read-as-one-bit.md) | C | engine | #39 | **gated on #49, decided 2026-09-16** |
| [04-the-defence-substitutes-when-the-offence-does.md](04-the-defence-substitutes-when-the-offence-does.md) | C | engine | 02, ADR-0015 | Q2 — practice now, or after the book |
| [05-the-offence-checks-against-the-box.md](05-the-offence-checks-against-the-box.md) | C | engine | ADR-0015, 04 | Q1 — M1 or M2 |
| [06-the-harness-carries-the-exchange.md](06-the-harness-carries-the-exchange.md) | E | tools | nothing | — |
| [07-comment-on-225-the-call-reads-the-grouping.md](07-comment-on-225-the-call-reads-the-grouping.md) | C | — | — | Q3 — a comment on #225, not an issue |
| [08-comment-on-227-the-selection-confound.md](08-comment-on-227-the-selection-confound.md) | C | — | — | a comment on #227, not an issue |
| [09-m2-anticipation-stream-line.md](09-m2-anticipation-stream-line.md) | — | — | M2 opens | a line for the designer, not an issue |

Dispatch order in the resolver region, which runs one at a time: **#39 → 03 → #224 →
#225 (with 07) → 04 → 05**. 01, 02 and 06 fit any gap. 03 is on #49's gate; 04 and 05 are
not unless the owner puts them there.
