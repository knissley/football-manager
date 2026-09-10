import Foundation
import Testing

@testable import simharness

/// The Budget block is arithmetic over one measured number and two constants from
/// docs/match-engine.md. The measurement itself cannot be asserted — it is whatever the
/// machine did — so what is tested here is the arithmetic, the shape of the block, and
/// that the budget it prints is still the one the doc derives.
@Suite("Budget block")
struct BudgetTests {

    /// docs/match-engine.md, found from this file rather than the working directory so
    /// the test passes wherever `swift test` is run from.
    private var documentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // BudgetTests.swift
            .deletingLastPathComponent()  // simharnessTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // simharness
            .deletingLastPathComponent()  // Tools
            .appendingPathComponent("docs/match-engine.md")
    }

    @Test("unit: ms per game and the season equivalent are the elapsed time over the games")
    func perGameAndPerSeason() {
        // 400 games in 8 s is 20 ms a game, and 272 of those is 5.44 s.
        let budget = Budget(games: 400, seconds: 8)
        #expect(budget.millisecondsPerGame == 20)
        #expect(abs(budget.secondsPerSeason - 5.44) < 0.000_001)
        #expect(abs(budget.ratioToBudget - 20.0 / 220.0) < 0.000_001)
    }

    @Test("unit: a run that simulated nothing reports zero rather than dividing by it")
    func noGames() {
        let budget = Budget(games: 0, seconds: 0)
        #expect(budget.millisecondsPerGame == 0)
        #expect(budget.secondsPerSeason == 0)
        #expect(budget.ratioToBudget == 0)
    }

    @Test("contract: the block is one section, four lines of prose and five labelled numbers")
    func blockShape() {
        let lines = Budget(games: 400, seconds: 8).lines
        #expect(lines.first == "  Budget")
        // The rest are indented four spaces, so nothing in the block can be read as a
        // section header by the CI summary's parser.
        #expect(lines.dropFirst().allSatisfy { $0.hasPrefix("    ") && !$0.hasPrefix("     ") })
        #expect(lines.contains { $0.contains("ms per game") && $0.contains("20.00") })
        #expect(
            lines.contains { $0.contains("seconds per 272-game season") && $0.contains("5.44") })
        #expect(lines.contains { $0.contains("budget") && $0.contains("220.00 ms per game") })
        #expect(lines.contains { $0.contains("ratio to budget") && $0.contains("0.09x") })
        #expect(lines.contains { $0.contains("400 games in 8.00 s") })
    }

    @Test("contract: the printed budget is the one match-engine.md derives from 272 games in 60 s")
    func budgetAgreesWithTheDocument() throws {
        #expect(Budget.seasonGames == 272)
        #expect(Budget.seasonSeconds == 60)
        // 60_000 ms / 272 games = 220.588…, which the doc states as the round "≈ 220 ms
        // per game" and this block prints. Within a millisecond is what that ≈ means; a
        // constant that drifted from the derivation by more than that would be a
        // different budget.
        let derived = Budget.seasonSeconds * 1000 / Double(Budget.seasonGames)
        #expect(abs(derived - Budget.millisecondsPerGameBudget) < 1)

        let document = try String(contentsOf: documentURL, encoding: .utf8)
        #expect(
            document.contains("272 games / 60s") && document.contains("220 ms per game"),
            "match-engine.md's performance budget no longer derives 220 ms from 272 games in 60 s"
        )
    }
}
