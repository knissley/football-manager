// What the simulate loop cost, measured against the performance budget.
//
// docs/match-engine.md#performance-budget derives the budget from one constraint: a
// season simulates in about 60 seconds. A regular season is 272 games, so that is
// 60_000 ms / 272 ≈ 220 ms a game. ADR-0006 calls the budget architectural — retrofitting
// it is a rewrite — and until this block existed nothing measured it (H3 #9).
//
// Reporting only. There is no gate here and no `CalibrationTarget` row: a wall-clock
// reading is a property of the machine that took it, not of the football, and a band
// would either be meaningless across runners or would fail this job on a noisy one.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Monotonic wall clock, in seconds, for measuring an interval.
///
/// A tool may read the clock. The `FM*` packages may not (CLAUDE.md rule 1,
/// [ADR-0004](docs/adr/0004-pure-swift-domain-core.md)), which is why the measurement is
/// taken from out here, around `GameSimulator.simulate`, and nothing inside the engine
/// knows it is being timed. `CLOCK_MONOTONIC` rather than `clock()` because the budget is
/// wall clock: a season the player waits through, not CPU time.
func monotonicSeconds() -> Double {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return Double(now.tv_sec) + Double(now.tv_nsec) / 1_000_000_000
}

/// The simulate loop's wall clock against the budget, as the lines the harness prints
/// last.
struct Budget {
    /// Games in a regular season: 32 teams × 17 games ÷ 2. The divisor in
    /// docs/match-engine.md#performance-budget.
    static let seasonGames = 272

    /// The seconds a season is budgeted, from which the per-game figure below is derived.
    static let seasonSeconds = 60.0

    /// The budget reference this block prints: 60 s ÷ 272 games ≈ 220 ms, the figure
    /// docs/match-engine.md states and ADR-0006 adopts. Kept as the doc's rounded number
    /// rather than the raw quotient (220.588…) so the harness prints what the doc says;
    /// `BudgetTests` asserts the two still agree.
    static let millisecondsPerGameBudget = 220.0

    /// Games actually simulated — not the `--games` argument, which counts the
    /// same-team pairings the loop skips.
    let games: Int

    /// Wall clock spent inside `GameSimulator.simulate`, in seconds. World generation,
    /// the weather draws and the report over the stream are all outside it.
    let seconds: Double

    var millisecondsPerGame: Double {
        games <= 0 ? 0 : seconds * 1000 / Double(games)
    }

    var secondsPerSeason: Double {
        millisecondsPerGame * Double(Self.seasonGames) / 1000
    }

    /// Measured ÷ budget. Under 1 is inside the budget.
    var ratioToBudget: Double {
        millisecondsPerGame / Self.millisecondsPerGameBudget
    }

    /// The block, printed after everything else so that a diff of two runs of the same
    /// binary at the same seed differs only here (#52 made the rest byte-identical, and
    /// `--no-timing` drops this so that property can still be checked with a plain
    /// `md5sum`).
    var lines: [String] {
        [
            "  Budget",
            "    Wall clock of the simulate calls alone — world generation, the weather draws",
            "    and this report are outside it. Reporting only: no gate, and not a calibration",
            "    target. It is the one block that moves between two runs of the same binary at",
            "    the same seed, which is what --no-timing exists for.",
            "    " + pad("simulate calls", 30) + "\(games) games in \(twoDecimals(seconds)) s",
            "    " + pad("ms per game", 30) + twoDecimals(millisecondsPerGame),
            "    " + pad("seconds per \(Self.seasonGames)-game season", 30)
                + twoDecimals(secondsPerSeason),
            "    " + pad("budget", 30) + twoDecimals(Self.millisecondsPerGameBudget)
                + " ms per game, \(Int(Self.seasonSeconds)) s a season"
                + " (match-engine.md#performance-budget)",
            "    " + pad("ratio to budget", 30) + twoDecimals(ratioToBudget) + "x",
        ]
    }
}
