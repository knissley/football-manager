# Fixture: a run only a joined scan can see

Not a document. This is the fixture that matters.

The entry below reproduces ten consecutive words of the fixture corpus, but the file's
hard wrap falls in the middle of them, so no single line holds ten of them in a row.
A per-line scan reports this file as clean. Measured on the real
`docs/reference/playing-rules.md`, that difference was five runs against ten — half the
reproductions in the file hid behind a line break.

If this fixture ever stops being reported as `joined`, the scanner has been rewritten
to look at lines one at a time and its zero means nothing.

- **7-3-2** — Our note says the relay is over when the
  anchor runner crosses the stripe, and that ends it.
