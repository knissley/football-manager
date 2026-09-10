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
    @Test("Onside kicks happen when a stop would not be enough, and not otherwise")
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
    @Test("Ball security reduces fumbles and a big hitter causes them")
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
    @Test("A quarterback is stripped more often than a runner is")
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
