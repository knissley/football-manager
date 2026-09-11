# Fixture: citations that do and do not resolve

Not a document. The fixture corpus has Rule 7 with Section 3 (two articles) and
Section 4 (one article), and the second of those sections has its heading broken across
a line the way a text extractor breaks one. So:

- `7-3-1` and `7-3-2` name articles the fixture corpus has.
- `7-4-1` names an article in the section whose heading was broken, so it resolves only
  if the repair works.
- `7-3-Penalty` names the penalty clause of a section that exists.
- `7-3-9` names nothing. The self-test expects this one to be reported, and nothing else
  on this page.
