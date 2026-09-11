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
    /// hold 105 flags between them of 20 distinct fouls; all thirty hold 6 offensive holds
    /// on dropbacks; ten hold 26 defensive interference calls; thirty hold 83 interference
    /// calls of either kind and 20 flags on downs where nobody threw; and the nine of
    /// `offendersAreReal`, which are six of these and three between another pair of clubs,
    /// hold 154. The thinnest of those is the six holds, which is what a floor of one is
    /// guarding: a change that stops drawing holding on dropbacks at all fails it, and one
    /// that draws a few fewer does not.
    ///
    /// **The six holds are the whole thirty, and they used to be claimed for the first
    /// eight.** Counted on this tree the eight-game prefix holds exactly one, and a claim
    /// resting on one occurrence is not a claim: `holdsAreExplicable` therefore reads all
    /// thirty, which costs nothing because every game here is already played.
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
    ///
    /// **All thirty games, and the margin is still thin.** A hold on a dropback is drawn
    /// about once in five games here, so the eight this used to read carried exactly one
    /// of them and `checked > 0` was a coin the engine tossed rather than a floor. Thirty
    /// carry six, with a leave-one-game-out jackknife standard error of 2.15 — a margin of
    /// 2.8 errors, which is thin enough that the next reader should know it: a change that
    /// halves the hold rate on dropbacks would leave this green about one time in twenty.
    /// Thirty is every game the shared corpus has, and reading them is free; resolving it
    /// properly would mean playing more, which is the suite-time budget's to spend.
    @Test("A hold on a pass play has a lost rep behind it", .tags(.contract))
    func holdsAreExplicable() {
        var checked = 0
        for (play, flag) in flags(seeds: 1...30)
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

    // MARK: - The pocket

    /// Twelve thousand deep dropbacks, walked by both tests below.
    ///
    /// **Deep, because the pocket has the longest to hold on one** — the read the
    /// quarterback is waiting on takes longest to come open, so it is the concept he is
    /// likeliest to give up on and run from. Measured on the tree this was written
    /// against: 515 of these twelve thousand end with him out of the pocket, against 338
    /// of eight thousand and 130 of four thousand on a medium route.
    ///
    /// **A forced draw rather than the corpus, because the corpus cannot reach this.**
    /// The thirty games above hold 74 downs the quarterback left the pocket on, five flags
    /// between them, and no illegal contact at all — so an assertion over them would have
    /// been green before this was fixed and green after, which is an assertion about
    /// nothing. `TestWorld.resolved` is the instrument its own documentation names for a
    /// rare exit: the same resolver on the same stream, thousands of times, able to say
    /// what it drew.
    private static let deepDropbacks: [TestWorld.Resolution] =
        TestWorld.resolved(.deepPass, count: 12_000)

    /// The downs of that draw the quarterback left the pocket on, and every flag on them.
    private static func afterLeavingThePocket() -> (downs: Int, fouls: [Foul]) {
        var downs = 0
        var fouls: [Foul] = []
        for resolution in deepDropbacks {
            guard resolution.decisions.contains(where: { $0.throwDecisionValue == .scramble })
            else { continue }
            downs += 1
            fouls += resolution.outcome.penalties.map(\.foul)
        }
        return (downs, fouls)
    }

    /// Illegal contact is not available once the quarterback has left the pocket.
    ///
    /// 2025 rulebook, 8-4-7. The restriction is written against a passer who *stays*:
    /// both halves of it — 8-4-2 inside five yards and 8-4-3 beyond them — are conditioned
    /// on the man who took the snap still being back there holding the ball. 8-4-7 says
    /// what happens when he is not, and is careful about which of the coverage fouls go
    /// with him: a quarterback who carries the ball out of the pocket takes illegal
    /// contact off the table, and the cut block with it, while the defence's holding
    /// restriction is untouched.
    ///
    /// **What the engine knows about the pocket is the scramble, and nothing else.** A
    /// `.throwDecision` of `.scramble` is the quarterback taking off with the ball, which
    /// is 8-4-7's sentence and not a proxy for it. On a down that ended as a pass there is
    /// no such fact anywhere in the record — nothing says where the passer was — so this
    /// asserts the half of the article the engine can see, and the half it cannot is
    /// written down in `docs/invariants.md` as a case the record cannot reach.
    ///
    /// Measured before this was fixed: of the 515 downs the quarterback ran out of the
    /// pocket on, 6 carried illegal contact. The 31 defensive holds on the same downs are
    /// the twin below, and they are what keeps this zero from being the zero of a draw
    /// that quietly stopped firing.
    @Test(
        "football · Rule 8-4-7 · illegal contact ends when the passer leaves the pocket",
        .tags(.football))
    func illegalContactEndsWhenThePasserLeavesThePocket() {
        let (downs, fouls) = Self.afterLeavingThePocket()
        #expect(downs > 300, "only \(downs) downs the quarterback left the pocket on")
        let called = fouls.filter { $0 == .illegalContact }.count
        #expect(
            called == 0,
            "\(called) illegal-contact calls on downs the quarterback had left the pocket on")
    }

    /// And the rest of the same sentence: defensive holding is not switched off with it.
    ///
    /// 2025 rulebook, 8-4-7 again — the article ends one of the two coverage fouls when
    /// the quarterback runs out of the pocket and leaves the other standing, and holding
    /// is the one left standing. 8-4-6 is the act it keeps available: a hand on an
    /// eligible receiver or on his jersey, or an arm put across him to steer him off his
    /// route or wrap him up.
    ///
    /// So the twin above may not be satisfied by dropping the coverage rep's flag
    /// wholesale, which is the easy way to make a count go to zero. A change that did
    /// would fail here.
    ///
    /// **The engine does tell the two acts apart**, which is why both halves of the
    /// article can be asserted rather than only the negative one:
    /// `Penalties.whenBeatenInCoverage` draws the contact once and then names it, holding
    /// or illegal contact, as two fouls and not one. What it does not model is holding's
    /// own conditions — the naming is a draw, not a grasp — so nothing here turns the
    /// contact 8-4-7 switched off into a hold instead. That would be inventing a foul to
    /// keep a rate up.
    ///
    /// Measured on the tree this was written against: 31 of these on the same 515 downs.
    /// The floor is a third of it, about four standard errors below, because what it is
    /// guarding is a draw that stopped firing and not the rate, which is the retune's.
    @Test(
        "football · Rule 8-4-7 · defensive holding survives the passer leaving the pocket",
        .tags(.football))
    func defensiveHoldingSurvivesThePasserLeavingThePocket() {
        let (downs, fouls) = Self.afterLeavingThePocket()
        #expect(downs > 300, "only \(downs) downs the quarterback left the pocket on")
        let held = fouls.filter { $0 == .defensiveHolding }.count
        let gone =
            "\(held) defensive holds on \(downs) downs the quarterback left the pocket on:"
            + " 8-4-7 keeps holding available and the engine has stopped drawing it"
        #expect(held > 10, "\(gone)")
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
    /// **Sixty games a side could not settle it, so the draw is forced instead.** Sixty
    /// quiet games hold 116 road pre-snap fouls and sixty loud ones hold 130, a lift of
    /// 14 with a leave-one-game-out jackknife standard error of 8.46. That is a margin of
    /// 1.7 errors: a comparison that says *loud is more* about four times in five whatever
    /// the engine does, which is not a test of anything. It had already been widened once,
    /// from twelve games to sixty, for the same reason — and sixty is where widening stops
    /// paying, because the quantity is a hundred-odd occurrences in two hundred games.
    ///
    /// So the two grounds are put to `Penalties.preSnap` directly, ten thousand snaps
    /// each, with a fresh stream per snap seeded identically on both sides. Everything but
    /// the crowd is the same object: the same personnel, the same call, the same
    /// situation, the same men. Noise enters that draw in exactly one place — the false
    /// start's probability, which rises with it — and `nextBool(probability:)` fires when
    /// one uniform falls under that probability, so on a shared stream the set of snaps
    /// that false-start at a quiet ground is a **subset** of the set that false-start at a
    /// loud one. That is the mechanism stated exactly, with no tolerance in it: noise may
    /// only add false starts, never move one somewhere else.
    ///
    /// What is left with any sampling error in it is whether it adds *any*, and that is
    /// 32 added snaps in ten thousand against an expectation of 28.8 — better than five
    /// standard errors, and a run that added none is a one-in-a-million-million event.
    ///
    /// **What a forced draw cannot see is the wire**, so the last check keeps it: the
    /// stadium's noise has to reach the draw through a whole game rather than stopping in
    /// the setup. Sixty seeds played at both grounds come out as different games 49 times;
    /// were the wire dead they would come out identical 60 times. The floor below is 30, a
    /// margin of about six errors. Those games are played for `noiseSparesTheHomeTeam`
    /// whatever this test does, so reading them here costs nothing.
    @Test("A loud stadium raises the road team's procedural fouls", .tags(.unit))
    func crowdNoiseIsTheMechanism() {
        let (_, chart, players) = TestWorld.team(seed: 4)
        let situation = Situation(
            quarter: 1, clockRemaining: 600, down: .first, distance: 10, ballOn: 60,
            possession: TeamID(1))
        let calls = Calls(
            offense: OffensiveCall(concept: .quickPass), defense: .baseCoverThree,
            offensiveCaller: .automatic, defensiveCaller: .automatic)

        /// The snaps of a shared stream on which a road offence at this ground false-starts.
        func falseStarts(noise: UInt8) -> Set<Int> {
            let context = PlayContext(
                offense: TeamID(1), defense: TeamID(2),
                offenseRotation: chart.rotation(), defenseRotation: chart.rotation(),
                players: players,
                offenseScheme: TeamScheme(offense: .westCoast, defense: .nickelMatch),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .fourThreeUnder),
                crowdNoise: noise, offenseIsHome: false, rules: .standard)
            // One lineup for the whole sweep, drawn off its own stream, so that the snaps
            // below differ in the crowd and in nothing else.
            var lineupRandom = SplittableRandom(seed: 4)
            let personnel = Lineup.onField(
                context, concept: .quickPass, situation: situation, random: &lineupRandom)
            var snaps: Set<Int> = []
            for snap in 0..<10_000 {
                var random = SplittableRandom(seed: 900_000 &+ UInt64(snap))
                if let flag = Penalties.preSnap(
                    situation: situation, calls: calls, context: context, personnel: personnel,
                    random: &random), flag.foul == .falseStart
                {
                    snaps.insert(snap)
                }
            }
            return snaps
        }

        let quiet = falseStarts(noise: 20)
        let deafening = falseStarts(noise: 100)
        #expect(
            quiet.isSubset(of: deafening),
            "\(quiet.subtracting(deafening).count) snaps false-started at a quiet ground and not at a loud one"
        )
        #expect(
            deafening.count > quiet.count,
            "noise made no difference to the road team: \(quiet.count) quiet, \(deafening.count) loud"
        )

        // And the crowd reaches the draw through a played game, not only through a context
        // a test built.
        var differing = 0
        for (atQuiet, atDeafening) in zip(Self.quiet, Self.deafening)
        where atQuiet.plays.map(\.outcome) != atDeafening.plays.map(\.outcome) {
            differing += 1
        }
        #expect(
            differing > 30,
            "only \(differing) of 60 seeds played a different game at the two grounds: the stadium's noise is not reaching the draw"
        )
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

    // MARK: - Interference is the reason the pass was not caught

    /// A defensive interference flag and a catch cannot both have happened on the matchup
    /// it was drawn on.
    ///
    /// 2025 rulebook, 8-5-1: interference is an act more than a yard past the line that
    /// significantly hinders an eligible receiver's opportunity to catch the ball, and the
    /// defence's restrictions run from the throw until the ball is touched. The engine
    /// draws the foul on one matchup — the man the pass was thrown to and the man covering
    /// him, which is its own simplification and not the article's — and on that matchup
    /// the two records contradict each other: the flag says his opportunity was
    /// significantly hindered, the catch says he took it anyway.
    ///
    /// What makes this true rather than filtered is the order: the foul is drawn at the
    /// throw and the catch is then resolved with the foul in hand.
    @Test(
        "football · Rule 8-5-1 · a defensive interference flag is the reason the pass was not caught",
        .tags(.football))
    func interferenceMeansNoCatch() {
        var checked = 0
        var caught = 0
        for (play, flag) in flags(seeds: 1...30)
        where flag.foul == .defensivePassInterference {
            checked += 1
            guard let result = play.decisions(ofKind: .catchAttempt).last?.catchResult else {
                continue
            }
            if result == .caught || result == .contestedCatch { caught += 1 }
        }
        #expect(checked > 20, "only \(checked) interference calls in thirty games")
        #expect(
            caught == 0,
            "\(caught) of \(checked) defensive interference flags sit on a ball the receiver caught"
        )
    }

    /// And the same fact at the level the record reports: the pass is incomplete.
    ///
    /// 8-5-1 again for what the foul is, and Rule 8 Section 5's Penalty clause for why the
    /// accept-or-decline choice cannot be relied on to hide it: the defence's interference
    /// is a first down for the offence at the spot of the foul, so a flag on an
    /// incompletion is worth taking and one on a completion that gained more is worth
    /// declining. A model that throws the flag and completes the pass anyway therefore
    /// reports a rate made almost entirely of declines, which is what the engine did:
    /// every one of them declined, in the printed game at seed 7.
    @Test(
        "football · Rule 8-5-1, 8-5-Penalty · an accepted defensive interference never sits on a completed pass",
        .tags(.football))
    func acceptedInterferenceIsNeverOnACompletion() {
        var accepted = 0
        var onCompletions = 0
        for (play, flag) in flags(seeds: 1...30)
        where flag.foul == .defensivePassInterference && flag.wasAccepted {
            accepted += 1
            if play.outcome.passResult == .complete { onCompletions += 1 }
        }
        #expect(accepted > 5, "only \(accepted) accepted interference calls in thirty games")
        #expect(
            onCompletions == 0,
            "\(onCompletions) of \(accepted) accepted interference calls sit on a completed pass")
    }

    /// There is no interference on a ball nobody could have caught.
    ///
    /// 2025 rulebook, 8-5-3-c: contact that would otherwise be interference is permissible
    /// when the pass is clearly uncatchable by the players involved — the article's one
    /// exception being the offence's blocking downfield (8-3-2, 8-5-4), which this engine
    /// does not model as an act of its own. `BallPlacement.uncatchable` is the record's
    /// name for exactly that throw: one put where nobody could reach it.
    ///
    /// It matters more than the count suggests, because the defence's interference is a
    /// spot foul: a flag on a throw nobody could catch hands the offence the ball at the
    /// spot the pass was going, for contact the rules do not make a foul at all.
    @Test(
        "football · Rule 8-5-3-c · interference is not called when the pass was clearly uncatchable",
        .tags(.football))
    func noInterferenceOnAnUncatchableBall() {
        var uncatchable = 0
        var flagged = 0
        for result in Self.neutral {
            for play in result.plays {
                guard play.decisions(ofKind: .ballArrival).last?.ballPlacement == .uncatchable
                else { continue }
                uncatchable += 1
                flagged +=
                    play.outcome.penalties.filter {
                        $0.foul == .defensivePassInterference
                            || $0.foul == .offensivePassInterference
                    }.count
            }
        }
        #expect(uncatchable > 40, "only \(uncatchable) throws nobody could reach in thirty games")
        #expect(
            flagged == 0,
            "\(flagged) interference calls on throws the record says were uncatchable")
    }

    /// The offence's interference is the other way round, and stays that way.
    ///
    /// 8-5-2 lists shoving or pushing off to create separation among the acts either side
    /// can be flagged for with the ball in the air, and Rule 8 Section 5's Penalty
    /// clause costs the offence ten yards from the previous spot — which takes the catch
    /// back rather than presuming there was not one. So a completed pass carrying
    /// offensive interference is the sport working normally, and the fix that stops the
    /// defence's flag landing on completions must not take this with it.
    ///
    /// Green before the change as well as after it: a guard on the other half of the
    /// draw, not a defect being closed.
    @Test(
        "football · Rule 8-5-2, 8-5-Penalty · offensive interference is a push-off, so it can sit on a catch",
        .tags(.football))
    func offensiveInterferenceCanSitOnACatch() {
        var offensive = 0
        var onCompletions = 0
        for (play, flag) in flags(seeds: 1...30)
        where flag.foul == .offensivePassInterference {
            offensive += 1
            if play.outcome.passResult == .complete { onCompletions += 1 }
        }
        #expect(offensive > 5, "only \(offensive) offensive interference calls in thirty games")
        #expect(
            onCompletions > 0,
            "none of \(offensive) offensive interference calls sits on a catch: the push-off has stopped nullifying anything"
        )
    }
}
