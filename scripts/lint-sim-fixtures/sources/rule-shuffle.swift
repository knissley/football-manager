// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `shuffle` rule of scripts/lint-sim.sh and
// the comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func order(_ deck: [Int]) -> [Int] {
    var copy = deck
    copy.shuffle()  // EXPECT: shuffle
    let mixed = deck.shuffled()  // EXPECT: shuffle
    // copy.shuffle() — must not fire
    /* deck.shuffled() — must not fire */
    return copy + mixed
}
