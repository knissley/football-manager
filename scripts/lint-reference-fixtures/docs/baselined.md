# Fixture: a run that the baseline carries

Not a document. The entry below reproduces ten consecutive words of the fixture corpus
on one line, exactly like `one-line.md` does — and `../baseline.txt` carries its content
key, so the self-test expects it NOT to be reported.

That is the third thing the self-test pins. A scanner that found reproductions and a
scanner that honoured the baseline are two separate pieces, and a rewrite that dropped
the second would otherwise show up only as a wall of noise on somebody else's branch.

- **7-4-1** — Our note says a dropped baton must be recovered by the runner who found it.
