import Testing

@testable import FMCore

/// A foul on a play that scores is not enforced on that play.
///
/// The engine used to record every one of them declined, because there was nowhere to
/// enforce them: a foul during a field goal or a safety belongs on the free kick that
/// follows, and a foul during a touchdown belongs on the try. So roughing the kicker on a
/// made field goal was worth nothing at all, and an offensive foul on a successful try
/// wiped the point out and skipped the re-try the book gives.
@Suite("A foul during a score")
struct FoulDuringAScoreTests {

    private let rules = Rules.standard

    private func situation(
        ballOn: UInt8 = 25, down: Down = .fourth, distance: UInt8 = 6
    )
        -> Situation
    {
        Situation(
            quarter: 2, clockRemaining: 600, down: down, distance: distance, ballOn: ballOn,
            possession: TeamID(1))
    }

    private func penalty(_ foul: Foul, byTeam team: TeamID) -> PenaltyRecord {
        PenaltyRecord(
            foul: foul, offender: PlayerSlot(foul.committedBy == .offense ? 3 : 14),
            offendingTeam: team, yards: foul.yards, wasAccepted: false)
    }

    /// Rule 12 Section 2 is the personal fouls and 12-3-1 the unsportsmanlike ones, and
    /// 14-2-3 turns on exactly that distinction: those are the fouls carried to the free
    /// kick when the opponent kicks a field goal, and the rest are not.
    ///
    /// Which side of the line a foul falls on is the article's own answer and not the
    /// section heading it is printed under. 12-2-12 prints two fouls and two penalties:
    /// its first marks roughing the kicker a personal foul in as many words, and its
    /// second says of running into the kicker that it is not one. So the two halves of a
    /// single article go different ways here, and the second belongs with the fouls
    /// 14-2-3 leaves behind.
    @Test(
        "football · Rule 12-2, 12-2-12, 12-3-1 · the personal and unsportsmanlike fouls are the ones the book carries to a succeeding spot",
        .tags(.football))
    func personalFoulsAreNamedByTheBook() {
        for foul in [
            Foul.chopBlock, .illegalBlindsideBlock, .unnecessaryRoughness, .illegalUseOfHelmet,
            .roughingThePasser, .roughingTheKicker, .tripping, .facemask,
            .horseCollarTackle, .lowBlock, .unsportsmanlikeConduct, .taunting,
        ] {
            #expect(foul.isPersonalOrUnsportsmanlike, "\(foul) is in Rule 12 Section 2 or 12-3")
        }
        for foul in [
            Foul.offensiveHolding, .defensiveHolding, .illegalContact, .illegalUseOfHands,
            .illegalBlockInTheBack, .falseStart, .offside, .delayOfGame,
            .defensivePassInterference, .offensivePassInterference, .illegalTouching,
            .ineligibleReceiverDownfield, .runningIntoTheKicker,
        ] {
            #expect(!foul.isPersonalOrUnsportsmanlike, "\(foul) is not one of those")
        }
    }

    /// The flagship case, and the one the engine got most wrong: three points wiped out
    /// and the offence handed a first down for being fouled.
    @Test(
        "football · Rule 14-2-3, 12-2-12 · roughing the kicker on a made field goal leaves the three points and is enforced on the succeeding free kick",
        .tags(.football))
    func roughingOnAMadeFieldGoalMovesTheFreeKick() {
        let before = situation()
        let kick = Outcome(kind: .fieldGoal, yards: 0, endedIn: .fieldGoalGood)
        let decision = rules.enforce(
            penalty(.roughingTheKicker, byTeam: TeamID(2)), on: before, outcome: kick,
            offendingTeamHadBall: false)

        #expect(decision.accepted, "the offended team does not have to decline it")
        #expect(decision.penalty.wasAccepted)
        #expect(decision.deferredTo == .theFreeKick)
        #expect(decision.penalty.yards == 15)
        #expect(decision.advancement.scoring == .fieldGoal)
        #expect(decision.advancement.points == rules.fieldGoal, "the three points stand")
        #expect(decision.advancement.requiresKickoff)
    }

    /// The other half of 14-2-3's first sentence. The defence scores the safety, so it is
    /// the offence's foul during the down that carries.
    @Test(
        "football · Rule 14-2-3 · a personal foul during a down in which the opponent scores a safety is enforced on the succeeding free kick",
        .tags(.football))
    func aPersonalFoulDuringASafetyMovesTheFreeKick() {
        let before = situation(ballOn: 97, down: .second, distance: 10)
        let play = Outcome(kind: .sack, yards: -4, endedIn: .safety)
        let decision = rules.enforce(
            penalty(.unsportsmanlikeConduct, byTeam: TeamID(1)), on: before, outcome: play,
            offendingTeamHadBall: true)

        #expect(decision.accepted)
        #expect(decision.deferredTo == .theFreeKick)
        #expect(decision.advancement.scoring == .safety)
        #expect(decision.advancement.points == rules.safety, "the two points stand")
        #expect(decision.advancement.requiresKickoff)
    }

    /// A five-yard foul is not a personal foul, so 14-2-3 does not carry it anywhere. The
    /// offended team's only alternative is to give up the points and replay the down, and
    /// nobody does that, so it is declined.
    @Test(
        "football · Rule 14-2-3 · a foul that is neither personal nor unsportsmanlike is not carried to the free kick, and a score is not given back for it",
        .tags(.football))
    func anOrdinaryFoulOnAMadeKickIsDeclined() {
        let decision = rules.enforce(
            penalty(.defensiveHolding, byTeam: TeamID(2)), on: situation(),
            outcome: Outcome(kind: .fieldGoal, yards: 0, endedIn: .fieldGoalGood),
            offendingTeamHadBall: false)

        #expect(!decision.accepted)
        #expect(decision.deferredTo == nil)
        #expect(decision.advancement.points == rules.fieldGoal)
    }

    /// The article's subject runs through both of its sentences: a personal or
    /// unsportsmanlike foul by the side that did *not* score. What the touchdown clause
    /// adds is *when* — live ball, dead ball, or between downs — and where it goes, which
    /// is the try rather than the free kick.
    @Test(
        "football · Rule 14-2-3 · a personal foul by the defence during a touchdown is enforced on the try, and the six points stand",
        .tags(.football))
    func aFoulDuringATouchdownGoesOnTheTry() {
        let before = situation(ballOn: 12, down: .first, distance: 10)
        let score = Outcome(kind: .rush, yards: 12, endedIn: .touchdown)
        let decision = rules.enforce(
            penalty(.facemask, byTeam: TeamID(2)), on: before, outcome: score,
            offendingTeamHadBall: false)

        #expect(decision.accepted)
        #expect(decision.deferredTo == .theTry)
        #expect(decision.advancement.scoring == .touchdown)
        #expect(decision.advancement.points == rules.touchdown)
        #expect(decision.advancement.requiresTry)

        // A dead-ball foul after the score is on the try too, and this one is not a
        // personal foul: 11-3-3 Item 1 puts every foul after a touchdown on the try.
        let afterTheWhistle = rules.enforce(
            penalty(.taunting, byTeam: TeamID(1)), on: before, outcome: score,
            offendingTeamHadBall: true)
        #expect(afterTheWhistle.deferredTo == .theTry)
        #expect(afterTheWhistle.advancement.points == rules.touchdown)
    }

    /// 11-3-3 Item 3-a. The try is *repeated* — the point comes off and the attempt comes
    /// back — where the engine wiped the point and went straight to the kickoff.
    @Test(
        "football · Rule 11-3-3 Item 3-a · an offensive foul during a successful try repeats the try from the enforced spot",
        .tags(.football))
    func anOffensiveFoulOnASuccessfulTryRepeatsIt() {
        let before = Situation(
            quarter: 2, clockRemaining: 600, down: .first, distance: 15,
            ballOn: rules.extraPointSnapYard, possession: TeamID(1))
        let good = Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood)
        let decision = rules.enforce(
            penalty(.offensiveHolding, byTeam: TeamID(1)), on: before, outcome: good,
            offendingTeamHadBall: true)

        #expect(decision.accepted)
        #expect(decision.deferredTo == nil, "the try is played again, not deferred")
        #expect(decision.advancement.points == 0, "the point comes off")
        #expect(decision.advancement.scoring == nil)
        #expect(decision.advancement.requiresTry, "and the try comes back")
        #expect(!decision.advancement.requiresKickoff)
        #expect(
            decision.advancement.ballOn == rules.extraPointSnapYard + 10,
            "ten yards back from the fifteen")
    }

    /// The other side of the same down: 11-3-3 Item 4-a puts a defensive foul on a try on
    /// the kickoff that follows, and the point stands.
    @Test(
        "football · Rule 11-3-3 Item 4-a · a defensive foul during a successful try leaves the point and is enforced on the succeeding free kick",
        .tags(.football))
    func aDefensiveFoulOnASuccessfulTryMovesTheFreeKick() {
        let before = Situation(
            quarter: 2, clockRemaining: 600, down: .first, distance: 15,
            ballOn: rules.extraPointSnapYard, possession: TeamID(1))
        let good = Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood)
        let decision = rules.enforce(
            penalty(.defensiveHolding, byTeam: TeamID(2)), on: before, outcome: good,
            offendingTeamHadBall: false)

        #expect(decision.accepted)
        #expect(decision.deferredTo == .theFreeKick)
        #expect(decision.advancement.points == rules.extraPoint, "the point stands")
        #expect(decision.advancement.requiresKickoff)
    }
}
