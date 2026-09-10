// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `random-element` rule of
// scripts/lint-sim.sh and the comment stripper in front of it. Every hit it must
// produce is listed in scripts/lint-sim-fixtures/expected.txt; run
// scripts/lint-sim.sh --self-test.

func pickStarter(_ roster: [Int]) -> Int? {
    let starter = roster.randomElement()  // EXPECT: random-element
    // let starter = roster.randomElement() — must not fire
    /* roster.randomElement() — must not fire */
    return starter
}
