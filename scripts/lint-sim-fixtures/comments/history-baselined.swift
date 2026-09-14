// A fixture for the baseline: never compiled, scanned only by
// scripts/lint-sim.sh --self-test.

struct Baselined {
    /// A carried hit — scripts/lint-sim-fixtures/baseline.txt holds this
    /// line's key, so it passes (#18).
    let carried = 0

    /// An uncarried hit beside it, so a baseline that stopped being read fails
    /// the self-test in both directions (#18).
    let uncarried = 1
}
