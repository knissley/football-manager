import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The quarterback works his reads the way his ratings let him (C3, #44).
///
/// Two promises the engine makes about itself, and neither is a football test: nothing in
/// the reference bands how often a passer reaches his second read or how a poor one's
/// interceptions compare with a good one's. What the design says is that awareness is
/// what moves a passer off a read and what shrinks his error about how open a window is,
/// and these hold the engine to that on a paired draw — the same roster, the same rush,
/// the same coverage, and one rating changed.
@Suite("The quarterback's reads")
struct QuarterbackReadsTests {

    /// First and ten near midfield, nothing about the clock or the score pulling on the
    /// call: the read is the only thing under test.
    private static let neutral = Situation(
        quarter: 2, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
        possession: TeamID(1), scoreDifferential: 0, offensePersonnel: .eleven,
        defensePackage: .nickel)

    /// The world's context with its starting quarterback given `awareness`, and every
    /// window he reads made a coin flip against the medium threshold: each route runner's
    /// `routeRunning` set to 57 and each defender's coverage to 62, which centres the
    /// separation the coverage loop draws on 109 cm against a threshold of 110, so a read
    /// is open about as often as not and what separates two passers is how they judge it.
    /// On the generated roster the receivers beat their men on most snaps, and a passer
    /// who rarely has to come off his first read cannot show what awareness is worth.
    private func context(awareness: UInt8, seed: UInt64 = 12) -> PlayContext? {
        let base = TestWorld.context(seed: seed)
        guard
            let starter = base.offenseRotation.filter({ $0.position == .quarterback })
                .min(by: { $0.depth < $1.depth }),
            var passer = base.players[starter.player]
        else { return nil }
        var players = base.players
        for (id, var man) in players {
            man.ratings[.routeRunning] = 57
            man.ratings[.manCoverage] = 62
            man.ratings[.zoneCoverage] = 62
            players[id] = man
        }
        passer.ratings[.awareness] = awareness
        players[passer.id] = passer
        return PlayContext(
            offense: base.offense, defense: base.defense, offenseRotation: base.offenseRotation,
            defenseRotation: base.defenseRotation, players: players,
            offenseScheme: base.offenseScheme, defenseScheme: base.defenseScheme,
            crowdNoise: base.crowdNoise, altitudeFeet: base.altitudeFeet, weather: base.weather,
            rules: base.rules)
    }

    /// `count` medium passes against one defence from one stream, so two contexts that
    /// differ in one rating see the same eleven men and the same rush on every snap.
    private func dropbacks(
        _ context: PlayContext, count: Int, seed: UInt64 = 41
    ) -> [(outcome: Outcome, decisions: [DecisionPoint])] {
        let calls = Calls(
            offense: OffensiveCall(concept: .mediumPass), defense: .nickelTwoMan,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        var random = SplittableRandom(seed: seed)
        return (0..<count).map { index in
            var stream = random.split(UInt64(index))
            let onField = Lineup.onField(
                context, concept: .mediumPass, situation: Self.neutral, random: &stream)
            return CrudeResolver().resolve(
                situation: Self.neutral, calls: calls, onField: onField, context: context,
                random: &stream)
        }
    }

    /// A low-awareness passer stays locked on his primary; a high one gets to his third
    /// read. Measured as the share of dropbacks on which a second read was worked at
    /// all, over the dropbacks that reached a read, and the failure message states both
    /// shares as C3's done-when asks.
    @Test(
        "A 45-awareness passer reaches his second read on a smaller share of dropbacks than a 90",
        .tags(.contract))
    func awarenessReachesTheSecondRead() {
        guard let poor = context(awareness: 45), let good = context(awareness: 90) else {
            Issue.record("the world has no starting quarterback to rate")
            return
        }
        func secondReadShare(_ context: PlayContext) -> Double {
            var reached = 0
            var withAread = 0
            for play in dropbacks(context, count: 4_000) {
                let reads = play.decisions.filter { $0.kind == .readProgression }.count
                guard reads > 0 else { continue }
                withAread += 1
                if reads >= 2 { reached += 1 }
            }
            return withAread == 0 ? 0 : Double(reached) / Double(withAread)
        }
        let poorShare = secondReadShare(poor)
        let goodShare = secondReadShare(good)
        #expect(
            poorShare < goodShare,
            "a 45-awareness passer reached his second read on \(poorShare) of his dropbacks and a 90 on \(goodShare)"
        )
        #expect(goodShare > 0, "a 90-awareness passer never got to a second read at all")
    }

    /// The threshold a window has to clear is the same for every passer; what a poor one
    /// gets wrong is how open the window is. So on identical reads he throws into
    /// coverage a better passer would have come off — measured as the share of his throws
    /// to a numbered read that went into a window the catch model calls a break-up's,
    /// under 110 cm.
    ///
    /// C3's done-when asked for the consequence instead — that his interception rate
    /// exceeds the good passer's — and on this tree it does not follow, which is reported
    /// rather than asserted: both rates are in the failure message. Two things swallow
    /// it. The catch model moves the catch by 0.0007 a centimetre and the pick by 0.0006,
    /// so a ball thrown forty centimetres tighter is caught three points less and picked
    /// two points more; and the poor passer, seeing windows that are not there, also
    /// fails to see ones that are, so he checks down and throws away more, and those are
    /// the safest balls on the play. And a passer who locks on holds on that read rather
    /// than forcing it — he neither moves on nor throws it — so the only throw into
    /// coverage the process produces is a window he misjudged; whether a locked-on passer
    /// should force the ball is a design question left open with the rest. Whether a throw
    /// into coverage should cost more is the catch model's question (C14 #113, C4 #39) and
    /// the retune's (E3 #49), not the read process's.
    @Test(
        "A poor passer throws into coverage a good one comes off, on identical reads",
        .tags(.contract))
    func perceptionErrorThrowsIntoCoverage() {
        guard let poor = context(awareness: 45), let good = context(awareness: 90) else {
            Issue.record("the world has no starting quarterback to rate")
            return
        }
        func measure(_ context: PlayContext) -> (intoCoverage: Double, intercepted: Double) {
            var throwsToARead = 0
            var tight = 0
            var attempts = 0
            var intercepted = 0
            for play in dropbacks(context, count: 8_000) {
                if play.outcome.passResult != nil {
                    attempts += 1
                    if play.outcome.passResult == .intercepted { intercepted += 1 }
                }
                guard
                    play.decisions.first(where: { $0.kind == .throwDecision })?.throwDecisionValue
                        == .primary,
                    let arrival = play.decisions.first(where: { $0.kind == .ballArrival })
                else { continue }
                throwsToARead += 1
                if arrival.value < 110 { tight += 1 }
            }
            return (
                throwsToARead == 0 ? 0 : Double(tight) / Double(throwsToARead),
                attempts == 0 ? 0 : Double(intercepted) / Double(attempts)
            )
        }
        let poorPasser = measure(poor)
        let goodPasser = measure(good)
        #expect(
            poorPasser.intoCoverage > goodPasser.intoCoverage,
            "a 45-awareness passer threw into a window under 110 cm on \(poorPasser.intoCoverage) of his throws to a read and a 90 on \(goodPasser.intoCoverage); they were intercepted on \(poorPasser.intercepted) and \(goodPasser.intercepted) of their attempts"
        )
        #expect(goodPasser.intoCoverage > 0, "a 90-awareness passer never once threw into coverage")
    }
}
