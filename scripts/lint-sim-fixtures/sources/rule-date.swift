// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `date` rule of scripts/lint-sim.sh and the
// comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func stamp() -> Date {
    let now = Date()  // EXPECT: date
    // let now = Date() — must not fire
    /* let now = Date() — must not fire */
    return now
}
