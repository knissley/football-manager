import Testing

@testable import simharness

/// What a completion for a loss does to each row built on pass yardage.
///
/// The harness used to sum every pass attempt as `max(0, yards)` and hand that one number
/// to four rows, three of whose bands were derived from a signed sum. A ball caught behind
/// the line for a three-yard loss counted as nothing, so the rows read high by however
/// many such catches the engine happened to throw — invisibly, because the word "gross"
/// in the band notes was used for the clamped quantity and the signed one in the same file.
///
/// These fix which row is which. The corpus is one of each shape, so every figure below can
/// be arrived at by hand from the four attempts in `corpus`.
@Suite("Pass yardage")
struct PassYardageTests {

    /// Four attempts: a gain, a catch for a loss, a catch for nothing, and an incompletion.
    private let corpus = [
        PassAttempt(yards: 12, isCompletion: true, endedInTouchdown: false),
        PassAttempt(yards: -3, isCompletion: true, endedInTouchdown: false),
        PassAttempt(yards: 0, isCompletion: true, endedInTouchdown: false),
        PassAttempt(yards: 0, isCompletion: false, endedInTouchdown: false),
    ]

    @Test("unit: the two sums differ by exactly the yardage lost on completions", .tags(.unit))
    func theTwoSumsDiffer() {
        let yardage = PassYardage.over(corpus)
        #expect(yardage.attempts == 4)
        #expect(yardage.completions == 3)
        #expect(yardage.completionsThatGained == 1)
        #expect(yardage.signedYards == 9.0, "12 - 3 + 0")
        #expect(yardage.positiveYards == 12.0, "the catch for a loss counted as nothing")
    }

    /// `row:yardsPerAttempt` and `row:yardsPerCompletion` are derived from the signed sum by
    /// `scripts/calibration-sources.py`, so the harness measures them the same way.
    @Test("unit: yards per attempt and per completion count a catch for a loss", .tags(.unit))
    func theSignedRows() {
        let yardage = PassYardage.over(corpus)
        #expect(yardage.yardsPerAttempt == 9.0 / 4.0)
        #expect(yardage.yardsPerCompletion == 9.0 / 3.0)
    }

    /// `row:yardsPerPlay` is the one row whose band was derived with the catch for a loss
    /// counted as nothing, so it is the one row the harness still clamps.
    @Test("unit: yards per play counts a catch for a loss as nothing", .tags(.unit))
    func theClampedRow() {
        let yardage = PassYardage.over(corpus)
        // Four attempts and one carry for 6, with a sack for -7: five scrimmage plays.
        let value = yardage.yardsPerPlay(rushYards: 6, sackYards: -7, scrimmagePlays: 5)
        #expect(value == (12.0 + 6.0 - 7.0) / 5.0)
    }

    @Test("unit: passing yards per team-game counts a catch for a loss", .tags(.unit))
    func passingYardsPerTeamGame() {
        let yardage = PassYardage.over(corpus)
        #expect(yardage.passingYards(perTeamGames: 2) == 4.5, "9 signed yards over two team-games")
    }

    /// The gap the clamp used to hide, stated as the quantity a reader can check: with no
    /// completion for a loss in the corpus the two sums agree, and every divergence between
    /// them is exactly that play.
    @Test("unit: with no completion for a loss the two sums agree", .tags(.unit))
    func noLossMeansNoDivergence() {
        let clean = corpus.filter { $0.yards >= 0 }
        let yardage = PassYardage.over(clean)
        #expect(yardage.signedYards == yardage.positiveYards)
    }

    /// A touchdown caught behind the line of scrimmage cannot happen, but a catch for no
    /// gain that scores can — the goal line is the line of scrimmage on a play from the
    /// one-inch line. The older gains-only inference counts it, and this pins that it does,
    /// because `completionsThatGained` is no longer any row's denominator and the only
    /// thing left reading it is the catch leaderboard.
    @Test("unit: a scoring catch for no gain is a catch that gained", .tags(.unit))
    func aScoringCatchForNoGain() {
        let yardage = PassYardage.over([
            PassAttempt(yards: 0, isCompletion: true, endedInTouchdown: true)
        ])
        #expect(yardage.completionsThatGained == 1)
        #expect(yardage.completions == 1)
    }

    /// A sentence in a band note is checked by nothing, which is how one file came to use
    /// "Gross." for the clamped quantity and the signed one eleven lines apart. Each row
    /// states which it is, in the words the arithmetic's own register supplies.
    @Test(
        "contract: every row built on pass yardage says in its note whether a completion for a loss is counted",
        .tags(.contract))
    func everyRowSaysWhatItCounts() {
        for row in PassYardageRow.allCases {
            guard let target = CalibrationTarget.all.first(where: { $0.id == row.rawValue }) else {
                Issue.record("\(row.rawValue) is not a row in Targets.swift")
                continue
            }
            #expect(
                target.note.contains(row.noteClause),
                "\(row.rawValue)'s note does not carry \"\(row.noteClause)\"")
        }
    }

    /// The word that did the hiding. It described two different quantities in one file, so
    /// it describes neither now — every note says what is counted instead of naming it.
    @Test("contract: no band note calls a pass-yardage quantity gross", .tags(.contract))
    func grossIsNotUsedForPassYardage() {
        for row in PassYardageRow.allCases {
            guard let target = CalibrationTarget.all.first(where: { $0.id == row.rawValue })
            else { continue }
            let note = target.note.lowercased()
            #expect(!note.contains("gross"), "\(row.rawValue)'s note still says \"gross\"")
        }
    }
}
