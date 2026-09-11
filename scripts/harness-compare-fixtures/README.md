# harness-compare fixtures

Two hand-written `simharness` captures and the report `scripts/harness-compare.sh`
must produce from them. `scripts/harness-compare.sh --self-test` compares its own
output against `expected.txt` and fails on any difference; CI runs it on every push.

Neither capture came from a harness run. They are written by hand so that every
category the comparison reports is exercised by exactly one row, which a real pair
of captures cannot be relied on to do:

| row | what it is there for |
| --- | --- |
| `kneels per game` | the defect this was written for: the verdict flips while the printed value does not move. |
| `third down conversion` | the band itself moved — a target changed, which is not a measurement moving. |
| `yards per carry` | a flip that also moved, and whose band prints at two precisions either side. The bands are numerically equal, so it must **not** be reported as a band move. |
| `kickoff touchbacks` (twice) | two rows sharing a label, told apart by their season, as a rule-sensitive row's variants are. The 2025 one flips; the 2024 one is `stale` on both sides and unchanged. |
| `spread of team win totals (σ)` | a row that loses its sample: a value on one side, an em dash and `n/a` on the other. |
| `points` | a value that moved without changing standing — the ordinary case. |
| `punts returned` | a row in the before run only. |
| `fourth down attempts per team-game` | a row in the after run only. |
| `scrambles per game` | unchanged, so the tally has something to count. |

The captures also carry the parts of a run that are **not** rows — the header, the
sources block, the column header and a `Budget` block — so that the parser is
exercised against them rather than against rows alone.

The metric labels and bands are the harness's own; the values are invented, and no
number here is a measurement of anything.
