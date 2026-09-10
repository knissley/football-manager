// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `shuffle-using` rule of
// scripts/lint-sim.sh and the comment stripper in front of it. Every hit it must
// produce is listed in scripts/lint-sim-fixtures/expected.txt; run
// scripts/lint-sim.sh --self-test.

func order<G: RandomNumberGenerator>(_ deck: [Int], using rng: inout G) -> [Int] {
    var copy = deck
    copy.shuffle(using: &rng)  // EXPECT: shuffle-using
    let mixed = deck.shuffled(using: &rng)  // EXPECT: shuffle-using
    // copy.shuffle(using: &rng) — must not fire
    /* deck.shuffled(using: &rng) — must not fire */
    return copy + mixed
}
