import Foundation
import Testing

@testable import simharness

/// The calibration table lives in one place. docs/match-engine.md shows it and
/// Targets.swift is it; these tests are what stops the two drifting apart, and what stops
/// a band being added without a season and a source.
@Suite("Calibration targets")
struct TargetsTests {

    /// docs/match-engine.md, found from this file rather than the working directory so
    /// the test passes wherever `swift test` is run from.
    private var documentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TargetsTests.swift
            .deletingLastPathComponent()  // simharnessTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // simharness
            .deletingLastPathComponent()  // Tools
            .appendingPathComponent("docs/match-engine.md")
    }

    @Test(
        "contract: the calibration table in match-engine.md is the one Targets.swift generates",
        .tags(.contract))
    func documentTableMatchesTargets() throws {
        let document = try String(contentsOf: documentURL, encoding: .utf8)
        let begin = "<!-- calibration-targets:begin -->"
        let end = "<!-- calibration-targets:end -->"
        guard let start = document.range(of: begin), let stop = document.range(of: end) else {
            Issue.record("docs/match-engine.md has lost its calibration-targets markers")
            return
        }
        let inDocument = document[start.upperBound..<stop.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = CalibrationTarget.markdownTable()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            inDocument == generated,
            "regenerate with `swift run --package-path Tools/simharness simharness --targets-markdown`"
        )
    }

    @Test(
        "contract: every target has a unique id, and a sourced band names a season and a source",
        .tags(.contract))
    func everyTargetIsSourcedOrSaysItIsNot() {
        var seen: Set<String> = []
        for target in CalibrationTarget.all {
            #expect(seen.insert(target.id).inserted, "duplicate id \(target.id)")
            switch target.season {
            case .seasons(let range):
                #expect(!target.source.isEmpty, "\(target.id) has a season but no source")
                #expect(target.low != nil && target.high != nil, "\(target.id) has no band")
                #expect(range.lowerBound <= range.upperBound, "\(target.id) season range")
            case .unsourced:
                #expect(target.source.isEmpty, "\(target.id) is unsourced but names a source")
            }
            if let low = target.low, let high = target.high {
                #expect(low <= high, "\(target.id) band is inverted")
            }
        }
    }

    /// The intended state until D2 (#46): under the 2025 rulebook the rows sourced from the
    /// 2024 kickoff season are stale, and under 2024 the 2025 ones are. A row sourced from
    /// 2023–24 that is sensitive to the kickoff would be stale under both, which is why no
    /// such row exists.
    @Test(
        "contract: rule-sensitive rows are stale under exactly the other rulebook", .tags(.contract)
    )
    func staleRowsFollowTheRulebook() {
        let under2025 = CalibrationTarget.stale(under: 2025)
        let under2024 = CalibrationTarget.stale(under: 2024)
        for target in CalibrationTarget.all {
            let sensitive = !target.rulesSensitiveTo.isEmpty
            switch target.season {
            case .seasons(let range)
            where sensitive && range.upperBound == 2024
                && !target.rulesSensitiveTo.isDisjoint(with: [.kickoff, .onsideKick, .overtime]):
                #expect(under2025[target.id] != nil, "\(target.id) should be stale under 2025")
                #expect(under2024[target.id] == nil, "\(target.id) should be current under 2024")
            case .seasons(let range) where sensitive && range.lowerBound == 2025:
                #expect(under2025[target.id] == nil, "\(target.id) should be current under 2025")
                #expect(under2024[target.id] != nil, "\(target.id) should be stale under 2024")
            default:
                #expect(under2025[target.id] == nil, "\(target.id) unexpectedly stale under 2025")
                #expect(under2024[target.id] == nil, "\(target.id) unexpectedly stale under 2024")
            }
        }
        #expect(!under2025.isEmpty)
        #expect(!under2024.isEmpty)
    }

    @Test(
        "unit: a value prints with the row's precision and unit, and a band without the unit",
        .tags(.unit))
    func formatting() {
        let target = CalibrationTarget(
            id: "t", label: "t", low: 1.25, high: 2, season: .season(2025), source: "s",
            rulesSensitiveTo: [], gate: true, decimals: 2, unit: "%")
        #expect(target.format(1.234) == "1.23%")
        #expect(target.format(-0.456) == "-0.46%", "a value in (-1, 0) keeps its sign")
        #expect(target.band == "1.25-2.00")
        let whole = CalibrationTarget(
            id: "w", label: "w", low: 152, high: 170, season: .season(2025), source: "s",
            rulesSensitiveTo: [], gate: true, decimals: 0)
        #expect(whole.format(157.6) == "158")
        #expect(whole.format(-2.6) == "-3")
        #expect(whole.band == "152-170")
        #expect(TargetSeason.seasons(2023...2024).printed == "2023-24")
        #expect(TargetSeason.season(2025).printed == "2025")
    }
}
