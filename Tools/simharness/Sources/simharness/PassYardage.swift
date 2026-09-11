/// One pass attempt, reduced to the three facts every yardage row reads off it.
///
/// A plain value rather than a `PlayRecord` so the fold below can be exercised on a corpus
/// written by hand — four attempts a reader can add up — instead of on four hundred games.
struct PassAttempt: Sendable, Hashable {
    /// Net yards from the previous line of scrimmage. Negative on a catch for a loss.
    var yards: Int16
    var isCompletion: Bool
    var endedInTouchdown: Bool
}

/// The pass-yardage sums the calibration rows are built from.
///
/// **Two sums, because two different quantities are wanted and one word was used for both.**
/// `signedYards` counts a ball caught three yards behind the line for a three-yard loss as
/// −3, which is what the league's own play-by-play records and what
/// `scripts/calibration-sources.py` derives the passing-yards, yards-per-attempt and
/// yards-per-completion bands from. `positiveYards` counts that catch as zero, and exists
/// for one row only: yards per play, whose band was derived that way and whose note says so.
///
/// It lives here rather than inline in `main.swift` for the reason `HarnessWorld` does —
/// nothing can reach top-level code, and a sum no test can reach is a sum nobody checks.
/// The harness summed every attempt as `max(0, yards)` and handed that one number to all
/// four rows for the life of the tool; three of them were being graded against a band
/// derived the other way, and the notes beside them called both quantities "gross".
struct PassYardage: Sendable {
    private(set) var attempts = 0
    private(set) var completions = 0
    /// The older gains-only inference — a catch that gained, or scored. No row's
    /// denominator any more; the catch leaderboard is what still reads it.
    private(set) var completionsThatGained = 0
    /// Every completion's yardage, losses included.
    private(set) var signedYards = 0.0
    /// The same, with a completion for a loss counted as nothing.
    private(set) var positiveYards = 0.0

    mutating func add(_ attempt: PassAttempt) {
        attempts += 1
        guard attempt.isCompletion else { return }
        completions += 1
        if attempt.yards > 0 || attempt.endedInTouchdown { completionsThatGained += 1 }
        signedYards += Double(attempt.yards)
        positiveYards += Double(max(0, attempt.yards))
    }

    static func over(_ attempts: some Sequence<PassAttempt>) -> PassYardage {
        var yardage = PassYardage()
        for attempt in attempts { yardage.add(attempt) }
        return yardage
    }

    /// `row:yardsPerAttempt`. Signed: `div(c["passYards"], c["attempts"])` in the script.
    var yardsPerAttempt: Double { signedYards / Double(max(1, attempts)) }

    /// `row:yardsPerCompletion`. Signed over every completion, both halves of which the
    /// script does the same way: `div(c["passYards"], c["completions"])`.
    var yardsPerCompletion: Double { signedYards / Double(max(1, completions)) }

    /// `row:passingYards`. Signed: `per_team_game("passYards")` in the script.
    func passingYards(perTeamGames teamGames: Double) -> Double {
        teamGames > 0 ? signedYards / teamGames : 0
    }

    /// `row:yardsPerPlay`, the one row built on the clamped sum, because its band is:
    /// `div(c["passYardsPositive"] + c["rushYards"] + c["sackYards"], c["scrimmage"])`.
    /// Scramble yards are in neither, on both sides.
    func yardsPerPlay(rushYards: Double, sackYards: Double, scrimmagePlays: Int) -> Double {
        (positiveYards + rushYards + sackYards) / Double(max(1, scrimmagePlays))
    }
}

/// The calibration rows built on pass yardage, and which of the two sums each one uses.
///
/// The register is here, beside the arithmetic, rather than in `Targets.swift`: a row's
/// note has to say whether a completion for a loss is counted, and a sentence in a note is
/// not checked by anything. Reading both sides off this list is what stops the table and
/// the arithmetic drifting again.
enum PassYardageRow: String, CaseIterable, Sendable {
    case passingYards
    case yardsPerAttempt
    case yardsPerPlay
    case yardsPerCompletion

    /// Whether a completion for a loss is counted at its own negative yardage.
    var countsLosses: Bool { self != .yardsPerPlay }

    /// The sentence this row's note in `Targets.swift` must carry.
    var noteClause: String {
        countsLosses
            ? "A completion for a loss counts as the loss."
            : "A completion for a loss counts as nothing."
    }
}
