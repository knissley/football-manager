// A fixture for the process-history rule: never compiled, never part of a
// package, and scanned only by scripts/lint-sim.sh --self-test. Every hit below
// is deliberate, and every line number is named in expected.txt.

/// One plain hit per pattern, each on a line of its own so the expectation says
/// which rule fired rather than only that something did.
struct HistoryHits {
    /// The spot is the previous spot because the foul happened there (#18).
    let spot = 0

    // Filed in wave 3 and landed with the enforcement change.
    let enforced = 1

    /* The audit found this the wrong way round. */
    let side = 2

    // The review asked for the kicking team here.
    let kicker = 3

    // The orchestrator dispatched this one.
    let dispatched = 4

    // Four at once, in capitals: Wave 4, an AUDIT, The Review, an Orchestrator.
    let capitals = 5
}

/// Real code and literal text are out of reach, because the scan reads what the
/// comment stripper removes and nothing else. None of the next line fires.
let notAComment = ["#18", "wave 3", "audit", "the review", "orchestrator"]
