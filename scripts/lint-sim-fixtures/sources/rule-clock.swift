// lint-sim fixture — never compiled, never part of any package, never scanned
// by the real lint. It exercises the `clock` rule of scripts/lint-sim.sh, one
// line per alternative in the pattern, and the comment stripper in front of it.
// Every hit it must produce is listed in
// scripts/lint-sim-fixtures/expected.txt; run scripts/lint-sim.sh --self-test.

func measure() {
    let a = ContinuousClock()  // EXPECT: clock
    let b = SuspendingClock()  // EXPECT: clock
    let c = DispatchTime.now()  // EXPECT: clock
    let d = ProcessInfo.processInfo  // EXPECT: clock
    let e = getenv("FM_SEED")  // EXPECT: clock
    var t = timespec()
    clock_gettime(CLOCK_MONOTONIC, &t)  // EXPECT: clock
    // let a = ContinuousClock() — must not fire
    /* ProcessInfo.processInfo, getenv("FM_SEED"), clock_gettime — must not fire */
    _ = (a, b, c, d, e, t)
}
