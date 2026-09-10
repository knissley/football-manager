// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `hasher` rule of scripts/lint-sim.sh — the
// use-site ban, not the golden-test check, which has its own fixture under
// scripts/lint-sim-fixtures/goldens/. Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func mix(_ value: Int) -> Int {
    var hasher = Hasher()  // EXPECT: hasher
    // var hasher = Hasher() — must not fire
    /* var hasher = Hasher() — must not fire */
    hasher.combine(value)
    return hasher.finalize()
}
