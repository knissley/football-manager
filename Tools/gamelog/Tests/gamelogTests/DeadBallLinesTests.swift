import FMCore
import FMSimulationScenarios
import Testing

@testable import gamelog

/// What the printer says about the dead ball between two downs.
///
/// A timeout used to be a difference between two consecutive situations and the
/// two-minute warning an inference from the clock landing on 2:00, so the log could show
/// neither. Both are on the record of the snap they preceded now, and the printer reads
/// them off it: the timeout with the team that took it and what it has left, the warning
/// as a line of its own, each above the line of the snap that followed.
@Suite("Timeouts and the warning in the log")
struct DeadBallLinesTests {

    /// The lines of the log that are the dead ball before a snap, with the surrounding
    /// spaces dropped.
    private func deadBallLines(in lines: [String]) -> [Substring] {
        lines.map { $0.drop(while: { $0 == " " }) }
            .filter { $0.hasPrefix("timeout: ") || $0 == "two-minute warning" }
    }

    /// Whoever is on defence in the fourth quarter of this scenario burns its timeouts,
    /// and both sides defend in it, so each side burns three; a regulation game has a
    /// warning in each half (2025 rulebook, 3-41). Every one is printed, in the order it
    /// happened, with the side that took it and what it has left counting down.
    @Test(
        "contract: every timeout is printed with its team and what it has left, and both warnings are printed",
        .tags(.contract))
    func timeoutsAndWarningsArePrinted() {
        let scenario = RulesScenario.neutralZoneInfractionInTheLastFortySecondsWithTheOffenseLeading
        let trace = scenario.run()
        let onTheRecord = trace.plays.reduce(0) {
            $0 + $1.timeoutsBeforeTheSnap.offense + $1.timeoutsBeforeTheSnap.defense
        }
        let warnings = trace.plays.filter(\.hasTwoMinuteWarningBeforeTheSnap).count
        #expect(onTheRecord == 6, "three a side; \(onTheRecord) recorded")
        #expect(warnings == 2, "one a half; \(warnings) recorded")

        let printed = deadBallLines(in: scenarioLines(scenario))
        let timeoutLines = printed.filter { $0.hasPrefix("timeout: ") }
        let warningLines = printed.filter { $0 == "two-minute warning" }
        #expect(timeoutLines.count == onTheRecord, "\(timeoutLines)")
        #expect(warningLines.count == warnings)

        // `timeout: NRW (2 left)`: the team, and what it has left, counting down per team.
        var remaining: [Substring: [Int]] = [:]
        for line in timeoutLines {
            let team = line.dropFirst("timeout: ".count).prefix(while: { $0 != " " })
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"),
                let left = Int(
                    line[line.index(after: open)..<close].split(separator: " ").first ?? "")
            else {
                Issue.record("unreadable timeout line: \(line)")
                continue
            }
            remaining[team, default: []].append(left)
        }
        #expect(remaining.count == 2, "both sides took some: \(timeoutLines)")
        for (team, left) in remaining {
            #expect(!team.isEmpty, "the line names the team")
            #expect(left == [2, 1, 0], "\(team) counted \(left)")
        }
    }

    /// The clock a play line was printed with, in seconds: `   7  Q2 1:57  NRW ...`.
    private func clock(ofPlayLine line: String) -> Int? {
        let fields = line.split(separator: " ")
        guard fields.count > 2, Int(fields[0]) != nil else { return nil }
        let parts = fields[2].split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else {
            return nil
        }
        return minutes * 60 + seconds
    }

    /// The warning is printed above the first snap taken with two minutes or less to
    /// play in the period, which is where the record puts it: the play line after it
    /// reads 2:00 or less, and the one before it read more.
    @Test("contract: the warning is printed above the first snap after 2:00", .tags(.contract))
    func warningIsPrintedBeforeTheSnapThatFollowedIt() {
        let lines = scenarioLines(.playRunningPastTheTwoMinuteWarning)
        guard
            let warning = lines.firstIndex(where: {
                $0.drop(while: { $0 == " " }) == "two-minute warning"
            })
        else {
            Issue.record("no warning printed")
            return
        }
        let after = lines[(warning + 1)...].lazy.compactMap(clock(ofPlayLine:)).first
        let before = lines[..<warning].reversed().lazy.compactMap(clock(ofPlayLine:)).first
        #expect(after.map { $0 <= 120 } == true, "the snap after the warning reads \(after ?? -1)")
        #expect(before.map { $0 > 120 } == true, "the snap before it read \(before ?? -1)")
    }
}
