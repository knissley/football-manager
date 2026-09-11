# Fixture: the run the lint cannot see

Not a document. The entry below reproduces **nine** consecutive words of the fixture
corpus and no ten of them, so the lint as shipped walks straight past it and a scan one
word shorter finds it at once. That is the blind spot, made visible.

It is here because the gap was found in use rather than by design: a run of eight words
was carried into a commit message, was invisible to the lint, and was caught only because
somebody was scanning more strictly than the tool asks for. Eight was then measured across
the whole tree and rejected — the script's header carries the count that rejected it — so
the blind spot is a decision, and a decision that is not exercised is a comment.

The self-test asserts both halves: nothing here at the shipped run length, and a hit one
word below it. Widen the shipped length and the second half goes red; lose the ability to
scan at a shorter length at all and it goes red too.

- **7-4-Penalty** — Our note says the team is moved back one place in the order, and no
  more than that.
