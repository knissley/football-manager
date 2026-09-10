import FMCore
import Testing

@testable import FMSimulation

/// What happened between two downs is on the record of the down that followed.
///
/// A timeout was visible only as a difference between two consecutive situations, so
/// one taken on the last play of a possession could not be attributed to a team, and the
/// two-minute warning was inferable from the clock landing on 2:00 and stated nowhere.
/// Both are rules-layer decision points on the next snap's record now, beside the play
/// clock and the clock elections: a `.timeout` says which side took it, and
/// `.twoMinuteWarning` says the warning was taken. A charged timeout that is the rules'
/// consequence of the play before — the offence's alternative to a runoff, an injury
/// timeout — stays a `.clockElection` on that play, which is where the referee announces
/// it.
@Suite("Timeouts and the warning on the record")
struct DeadBallRecordTests {

    private static let sample: [GameResult] = (UInt64(1)...40).map {
        TestWorld.game(seed: $0, game: GameID($0))
    }

    /// Each team's timeouts as one situation carries them, keyed by team.
    private func counts(_ situation: Situation, in result: GameResult) -> [TeamID: Int] {
        var counts: [TeamID: Int] = [situation.possession: Int(situation.offenseTimeouts)]
        for team in result.rosters.keys where team != situation.possession {
            counts[team] = Int(situation.defenseTimeouts)
        }
        return counts
    }

    /// Every drop in a team's count between two consecutive snaps of a period is on the
    /// record: a `.timeout` on the later snap charged to that side, or a clock election
    /// on the earlier one. The injury election does not say which team, so a pair with
    /// one on it is checked as a sum over both teams.
    @Test(
        "Every charged timeout is on the record with its side, and the counts agree",
        .tags(.contract))
    func timeoutsAreOnTheRecord() {
        var recorded = 0
        for result in Self.sample {
            for (previous, next) in zip(result.plays, result.plays.dropFirst())
            where previous.situation.quarter == next.situation.quarter {
                let at = "plays \(previous.index) and \(next.index) of game \(result.game)"
                let before = counts(previous.situation, in: result)
                let after = counts(next.situation, in: result)
                let elections = previous.decisions.compactMap(\.clockElectionValue)
                let runoffTimeouts = elections.filter { $0 == .timeoutInsteadOfRunoff }.count
                let injuryTimeouts = elections.filter { $0 == .injuryTimeoutCharged }.count
                let taken = next.timeoutsBeforeTheSnap
                recorded += taken.offense + taken.defense

                var charged: [TeamID: Int] = [:]
                let offense = next.situation.possession
                charged[offense, default: 0] += taken.offense
                for team in result.rosters.keys where team != offense {
                    charged[team, default: 0] += taken.defense
                }
                charged[previous.situation.possession, default: 0] += runoffTimeouts

                if injuryTimeouts == 0 {
                    for (team, count) in before {
                        let drop = count - (after[team] ?? count)
                        #expect(
                            drop == charged[team] ?? 0,
                            "\(at): \(team) lost \(drop) timeouts and the record charges \(charged[team] ?? 0)"
                        )
                    }
                } else {
                    let drop = before.values.reduce(0, +) - after.values.reduce(0, +)
                    let explained = charged.values.reduce(0, +) + injuryTimeouts
                    #expect(
                        drop == explained, "\(at): \(drop) timeouts lost, \(explained) recorded")
                }
            }
        }
        #expect(recorded > 100, "forty games and \(recorded) timeouts taken before a snap")
    }

    /// The warning is taken at the end of the last down snapped before 2:00 of the second
    /// and fourth periods (2025 rulebook, 3-41) and of a regular-season overtime period
    /// (16-1-3-e), so it is on the first snap of that period taken with two minutes or
    /// less to play, and on no other.
    @Test(
        "The two-minute warning is on the record once a half, on the first snap after it",
        .tags(.contract))
    func warningIsOnTheRecord() {
        for result in Self.sample {
            let periods = Set(result.plays.map(\.situation.quarter))
            for quarter in periods {
                let inPeriod = result.plays.filter { $0.situation.quarter == quarter }
                let warned = inPeriod.filter(\.hasTwoMinuteWarningBeforeTheSnap)
                let at = "period \(quarter) of game \(result.game)"
                if quarter == 2 || quarter == 4 || quarter == 5 {
                    #expect(warned.count == 1, "\(at): \(warned.count) warnings")
                    let firstUnderTwo = inPeriod.first { $0.situation.clockRemaining <= 120 }
                    #expect(
                        warned.first?.index == firstUnderTwo?.index,
                        "\(at): warned before play \(String(describing: warned.first?.index)), two minutes at play \(String(describing: firstUnderTwo?.index))"
                    )
                } else {
                    #expect(warned.isEmpty, "\(at): a warning in a period that has none")
                }
            }
        }
    }
}
