import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The kicking game as a phase, rather than as a way of ending a drive.
@Suite("Special teams")
struct SpecialTeamsTests {

    private func situation(
        quarter: UInt8 = 4, clock: UInt16 = 120, differential: Int16 = -10,
        defenseTimeouts: UInt8 = 3
    ) -> Situation {
        Situation(
            quarter: quarter, clockRemaining: clock, down: .first, distance: 10,
            ballOn: 65, possession: TeamID(1), scoreDifferential: differential,
            defenseTimeouts: defenseTimeouts)
    }

    private func onside(_ situation: Situation) -> Bool {
        BaselineCaller().kicksOnside(situation: situation, classified: SituationClass(situation))
    }

    /// You kick it away when a stop gets you the ball back, and you kick onside when it
    /// does not. Getting this wrong in either direction is glaring: a team kicking onside
    /// while ahead looks broken, and one that never does it cannot come back from ten.
    @Test("Onside kicks happen when a stop would not be enough, and not otherwise", .tags(.unit))
    func onsideJudgement() {
        #expect(onside(situation(clock: 120, differential: -10)), "two scores down, two minutes")
        #expect(onside(situation(clock: 60, differential: -14)))

        #expect(!onside(situation(differential: 7)), "kicking onside while ahead")
        #expect(!onside(situation(differential: 0)), "kicking onside while level")
        #expect(!onside(situation(clock: 600, differential: -10)), "ten minutes still left")
        #expect(!onside(situation(quarter: 2, clock: 60, differential: -10)), "before half")
        #expect(
            !onside(situation(clock: 120, differential: -3, defenseTimeouts: 3)),
            "one score down with timeouts: get a stop")
        #expect(
            onside(situation(clock: 40, differential: -3, defenseTimeouts: 0)),
            "one score down, no timeouts, under a minute")
    }

    /// The sign check. A back who protects the ball has to fumble *less* than one who
    /// does not — an injury model in this repo once had exactly this backwards and gave
    /// the sturdiest players the longest absences, so it gets asserted rather than
    /// assumed.
    @Test("Ball security reduces fumbles and a big hitter causes them", .tags(.unit))
    func fumbleSigns() {
        func rate(carrying: UInt8, hitPower: UInt8) -> Double {
            var personnel = Lineup()
            personnel.place(PlayerID(1), position: .runningBack, at: 1)
            personnel.place(PlayerID(2), position: .linebacker, at: 15)

            let context = PlayContext(
                offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
                players: [
                    PlayerID(1): player(
                        id: 1, position: .runningBack, ratings: [.carrying: carrying]),
                    PlayerID(2): player(
                        id: 2, position: .linebacker, ratings: [.hitPower: hitPower]),
                ],
                offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
                rules: .standard)

            var random = SplittableRandom(seed: 99)
            var fumbles = 0
            for _ in 0..<20_000 {
                if Fumbles.drawn(
                    carrier: PlayerSlot(1), tackler: PlayerSlot(15), isSack: false,
                    personnel: personnel, context: context, random: &random) != nil
                {
                    fumbles += 1
                }
            }
            return Double(fumbles) / 20_000
        }

        #expect(rate(carrying: 90, hitPower: 60) < rate(carrying: 50, hitPower: 60))
        #expect(rate(carrying: 70, hitPower: 90) > rate(carrying: 70, hitPower: 50))
    }

    /// A strip sack comes loose far more often than a hit on a ball carrier who saw it.
    @Test("A quarterback is stripped more often than a runner is", .tags(.unit))
    func stripSacksAreMoreLikely() {
        #expect(Fumbles.onSack > Fumbles.onContact * 2)
    }

    private func player(id: UInt64, position: Position, ratings: [RatingKey: UInt8]) -> Player {
        var values: Ratings = [:]
        for key in RatingKey.allCases { values[key] = ratings[key] ?? 68 }
        return Player(
            id: PlayerID(id), name: PersonName(given: "Test", family: "Player"),
            birthSeason: 2004,
            college: College(name: "Fallback State", profile: .midMajor), draft: nil,
            firstSeason: 2026,
            position: position, secondaryPositions: [],
            physical: PhysicalProfile(
                heightInches: 71, weightPounds: 215, fortyYardDash: 452, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 18),
            ratings: values, traits: [],
            hidden: HiddenAttributes(
                ceiling: 80, developmentTrait: .normal, workEthic: 60, durability: 70),
            status: .active)
    }
}

/// A punt is an attempt to put the ball somewhere, and where it lands is the punter's.
///
/// Every punt used to be struck at full distance, so from inside the opponent's 45 the
/// ball reached the end zone and the receivers took it at their 20 — a touchback four
/// times in five from the one part of the field where a punter's touch is the whole
/// point of him.
@Suite("Punting")
struct PuntingTests {

    /// The world's context with one club's punter given the leg and the touch named.
    private func context(touch: UInt8, power: UInt8 = 68, seed: UInt64 = 12) -> PlayContext {
        let (_, chart, players) = TestWorld.team(seed: seed)
        var adjusted = players
        if let punter = chart.starter(at: .punter), var man = adjusted[punter] {
            man.ratings[.puntAccuracy] = touch
            man.ratings[.puntPower] = power
            adjusted[punter] = man
        }
        let rotation = chart.rotation()
        return PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: adjusted,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)
    }

    /// Punts from `ballOn`, in the kicking team's frame, with the flagged ones dropped:
    /// a punt that never happened says nothing about where a punt lands.
    private func punts(
        from ballOn: UInt8, touch: UInt8, power: UInt8 = 68, count: Int = 3_000,
        seed: UInt64 = 23
    ) -> [Outcome] {
        let context = context(touch: touch, power: power)
        let situation = Situation(
            quarter: 2, clockRemaining: 700, down: .fourth, distance: 8, ballOn: ballOn,
            possession: TeamID(1), scoreDifferential: 0)
        let calls = Calls(
            offense: CrudePlaybook.call(.punt), defense: .preventShell,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        var random = SplittableRandom(seed: seed)
        return (0..<count).compactMap { _ in
            let resolved = CrudeResolver().resolve(
                situation: situation, calls: calls, context: context, random: &random)
            return resolved.outcome.kind == .punt ? resolved.outcome : nil
        }
    }

    /// Where the receiving team takes over, as its own yard line.
    private func averageStart(_ outcomes: [Outcome]) -> Double {
        let spots = outcomes.compactMap { outcome -> Int? in
            switch outcome.endedIn {
            // 9-5-1 Note (a): a scrimmage kick that ends in a touchback is dead on the
            // 20, wherever it was struck from.
            case .touchback: return 20
            case .downed, .outOfBounds, .fairCatch, .tackled: return Int(outcome.finalSpot ?? 20)
            // Returned for a score: the receivers did not take over anywhere.
            default: return nil
            }
        }
        guard !spots.isEmpty else { return 0 }
        return Double(spots.reduce(0, +)) / Double(spots.count)
    }

    private func touchbackShare(_ outcomes: [Outcome]) -> Double {
        guard !outcomes.isEmpty else { return 0 }
        return Double(outcomes.filter { $0.endedIn == .touchback }.count) / Double(outcomes.count)
    }

    /// What a punter from plus territory is trying to do, and why it is worth doing.
    ///
    /// 2025 rulebook, 11-6-2-c: a scrimmage kick the receivers have not touched beyond
    /// the line is a touchback once it touches the ground on or behind their goal line.
    /// 9-5-1 Note (a): the dead-ball spot for a scrimmage kick that ends in a touchback is
    /// the 20-yard line. 9-4-4: a scrimmage kick that crosses a sideline short of either
    /// goal line, or that comes to rest with nobody going after it, is the receiving
    /// team's where it died.
    ///
    /// So from the opponent's 40 a punter who places it at the 8 has bought twelve yards
    /// that a punter who hits it into the end zone has not, and the average takeover has
    /// to be nearer the goal than the 20 the touchback hands back. That last sentence is
    /// what the three articles give: the 20 is the floor a touchback puts under the
    /// receivers, and anything placed short of their goal line beats it. How often a
    /// punter with touch avoids the end zone from there is not in any of them, and is
    /// pinned separately.
    @Test(
        "football · Rule 11-6-2-c, 9-5-1 Note a, 9-4-4 · a punt from inside the opponent's 45 leaves the receivers nearer their goal than the 20 a touchback gives them",
        .tags(.football))
    func plusTerritoryPuntsBeatTheTouchback() {
        let outcomes = punts(from: 40, touch: 68)
        #expect(outcomes.count > 2_000, "only \(outcomes.count) punts were actually kicked")
        let start = averageStart(outcomes)
        #expect(start < 20, "the receivers averaged their own \(start), worse than a touchback")
    }

    /// How often the corner is actually found, which is ours and not the rulebook's.
    ///
    /// Fewer than a sixth of these punts reaching the end zone is a convention, taken
    /// from the plan that built the aimed punt rather than from an article or a sourced
    /// season. It is pinned rather than dropped because the average-start test above
    /// would still pass with a touchback rate that made the aim pointless, and every punt
    /// being struck at full distance from the opponent's 40 is exactly the behaviour this
    /// suite was written for.
    @Test(
        "pin: a punter with touch puts fewer than 15% of his plus-territory punts in the end zone (a convention, not a sourced rate)",
        .tags(.pin))
    func plusTerritoryTouchbacksStayRare() {
        let outcomes = punts(from: 40, touch: 68)
        #expect(outcomes.count > 2_000, "only \(outcomes.count) punts were actually kicked")
        let touchbacks = touchbackShare(outcomes)
        #expect(touchbacks < 0.15, "touchbacks from the 40: \(touchbacks)")
    }

    /// The call itself, before anybody kicks anything.
    @Test("A punt from plus territory is aimed, and one from your own end is hit", .tags(.unit))
    func theCallDependsOnTheField() {
        // Outside the opponent's 45 there is nothing to aim at.
        #expect(PuntPlan.chosen(from: 88, touch: 92) == .maximumDistance)
        #expect(PuntPlan.chosen(from: 60, touch: 92) == .maximumDistance)
        #expect(PuntPlan.chosen(from: 46, touch: 92) == .maximumDistance)

        // Inside it, the corner if the punter can be trusted with it and a pooch if not.
        #expect(PuntPlan.chosen(from: 42, touch: 92) == .coffinCorner)
        #expect(PuntPlan.chosen(from: 42, touch: 60) == .pooch)
        #expect(PuntPlan.chosen(from: 45, touch: 78) == .coffinCorner)
        #expect(PuntPlan.chosen(from: 30, touch: 92) == .pooch, "too close for the corner")

        #expect(PuntPlan.maximumDistance.aimedAt == nil)
        #expect(PuntPlan.pooch.aimedAt == 5...10)
        #expect(PuntPlan.coffinCorner.aimedAt == 3...5)
    }

    /// The rating has to decide something. A punter who can place it is worth more than
    /// one who can only hit it, and from plus territory that is the whole of his value.
    @Test("A punter's touch decides where the ball comes down", .tags(.unit))
    func touchDecidesPlacement() {
        let placed = punts(from: 40, touch: 92)
        let sprayed = punts(from: 40, touch: 45)

        #expect(
            touchbackShare(placed) < touchbackShare(sprayed) / 2,
            "touch \(touchbackShare(placed)) against spray \(touchbackShare(sprayed))")
        #expect(
            averageStart(placed) + 3 < averageStart(sprayed),
            "placed \(averageStart(placed)) against sprayed \(averageStart(sprayed))")
    }

    /// And the leg has to decide the other half. From his own end there is nothing to aim
    /// at and the only question is how far he can hit it.
    @Test("A punter's leg decides how far it goes from his own end", .tags(.unit))
    func legDecidesDistance() {
        func net(_ outcomes: [Outcome], from ballOn: Int) -> Double {
            let spots = outcomes.compactMap { outcome -> Int? in
                switch outcome.endedIn {
                case .touchback: return 20
                case .downed, .outOfBounds, .fairCatch, .tackled:
                    return Int(outcome.finalSpot ?? 20)
                default: return nil
                }
            }
            guard !spots.isEmpty else { return 0 }
            return Double(ballOn) - Double(spots.reduce(0, +)) / Double(spots.count)
        }

        let strong = punts(from: 88, touch: 68, power: 92)
        let weak = punts(from: 88, touch: 68, power: 45)
        #expect(
            net(strong, from: 88) > net(weak, from: 88) + 5,
            "strong \(net(strong, from: 88)) against weak \(net(weak, from: 88))")
    }
}
