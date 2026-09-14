# Fixture: the citations `--show` reads out of a branch diff

Not a document, and not football. `--self-test` commits this page onto a branch of a
throwaway repository, so every number below is a number that branch *adds* — which is
what `--show` with no argument is asked to find.

One line each, because each one pins a different way the article printer can be wrong.

- `7-3-1` is an ordinary article in the middle of the fixture corpus, closed by the
  heading of the article after it.
- `11-1-1` is the last one in the corpus with nothing behind it at all, so a printer
  that closes an article only on the next heading has to reach the end of the file.
- `6-1-6` is one of the four numbers the two editions disagree about, and the fixture
  corpus has no rule 6 — so this one has to carry the edition warning *and* say plainly
  that it is absent.
- `7-3-9` is a number nothing here answers to, and must cost one line rather than
  silence a reader would take for a blank article.
- `7-3-Penalty` is a penalty clause rather than an article, and is counted and skipped.
- `7-3-1` is named a second time on purpose: one article, one block, both places listed.
