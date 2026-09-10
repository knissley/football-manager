import FMCore
import Testing

/// The queries over a kick, a takeaway and the dead ball before a snap.
///
/// Gross, return and net are arithmetic over three spots on the record — where the kick
/// was kicked from, where it was fielded and where it came to rest — and a touchback,
/// which was fielded nowhere, is measured to the goal line and netted to the twenty, as
/// the league does it.
@Suite("Kick and dead-ball queries")
struct KickQueryTests {

    private func kick(
        _ kind: PlayKind, from ballOn: UInt8, endedIn: PlayEnding, fieldedAt: Int8? = nil,
        finalSpot: UInt8? = nil, decisions: [DecisionPoint] = []
    ) -> PlayRecord {
        PlayRecord(
            game: GameID(1), index: 3,
            situation: Situation(
                quarter: 1, clockRemaining: 700, down: .fourth, distance: 7, ballOn: ballOn,
                possession: TeamID(1)),
            calls: Calls(
                offense: OffensiveCall(concept: kind == .punt ? .punt : .kickoff),
                defense: .preventShell, offensiveCaller: .automatic,
                defensiveCaller: .automatic),
            decisions: decisions,
            outcome: Outcome(
                kind: kind, yards: 0, endedIn: endedIn, finalSpot: finalSpot,
                fieldedAt: fieldedAt, clockRunoff: 6))
    }

    @Test("A returned punt is gross to the catch, return to the tackle, net between", .tags(.unit))
    func returnedPunt() {
        let punt = kick(.punt, from: 60, endedIn: .tackled, fieldedAt: 15, finalSpot: 24)
        #expect(punt.kickDistance == 45)
        #expect(punt.returnYards == 9)
        #expect(punt.netPuntDistance(rules: .standard) == 36)
    }

    @Test("A fair catch is gross with no return, and the net is the gross", .tags(.unit))
    func fairCatch() {
        let punt = kick(.punt, from: 60, endedIn: .fairCatch, fieldedAt: 18, finalSpot: 18)
        #expect(punt.kickDistance == 42)
        #expect(punt.returnYards == 0)
        #expect(punt.netPuntDistance(rules: .standard) == 42)
    }

    @Test("A touchback is measured to the goal line and netted to the twenty", .tags(.unit))
    func touchback() {
        let punt = kick(.punt, from: 55, endedIn: .touchback)
        #expect(punt.kickDistance == 55)
        #expect(punt.returnYards == nil)
        #expect(punt.netPuntDistance(rules: .standard) == 35)
        var deeper = Rules.standard
        deeper.puntTouchbackOwnYard = 25
        #expect(punt.netPuntDistance(rules: deeper) == 30)
    }

    @Test("A kickoff fielded in the end zone counts the depth in the return", .tags(.unit))
    func kickoffFromDeep() {
        let kickoff = kick(.kickoff, from: 65, endedIn: .tackled, fieldedAt: -3, finalSpot: 25)
        #expect(kickoff.kickDistance == 68)
        #expect(kickoff.returnYards == 28)
        #expect(kickoff.netPuntDistance(rules: .standard) == nil, "a kickoff has no net punt")
    }

    @Test("A play from scrimmage has no kick to measure", .tags(.unit))
    func scrimmagePlay() {
        let run = PlayRecord(
            game: GameID(1), index: 4,
            situation: Situation(
                quarter: 1, clockRemaining: 600, down: .first, distance: 10, ballOn: 70,
                possession: TeamID(1)),
            calls: Calls(
                offense: OffensiveCall(concept: .insideRun), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic),
            outcome: Outcome(kind: .rush, yards: 4, endedIn: .tackled, clockRunoff: 6))
        #expect(run.kickDistance == nil)
        #expect(run.returnYards == nil)
        #expect(run.netPuntDistance(rules: .standard) == nil)
        #expect(run.outcome.possessionLostAt == nil)
    }

    @Test("A takeaway carries the spot possession was lost, in the offence's frame", .tags(.unit))
    func takeawaySpot() {
        let pick = Outcome(
            kind: .pass, yards: 0, endedIn: .intercepted, passResult: .intercepted,
            finalSpot: 75, possessionLostAt: 48, clockRunoff: 7)
        #expect(pick.possessionLostAt == 48)
        #expect(pick.finalSpot == 75)
    }

    @Test("The dead ball before a snap is read off the decision points", .tags(.unit))
    func deadBallBeforeTheSnap() {
        let snap = kick(
            .punt, from: 60, endedIn: .fairCatch, fieldedAt: 20, finalSpot: 20,
            decisions: [
                .twoMinuteWarning, .timeout(byOffense: false), .timeout(byOffense: true),
                .timeout(byOffense: false), .playClock(seconds: 25, remaining: 3),
            ])
        #expect(snap.hasTwoMinuteWarningBeforeTheSnap)
        #expect(snap.timeoutsBeforeTheSnap.offense == 1)
        #expect(snap.timeoutsBeforeTheSnap.defense == 2)
        #expect(DecisionPoint.timeout(byOffense: true).timeoutByOffense == true)
        #expect(DecisionPoint.timeout(byOffense: false).timeoutByOffense == false)
        #expect(DecisionPoint.twoMinuteWarning.timeoutByOffense == nil)
        #expect(DecisionPoint.twoMinuteWarning.isTwoMinuteWarning)
        #expect(!DecisionPoint.playClock(seconds: 40, remaining: 12).isTwoMinuteWarning)
        #expect(DecisionPoint.twoMinuteWarning.primary.isNone, "the warning names nobody")
        #expect(DecisionPoint.timeout(byOffense: true).primary.isNone, "a timeout names nobody")

        let quiet = kick(.punt, from: 60, endedIn: .fairCatch, fieldedAt: 20, finalSpot: 20)
        #expect(!quiet.hasTwoMinuteWarningBeforeTheSnap)
        #expect(
            quiet.timeoutsBeforeTheSnap.offense == 0 && quiet.timeoutsBeforeTheSnap.defense == 0)
    }
}
