import FMCore
import Testing

@testable import FMSimulation

/// A completion is a fact in the record, and so are the points.
///
/// `PlayEnding` cannot say a pass was caught: a catch for a loss ends `.tackled` exactly
/// like a run, so the harness inferred a completion from positive yards and read three
/// points low while showing green (S14 in the audit). `Outcome.passResult` says it
/// outright. And `Outcome.pointsScored` sat on every record at zero, so a scoreboard was
/// never a sum over the stream — it was the rules run again.
///
/// Promises the engine makes about its stream, not claims about the sport.
@Suite("Completions and points in the record")
struct CompletionTests {

    private static func game(seed: UInt64) -> GameResult {
        TestWorld.game(seed: seed, game: GameID(seed))
    }

    private static let sample: [GameResult] = (UInt64(1)...20).map(game(seed:))
    private static var plays: [PlayRecord] { sample.flatMap(\.plays) }

    /// The whole point: a ball caught behind the line, or for nothing, is a completion.
    @Test("Completions for zero or fewer yards occur, and are marked complete", .tags(.contract))
    func completionsForNothingAreComplete() {
        let caughtForNothing = Self.plays.filter {
            $0.outcome.kind == .pass && $0.outcome.passResult == .complete && $0.outcome.yards <= 0
        }
        #expect(
            caughtForNothing.count > 10,
            "twenty games and \(caughtForNothing.count) catches for nothing")
        for play in caughtForNothing {
            #expect(play.isCompletion)
            #expect(play.outcome.endedIn != .incomplete, "a completion that ended incomplete")
        }
    }

    /// Every pass says how it ended as a pass, and nothing that was not a pass does.
    @Test("Every pass attempt carries a pass result and no other play does", .tags(.contract))
    func passResultsAreWherePassesAre() {
        for play in Self.plays {
            let kind = play.outcome.kind
            let isThrow = kind == .pass || kind == .twoPointConversion || kind == .spike
            if isThrow {
                #expect(
                    play.outcome.passResult != nil,
                    "play \(play.index): a \(kind) with no pass result")
            } else {
                #expect(
                    play.outcome.passResult == nil,
                    "play \(play.index): a \(kind) carrying a pass result")
            }
        }
    }

    /// The pass result and the ending describe the same play.
    @Test("The pass result agrees with the ending and the catch decision", .tags(.contract))
    func passResultAgreesWithTheEnding() {
        var seen: Set<PassResult> = []
        for play in Self.plays where play.outcome.kind == .pass {
            guard let result = play.outcome.passResult else { continue }
            seen.insert(result)
            let ending = play.outcome.endedIn
            switch result {
            case .incomplete:
                #expect(ending == .incomplete, "play \(play.index): incomplete but ended \(ending)")
            case .intercepted:
                #expect(
                    ending == .intercepted, "play \(play.index): intercepted but ended \(ending)")
            case .complete:
                #expect(
                    ending != .incomplete && ending != .intercepted,
                    "play \(play.index): complete but ended \(ending)")
            }
            if let attempt = play.decisions(ofKind: .catchAttempt).last?.catchResult {
                let caught = attempt == .caught || attempt == .contestedCatch
                #expect(
                    (result == .complete) == caught,
                    "play \(play.index): the catch decision says \(attempt), the record says \(result)"
                )
            }
        }
        #expect(
            seen == Set(PassResult.allCases),
            "the sample never produced \(Set(PassResult.allCases).subtracting(seen))")
    }

    /// The points are on the play that scored them, with who scored, and nowhere else.
    @Test("Points sit on scoring plays only, and say who scored", .tags(.contract))
    func pointsSitOnScoringPlays() {
        var kinds: Set<Scoring> = []
        for play in Self.plays {
            let outcome = play.outcome
            if let scoring = outcome.scoring {
                kinds.insert(scoring)
                #expect(outcome.pointsScored > 0, "play \(play.index): \(scoring) worth nothing")
            } else {
                #expect(outcome.pointsScored == 0, "play \(play.index): points with no score")
            }
        }
        for kind in [
            Scoring.touchdown, .fieldGoal, .extraPoint, .twoPointConversion, .safety,
            .defensiveTouchdown,
        ] {
            #expect(kinds.contains(kind), "twenty games never scored a \(kind)")
        }
    }
}
