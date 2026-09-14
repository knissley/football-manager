// A fixture for the second structural exception: never compiled, scanned only by
// scripts/lint-sim.sh --self-test.

enum Registers {
    /// lint-sim: unreachable-register — the decision details the crude engine
    /// cannot produce, each naming the issue that makes it reachable (#39). The
    /// marker exempts this block and the declaration it introduces, to the
    /// bracket that closes it.
    static let unreachableTackleResults: [String: String] = [
        /// Assisted tackles arrive with #39.
        "assisted": "nobody assists",
        /// Missed tackles arrive with #39 too.
        "missed": "nobody misses",
    ]

    /// One line past the closing bracket, the same sentence fails (#39).
    static let reachable = 0
}
