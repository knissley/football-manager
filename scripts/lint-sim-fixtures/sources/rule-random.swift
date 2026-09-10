// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `random` rule of scripts/lint-sim.sh and
// the comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func drive() -> Int {
    let yards = Int.random(in: 1...10)  // EXPECT: random
    // let yards = Int.random(in: 1...10) — behind a line comment, must not fire
    /* let yards = Int.random(in: 1...10) — inside a block comment, must not fire */
    return yards
}
