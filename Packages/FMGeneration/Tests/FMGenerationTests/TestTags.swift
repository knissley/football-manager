import Testing

/// What kind of claim a test makes. Every `@Test` in this target carries exactly one of
/// these, and `scripts/test-census.sh` fails on one that carries none.
///
/// The taxonomy is CLAUDE.md's rule 11 and *Conventions → Tests*; the shares it produces
/// are in [`docs/testing.md`](../../../../docs/testing.md). It is declared once per test
/// target because Swift Testing tags are ordinary Swift declarations and each target is
/// its own module.
extension Tag {

    /// Asserts something true of the sport, and cites where it comes from: a rule
    /// article and rulebook season, or a real-league season and its source. A test with
    /// no citation is not one of these, however football it sounds.
    @Tag static var football: Self

    /// Asserts a promise the engine makes about itself — the same seed replays
    /// identically, a projection is the fold of its stream, the scoreboard is the stream
    /// summed, every case the vocabulary declares is reachable.
    @Tag static var contract: Self

    /// Asserts a unit computes or validates what it should: cap maths, RNG known
    /// answers, a table's own arithmetic.
    @Tag static var unit: Self

    /// Pins current behaviour because changing it would be surprising. The test's name
    /// says what it pins and why, and names the issue that owns changing it.
    @Tag static var pin: Self
}
