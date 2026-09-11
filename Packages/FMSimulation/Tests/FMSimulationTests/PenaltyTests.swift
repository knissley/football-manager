import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The obvious implementation — roll a die each play — produces penalties that are
/// frequent, meaningless and inexplicable. These assert the two things that stop that:
/// a foul committed while *losing* is drawn at the matchup that beat him, and home field
/// advantage is a mechanism rather than a bonus.
@Suite("Penalties")
struct PenaltyTests {

    /// The stadium is fixed rather than the home team's, because noise is the variable
    /// under test: a generated ground brings its own, and the quiet-versus-loud comparison
    /// below would then be measuring two grounds instead of one mechanism.
    private static func game(
        seed: UInt64, noise: UInt8 = 50, home: Int = 0, away: Int = 1
    ) -> GameResult {
        TestWorld.game(
            seed: seed, home: home, away: away,
            stadium: Stadium(name: "Test Field", capacity: 68_000, noise: noise))
    }

    /// The thirty games at the neutral setting that every test but the noise pair reads.
    ///
    /// **One set, sliced, rather than a set per test.** Six tests below walk the first
    /// six, eight, ten or thirty of these seeds, and each used to simulate its own: a
    /// hundred and two games to read thirty. A game is a pure function of its setup, so
    /// the seventh reading of seed 3 is the same football as the first — and the slices
    /// are prefixes of one another, so a test that says six games still reads exactly the
    /// six games it said.
    ///
    /// **What each slice actually carries**, measured on the tree this was written
    /// against, so that the floors below are floors rather than hopes: the first six games
    /// hold 105 flags between them of 20 distinct fouls; eight hold 6 offensive holds on
    /// dropbacks; ten hold 26 defensive interference calls; thirty hold 83 interference
    /// calls of either kind and 20 flags on downs where nobody threw; and the nine of
    /// `offendersAreReal`, which are six of these and three between another pair of clubs,
    /// hold 154. The thinnest of those is the six holds, which is what a floor of one is
    /// guarding: a change that stops drawing holding on dropbacks at all fails it, and one
    /// that draws a few fewer does not.
    private static let neutral: [GameResult] = (UInt64(1)...30).map { game(seed: $0) }

    /// The paired noise comparison's two sides, each played once and read by both tests.
    /// The two tests are the same sixty fixtures counted twice over, once for each side of
    /// the ball, so playing them twice was a hundred and twenty games nobody needed.
    private static let quiet: [GameResult] = (UInt64(1)...60).map { game(seed: $0, noise: 20) }
    private static let deafening: [GameResult] = (UInt64(1)...60).map {
        game(seed: $0, noise: 100)
    }

    private func flags(seeds: ClosedRange<UInt64>) -> [(PlayRecord, PenaltyRecord)] {
        Self.neutral[Int(seeds.lowerBound - 1)...Int(seeds.upperBound - 1)].flatMap { result in
            result.plays.flatMap { play in play.outcome.penalties.map { (play, $0) } }
        }
    }

    // MARK: - Flags happen at all

    @Test("A game produces flags, and a spread of them", .tags(.unit))
    func flagsHappen() {
        let drawn = flags(seeds: 1...6)
        #expect(drawn.isEmpty == false, "six games and not a single flag")
        #expect(Set(drawn.map(\.1.foul)).count >= 6, "the same handful of fouls every time")
    }

    /// Both classes have to exist. Procedural fouls nobody caused, and fouls somebody
    /// committed because he was losing.
    @Test("Both classes of foul occur", .tags(.unit))
    func bothClassesOccur() {
        let drawn = flags(seeds: 1...6)
        #expect(drawn.contains { $0.1.foul.isPreSnap }, "no procedural fouls")
        #expect(drawn.contains { !$0.1.foul.isPreSnap }, "no fouls from losing a matchup")
    }

    // MARK: - Explicability

    /// The whole point of drawing a hold at the moment a blocker loses: the flag and the
    /// reason for it are the same event. *He held because he was beaten in 1.9 seconds*,
    /// with the lost rep sitting right there in the record.
    ///
    /// The rep is what this asks about, so it reads the `.blockResult` that records it.
    /// It used to read `.pressureAllowed`, which was the same thing back when every lost
    /// rep was called pressure; it is not any more — a blocker can lose and the ball be
    /// gone before his man arrives — and a hold drawn on that rep is still explicable.
    @Test("A hold on a pass play has a lost rep behind it", .tags(.contract))
    func holdsAreExplicable() {
        var checked = 0
        for (play, flag) in flags(seeds: 1...8)
        where flag.foul == .offensiveHolding && play.outcome.kind.isDropback {
            checked += 1
            #expect(
                play.decisions.contains {
                    $0.kind == .blockResult && $0.blockResultValue == .lost
                        && $0.primary == flag.offender
                },
                "a hold by somebody who never lost his rep")
        }
        #expect(checked > 0, "no holds on pass plays to check")
    }

    /// Interference is drawn against defenders who were beaten, so it should never land
    /// on somebody who had the receiver blanketed.
    @Test("Interference lands on a defender who was beaten", .tags(.contract))
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

    /// There is no such thing as interference on a play nobody threw.
    ///
    /// 2025 rulebook, 8-5-1. Interference of either kind needs a forward pass thrown
    /// from behind the line to exist at all, legal or not and whether or not it gets
    /// past the line. The article fixes the window too — the defence's restrictions run
    /// from the throw until the ball is touched — and says what contact nearer the line
    /// than a yard is instead, which is holding by one side or the other.
    ///
    /// So a sack, a scramble and a throwaway can carry defensive holding or illegal
    /// contact and cannot carry interference of either kind.
    @Test(
        "football · Rule 8-5-1 · interference cannot be called on a down with no forward pass",
        .tags(.football))
    func noInterferenceWithoutAThrow() {
        var withoutAThrow = 0
        var flagged = 0
        for (play, flag) in flags(seeds: 1...30) {
            let noThrow = play.outcome.kind == .sack || play.outcome.kind == .scramble
            guard noThrow else { continue }
            withoutAThrow += 1
            if flag.foul == .defensivePassInterference || flag.foul == .offensivePassInterference {
                flagged += 1
            }
        }
        // The count itself falls when the fix lands, because the interference flags on
        // these downs stop being drawn rather than becoming some other foul. It is here
        // to prove the case was exercised at all, not as a rate.
        #expect(withoutAThrow > 10, "only \(withoutAThrow) flags on downs with no throw")
        #expect(flagged == 0, "\(flagged) interference calls on downs where nobody threw it")
    }

    /// And interference is on the man the ball was thrown to.
    ///
    /// 8-5-1 again: interference is hindering an eligible receiver's chance at the ball,
    /// and 8-5-4's version of the offence's is a block near whoever the pass is going to.
    /// A flag on a receiver the quarterback never looked at is a flag with no ball near
    /// it.
    @Test("Interference is on the target's matchup, not on somebody else's", .tags(.contract))
    func interferenceIsOnTheTarget() {
        var checked = 0
        for (play, flag) in flags(seeds: 1...30) {
            guard
                flag.foul == .defensivePassInterference
                    || flag.foul == .offensivePassInterference
            else { continue }
            guard
                let target = play.outcome.participants.first(where: { $0.role == .target })
            else {
                Issue.record("interference on a play with no target at all")
                continue
            }
            checked += 1
            if flag.foul == .offensivePassInterference {
                #expect(
                    flag.offender == target.slot,
                    "offensive interference by a receiver who was not the target")
                continue
            }
            let covering = play.decisions.first {
                $0.kind == .coverageAssignment && $0.secondary == target.slot
            }
            #expect(
                covering?.primary == flag.offender,
                "interference by a defender who was covering somebody else")
        }
        #expect(checked > 10, "only \(checked) interference calls to check")
    }

    /// A flag names a slot, and the record resolves every slot: `onField` carries the
    /// twenty-two men, so a receiver running a decoy route, a rusher who never reached
    /// the kicker or a blocker on a return is as identifiable as the man who made the
    /// tackle. For a while he was not. The only way to resolve a slot was
    /// `outcome.participants`, a flag on a man the play never credited named nobody, and
    /// this test carried a register of the eight fouls that could do it — it had asserted
    /// the contract over six seeds and passed by luck, then pinned the gap instead. The
    /// register is gone with the gap, and the contract is asserted the way a reader of
    /// the stream would use it: through `player(at:rosters:)`, over the six seeds the
    /// original asked and three more between a different pair of clubs.
    ///
    /// Three things per flag: the record names the offender, he is on the offending
    /// team's roster, and the slot is on the side of the ball the team was.
    @Test("Every flag names a player the record identifies", .tags(.contract))
    func offendersAreReal() {
        let games =
            Array(Self.neutral.prefix(6))
            + (UInt64(1)...3).map { Self.game(seed: $0, home: 3, away: 6) }
        var checked = 0
        for result in games {
            for play in result.plays {
                for flag in play.outcome.penalties {
                    checked += 1
                    let offender = play.player(at: flag.offender, rosters: result.rosters)
                    #expect(
                        offender != nil,
                        "\(flag.foul) charged to slot \(flag.offender), whom the record cannot name"
                    )
                    if let offender {
                        #expect(
                            result.rosters[flag.offendingTeam]?.contains(offender) == true,
                            "\(flag.foul) charged to a man not on the offending team")
                    }
                    let offenceCommitted = flag.offendingTeam == play.situation.possession
                    #expect(
                        flag.offender.isOffense == offenceCommitted,
                        "\(flag.foul) charged to the wrong side of the ball")
                }
            }
        }
        #expect(checked > 100, "nine games and \(checked) flags to check")
    }

    // MARK: - Home field as a mechanism

    /// Noise raises the visiting offence's pre-snap fouls, drives stall, and the
    /// advantage *emerges* — rather than a bonus applied after the fact, which the
    /// engine's honesty pillar would have to swallow.
    ///
    /// **Sixty games a side, not twelve.** Twelve games hold about twenty road pre-snap
    /// fouls, and the lift being measured is a fifth of that — so the comparison was
    /// reading the sample rather than the mechanism, and it passed on the size of a
    /// rounding error. [#67](https://github.com/knissley/football-manager/issues/67) moved
    /// the generated world (older rosters, ratings with them) and the twelve-game counts
    /// came out 19 quiet against 18 loud while the same games at sixty seeds gave 106
    /// against 126. On the tree before that change the two samples were 30 against 36 and
    /// 117 against 151: the mechanism is the same size on both, and only the small sample
    /// disagrees with it. Paired — the same seeds, the same games, one thing different — so
    /// what is left after the pairing is the noise and nothing else.
    @Test("A loud stadium raises the road team's procedural fouls", .tags(.unit))
    func crowdNoiseIsTheMechanism() {
        func roadPreSnapFouls(_ games: [GameResult]) -> Int {
            var count = 0
            for result in games {
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

        let quiet = roadPreSnapFouls(Self.quiet)
        let deafening = roadPreSnapFouls(Self.deafening)
        #expect(
            deafening > quiet,
            "noise made no difference to the road team: \(quiet) quiet, \(deafening) loud")
    }

    /// And it has to be *asymmetric*, or it is not home field advantage — it is weather.
    ///
    /// **Sixty games a side, for the reason the road-side twin above gives.** The home
    /// offence's pre-snap draw does not read the crowd at all — `Penalties.preSnap` takes
    /// the noise term as zero when the offence is the home team — so what is left in the
    /// counts is the stream being reshuffled: a road false start is an extra play, every
    /// play after it is drawn from a different split, and the home team's own flags land
    /// in different places. Twelve games hold about fifteen of them and the reshuffle
    /// moves more than the tolerance, so the small sample was reading the shuffle. Across
    /// nine noise settings at twelve games the counts ran 14, 15, 15, 15, 16, 21, 25, 25,
    /// 23; the same settings at sixty games ran 106, 111, 110, 112, 119, 122, 128, 129,
    /// 124 — a drift of a fifth on a quantity the code cannot move, which is the size of
    /// the shuffle and not of a mechanism.
    @Test("Noise does not punish the home team", .tags(.unit))
    func noiseSparesTheHomeTeam() {
        func homePreSnapFouls(_ games: [GameResult]) -> Int {
            var count = 0
            for result in games {
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

        let quiet = homePreSnapFouls(Self.quiet)
        let deafening = homePreSnapFouls(Self.deafening)
        #expect(
            deafening <= quiet + (quiet / 3) + 3,
            "the home crowd punished its own offence: \(quiet) quiet, \(deafening) loud")
    }

    // MARK: - Tempo

    /// Twelve men is a substitution failure, not a player failure — which is what makes
    /// hurry-up a weapon rather than a clock tactic. It does not only save time, it
    /// catches defences with twelve on the grass.
    @Test("Hurry-up catches defences with twelve on the field", .tags(.unit))
    func tempoCausesSubstitutionFouls() {
        let (_, chart, players) = TestWorld.team(seed: 4)

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
                context, concept: .insideRun, situation: situation, random: &random)
            let calls = Calls(
                offense: OffensiveCall(concept: .quickPass, tempo: tempo), defense: .baseCoverThree,
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
    @Test("Flags are enforced, and some are declined", .tags(.unit))
    func flagsAreEnforced() {
        let drawn = flags(seeds: 1...10)
        #expect(drawn.contains { $0.1.wasAccepted }, "no flag was ever accepted")
        #expect(drawn.contains { !$0.1.wasAccepted }, "no flag was ever declined")
        // A declined flag awards nothing.
        #expect(drawn.allSatisfy { $0.1.wasAccepted || !$0.1.awardedFirstDown })
    }

    /// A pre-snap foul kills the play, so nothing can have happened on it.
    @Test("A pre-snap foul means no play happened", .tags(.unit))
    func preSnapKillsThePlay() {
        for (play, flag) in flags(seeds: 1...8) where flag.foul.isPreSnap {
            #expect(play.outcome.kind == .penaltyOnly)
            #expect(play.outcome.yards == 0)
            #expect(play.outcome.endedIn == .penaltyEnforced)
        }
    }
}
