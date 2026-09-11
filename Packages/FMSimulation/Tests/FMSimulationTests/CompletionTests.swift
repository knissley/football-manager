import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

/// A completion is a fact in the record, and so are the points.
///
/// `PlayEnding` cannot say a pass was caught: a catch for a loss ends `.tackled` exactly
/// like a run, so a reader that infers a completion from positive yards misses every
/// catch that gained nothing — which is worth about three points of completion
/// percentage, and shows green the whole time. `Outcome.passResult` says it outright.
/// And `Outcome.pointsScored` sat on every record at zero, so a scoreboard was never a
/// sum over the stream — it was the rules run again.
///
/// Promises the engine makes about its stream, not claims about the sport.
@Suite("Completions and points in the record")
struct CompletionTests {

    /// The standard corpus, whose size is derived where it is defined.
    ///
    /// This suite used to size the sample itself, and the number it arrived at was a
    /// coverage floor for the rarest thing it asserted: the safety, which in the first
    /// forty games of this world was one. Which game a safety falls in moves whenever the
    /// caller does, and it moved: the sample had to be widened from twenty to forty when a
    /// caller change took the first one past game twenty. Forty was never enough either —
    /// the rate is 0.075 a game, so forty games miss a safety one time in twenty. The
    /// safety is asserted against a fixture that constructs one now, and nothing left over
    /// this sample is rarer than a two-point conversion at a fifth of a game.
    private static let sample: [GameResult] = TestWorld.corpus
    private static var plays: [PlayRecord] { sample.flatMap(\.plays) }

    /// A game in which somebody is tackled in his own end zone, scripted rather than
    /// waited for.
    ///
    /// The scoring plays this suite asserts on are common except this one, and a sample
    /// is the wrong instrument for a case at 0.075 a game: it either drew one or it did
    /// not, and no size makes the answer certain. `RulesScenario.safetyFreeKick` builds a
    /// game around the play, so the assertion below fails the moment a safety stops being
    /// recorded as one — immediately, and for the reason it says.
    private static let scriptedSafety: [PlayRecord] = RulesScenario.safetyFreeKick.run().plays

    /// The whole point: a ball caught behind the line, or for nothing, is a completion.
    ///
    /// The floor is a guard on the instrument. Measured over the corpus: 1,812 completions
    /// in forty games and 107 of them for nothing, so the sample carries ten times what the
    /// floor asks and the assertion after it is made of a hundred plays rather than of one.
    @Test("Completions for zero or fewer yards occur, and are marked complete", .tags(.contract))
    func completionsForNothingAreComplete() {
        let caughtForNothing = Self.plays.filter {
            $0.outcome.kind == .pass && $0.outcome.passResult == .complete && $0.outcome.yards <= 0
        }
        #expect(
            caughtForNothing.count > 10,
            "forty games and \(caughtForNothing.count) catches for nothing")
        for play in caughtForNothing {
            #expect(play.isCompletion)
            #expect(play.outcome.endedIn != .incomplete, "a completion that ended incomplete")
        }
    }

    /// Every pass says how it ended as a pass, and nothing that was not a pass does.
    ///
    /// A two-point conversion is a run or a pass at the caller's choice (11-3-1) and both
    /// are `PlayKind.twoPointConversion`, so the concept on the call is what says which.
    /// Reading the kind alone made every conversion a throw, which is the rule the engine
    /// used to have wrong.
    ///
    /// **A called pass is not always a thrown one, and on a try the kind cannot say so.**
    /// An ordinary dropback that ends in a sack or a scramble is recorded as a `.sack` or
    /// a `.scramble` and never as a `.pass`, so the kind settles it. A try is one
    /// scrimmage down and is the try however it ended (11-3-1, 11-3-2-e), so its kind
    /// stays `.twoPointConversion` down every exit and the sacked and scrambled ones look
    /// from the outside exactly like the thrown ones. The ball did not leave on either,
    /// so neither has a pass result — and this reads the throw decision, which is the only
    /// thing on the record that separates them.
    ///
    /// This used to say a try called as a pass always carries a pass result, which was
    /// true of the engine and not of the sport: a beaten blocker could not reach the
    /// quarterback before a try's 1,500 ms throw, so the pressure exits were dead on one.
    /// They are live now. Rewritten rather than deleted, because the claim it was making
    /// about a *thrown* try is still the claim worth making.
    @Test("Every pass attempt carries a pass result and no other play does", .tags(.contract))
    func passResultsAreWherePassesAre() {
        for play in Self.plays {
            let kind = play.outcome.kind
            // The ball never left: the pocket broke and he went down with it or ran.
            let neverThrown = play.decisions(ofKind: .throwDecision).contains {
                $0.throwDecisionValue == .sack || $0.throwDecisionValue == .scramble
            }
            let isThrow =
                kind == .pass || kind == .spike
                || (kind == .twoPointConversion && play.calls.offense.concept == .twoPointPass
                    && !neverThrown)
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
    ///
    /// The promise holds over every play in both streams; the *coverage* half — that each
    /// way of scoring turns up at all — is split by how often the engine produces it.
    /// Measured over the corpus's first eighty games, per game: the try-kick 5.4, the
    /// touchdown 5.8, the field goal 3.1, the defensive touchdown 0.31, the two-point
    /// conversion 0.20. Forty games expect eight of the thinnest of those. The safety, at
    /// 0.075, is an order thinner than any of them and is asserted against the scripted
    /// game instead.
    @Test("Points sit on scoring plays only, and say who scored", .tags(.contract))
    func pointsSitOnScoringPlays() {
        var kinds: Set<Scoring> = []
        for play in Self.plays + Self.scriptedSafety {
            let outcome = play.outcome
            if let scoring = outcome.scoring {
                kinds.insert(scoring)
                #expect(outcome.pointsScored > 0, "play \(play.index): \(scoring) worth nothing")
            } else {
                #expect(outcome.pointsScored == 0, "play \(play.index): points with no score")
            }
        }
        for kind in [
            Scoring.touchdown, .fieldGoal, .extraPoint, .twoPointConversion, .defensiveTouchdown,
        ] {
            #expect(kinds.contains(kind), "forty games never scored a \(kind)")
        }
        #expect(
            Self.scriptedSafety.contains { $0.outcome.scoring == .safety },
            "the scripted safety did not record one")
    }
}
