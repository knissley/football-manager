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

    /// The defence burns its three timeouts in the fourth quarter of this scenario, and a
    /// regulation game has a warning in each half (2025 rulebook, 3-41). Every one is
    /// printed, and printed in the order it happened.
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
        #expect(onTheRecord == 3, "the scenario's defence burns three; \(onTheRecord) recorded")
        #expect(warnings == 2, "one a half; \(warnings) recorded")

        let printed = deadBallLines(in: scenarioLines(scenario))
        let timeoutLines = printed.filter { $0.hasPrefix("timeout: ") }
        let warningLines = printed.filter { $0 == "two-minute warning" }
        #expect(timeoutLines.count == onTheRecord, "\(timeoutLines)")
        #expect(warningLines.count == warnings)

        // The same side three times, counting down: `timeout: NRW (2 left)`.
        let remaining = timeoutLines.compactMap { line -> Int? in
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")") else {
                return nil
            }
            return Int(line[line.index(after: open)..<close].split(separator: " ").first ?? "")
        }
        #expect(remaining == [2, 1, 0], "\(timeoutLines)")
        let teams = Set(
            timeoutLines.map { $0.dropFirst("timeout: ".count).prefix(while: { $0 != " " }) })
        #expect(teams.count == 1, "one side took all three: \(teams)")
        #expect(teams.first.map { !$0.isEmpty } == true, "the line names the team")
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
