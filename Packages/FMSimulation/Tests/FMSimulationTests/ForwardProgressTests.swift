import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// Forward progress, on the one play where the engine can produce the case.
///
/// A completion is composed as the depth the ball was caught at plus what happened after
/// the catch, so "the receiver is spotted where his advance ended" is the claim that the
/// second term is never negative. Rule **3-12-1** makes a runner's — or an airborne
/// receiver's — progress the furthest he got toward the defence's goal line, and leaves the
/// ball dead there however far an opponent afterwards drives him back. **7-3-3** settles the
/// airborne case the same way: a man who takes the ball in the air in bounds with an
/// opponent carrying him back is down at once, and his spot is where that opponent first hit
/// him once he had control aloft. Either way the spot is the catch point and never a yard
/// line behind it.
///
/// **The claim is checked at the resolver's seam rather than over a play stream, because
/// the catch point is not on the record.** `PlayRecord` carries the total a completion
/// gained and not the depth the ball was caught at, so no query over the stream can say
/// whether a given completion was spotted at its catch point or two yards behind it: the
/// two are the same number on the record. `yardsAfterCatch` is the term that would be
/// negative, so that is where the claim is asserted, with real personnel, real ratings and
/// the resolver's own draws.
@Suite("Forward progress")
struct ForwardProgressTests {

    /// The situation the snaps below are taken from: first and ten at midfield, nothing
    /// about the clock or the score pulling on anything.
    private static let midfield = Situation(
        quarter: 2, clockRemaining: 800, down: .first, distance: 10, ballOn: 50,
        possession: TeamID(1), scoreDifferential: 0, offensePersonnel: .eleven,
        defensePackage: .nickel)

    /// The separation the catch is made at. Below `inStride`'s threshold, so nothing is
    /// added for separation earned before the ball arrived, and below the point where a
    /// blown coverage becomes likely: what is left is the receiver, the man on him, and
    /// the contact.
    private static let tightWindow = 100

    /// A league in which no receiver creates anything after the catch and no defender
    /// misses a tackle.
    ///
    /// This is the case the article governs, constructed rather than waited for. With
    /// ordinary ratings a negative after-catch term is a tail event — it needs a receiver
    /// well below average with the ball and a tackle made on the first attempt — and a
    /// suite that waits for one is a suite whose green run means the draw went a
    /// particular way. Floored elusiveness and speed on the offence put the after-catch
    /// term below zero on most snaps; maximum tackling on the defence keeps the first man
    /// from being beaten, so nothing is added back.
    private static func noYardsAfterTheCatch(seed: UInt64 = 5) -> PlayContext {
        let setup = TestWorld.setup(seed: seed)
        let players = setup.players.mapValues { player -> Player in
            var rigged = player
            rigged.ratings[.elusiveness] = 0
            rigged.ratings[.speed] = 0
            rigged.ratings[.breakTackle] = 0
            rigged.ratings[.tackling] = 99
            return rigged
        }
        return PlayContext(
            offense: setup.home.id,
            defense: setup.away.id,
            offenseRotation: setup.home.rotation(),
            defenseRotation: setup.away.rotation(),
            players: players,
            offenseScheme: setup.home.scheme,
            defenseScheme: setup.away.scheme,
            rules: .standard)
    }

    /// What he does with it once it is in his hands, over a sweep of snaps: the yardage
    /// after the catch, and whether the coverage was blown — which is the other branch the
    /// spot comes out of, and has its own arithmetic.
    private func afterTheCatch(count: Int, seed: UInt64 = 31) -> [(yards: Int, wideOpen: Bool)] {
        let context = Self.noYardsAfterTheCatch()
        let resolver = CrudeResolver()
        var random = SplittableRandom(seed: seed)
        var swept: [(yards: Int, wideOpen: Bool)] = []
        swept.reserveCapacity(count)
        for _ in 0..<count {
            let personnel = Lineup.onField(
                context, concept: .mediumPass, situation: Self.midfield, random: &random)
            guard
                let carrier = SlotLayout.receivers.first(where: { personnel[$0] != nil }),
                let coveredBy = SlotLayout.coverage.first(where: { personnel[$0] != nil })
            else {
                Issue.record("the lineup had nobody to throw to or nobody covering him")
                return swept
            }
            var decisions: [DecisionPoint] = []
            var participants: [Participation] = []
            let result = resolver.yardsAfterCatch(
                carrier: carrier, coveredBy: coveredBy, personnel: personnel, context: context,
                separation: Self.tightWindow, sideline: 0.12,
                decisions: &decisions, participants: &participants, startTick: 20,
                random: &random)
            // The blown-coverage branch writes a hole-quality point of its own and the
            // ordinary one does not, so the record says which arithmetic produced the
            // number.
            let wideOpen = decisions.contains { $0.kind == .holeQuality && $0.detail == 3 }
            swept.append((result.yards, wideOpen))
        }
        return swept
    }

    /// A receiver cannot be spotted behind the point where his advance ended.
    ///
    /// Both of the resolver's after-catch branches are swept, because both can compute a
    /// negative number and both are floored: the ordinary one, where what he does with the
    /// ball is worth less than nothing and the first tackler is not beaten, and the
    /// blown-coverage one, where the burst a slow receiver runs into the open field comes
    /// out below zero. A sweep that reached only one of them would leave the other
    /// unasserted, so the count of each is checked before the claim is made of either.
    @Test(
        "football · Rules 3-12-1, 7-3-3 · a receiver whose after-catch contact would carry him backward is spotted at the catch point",
        .tags(.football))
    func aReceiverIsSpottedWhereHisAdvanceEnded() {
        let swept = afterTheCatch(count: 4_000)
        let wideOpen = swept.filter(\.wideOpen)
        let covered = swept.filter { !$0.wideOpen }

        // The instrument before the claim: a sweep that never reached a branch cannot say
        // anything about it, and a sweep where nothing was ever spotted at the catch point
        // never put the floor under load at all.
        #expect(covered.count > 100, "\(covered.count) snaps ended with the man on him making it")
        #expect(wideOpen.count > 10, "\(wideOpen.count) snaps blew the coverage")
        #expect(
            covered.count(where: { $0.yards == 0 }) > 50,
            "no snap was spotted at the catch point, so the spot was never under load")

        for (yards, wideOpen) in swept {
            let branch = wideOpen ? "a blown coverage" : "the man on him"
            #expect(
                yards >= 0,
                "a receiver was carried \(-yards) yards behind the catch point by \(branch)")
        }
    }
}
