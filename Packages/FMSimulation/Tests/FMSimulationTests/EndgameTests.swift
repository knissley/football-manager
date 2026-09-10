import FMCore
import FMRandom
import FMSimulationScenarios
import Testing

@testable import FMSimulation

/// The two-minute drill and the victory formation are where players pay the most
/// attention, and until now the caller could play neither: it never knelt, never spiked,
/// and never called a timeout, so `Situation.offenseTimeouts` was decoration.
@Suite("The endgame")
struct EndgameTests {

    private let caller = BaselineCaller()

    private func context(clockRunning: Bool) -> PlayContext {
        PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
            players: [:], offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
            clockIsRunning: clockRunning, rules: .standard)
    }

    private func situation(
        down: Down = .first, distance: UInt8 = 10, ballOn: UInt8 = 60,
        quarter: UInt8 = 4, clock: UInt16 = 90, differential: Int16 = 0,
        offenseTimeouts: UInt8 = 3, defenseTimeouts: UInt8 = 3
    ) -> Situation {
        Situation(
            quarter: quarter, clockRemaining: clock, down: down, distance: distance,
            ballOn: ballOn, possession: TeamID(1), scoreDifferential: differential,
            offenseTimeouts: offenseTimeouts, defenseTimeouts: defenseTimeouts)
    }

    private func concept(
        _ situation: Situation, clockRunning: Bool = true, seed: UInt64 = 1
    ) -> PlayConcept {
        var random = SplittableRandom(seed: seed)
        let call = caller.offensiveCall(
            for: situation, classified: SituationClass(situation),
            context: context(clockRunning: clockRunning), random: &random)
        return call.concept
    }

    // MARK: - Victory formation

    /// The lead is safe if the clock can be exhausted. Running a play you did not need
    /// to is how a won game becomes a fumble.
    @Test("A team leading late kneels the game out", .tags(.unit))
    func kneelsWhenTheClockCanBeBurned() {
        let safe = situation(
            down: .first, quarter: 4, clock: 80, differential: 7, defenseTimeouts: 0)
        #expect(concept(safe) == .kneel)
    }

    /// Kneeling a play too early hands the ball back. Timeouts are exactly what buys the
    /// defence that chance.
    @Test("Defensive timeouts make the lead unsafe", .tags(.unit))
    func timeoutsPreventKneeling() {
        let withTimeouts = situation(
            down: .first, quarter: 4, clock: 80, differential: 7, defenseTimeouts: 3)
        #expect(concept(withTimeouts) != .kneel, "three timeouts can still get the ball back")

        let noTimeouts = situation(
            down: .first, quarter: 4, clock: 80, differential: 7, defenseTimeouts: 0)
        #expect(concept(noTimeouts) == .kneel)
    }

    @Test("A team that is behind or level never kneels", .tags(.unit))
    func neverKneelsWhenItCannotAfford() {
        #expect(concept(situation(clock: 40, differential: -3, defenseTimeouts: 0)) != .kneel)
        #expect(concept(situation(clock: 40, differential: 0, defenseTimeouts: 0)) != .kneel)
    }

    @Test("Nobody kneels in the first quarter", .tags(.unit))
    func neverKneelsEarly() {
        #expect(
            concept(situation(quarter: 1, clock: 80, differential: 7, defenseTimeouts: 0))
                != .kneel)
    }

    /// A knee on fourth down gives the ball up on downs — unless the period cannot
    /// survive the play clock standing in front of it. A down that ended in bounds
    /// leaves the game clock running, the next snap has to come inside the forty seconds
    /// of 4-6-1, and nothing extends a period that expires between downs: 4-8-1 extends
    /// one only while the ball is in play and 4-8-2 only for a foul in the down that
    /// expired it. With less than a play clock left and the clock running there is no
    /// fourth-down snap to give away, and the knee is the offence standing on the ball.
    ///
    /// Rewritten. This used to assert that fourth down is never a kneel, and it made
    /// that case at twenty seconds with the clock running — which is exactly the case
    /// where the down is never played. The rule was true; it was stated too widely.
    @Test(
        "football · Rules 4-6-1, 4-8-1, 4-8-2 · a knee on fourth down is a turnover on downs unless the period expires in the play clock before the snap",
        .tags(.football))
    func fourthDownIsAKneelOnlyWhenThePeriodExpiresFirst() {
        // Forty-five seconds and a running clock: the ball has to be snapped, and a knee
        // would hand it over.
        #expect(
            concept(situation(down: .fourth, clock: 45, differential: 7, defenseTimeouts: 0))
                != .kneel)
        // Twenty, and the play clock runs the period out before there can be a snap.
        #expect(
            concept(situation(down: .fourth, clock: 20, differential: 7, defenseTimeouts: 0))
                == .kneel)
        // A stopped clock is a snap whenever the offence likes, so the down is real again.
        #expect(
            concept(
                situation(down: .fourth, clock: 20, differential: 7, defenseTimeouts: 0),
                clockRunning: false) != .kneel)
    }

    /// A half is worth ending too, and the old guard would not let the caller do it: it
    /// asked for the endgame, which is the last five minutes of the fourth period and
    /// nothing before the break. Up a score with the ball and half a minute to go, the
    /// snap can only lose it; level and backed up on your own goal line it can lose it
    /// worse. Behind, never — the half is short but the points still count.
    @Test("A team kneels out the first half when a snap can only cost it", .tags(.unit))
    func kneelsOutTheFirstHalf() {
        #expect(
            concept(situation(quarter: 2, clock: 30, differential: 7, defenseTimeouts: 0))
                == .kneel,
            "up seven with thirty seconds to the break")
        #expect(
            concept(
                situation(
                    ballOn: 96, quarter: 2, clock: 30, differential: 0, defenseTimeouts: 0)
            ) == .kneel,
            "level on your own four, thirty seconds to the break: a snap here can only lose it")
        #expect(
            concept(
                situation(
                    ballOn: 96, quarter: 2, clock: 30, differential: -7, defenseTimeouts: 0)
            ) != .kneel,
            "seven behind on your own four, the half is still worth playing")

        // With the half still there to be used, nobody kneels it away.
        #expect(
            concept(situation(quarter: 2, clock: 110, differential: 7, defenseTimeouts: 3))
                != .kneel)
        // And a lead is not a reason to kneel away points: in range before the break the
        // half is worth playing, whatever the scoreboard says.
        #expect(
            concept(
                situation(
                    distance: 3, ballOn: 3, quarter: 2, clock: 16, differential: 7,
                    defenseTimeouts: 0)) != .kneel,
            "first and goal at the three before the break is a play, not a knee")
        #expect(
            concept(
                situation(ballOn: 40, quarter: 2, clock: 30, differential: 7, defenseTimeouts: 0)
            ) != .kneel,
            "a field goal from the opponent's forty is still three points")
        // Level in the middle of the field, the half is worth playing out.
        #expect(
            concept(situation(quarter: 2, clock: 30, differential: 0, defenseTimeouts: 0))
                != .kneel)
    }

    /// A knee is the offence saying the game is over, and the arithmetic behind it is
    /// all rulebook. A down that ends in bounds leaves the clock running, so the next
    /// snap has to come inside the forty seconds of the play clock (2025 rulebook,
    /// 4-6-1) and every second of that is the offence's to spend; a period whose time
    /// runs out between downs simply ends, because 4-8-1 extends one only while the ball
    /// is in play and 4-8-2 only for a foul in the down that expired it. A charged
    /// timeout hands one of those intervals back, since the clock then starts on the
    /// next snap (4-3-2), and the defence has three of them a half (4-5-1 Item 1).
    ///
    /// So: up a score with the ball, count the intervals the defence cannot take away.
    @Test(
        "A one-score lead is not knelt out while the defence can still stop the clock",
        .tags(.unit))
    func kneelsOnlyWhenTheDefenceCannotStopTheClock() {
        // First and ten, 1:52, two timeouts left to the defence: two of the intervals
        // ahead can be taken away and there is far too much clock for the rest.
        #expect(
            concept(situation(quarter: 4, clock: 112, differential: 8, defenseTimeouts: 2))
                != .kneel,
            "up eight at 1:52 against two timeouts is too early")
        // Fifty seconds, and the defence has nothing left to stop it with.
        #expect(
            concept(situation(quarter: 4, clock: 50, differential: 8, defenseTimeouts: 0))
                == .kneel)
        // And having knelt once, it kneels again: second and eleven with the clock down
        // by the knee alone, then third and twelve a play clock later.
        #expect(
            concept(
                situation(
                    down: .second, distance: 11, quarter: 4, clock: 48, differential: 8,
                    defenseTimeouts: 0)) == .kneel)
        #expect(
            concept(
                situation(
                    down: .third, distance: 12, quarter: 4, clock: 9, differential: 8,
                    defenseTimeouts: 0)) == .kneel)
    }

    /// A game the leading side has to end. It scores on the opening drive, and in the
    /// fourth quarter the trailing side hands the ball straight back on every snap it
    /// takes, so the lead is never in doubt and the only question is what the baseline
    /// caller does with the clock. Everything the leading side does is its own decision.
    private func mustBeKnelt() -> Trace {
        ScriptedGame { snap in
            if let staged = RulesScenarios.leadBySeven(snap) { return staged }
            guard snap.isScrimmage, snap.quarter == 4 else { return snap.neutral }
            return snap.differential < 0 ? .interception(to: 50) : snap.neutral
        }
        .run(with: caller)
    }

    /// Once a team has decided the game is over, it does not go back to running plays.
    ///
    /// The football is the arithmetic quoted above: the intervals a kneel-down sequence
    /// spends are the play clock's (4-6-1), what the defence can take back is a charged
    /// timeout's restart on the snap (4-3-2), and what ends it is the period expiring
    /// between downs with nothing to extend it (4-8-1, 4-8-2). Count those right and the
    /// decision is monotone by construction: the clock the next snap faces is exactly
    /// what this knee leaves, so a lead that could be knelt out on first down can still
    /// be knelt out on second. Count them wrong and the caller kneels twice and then
    /// runs an ordinary play, which is what a lead gets fumbled away on.
    @Test(
        "football · Rules 4-6-1, 4-3-2, 4-8-1, 4-8-2 · a lead knelt out stays knelt out: the play clock and the defence's timeouts decide it, and the period ends between downs",
        .tags(.football)
    )
    func theGameEndsInVictoryFormation() {
        let trace = mustBeKnelt()
        guard
            let first = trace.first(where: {
                $0.situation.quarter == 4 && $0.outcome.kind == .kneel
            })
        else {
            Issue.record("the leading side never took a knee in the fourth quarter")
            return
        }
        let rest = trace.plays[first.index...]
        #expect(
            rest.allSatisfy { $0.outcome.kind == .kneel },
            "after the first knee the leading side ran \(rest.filter { $0.outcome.kind != .kneel }.count) more plays"
        )
        #expect(
            rest.allSatisfy { $0.situation.possession == first.play.situation.possession },
            "the ball changed hands after the knee")
        #expect(trace.plays.last?.situation.quarter == 4, "the game did not end in regulation")
    }

    // MARK: - Spiking

    /// Costs a down and a second. Worth it only when the clock is running and there is
    /// no timeout to spend instead.
    @Test("A team out of timeouts spikes to stop the clock", .tags(.unit))
    func spikesWithNoTimeouts() {
        let racing = situation(
            down: .second, quarter: 4, clock: 22, differential: -4, offenseTimeouts: 0)
        #expect(concept(racing, clockRunning: true) == .spike)
    }

    @Test("A team with a timeout uses it rather than burning a down", .tags(.unit))
    func doesNotSpikeWithTimeouts() {
        let hasTimeouts = situation(
            down: .second, quarter: 4, clock: 22, differential: -4, offenseTimeouts: 2)
        #expect(concept(hasTimeouts, clockRunning: true) != .spike)
    }

    /// Spiking on a stopped clock wastes a down for nothing.
    @Test("Nobody spikes when the clock is already stopped", .tags(.unit))
    func doesNotSpikeOnAStoppedClock() {
        let stopped = situation(
            down: .second, quarter: 4, clock: 22, differential: -4, offenseTimeouts: 0)
        #expect(concept(stopped, clockRunning: false) != .spike)
    }

    @Test("A spike on fourth down is a turnover with extra steps", .tags(.unit))
    func neverSpikesOnFourth() {
        let fourth = situation(
            down: .fourth, quarter: 4, clock: 20, differential: -4, offenseTimeouts: 0)
        #expect(concept(fourth, clockRunning: true) != .spike)
    }

    // MARK: - Timeouts

    private func callsTimeout(
        _ situation: Situation, isOffense: Bool, clockRunning: Bool = true
    ) -> Bool {
        caller.callsTimeout(
            for: situation, classified: SituationClass(situation), isOffense: isOffense,
            context: context(clockRunning: clockRunning))
    }

    @Test("A trailing offence spends timeouts to keep the clock", .tags(.unit))
    func offenceSpendsToSurvive() {
        #expect(callsTimeout(situation(clock: 60, differential: -4), isOffense: true))
        #expect(
            callsTimeout(
                situation(clock: 60, differential: -4, offenseTimeouts: 0), isOffense: true)
                == false)
    }

    /// The half nothing does if you only model the team with the ball: the defence
    /// spends timeouts to get it back.
    @Test("A trailing defence spends timeouts to get the ball back", .tags(.unit))
    func defenceSpendsToGetItBack() {
        // `scoreDifferential` is the offence's, so a positive number means the team
        // without the ball is the one behind.
        #expect(callsTimeout(situation(clock: 150, differential: 6), isOffense: false))
        #expect(
            callsTimeout(situation(clock: 150, differential: -6), isOffense: false) == false,
            "a defence that is ahead wants the clock to run")
    }

    /// Three scores down with two minutes left, the ball is not coming back to any
    /// purpose, and burning all three timeouts to shorten the loss is not football. The
    /// timeout is spent to get the ball back in a game that is still there to win.
    @Test("A defence more than two scores behind keeps its timeouts", .tags(.unit))
    func defenceOutOfReachKeepsItsTimeouts() {
        // `scoreDifferential` is the offence's, so a positive number means the team
        // without the ball is the one behind.
        #expect(callsTimeout(situation(clock: 150, differential: 8), isOffense: false))
        #expect(
            callsTimeout(situation(clock: 150, differential: 16), isOffense: false),
            "two scores down is still a game")
        #expect(
            callsTimeout(situation(clock: 150, differential: 17), isOffense: false) == false,
            "three scores down with two and a half minutes left")
        #expect(callsTimeout(situation(clock: 150, differential: 30), isOffense: false) == false)
    }

    @Test("Nobody calls a timeout on a stopped clock or in the first quarter", .tags(.unit))
    func timeoutsAreNotWasted() {
        #expect(
            callsTimeout(
                situation(clock: 60, differential: -4), isOffense: true, clockRunning: false)
                == false)
        #expect(
            callsTimeout(situation(quarter: 1, clock: 600, differential: -4), isOffense: true)
                == false)
    }

    // MARK: - In a real game

    private func game(seed: UInt64) -> GameResult {
        TestWorld.game(seed: seed)
    }

    /// Timeouts are spent, and the counts in the stream are what records it — no new
    /// event type, because the next play's situation already carries them.
    @Test("Timeouts are spent over a game and visible in the stream", .tags(.contract))
    func timeoutsAreSpentAndVisible() {
        var everSpent = false
        for seed in UInt64(1)...8 {
            let plays = game(seed: seed).plays
            for (previous, next) in zip(plays, plays.dropFirst())
            where previous.situation.possession == next.situation.possession {
                if next.situation.offenseTimeouts < previous.situation.offenseTimeouts {
                    everSpent = true
                }
            }
        }
        #expect(everSpent, "eight games and nobody ever called a timeout")
    }

    @Test("Timeouts never go negative and reset at the half", .tags(.contract))
    func timeoutsStayLegal() {
        for seed in UInt64(1)...6 {
            let plays = game(seed: seed).plays
            #expect(plays.allSatisfy { $0.situation.offenseTimeouts <= 3 })
            #expect(plays.allSatisfy { $0.situation.defenseTimeouts <= 3 })

            // Somebody starts the second half with a full complement.
            let secondHalf = plays.first { $0.situation.quarter == 3 }
            #expect(secondHalf?.situation.offenseTimeouts == 3, "timeouts did not reset")
        }
    }

    /// The other half of the same promise, over seeded games rather than a script: a
    /// possession that has started kneeling never produces another kind of snap.
    @Test(
        "contract · once the baseline kneels, every later snap of that possession is a kneel",
        .tags(.contract))
    func aKneelIsNeverFollowedByALivePlay() {
        for seed in UInt64(1)...60 {
            var possession: TeamID?
            var quarter: UInt8 = 0
            var kneeled = false
            for play in game(seed: seed).plays {
                // A flag before the snap is not a snap: the down is replayed, and a false
                // start on a knee changes nothing about the decision.
                if play.outcome.kind == .penaltyOnly { continue }
                // A free kick and a new period each start a sequence of their own, and the
                // side that kneels a half out can be the side that kicks off to open the
                // next one — the kicking team has possession on a kickoff, so nothing else
                // marks that boundary.
                if play.outcome.kind == .kickoff || play.situation.quarter != quarter
                    || play.situation.possession != possession
                {
                    quarter = play.situation.quarter
                    possession = play.situation.possession
                    kneeled = false
                }
                let isKneel = play.outcome.kind == .kneel
                if kneeled && !isKneel {
                    Issue.record(
                        "seed \(seed), play \(play.index): a \(play.outcome.kind) followed a knee on the same possession"
                    )
                }
                kneeled = kneeled || isKneel
            }
        }
    }

    /// Games should end in victory formation rather than with a meaningless snap.
    @Test("Won games get knelt out", .tags(.unit))
    func gamesEndInVictoryFormation() {
        var kneels = 0
        for seed in UInt64(1)...10 {
            kneels += game(seed: seed).plays.filter { $0.outcome.kind == .kneel }.count
        }
        #expect(kneels > 0, "ten games and nobody ever took a knee")
    }

    // MARK: - The runoff decisions (A5, #32)

    /// Not a rule: the rulebook gives the offence a timeout instead of the runoff and
    /// the defence the right to decline it (4-7-1 Item 1), and which way each goes is a
    /// coaching decision. These pin the protocol's baseline answers, which every caller
    /// inherits: the offence spends a timeout only at fifteen seconds or less with one
    /// in hand; the defence accepts the runoff when level or leading and declines it
    /// when trailing; and after a defensive dead-ball foul the offence has the clock
    /// wait for the snap unless it leads.
    @Test(
        "pin · the baseline runoff decisions: a timeout at 15 seconds or less with one in hand, the defence declines only when trailing, the offence takes the snap start unless it leads (PlayCaller defaults; coaching decisions, not rules)",
        .tags(.pin)
    )
    func runoffDecisionDefaults() {
        func at(_ clock: UInt16, differential: Int16 = 0, timeouts: UInt8 = 1) -> Situation {
            situation(clock: clock, differential: differential, offenseTimeouts: timeouts)
        }
        func classified(_ situation: Situation) -> SituationClass { SituationClass(situation) }

        #expect(
            caller.takesTimeoutInsteadOfRunoff(situation: at(15), classified: classified(at(15))))
        #expect(
            caller.takesTimeoutInsteadOfRunoff(situation: at(16), classified: classified(at(16)))
                == false)
        #expect(
            caller.takesTimeoutInsteadOfRunoff(
                situation: at(10, timeouts: 0), classified: classified(at(10, timeouts: 0)))
                == false)

        // `scoreDifferential` is the offence's, so a positive number means the defence trails.
        #expect(
            caller.declinesRunoff(
                situation: at(40, differential: 7), classified: classified(at(40, differential: 7)))
        )
        #expect(caller.declinesRunoff(situation: at(40), classified: classified(at(40))) == false)
        #expect(
            caller.declinesRunoff(
                situation: at(40, differential: -7),
                classified: classified(at(40, differential: -7)))
                == false)

        #expect(
            caller.startsClockOnTheSnap(
                afterDefensiveFoul: at(40, differential: -7),
                classified: classified(at(40, differential: -7))))
        #expect(
            caller.startsClockOnTheSnap(afterDefensiveFoul: at(40), classified: classified(at(40))))
        #expect(
            caller.startsClockOnTheSnap(
                afterDefensiveFoul: at(40, differential: 7),
                classified: classified(at(40, differential: 7)))
                == false)
    }

    /// Not a rule the engine enforces, and the pin says why. A replay review after the
    /// two-minute warning that reverses a ruling, or a foul nullified after the fact,
    /// runs ten seconds off when the correct ruling would not have stopped the clock
    /// (2025 rulebook, 4-7-4). There is no replay system in this engine and no foul is
    /// ever nullified after it is called, so nothing can produce that runoff: every
    /// choice about the clock the record can carry is one of the offence's foul (4-7-1),
    /// the last forty seconds (4-7-3) or an injury timeout (4-5-4), and every runoff
    /// in a game is one of those. When a replay system lands, this fails and Article 4
    /// gets its scenario.
    @Test(
        "pin · Rule 4-7-4 is excluded: no runoff follows a replay reversal or a nullified foul, because there is no replay system and no foul is ever nullified after the fact; every clock election the record can carry, and every runoff a game produces, is a foul's (4-7-1), the last forty seconds' (4-7-3) or an injury timeout's (4-5-4)",
        .tags(.pin)
    )
    func noRunoffFollowsAReplay() {
        let modelled: Set<ClockElection> = [
            .runoff, .timeoutInsteadOfRunoff, .runoffDeclined, .clockStartsOnTheSnap,
            .clockStartsOnTheReady, .halfEnded, .playedOn, .injuryTimeoutCharged,
            .excessInjuryTimeout, .injuryRunoff, .injuryRunoffDeclined,
        ]
        #expect(
            Set(ClockElection.allCases) == modelled,
            "the record can now carry a clock election this pin does not know; if it is a replay's, 4-7-4 wants its scenario"
        )
        for seed in UInt64(1)...8 {
            for play in game(seed: seed).plays {
                for election in play.decisions.compactMap(\.clockElectionValue) {
                    #expect(modelled.contains(election), "play \(play.index) at seed \(seed)")
                }
            }
        }
    }

    // MARK: - The walk-off

    /// A game the baseline caller plays to a walk-off: one side leads by `deficit` from
    /// the opening drive, and in the fourth quarter it throws an interception on every
    /// snap it takes, so it can never kick a field goal and change the arithmetic; the
    /// trailing side gains a yard at a time until, inside the last minute, it scores as
    /// time expires.
    private func walkOff(deficit: Int16) -> Trace {
        let opening: @Sendable (Snap) -> Outcome? =
            deficit == 7 ? RulesScenarios.leadBySeven : RulesScenarios.leadBySix
        return ScriptedGame { snap in
            if let staged = opening(snap) { return staged }
            guard snap.isScrimmage, snap.quarter == 4 else { return snap.neutral }
            if snap.differential > 0 { return .interception(to: 50) }
            return snap.clock <= 60 ? snap.touchdownAsTimeExpires() : snap.neutral
        }
        .run(with: caller)
    }

    /// A touchdown as the fourth quarter expires, with the baseline caller deciding the
    /// try. The football — that the try is played as an untimed down of the fourth
    /// period, at 0:00 (2025 rulebook, 4-8-2, 4-8-2-c) — is asserted in the
    /// rules-conformance suite with a scripted caller. What this adds is the engine's
    /// promise about itself: the try that is snapped is the try the caller chose for
    /// that situation, kick or conversion, from that try's spot. Down six the baseline
    /// kicks to win; down seven it goes for two to win rather than kick to tie.
    @Test(
        "contract · after a walk-off touchdown the try snapped is the one the caller chose for its situation, at 0:00 of the fourth period (4-8-2)",
        .tags(.contract),
        arguments: [Int16(6), Int16(7)])
    func walkOffTryIsTheCallerChoice(deficit: Int16) {
        let trace = walkOff(deficit: deficit)
        guard
            let touchdown = trace.first(where: {
                $0.situation.quarter == 4 && $0.outcome.endedIn == .touchdown
                    && $0.outcome.kind == .rush
            })
        else {
            Issue.record("the script never scored as the fourth quarter expired")
            return
        }
        guard let attempt = trace[touchdown.index + 1] else {
            Issue.record("no try followed the touchdown: the game ended on it")
            return
        }
        #expect(attempt.situation.quarter == 4 && attempt.situation.clockRemaining == 0)
        let goesForTwo = caller.goesForTwo(
            situation: attempt.situation, classified: SituationClass(attempt.situation))
        #expect(
            attempt.outcome.kind == (goesForTwo ? .twoPointConversion : .extraPoint),
            "the try snapped disagrees with the caller's answer for that situation")
        let rules = Rules.standard
        let spot = goesForTwo ? rules.twoPointSnapYard : rules.extraPointSnapYard
        #expect(attempt.situation.ballOn == spot, "and it is snapped from that try's spot")
    }
}
