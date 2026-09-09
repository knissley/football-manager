import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// M1 models availability only: he is out, and for how many games. Severity,
/// rehabilitation and reaggravation are M3's, and building them against a resolver that
/// is being deleted would mean tuning them twice.
@Suite("Injuries")
struct InjuryTests {

    private func game(seed: UInt64) -> GameResult {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let homeRoster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        let awayRoster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        var players: [PlayerID: Player] = [:]
        for player in homeRoster + awayRoster { players[player.id] = player }

        return GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(
                GameSetup(
                    game: GameID(1),
                    home: GameTeam(
                        id: TeamID(1), depthChart: RosterGenerator.depthChart(from: homeRoster),
                        scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
                    away: GameTeam(
                        id: TeamID(2), depthChart: RosterGenerator.depthChart(from: awayRoster),
                        scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
                    players: players, seed: seed))
    }

    private func injuries(_ seeds: ClosedRange<UInt64>) -> [(GameResult, InjuryEvent)] {
        seeds.flatMap { seed in
            let result = game(seed: seed)
            return result.injuries.map { (result, $0) }
        }
    }

    @Test("Players get hurt, and most knocks are brief")
    func injuriesHappen() {
        let all = injuries(1...10).map(\.1)
        #expect(all.isEmpty == false, "ten games and nobody was hurt")

        let brief = all.filter { $0.gamesOut <= 1 }.count
        #expect(
            Double(brief) / Double(all.count) > 0.3,
            "most injuries should be knocks rather than season-enders")
        #expect(all.contains { $0.gamesOut >= 4 }, "nobody was ever seriously hurt")
    }

    /// An injury is located by the play it happened on. The reference names the game,
    /// the game names the week, and nothing has to agree with anything.
    @Test("Every injury points at a real play in the game it happened in")
    func injuriesPointAtRealPlays() {
        for (result, injury) in injuries(1...8) {
            #expect(injury.occurredOn.game == result.game)
            let play = result.plays.first { $0.id == injury.occurredOn }
            #expect(play != nil, "an injury on a play that is not in the stream")
            #expect(
                play?.outcome.participants.contains { $0.player == injury.player } == true,
                "somebody was hurt on a play he did not take part in")
        }
    }

    /// A knock he plays through still belongs in the stream — *he was hurt in the third
    /// and stayed in* is a real thing to be able to say.
    @Test("Some injuries end a player's game and some do not")
    func someAredPlayedThrough() {
        let all = injuries(1...10).map(\.1)
        #expect(all.contains { $0.leavesTheGame })
        #expect(all.contains { !$0.leavesTheGame })
    }

    /// The point of availability: a hurt player stops taking snaps, and next man up
    /// falls out of the depth chart with nothing else changing.
    @Test("A player forced out takes no further snaps")
    func hurtPlayersLeaveTheField() {
        for seed in UInt64(1)...8 {
            let result = game(seed: seed)
            for injury in result.injuries where injury.leavesTheGame {
                guard let index = result.plays.firstIndex(where: { $0.id == injury.occurredOn })
                else { continue }
                let afterwards = result.plays[(index + 1)...]
                #expect(
                    afterwards.allSatisfy { play in
                        !play.outcome.participants.contains { $0.player == injury.player }
                    },
                    "a player who left the game kept playing")
            }
        }
    }

    /// Contact is what hurts people. A kneel or a spike should almost never do it.
    @Test("Injuries happen on contact, not on administrative plays")
    func injuriesFollowContact() {
        var administrative = 0
        var contact = 0
        for (result, injury) in injuries(1...12) {
            guard let play = result.plays.first(where: { $0.id == injury.occurredOn }) else {
                continue
            }
            switch play.outcome.kind {
            case .kneel, .spike, .penaltyOnly, .extraPoint: administrative += 1
            default: contact += 1
            }
        }
        #expect(contact > 0)
        #expect(
            administrative * 10 < contact,
            "\(administrative) injuries on plays with no contact against \(contact) with")
    }

    /// Durability and injury resistance are what separate a player who misses a quarter
    /// from one who misses a month. A first pass had the sign backwards and gave the
    /// sturdiest players the longest absences.
    @Test("Durable players miss less time")
    func durabilityShortensAbsences() {
        func averageAbsence(resistance: UInt8, durability: UInt8) -> Double {
            var random = SplittableRandom(seed: 21)
            var total = 0
            var count = 0

            let player = Player(
                id: PlayerID(1), name: PersonName(given: "Test", family: "Back"),
                birthSeason: 2004,
                college: College(name: "Fallback State", profile: .midMajor), draft: nil,
                position: .runningBack, secondaryPositions: [],
                physical: PhysicalProfile(
                    heightInches: 71, weightPounds: 215, fortyYardDash: 452, verticalJump: 350,
                    broadJump: 1200, threeCone: 690, benchReps: 18),
                ratings: [.injuryResistance: resistance, .carrying: 70],
                traits: [],
                hidden: HiddenAttributes(
                    ceiling: 85, developmentTrait: .normal, workEthic: 60,
                    durability: durability),
                status: .active)

            let context = PlayContext(
                offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
                players: [player.id: player],
                offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
                rules: .standard)

            let play = PlayRecord(
                game: GameID(1), index: 0,
                situation: Situation(
                    quarter: 1, clockRemaining: 900, down: .first, distance: 10, ballOn: 60,
                    possession: TeamID(1)),
                calls: Calls(
                    offense: CrudePlaybook.call(.insideRun), defense: .runStuff,
                    offensiveCaller: .automatic, defensiveCaller: .automatic),
                outcome: Outcome(
                    kind: .rush, yards: 4, endedIn: .tackled,
                    participants: [
                        Participation(
                            slot: PlayerSlot(1), player: player.id, position: .runningBack,
                            role: .rusher)
                    ]))

            for _ in 0..<6_000 {
                if let injury = Injuries.drawn(on: play, context: context, random: &random) {
                    total += Int(injury.gamesOut)
                    count += 1
                }
            }
            return count == 0 ? 0 : Double(total) / Double(count)
        }

        let fragile = averageAbsence(resistance: 40, durability: 40)
        let sturdy = averageAbsence(resistance: 95, durability: 95)
        #expect(fragile > sturdy, "sturdy \(sturdy) missed more than fragile \(fragile)")
    }

    @Test("The same seed produces the same injuries")
    func deterministic() {
        #expect(game(seed: 5).injuries == game(seed: 5).injuries)
    }
}
