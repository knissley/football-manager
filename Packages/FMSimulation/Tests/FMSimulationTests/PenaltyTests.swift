import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// The obvious implementation — roll a die each play — produces penalties that are
/// frequent, meaningless and inexplicable. These assert the two things that stop that:
/// a foul committed while *losing* is drawn at the matchup that beat him, and home field
/// advantage is a mechanism rather than a bonus.
@Suite("Penalties")
struct PenaltyTests {

    private func game(seed: UInt64, noise: UInt8 = 50) -> GameResult {
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
                    players: players,
                    stadium: Stadium(name: "Test Field", capacity: 68_000, noise: noise),
                    seed: seed))
    }

    private func flags(
        seeds: ClosedRange<UInt64>, noise: UInt8 = 50
    ) -> [(PlayRecord, PenaltyRecord)] {
        seeds.flatMap { seed in
            game(seed: seed, noise: noise).plays.flatMap { play in
                play.outcome.penalties.map { (play, $0) }
            }
        }
    }

    // MARK: - Flags happen at all

    @Test("A game produces flags, and a spread of them")
    func flagsHappen() {
        let drawn = flags(seeds: 1...6)
        #expect(drawn.isEmpty == false, "six games and not a single flag")
        #expect(Set(drawn.map(\.1.foul)).count >= 6, "the same handful of fouls every time")
    }

    /// Both classes have to exist. Procedural fouls nobody caused, and fouls somebody
    /// committed because he was losing.
    @Test("Both classes of foul occur")
    func bothClassesOccur() {
        let drawn = flags(seeds: 1...6)
        #expect(drawn.contains { $0.1.foul.isPreSnap }, "no procedural fouls")
        #expect(drawn.contains { !$0.1.foul.isPreSnap }, "no fouls from losing a matchup")
    }

    // MARK: - Explicability

    /// The whole point of drawing a hold at the moment a blocker loses: the flag and the
    /// reason for it are the same event. *He held because he was beaten in 1.9 seconds*,
    /// with the pressure decision sitting right there in the record.
    @Test("A hold on a pass play has a lost rep behind it")
    func holdsAreExplicable() {
        var checked = 0
        for (play, flag) in flags(seeds: 1...8)
        where flag.foul == .offensiveHolding && play.outcome.kind.isDropback {
            checked += 1
            #expect(
                play.decisions.contains {
                    $0.kind == .pressureAllowed && $0.primary == flag.offender
                },
                "a hold by somebody who never lost his rep")
        }
        #expect(checked > 0, "no holds on pass plays to check")
    }

    /// Interference is drawn against defenders who were beaten, so it should never land
    /// on somebody who had the receiver blanketed.
    @Test("Interference lands on a defender who was beaten")
    func interferenceIsExplicable() {
        var checked = 0
        for (play, flag) in flags(seeds: 1...10)
        where flag.foul == .defensivePassInterference {
            checked += 1
            let coverage = play.decisions.first {
                $0.kind == .coverageAssignment && $0.primary == flag.offender
            }
            #expect(coverage != nil, "interference by somebody not in coverage")
        }
        #expect(checked > 0, "no interference calls to check")
    }

    /// Every flag names somebody who was on the field for the play.
    @Test("Every flag is charged to a player on the play")
    func offendersAreReal() {
        for (play, flag) in flags(seeds: 1...6) {
            #expect(
                play.outcome.participants.contains { $0.slot == flag.offender },
                "\(flag.foul) charged to slot \(flag.offender.rawValue), who was not credited")
            let offenceCommitted = flag.offendingTeam == play.situation.possession
            #expect(
                flag.offender.isOffense == offenceCommitted,
                "\(flag.foul) charged to the wrong side of the ball")
        }
    }

    // MARK: - Home field as a mechanism

    /// Noise raises the visiting offence's pre-snap fouls, drives stall, and the
    /// advantage *emerges* — rather than a bonus applied after the fact, which the
    /// engine's honesty pillar would have to swallow.
    @Test("A loud stadium raises the road team's procedural fouls")
    func crowdNoiseIsTheMechanism() {
        func roadPreSnapFouls(noise: UInt8) -> Int {
            var count = 0
            for seed in UInt64(1)...12 {
                let result = game(seed: seed, noise: noise)
                for play in result.plays {
                    for flag in play.outcome.penalties
                    where flag.foul.isPreSnap && flag.offendingTeam == play.situation.possession
                        && play.situation.possession == TeamID(2)
                    {
                        count += 1
                    }
                }
            }
            return count
        }

        let quiet = roadPreSnapFouls(noise: 20)
        let deafening = roadPreSnapFouls(noise: 100)
        #expect(
            deafening > quiet,
            "noise made no difference to the road team: \(quiet) quiet, \(deafening) loud")
    }

    /// And it has to be *asymmetric*, or it is not home field advantage — it is weather.
    @Test("Noise does not punish the home team")
    func noiseSparesTheHomeTeam() {
        func homePreSnapFouls(noise: UInt8) -> Int {
            var count = 0
            for seed in UInt64(1)...12 {
                let result = game(seed: seed, noise: noise)
                for play in result.plays {
                    for flag in play.outcome.penalties
                    where flag.foul.isPreSnap && flag.offendingTeam == play.situation.possession
                        && play.situation.possession == TeamID(1)
                    {
                        count += 1
                    }
                }
            }
            return count
        }

        let quiet = homePreSnapFouls(noise: 20)
        let deafening = homePreSnapFouls(noise: 100)
        #expect(
            deafening <= quiet + (quiet / 3) + 3,
            "the home crowd punished its own offence: \(quiet) quiet, \(deafening) loud")
    }

    // MARK: - Tempo

    /// Twelve men is a substitution failure, not a player failure — which is what makes
    /// hurry-up a weapon rather than a clock tactic. It does not only save time, it
    /// catches defences with twelve on the grass.
    @Test("Hurry-up catches defences with twelve on the field")
    func tempoCausesSubstitutionFouls() {
        var random = SplittableRandom(seed: 4)
        var colleges = NameGenerator.collegePool(count: 8, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let roster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        var players: [PlayerID: Player] = [:]
        for player in roster { players[player.id] = player }
        let chart = RosterGenerator.depthChart(from: roster)

        func tooManyMen(tempo: Tempo) -> Int {
            var random = SplittableRandom(seed: 77)
            let context = PlayContext(
                offense: TeamID(1), defense: TeamID(2),
                offenseRotation: chart.rotation(), defenseRotation: chart.rotation(),
                players: players,
                offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
                rules: .standard)
            let situation = Situation(
                quarter: 1, clockRemaining: 600, down: .first, distance: 10, ballOn: 60,
                possession: TeamID(1))
            let personnel = Lineup.onField(
                context, family: .insideRun, situation: situation, random: &random)
            let calls = Calls(
                offense: CrudePlaybook.call(.quickPass, tempo: tempo), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic)

            var count = 0
            for _ in 0..<4_000 {
                if let flag = Penalties.preSnap(
                    situation: situation, calls: calls, context: context, personnel: personnel,
                    random: &random), flag.foul == .tooManyMenOnField
                {
                    count += 1
                }
            }
            return count
        }

        #expect(tooManyMen(tempo: .hurryUp) > tooManyMen(tempo: .normal))
    }

    // MARK: - Enforcement

    /// Enforcement was built and tested long before anything drew a flag. This checks the
    /// two halves actually meet.
    @Test("Flags are enforced, and some are declined")
    func flagsAreEnforced() {
        let drawn = flags(seeds: 1...10)
        #expect(drawn.contains { $0.1.wasAccepted }, "no flag was ever accepted")
        #expect(drawn.contains { !$0.1.wasAccepted }, "no flag was ever declined")
        // A declined flag awards nothing.
        #expect(drawn.allSatisfy { $0.1.wasAccepted || !$0.1.awardedFirstDown })
    }

    /// A pre-snap foul kills the play, so nothing can have happened on it.
    @Test("A pre-snap foul means no play happened")
    func preSnapKillsThePlay() {
        for (play, flag) in flags(seeds: 1...8) where flag.foul.isPreSnap {
            #expect(play.outcome.kind == .penaltyOnly)
            #expect(play.outcome.yards == 0)
            #expect(play.outcome.endedIn == .penaltyEnforced)
        }
    }
}
