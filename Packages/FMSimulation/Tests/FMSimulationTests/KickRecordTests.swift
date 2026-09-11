import FMCore
import Testing

@testable import FMSimulation

/// What the record says about a kick and a takeaway, and what follows from it.
///
/// A returned punt used to carry only where it came to rest, so the gross of a returned
/// punt, the return itself and the net the harness graded could not be recovered from
/// the stream: the harness read the net off the resting spot and called a touchback a
/// punt to the goal line. A takeaway carried no spot where possession was lost, so a
/// defensive foul on one was enforced from the previous spot, with a comment admitting
/// it. Both facts are on `Outcome` now, and everything else is a query over them.
@Suite("Kicks and takeaways on the record")
struct KickRecordTests {

    private static let sample: [GameResult] = (UInt64(1)...40).map {
        TestWorld.game(seed: $0, game: GameID($0))
    }

    /// The Done-when: gross, return and net for every punt in forty games, off the
    /// record alone. The identities are what make the derivations checkable without
    /// the resolver's own numbers: a kick is fielded short of where it was kicked from,
    /// a return ends no nearer the receivers' goal than where it began, a kick that was
    /// fair caught, downed or run out of bounds is dead where it was fielded, and the net
    /// is the line to where the ball came to rest — or to the twenty on a touchback,
    /// which is how the league scores one.
    @Test(
        "Every kick says where it was fielded, and gross, return and net follow from it",
        .tags(.contract))
    func kickDistancesAreDerivable() {
        let rules = Rules.standard
        var punts = 0
        var returned = 0
        var touchbacks = 0
        var kickoffs = 0
        for result in Self.sample {
            for play in result.plays
            where play.outcome.kind == .punt || play.outcome.kind == .kickoff {
                let outcome = play.outcome
                let at = "play \(play.index) of game \(result.game)"
                let ballOn = Int(play.situation.ballOn)
                if outcome.kind == .punt { punts += 1 } else { kickoffs += 1 }

                switch outcome.endedIn {
                case .touchback:
                    touchbacks += 1
                    #expect(outcome.fieldedAt == nil, "\(at): a touchback was fielded by nobody")
                    #expect(
                        play.kickDistance == ballOn,
                        "\(at): a touchback is measured to the goal line")
                    #expect(play.returnYards == nil, "\(at): nothing was returned")
                    if outcome.kind == .punt {
                        #expect(
                            play.netPuntDistance(rules: rules)
                                == ballOn - Int(rules.puntTouchbackOwnYard),
                            "\(at): a touchback nets a punt to the twenty")
                    }
                case .blocked:
                    #expect(play.kickDistance == nil, "\(at): a blocked kick has no distance")
                default:
                    guard let fielded = outcome.fieldedAt, let resting = outcome.finalSpot else {
                        Issue.record(
                            "\(at): \(outcome.endedIn) with no fielding spot or resting spot")
                        continue
                    }
                    #expect(
                        Int(fielded) < ballOn,
                        "\(at): fielded at \(fielded) on a kick from \(ballOn)")
                    #expect(play.kickDistance == ballOn - Int(fielded), "\(at): the gross")
                    if outcome.endedIn == .tackled || outcome.endedIn == .touchdown {
                        returned += 1
                        #expect(Int(resting) >= Int(fielded), "\(at): a return that lost ground")
                        #expect(
                            play.returnYards == Int(resting) - Int(fielded), "\(at): the return")
                    } else {
                        #expect(
                            Int(resting) == Int(fielded),
                            "\(at): \(outcome.endedIn) is dead where it was fielded")
                        #expect(play.returnYards == 0, "\(at): \(outcome.endedIn) is no return")
                    }
                    if outcome.kind == .punt {
                        #expect(
                            play.netPuntDistance(rules: rules) == ballOn - Int(resting),
                            "\(at): the net is the line to where the ball came to rest")
                    }
                }
            }
        }
        #expect(punts > 200, "forty games and \(punts) punts")
        #expect(kickoffs > 200, "forty games and \(kickoffs) kickoffs")
        #expect(returned > 100, "forty games and \(returned) returns")
        #expect(touchbacks > 10, "forty games and \(touchbacks) touchbacks")
    }

    /// A kick that is not a kick carries none of it, and neither does a play from
    /// scrimmage.
    @Test("Nothing but a kick says where it was fielded", .tags(.contract))
    func onlyKicksAreFielded() {
        for result in Self.sample {
            for play in result.plays
            where play.outcome.kind != .punt && play.outcome.kind != .kickoff {
                #expect(
                    play.outcome.fieldedAt == nil,
                    "play \(play.index) of game \(result.game): a \(play.outcome.kind) was fielded")
                #expect(play.kickDistance == nil)
                #expect(play.returnYards == nil)
                #expect(play.netPuntDistance(rules: .standard) == nil)
            }
        }
    }

    /// The spot a defensive foul on a takeaway is enforced from, and nothing else.
    @Test("Every takeaway says where possession was lost", .tags(.contract))
    func takeawaysCarryTheSpot() {
        var takeaways = 0
        for result in Self.sample {
            for play in result.plays {
                let at = "play \(play.index) of game \(result.game)"
                guard play.outcome.endedIn.isTurnover else {
                    #expect(
                        play.outcome.possessionLostAt == nil,
                        "\(at): possession was not lost on a \(play.outcome.endedIn)")
                    continue
                }
                takeaways += 1
                guard let lost = play.outcome.possessionLostAt else {
                    Issue.record("\(at): a \(play.outcome.endedIn) with no spot")
                    continue
                }
                #expect(lost >= 1 && lost <= 99, "\(at): lost at \(lost)")
                if let resting = play.outcome.finalSpot {
                    #expect(
                        resting >= lost,
                        "\(at): the ball came to rest at \(resting), nearer the goal than \(lost)")
                }
            }
        }
        #expect(takeaways > 50, "forty games and \(takeaways) takeaways")
    }
}
