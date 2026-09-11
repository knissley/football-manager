import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// M1 models availability only: he is out, and for how many games. Severity,
/// rehabilitation and reaggravation are M3's, and building them against a resolver that
/// is being deleted would mean tuning them twice.
@Suite("Injuries")
struct InjuryTests {

    /// The twelve games every test in here reads a prefix of.
    ///
    /// Five tests walked their own runs of seeds — eight, ten, ten, twelve, five — and
    /// each simulated its own, which was forty-five games played to read twelve. The runs
    /// are prefixes of one another, so a test that says ten games still reads exactly the
    /// ten games it said; it just does not play them again.
    ///
    /// Twelve is what the rate asks. Measured on this fixture, a game produces about 3.7
    /// injuries — 24 across the first eight games, 32 across ten and 45 across twelve — so
    /// the smallest run any test takes carries two dozen of them and the floors below fire
    /// when nobody is getting hurt rather than when a draw came up short.
    private static let sample: [GameResult] = (UInt64(1)...12).map { TestWorld.game(seed: $0) }

    private func games(_ seeds: ClosedRange<UInt64>) -> ArraySlice<GameResult> {
        Self.sample[Int(seeds.lowerBound - 1)...Int(seeds.upperBound - 1)]
    }

    private func injuries(_ seeds: ClosedRange<UInt64>) -> [(GameResult, InjuryEvent)] {
        games(seeds).flatMap { result in result.injuries.map { (result, $0) } }
    }

    @Test("Players get hurt, and most knocks are brief", .tags(.unit))
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
    @Test("Every injury points at a real play in the game it happened in", .tags(.contract))
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
    @Test("Some injuries end a player's game and some do not", .tags(.unit))
    func someAredPlayedThrough() {
        let all = injuries(1...10).map(\.1)
        #expect(all.contains { $0.leavesTheGame })
        #expect(all.contains { !$0.leavesTheGame })
    }

    /// The point of availability: a hurt player stops taking snaps, and next man up
    /// falls out of the depth chart with nothing else changing.
    @Test("A player forced out takes no further snaps", .tags(.contract))
    func hurtPlayersLeaveTheField() {
        for result in games(1...8) {
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

    /// Contact is what hurts people, and a down nobody was hit on hurts nobody at all.
    ///
    /// This used to allow one injury on a snap with no contact for every ten with, which
    /// is a bound rather than a claim: it passes whether the rate is a tenth or a
    /// thousandth, and it passed for as long as a quarterback taking a knee could tear an
    /// achilles. The claim is zero, and the reason is in
    /// `test:noInjuryOnADownNobodyWasHitOn` — a knee, a spike and a down that was never
    /// snapped have no tackler, no blocker and nobody who ran.
    ///
    /// A kick keeps its exposure and is not in the list: a field goal and a try are
    /// scrimmage downs with a rush to block.
    ///
    /// Twelve games is a floor, not the measurement. A draw this forbids is rare enough
    /// that a sample this size would miss it most of the time either way, which is
    /// exactly why the claim is asserted over forced draws next door rather than here.
    @Test("contract · no injury comes off a down nobody was hit on", .tags(.contract))
    func injuriesFollowContact() {
        var administrative: [PlayKind] = []
        var contact = 0
        for (result, injury) in injuries(1...12) {
            guard let play = result.plays.first(where: { $0.id == injury.occurredOn }) else {
                continue
            }
            switch play.outcome.kind {
            case .kneel, .spike, .penaltyOnly: administrative.append(play.outcome.kind)
            default: contact += 1
            }
        }
        #expect(contact > 0, "twelve games and nobody was hurt on a play with contact")
        #expect(
            administrative.isEmpty,
            "hurt on a down nobody was hit on: \(administrative.map(String.init(describing:)))")
    }

    /// Durability and injury resistance are what separate a player who misses a quarter
    /// from one who misses a month. A first pass had the sign backwards and gave the
    /// sturdiest players the longest absences.
    @Test("Durable players miss less time", .tags(.unit))
    func durabilityShortensAbsences() {
        func averageAbsence(resistance: UInt8, durability: UInt8) -> Double {
            var random = SplittableRandom(seed: 21)
            var total = 0
            var count = 0

            let player = Player(
                id: PlayerID(1), name: PersonName(given: "Test", family: "Back"),
                birthSeason: 2004,
                college: College(name: "Fallback State", profile: .midMajor), draft: nil,
                firstSeason: 2026,
                position: .runningBack, secondaryPositions: [],
                physical: PhysicalProfile(
                    heightInches: 71, weightPounds: 215, fortyYardDash: 452, verticalJump: 350,
                    broadJump: 1200, threeCone: 690, benchReps: 18),
                ratings: {
                    var ratings = Ratings.uniform(60)
                    ratings[.injuryResistance] = resistance
                    ratings[.carrying] = 70
                    return ratings
                }(),
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
                    offense: OffensiveCall(concept: .insideRun), defense: .runStuff,
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

    /// **Simulated twice on purpose**, which is why this does not read the shared sample
    /// above: a replay test served from a remembered result compares a value with itself
    /// and passes whatever the engine does.
    @Test("The same seed produces the same injuries", .tags(.contract))
    func deterministic() {
        #expect(TestWorld.game(seed: 5).injuries == TestWorld.game(seed: 5).injuries)
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
            firstSeason: 2026,
            position: .wideReceiver, secondaryPositions: [],
            physical: PhysicalProfile(
                heightInches: 73, weightPounds: 200, fortyYardDash: 445, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 14),
            ratings: {
                var ratings = Ratings.uniform(60)
                ratings[.speed] = 90
                ratings[.routeRunning] = 82
                return ratings
            }(),
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
                offense: OffensiveCall(concept: .mediumPass), defense: .baseCoverThree,
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
    @Test("A receiver can go down on an incompletion", .tags(.unit))
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
    @Test("Non-contact injuries always cost time, and often a lot of it", .tags(.unit))
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
    @Test("Only players moving hard are exposed", .tags(.unit))
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
    @Test("A scrambling quarterback is exposed and a passing one is not", .tags(.unit))
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

    /// The same phone booth, one step further out: a man standing on the ball.
    ///
    /// A knee and a spike are snaps taken to stop the game rather than to play it, and
    /// the record credits one man on each. On a knee it is the quarterback as a
    /// `.rusher`, because he carried the ball — not because he ran; on a spike it is the
    /// quarterback as a `.passer`. Neither record carries a tackler, a blocker or a pass
    /// rusher, so there is nobody on it to have hit him, and neither carries anybody who
    /// changed direction at speed. A dead-ball foul is not a snap at all: the down is
    /// replayed and nobody has moved. `onlyExplosiveRolesAreExposed` makes this argument
    /// about a guard and `scramblingExposesTheQuarterback` about a passer; the role alone
    /// cannot make it about a knee, because the role on a knee reads `.rusher`.
    ///
    /// This is not a cosmetic point about who limps off. After the two-minute warning an
    /// injury costs the injured player's team a charged team timeout (2025 rulebook,
    /// 4-5-4-a) and the game clock then waits for the next snap (4-3-2). So a quarterback
    /// hurt taking a knee hands the clock back to the side that has just knelt the half
    /// away, and a caller counting a clock that is no longer running has to play the down
    /// after all.
    ///
    /// Forced draws rather than a sample, and with a control: the same draw over a carry
    /// has to keep producing injuries, or a zero here would mean nothing.
    @Test(
        "contract · a down nobody was hit on and nobody ran on injures nobody: a knee, a spike, and a down that was never snapped",
        .tags(.contract))
    func noInjuryOnADownNobodyWasHitOn() {
        let (context, _) = world()

        func snap(_ kind: PlayKind, _ role: PlayRole, _ position: Position) -> PlayRecord {
            PlayRecord(
                game: GameID(1), index: 0,
                situation: play(.tackled).situation, calls: play(.tackled).calls,
                outcome: Outcome(
                    kind: kind, yards: kind == .kneel ? -1 : 0,
                    endedIn: kind == .kneel ? .tackled : .incomplete,
                    participants: [
                        Participation(
                            slot: SlotLayout.quarterback, player: PlayerID(1),
                            position: position, role: role)
                    ]))
        }

        let dead: [(String, PlayRecord)] = [
            ("a knee", snap(.kneel, .rusher, .quarterback)),
            ("a spike", snap(.spike, .passer, .quarterback)),
            ("a down never snapped", snap(.penaltyOnly, .rusher, .quarterback)),
        ]

        for (name, record) in dead {
            var random = SplittableRandom(seed: 4_051)
            var hurt = 0
            for _ in 0..<200_000 {
                if Injuries.drawn(on: record, context: context, random: &random) != nil {
                    hurt += 1
                }
            }
            #expect(hurt == 0, "\(hurt) men hurt on \(name) across two hundred thousand of them")
        }

        // The control. Same draw, same seed, a carry instead — if this is zero too, the
        // zeroes above are the harness rather than the model.
        var random = SplittableRandom(seed: 4_051)
        var carried = 0
        for _ in 0..<200_000 {
            if Injuries.drawn(
                on: snap(.rush, .rusher, .runningBack), context: context, random: &random) != nil
            {
                carried += 1
            }
        }
        #expect(carried > 0, "the control drew no injuries at all, so the zeroes above say nothing")
    }

    /// The resolver had no way to produce a scramble at all, so `PlayKind.scramble` was a
    /// case nothing could reach and a quarterback could not be hurt running.
    /// Five games, because a scramble is not rare: fourteen of them across these five,
    /// measured, which is three a game. The floor is a guard against the resolver losing
    /// the exit entirely, which is the state this was written out of.
    private static let sample: [GameResult] = (UInt64(1)...5).map { TestWorld.game(seed: $0) }

    @Test("Quarterbacks actually scramble", .tags(.unit))
    func scramblesHappen() {
        let scrambles = Self.sample.flatMap { result in
            result.plays.filter { $0.outcome.kind == PlayKind.scramble }
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
}
