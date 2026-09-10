// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the comment stripper in scripts/lint-sim.sh
// rather than any one rule: the shapes a Swift file can put a banned token in,
// and which of them the lint is meant to see. Every hit it must produce is
// listed in scripts/lint-sim-fixtures/expected.txt; run
// scripts/lint-sim.sh --self-test.
//
// Each case here is meant to discriminate — break the branch of the stripper it
// exercises and the hit moves, so the self-test fails. Two of them earn that by
// putting a `//` inside the literal, where a quote read wrongly turns the rest
// of the line into a comment and the banned name disappears.

/// The doc-comment case the stripper exists for: prose that names
/// `Int.random(in:using:)`, `UUID()` and `Hasher()` the way SplittableRandom's
/// own doc comment does. None of it fires.
func stripper() {
    /* A block comment that runs for several lines and names UUID()
       and Date() and ProcessInfo on the way past. None of them fire.
       Not even SystemRandomNumberGenerator() on the closing line. */
    let d = Date()  // EXPECT: date — and this trailing comment names UUID(), which does not fire
    /* a block that closes mid-line */ let u = UUID()  // EXPECT: uuid
    let u2 = UUID() /* a block that opens after the code — EXPECT: uuid
       carries on across a line that names Date(), which does not fire,
       */ let u3 = UUID()  // EXPECT: uuid
    let inString = "a string literal is not stripped: Date()"  // EXPECT: date
    let slashes = ("// not a comment", UUID())  // EXPECT: uuid
    let stars = ("/* not a block comment", Date())  // EXPECT: date
    // The escaped quote has to be read as part of the literal. If it closed the
    // string, the `//` after it would start a comment and the UUID() would be
    // stripped away instead of firing, so this line pins that branch.
    let escaped = "an escaped quote \" does not end it // UUID()"  // EXPECT: uuid
    // The same trick for the multi-line string: the line inside it opens with
    // `//`, so its Date() only survives if the """ was understood.
    let multi = """
        // Date() here is string content, not a comment.  // EXPECT: date
        """
    // The gap the script header names, pinned here so it is discoverable rather
    // than folklore: a token split by an inline block comment escapes every
    // rule. The next line is a clock read and fires nothing.
    let gap = Date/* still a clock read */()
    _ = (d, u, u2, u3, inString, slashes, stars, escaped, multi, gap)
}
