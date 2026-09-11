import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The dynamic kickoff, as the crude resolver plays it.
///
/// The kickoff used to be a coin flip between a touchback and a return, and it never
/// looked at where the ball was being kicked from — so a flag on the kicking team moved
/// the spot and changed nothing at all about the kick. Under the 2025 book the spot is
/// most of the play: it decides whether the ball can reach the end zone, what the
/// receiving team is given when it does not, and where a legal onside recovery can
/// happen.
@Suite("The dynamic kickoff")
struct KickoffTests {

    private let rules = Rules.standard

    private func kickoff(from ownYard: UInt8 = 35) -> Situation {
        Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10,
            ballOn: Rules.standard.ballOnFromOwnYard(ownYard), possession: TeamID(1),
            scoreDifferential: -7)
    }

    /// Resolve `count` free kicks of one concept and hand back the ones that were actually
    /// kicked. A pre-snap flag kills the play before the kick, and a play that never
    /// happened says nothing about the kick.
    private func kicks(
        _ concept: PlayConcept = .kickoff, from ownYard: UInt8 = 35, count: Int = 3_000,
        seed: UInt64 = 4, weather: WeatherState = .clear
    ) -> [Outcome] {
        let context = TestWorld.context(seed: 5, weather: weather)
        let calls = Calls(
            offense: OffensiveCall(concept: concept), defense: .preventShell,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        let situation = kickoff(from: ownYard)
        let root = SplittableRandom(seed: seed)
        var kicked: [Outcome] = []
        for index in 0..<count {
            var random = root.split(UInt64(index))
            let onField = Lineup.onField(
                context, concept: concept, situation: situation, random: &random)
            let resolved = CrudeResolver().resolve(
                situation: situation, calls: calls, onField: onField, context: context,
                random: &random)
            guard resolved.outcome.kind == .kickoff else { continue }
            kicked.append(resolved.outcome)
        }
        return kicked
    }

    private func share(_ outcomes: [Outcome], _ predicate: (Outcome) -> Bool) -> Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter(predicate).count) / Double(outcomes.count)
    }

    /// The headline of the dynamic kickoff: a kick that comes down in the landing zone is
    /// a live ball the receiving team has to do something with, and no fair catch is
    /// available on it because a free kick may be fair caught only in the air. So the
    /// ordinary kickoff is a return, and the touchback is the exception rather than the
    /// rule it was under the old kickoff.
    @Test(
        "football · Rule 6-1-4, 6-1-5, 10-2-1 · a kick into the landing zone is returned, not fair caught, and the touchback is the minority outcome",
        .tags(.football))
    func aKickIntoTheLandingZoneIsReturned() {
        let outcomes = kicks()
        #expect(outcomes.count > 2_500, "the sample is mostly flags, so it says nothing")

        let returned = share(outcomes) { $0.endedIn == .tackled || $0.endedIn == .touchdown }
        let touchbacks = share(outcomes) { $0.endedIn == .touchback }
        #expect(returned > touchbacks, "most kickoffs are returned")
        #expect(returned > 0.5, "returned on \(returned) of kicks")
        #expect(touchbacks > 0.05, "a touchback has to remain a real outcome")

        #expect(
            !outcomes.contains { $0.endedIn == .fairCatch },
            "a kick that has come down cannot be fair caught")

        // A return starts in the landing zone or the end zone and goes forward, so it
        // never ends behind the receiving team's goal line and never in the zone it was
        // caught in without a tackler.
        for outcome in outcomes where outcome.endedIn == .tackled {
            guard let spot = outcome.finalSpot else {
                Issue.record("a returned kick with no resting spot")
                continue
            }
            #expect(spot >= 1 && spot <= 99)
            #expect(
                outcome.participants.contains { $0.role == .returner },
                "somebody has to have returned it")
        }
    }

    /// The spot of the kick is the kicking team's restraining line as a distance penalty
    /// has moved it. Fifteen yards back is fifteen more yards of carry needed to reach
    /// the end zone, so the touchback all but disappears; fifteen forward and it is the
    /// easy outcome. Nothing about the old kickoff read the spot at all.
    @Test(
        "football · Rule 6-1-2-a, 6-1-6-b · the kick is made from the restraining line as a distance penalty has moved it, so a penalty changes what the kick can do",
        .tags(.football))
    func aPenaltyMovesTheKickAndChangesIt() {
        let fromTheThirtyFive = share(kicks()) { $0.endedIn == .touchback }
        let penalised = share(kicks(from: 20)) { $0.endedIn == .touchback }
        let rewarded = share(kicks(from: 50)) { $0.endedIn == .touchback }

        #expect(
            penalised < fromTheThirtyFive - 0.10,
            "fifteen yards back: \(penalised) against \(fromTheThirtyFive)")
        #expect(
            rewarded > fromTheThirtyFive + 0.10,
            "fifteen yards forward: \(rewarded) against \(fromTheThirtyFive)")
    }

    /// A kick that never reaches the landing zone, or that crosses a sideline, is a foul,
    /// and the receiving team is given field position for it rather than being made to
    /// play from wherever the ball happened to stop.
    @Test(
        "football · Rule 6-2-4 · a kick out of bounds or short of the landing zone hands the receiving team the ball around its own 40",
        .tags(.football))
    func aShortOrOutOfBoundsKickIsGivenAway() {
        let outcomes = kicks()
        let mishit = outcomes.filter { $0.endedIn == .outOfBounds || $0.endedIn == .downed }
        #expect(!mishit.isEmpty, "no kick ever missed the landing zone")
        #expect(
            Double(mishit.count) / Double(outcomes.count) < 0.12,
            "missing the zone is a mistake, not the usual result")

        for outcome in mishit {
            let advancement = rules.advance(from: kickoff(), outcome: outcome)
            #expect(advancement.possessionChanged)
            #expect(
                advancement.ballOn >= 55 && advancement.ballOn <= 60,
                "between the 25 yards on the article awards and where a short kick lay")
            #expect(outcome.clockRunoff == 0, "a kick nobody legally touched starts no clock")
        }
    }

    /// The kicking team may not touch an onside kick until it has reached the receiving
    /// team's restraining line, ten yards in advance of its own, so the earliest either
    /// side can come up with the ball is there. The engine spotted a *failed* onside kick
    /// twenty yards further downfield than a recovered one, which handed the receiving
    /// team ten yards it is not owed.
    @Test(
        "football · Rule 6-1-6-e, 6-1-6-g · an onside kick is recovered at or beyond the receiving team's restraining line, whichever side comes up with it",
        .tags(.football))
    func anOnsideKickIsRecoveredAtTheReceiversRestrainingLine() {
        let outcomes = kicks(.onsideKick, count: 1_200)
        #expect(!outcomes.isEmpty)

        // The kick is from the kicking team's 35 (6-1-6-b), so the receiving team's
        // restraining line is the kicking team's 45 — spot 55 in the kicking team's frame,
        // since a spot counts down towards the receiving team's goal. The ball cannot be
        // legally recovered before it gets there, and it is a short kick everybody is
        // standing on, so it dies between there and a few yards past it.
        for outcome in outcomes {
            guard let spot = outcome.finalSpot else {
                Issue.record("an onside kick with no resting spot")
                continue
            }
            #expect(
                spot <= 55,
                "dead at the kicking team's \(100 - Int(spot)), past the restraining line it is kicked from"
            )
            #expect(
                spot >= 49,
                "dead at the kicking team's \(100 - Int(spot)), short of the receiving team's restraining line at its 45"
            )
        }

        let recovered = outcomes.filter { $0.endedIn == .fumbleRecovered }
        #expect(!recovered.isEmpty, "the kicking team never recovered one")
        #expect(
            recovered.count < outcomes.count / 4,
            "an onside kick is recovered about one time in nine, not routinely")

        // Whoever comes up with it, the ball is at the same place: the kicking team keeps
        // it there and the receiving team takes it there.
        for outcome in outcomes {
            let advancement = rules.advance(from: kickoff(), outcome: outcome)
            let spot = Int(outcome.finalSpot ?? 0)
            if outcome.endedIn == .fumbleRecovered {
                #expect(!advancement.possessionChanged)
                #expect(Int(advancement.ballOn) == spot)
            } else {
                #expect(advancement.possessionChanged)
                #expect(Int(advancement.ballOn) == 100 - spot)
            }
        }
    }
}
