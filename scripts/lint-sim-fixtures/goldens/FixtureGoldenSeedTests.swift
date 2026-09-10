// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the second check in scripts/lint-sim.sh, the
// one that looks for Hasher in a *Golden*Tests.swift file, and the comment
// stripper in front of it. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

/// The doc-comment case: this checksum is deliberately FNV-1a and deliberately
/// not `Hasher`, whose seed is randomised per process. Saying so must not fire.
struct Checksum {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
}

func drifting(_ value: Int) -> Int {
    var hasher = Hasher()  // EXPECT: golden-hasher
    // var hasher = Hasher() — must not fire
    /* var hasher = Hasher() — must not fire */
    hasher.combine(value)
    return hasher.finalize()
}
