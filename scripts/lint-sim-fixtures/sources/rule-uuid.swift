// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `uuid` rule of scripts/lint-sim.sh and the
// comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func identify() -> UUID {
    let id = UUID()  // EXPECT: uuid
    // let id = UUID() — must not fire
    /* let id = UUID() — must not fire */
    return id
}
