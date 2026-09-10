import FMCore
import FMSimulationScenarios
import Testing

@testable import FMSimulation

// The assertions a rules scenario makes over a scripted game's stream.
//
// The stream itself, and everything that produces one — `Snap`, the outcome vocabulary,
// `ScriptedCaller`, `ScriptedGame` and `Trace` — is `FMSimulationScenarios`, a plain
// library, so that `gamelog --scenario <name>` can walk the same game a test asserts on.
// These are the half that only a test can hold: they are `#expect` and `Issue.record`,
// and Swift Testing does not belong in a module a tool links.
//
// Nothing here decides anything about football. Each one checks the facts a scenario
// names and says which play it was looking at when it did not find them; a scenario that
// runs a different game from the one it meant to is a failure that reads like one.

extension Trace {

    /// One play, checked against every fact the scenario names. A `nil` fact is not
    /// checked. A missing play is one failure, not ten.
    func expectPlay(
        _ index: Int,
        kind: PlayKind? = nil,
        endedIn: PlayEnding? = nil,
        possession: TeamID? = nil,
        quarter: UInt8? = nil,
        clock: UInt16? = nil,
        down: Down? = nil,
        distance: UInt8? = nil,
        ballOn: UInt8? = nil,
        clockRunning: Bool? = nil,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let play = self[index] else {
            Issue.record(
                "no play \(index): the game had \(plays.count) — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
            return
        }
        let at = "play \(index)"
        if let kind {
            #expect(
                play.outcome.kind == kind, "\(at) kind — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let endedIn {
            #expect(
                play.outcome.endedIn == endedIn, "\(at) ending — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let possession {
            #expect(
                play.situation.possession == possession,
                "\(at) possession — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let quarter {
            #expect(
                play.situation.quarter == quarter,
                "\(at) quarter — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let clock {
            #expect(
                play.situation.clockRemaining == clock,
                "\(at) clock — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let down {
            #expect(
                play.situation.down == down, "\(at) down — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let distance {
            #expect(
                play.situation.distance == distance,
                "\(at) distance — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let ballOn {
            #expect(
                play.situation.ballOn == ballOn,
                "\(at) ball on — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let clockRunning {
            #expect(
                self.clockRunning(into: index) == clockRunning,
                "\(at) clock running into the snap — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
    }

    func expectScore(
        _ team: TeamID, _ points: Int16, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            score(of: team) == points,
            "score of \(team == home ? "home" : "away") — \(comment?.description ?? "")",
            sourceLocation: sourceLocation)
    }

    func expectScore(
        home homePoints: Int16, away awayPoints: Int16, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        expectScore(home, homePoints, comment, sourceLocation: sourceLocation)
        expectScore(away, awayPoints, comment, sourceLocation: sourceLocation)
    }

    /// The kinds of the plays from `index` on, in order.
    func expectSequence(
        _ kinds: [PlayKind], from index: Int, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = plays.dropFirst(index).prefix(kinds.count).map(\.outcome.kind)
        #expect(
            Array(actual) == kinds,
            "plays from \(index) — \(comment?.description ?? "")", sourceLocation: sourceLocation)
    }

    func expectWinner(
        _ team: TeamID?, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(result.winner == team, comment, sourceLocation: sourceLocation)
    }

    /// The game's last play is the one at `index`: nothing was played after it.
    func expectLastPlay(
        _ index: Int, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            plays.count == index + 1,
            "the game went on for \(plays.count - index - 1) more plays — \(comment?.description ?? "")",
            sourceLocation: sourceLocation)
    }
}
