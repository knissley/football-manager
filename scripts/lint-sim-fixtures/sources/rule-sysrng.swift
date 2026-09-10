// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `sysrng` rule of scripts/lint-sim.sh and
// the comment stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func kickoff() -> Int {
    var rng = SystemRandomNumberGenerator()  // EXPECT: sysrng
    // var rng = SystemRandomNumberGenerator() — must not fire
    /* var rng = SystemRandomNumberGenerator() — must not fire */
    return Int(bitPattern: UInt(rng.next() % 100))
}
