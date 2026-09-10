import FMCore
import FMSimulationScenarios
import Testing

@testable import gamelog

/// What the drive summaries say about a game that runs past one overtime period.
///
/// `gamelog` prints a drive summary at every change of possession — how many plays, how
/// many yards, how long the drive had the ball, and how it ended — and a scoreboard at
/// every period boundary. Both are folds over the `PlayRecord` stream, and both were
/// written when a game could reach at most one overtime period, of one length. A
/// postseason game plays as many periods as it takes, each of fifteen minutes, and it
/// resumes them from where the ball was rather than with a kickoff (2025 rulebook,
/// 16-1-4-d). #74 taught the period labels to count them; the arithmetic under those
/// labels did not follow, which is #87.
///
/// These are `.contract` tests: they assert what the printer promises about the stream —
/// that a drive's time is the clock it consumed and that a drive summary is printed when
/// a drive actually ends — not a rule of the sport. The football they lean on is cited
/// where it decides the shape of the assertion.
@Suite("Drive summaries past one overtime period")
struct DriveSummaryTests {

    // MARK: Reading the printed lines

    /// The drive summaries, in the order they were printed.
    private func driveSummaries(in lines: [String]) -> [String] {
        lines.filter { $0.contains(" drive: ") }
    }

    /// The `M:SS` a drive summary reports as its time of possession, in seconds.
    private func time(ofDrive summary: String) -> Int? {
        // `        ── NRW drive: 4 plays, 4 yards, 1:57 — turnover on downs`
        guard let field = summary.split(separator: ",").dropFirst(2).first,
            let clock = field.split(separator: " ").first
        else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let rest = Int(parts[1]) else {
            return nil
        }
        return minutes * 60 + rest
    }

    /// Seconds of football played by the end of `play`, from the period lengths the game
    /// was played under.
    ///
    /// Every period before it at its own length — `quarterLength` in regulation and
    /// `overtimeLength(isPostseason:)` after it, the lengths `GameClock.advancingPeriod`
    /// hands out — plus the clock this period had spent by the reading `play` carries,
    /// plus the play itself. All but the last term is derived from `Rules` and the record
    /// alone, which is what makes it a check on the tool rather than a copy of it.
    ///
    /// **The last term is not independent.** The interval before a snap is nowhere in a
    /// `PlayRecord`, so neither the tool nor this can say when the final play of a game
    /// actually ended; both take the reading plus the play's own seconds, clamped to the
    /// end of the period, and this expectation is *pinned* to that approximation on
    /// purpose — a game that ends on a score has to be measured the same way on both
    /// sides or the sum can never balance. It is worth six seconds here. What the test
    /// is for survives either definition: the bug it was written against had these two
    /// games' drives summing to 5257 and 5207 against a little over 4500.
    private func clockPlayed(through play: PlayRecord, rules: Rules, isPostseason: Bool) -> Int {
        func length(ofPeriod period: UInt8) -> Int {
            period <= rules.quarters
                ? Int(rules.quarterLength) : Int(rules.overtimeLength(isPostseason: isPostseason))
        }
        let quarter = play.situation.quarter
        var played = 0
        for period in 1..<quarter { played += length(ofPeriod: period) }
        let periodEnd = played + length(ofPeriod: quarter)
        let atTheSnap = periodEnd - Int(play.situation.clockRemaining)
        return min(periodEnd, atTheSnap + Int(play.outcome.clockRunoff))
    }

    // MARK: The tests

    /// Every second of these games belongs to a drive: both are walked a yard at a time,
    /// every kickoff in them is a touchback, which consumes no clock (4-3-1-a), and
    /// nobody scores a touchdown, so no try is played. So the drive times are the whole
    /// game, and if they sum to anything but the clock played, a drive has been measured
    /// against the wrong period.
    ///
    /// Both scenarios are postseason games decided in a second overtime period, which is
    /// the case the tool measured as one period of the regular season's ten minutes.
    @Test(
        "contract: the drive times of a two-period postseason overtime sum to the clock played",
        .tags(.contract),
        arguments: [
            RulesScenario.scorelessPostseasonUntilTheSixthPeriod,
            RulesScenario.falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes,
        ])
    func timesOfPossessionSumToTheClockPlayed(scenario: RulesScenario) throws {
        let game = scenario.game
        let trace = scenario.run()
        let rules = game.rules

        // The premise, asserted rather than assumed: nothing between the drives took any
        // clock, so every second of the game is inside one.
        #expect(game.isPostseason)
        for play in trace.plays where play.outcome.kind == .kickoff {
            #expect(
                play.outcome.endedIn == .touchback,
                "a returned kickoff would take clock that belongs to no drive")
        }
        #expect(
            !trace.plays.contains {
                $0.outcome.kind == .extraPoint || $0.outcome.kind == .twoPointConversion
            }, "a try would take clock that belongs to no drive")

        let last = try #require(trace.plays.last)
        #expect(last.situation.quarter == rules.quarters + 2, "this game is decided in a 2OT")
        let played = clockPlayed(through: last, rules: rules, isPostseason: game.isPostseason)

        let summaries = driveSummaries(in: scenarioLines(scenario))
        var total = 0
        for summary in summaries {
            total += try #require(time(ofDrive: summary), "unreadable drive line: \(summary)")
        }
        #expect(
            total == played,
            "\(summaries.count) drives sum to \(total)s in a game that played \(played)s")
    }

    /// A postseason overtime period that ends undecided is not a break in play: the next
    /// period begins with the ball where it was and the same team in possession
    /// (16-1-4-d). So a drive under way at the end of a first overtime period is still
    /// under way in the second, and printing its summary there ends a drive that did not
    /// end — under a label that is wrong twice over, because a first postseason overtime
    /// period does not end a half either (16-1-4-h).
    @Test(
        "contract: a drive is not closed at the end of a first postseason overtime period",
        .tags(.contract))
    func aDriveCarriesIntoTheSecondPostseasonOvertimePeriod() throws {
        let scenario = RulesScenario.falseStartInAFirstPostseasonOvertimePeriodOutsideTwoMinutes
        let lines = scenarioLines(scenario)

        // The scoreboard at the end of the first overtime period, and the line before the
        // rule that opens it — which is the last thing printed while that period was on.
        let banner = try #require(
            lines.firstIndex { $0.contains("end of OT ·") }, "no end-of-OT scoreboard was printed")
        try #require(banner >= 2)
        #expect(
            !lines[banner - 2].contains(" drive: "),
            "a drive was closed at the end of the first overtime period: \(lines[banner - 2])")

        // And nothing after regulation is called the end of a half.
        let regulation = try #require(
            lines.firstIndex { $0.contains("end of Q4 ·") }, "no end-of-Q4 scoreboard was printed")
        for line in lines[regulation...] where line.contains(" drive: ") {
            #expect(
                !line.hasSuffix("end of half"),
                "a drive in overtime was called the end of a half: \(line)")
        }
    }
}
