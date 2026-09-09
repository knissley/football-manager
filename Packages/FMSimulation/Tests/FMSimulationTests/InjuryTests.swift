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

/// A non-contact injury is a **different event**, not a heavier tackle. Nobody touched
/// him, it is uncorrelated with how the play went, and it is where the season-ending
/// ones come from. A model with only contact cannot produce a receiver planting on an
/// incompletion, which is one of the more common ways a season actually ends.
@Suite("Non-contact injuries")
struct NonContactInjuryTests {

    private func world() -> (PlayContext, Player) {
        let player = Player(
            id: PlayerID(1), name: PersonName(given: "Test", family: "Receiver"),
            birthSeason: 2004,
            college: College(name: "Fallback State", profile: .midMajor), draft: nil,
            position: .wideReceiver, secondaryPositions: [],
            physical: PhysicalProfile(
                heightInches: 73, weightPounds: 200, fortyYardDash: 445, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 14),
            ratings: [.speed: 90, .routeRunning: 82, .injuryResistance: 60],
            traits: [],
            hidden: HiddenAttributes(
                ceiling: 88, developmentTrait: .normal, workEthic: 60, durability: 60),
            status: .active)

        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
            players: [player.id: player],
            offenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            defenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            rules: .standard)
        return (context, player)
    }

    private func play(_ ending: PlayEnding, kind: PlayKind = .pass) -> PlayRecord {
        PlayRecord(
            game: GameID(1), index: 0,
            situation: Situation(
                quarter: 1, clockRemaining: 900, down: .first, distance: 10, ballOn: 60,
                possession: TeamID(1)),
            calls: Calls(
                offense: CrudePlaybook.call(.mediumPass), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic),
            outcome: Outcome(
                kind: kind, yards: 0, endedIn: ending,
                participants: [
                    Participation(
                        slot: PlayerSlot(2), player: PlayerID(1), position: .wideReceiver,
                        role: .receiver)
                ]))
    }

    /// The case a contact-only model cannot produce: nobody was tackled, and a season
    /// ends anyway.
    @Test("A receiver can go down on an incompletion")
    func happensWithNoContact() {
        let (context, _) = world()
        var random = SplittableRandom(seed: 9)
        var found = 0
        for _ in 0..<20_000 {
            if let injury = Injuries.nonContactInjury(
                on: play(.incomplete), context: context, random: &random)
            {
                #expect(injury.cause == .nonContact)
                found += 1
            }
        }
        #expect(found > 0, "twenty thousand incompletions and nobody ever pulled up")
    }

    /// They skew long. There is no walk-it-off branch: an achilles is most of a season
    /// and a hamstring is still weeks.
    @Test("Non-contact injuries always cost time, and often a lot of it")
    func theyAreSevere() {
        let (context, _) = world()
        var random = SplittableRandom(seed: 11)
        var absences: [Int] = []
        for _ in 0..<40_000 {
            if let injury = Injuries.nonContactInjury(
                on: play(.incomplete), context: context, random: &random)
            {
                absences.append(Int(injury.gamesOut))
            }
        }
        #expect(absences.isEmpty == false)
        #expect(absences.allSatisfy { $0 >= 1 }, "somebody walked off a torn achilles")
        #expect(absences.contains { $0 >= 9 }, "nothing ever ended a season")

        let mean = Double(absences.reduce(0, +)) / Double(absences.count)
        #expect(mean > 4, "non-contact injuries should cost more than contact ones: \(mean)")
    }

    /// Linemen in a phone booth do not tear knees coming out of breaks.
    @Test("Only players moving hard are exposed")
    func onlyExplosiveRolesAreExposed() {
        let (context, _) = world()
        var random = SplittableRandom(seed: 13)

        let linemenOnly = PlayRecord(
            game: GameID(1), index: 0,
            situation: play(.tackled).situation, calls: play(.tackled).calls,
            outcome: Outcome(
                kind: .rush, yards: 3, endedIn: .tackled,
                participants: [
                    Participation(
                        slot: PlayerSlot(7), player: PlayerID(1), position: .leftGuard,
                        role: .blocker)
                ]))

        for _ in 0..<20_000 {
            #expect(
                Injuries.nonContactInjury(on: linemenOnly, context: context, random: &random)
                    == nil,
                "a guard tore something in a phone booth")
        }
    }

    /// A quarterback scrambling is exposed; one standing in the pocket is not.
    @Test("A scrambling quarterback is exposed and a passing one is not")
    func scramblingExposesTheQuarterback() {
        let (context, _) = world()
        var random = SplittableRandom(seed: 17)

        func passerPlay(kind: PlayKind) -> PlayRecord {
            PlayRecord(
                game: GameID(1), index: 0,
                situation: play(.tackled).situation, calls: play(.tackled).calls,
                outcome: Outcome(
                    kind: kind, yards: 6, endedIn: .tackled,
                    participants: [
                        Participation(
                            slot: PlayerSlot(0), player: PlayerID(1), position: .quarterback,
                            role: .passer)
                    ]))
        }

        var scrambling = 0
        for _ in 0..<20_000 {
            if Injuries.nonContactInjury(
                on: passerPlay(kind: .scramble), context: context, random: &random) != nil
            {
                scrambling += 1
            }
        }
        #expect(scrambling > 0, "a scrambling quarterback was never exposed")

        for _ in 0..<20_000 {
            #expect(
                Injuries.nonContactInjury(
                    on: passerPlay(kind: .pass), context: context, random: &random) == nil,
                "a quarterback pulled up standing in the pocket")
        }
    }

    /// The resolver had no way to produce a scramble at all, so `PlayKind.scramble` was a
    /// case nothing could reach and a quarterback could not be hurt running.
    @Test("Quarterbacks actually scramble")
    func scramblesHappen() {
        var scrambles: [PlayRecord] = []
        for seed in UInt64(1)...5 {
            scrambles.append(contentsOf: scrambleGame(seed: seed))
        }
        #expect(scrambles.isEmpty == false, "five games and nobody ever escaped the pocket")
        for play in scrambles {
            #expect(
                play.decisions.contains {
                    $0.kind == .throwDecision && $0.detail == ThrowDecision.scramble.rawValue
                },
                "a scramble with no decision to scramble")
            #expect(play.outcome.participants.contains { $0.role == .passer })
        }
    }

    private func scrambleGame(seed: UInt64) -> [PlayRecord] {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let roster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        var players: [PlayerID: Player] = [:]
        for player in roster { players[player.id] = player }
        let chart = RosterGenerator.depthChart(from: roster)

        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(
                GameSetup(
                    game: GameID(1),
                    home: GameTeam(
                        id: TeamID(1), depthChart: chart,
                        scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
                    away: GameTeam(
                        id: TeamID(2), depthChart: chart,
                        scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
                    players: players, seed: seed))

        return result.plays.filter { $0.outcome.kind == .scramble }
    }
}
