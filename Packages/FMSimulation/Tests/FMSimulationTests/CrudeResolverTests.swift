import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The constraints in this suite are the point of the crude resolver, not a nicety.
///
/// A resolver that drew a result and decorated it with plausible reasons would let the
/// analysis layer appear to work while reading fiction — the named risk of building M2
/// against scaffolding ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
/// These assert the causal chain and the outcome describe the same play.
@Suite("Crude resolver")
struct CrudeResolverTests {

    private func world(seed: UInt64 = 5) -> (GameSetup, [PlayerID: Player]) {
        let setup = TestWorld.setup(seed: seed)
        return (setup, setup.players)
    }

    /// The eight games the tests below read a prefix of.
    ///
    /// Six tests walked four, six, six, eight, four and four seeds and each simulated its
    /// own, which was thirty-three games played to read eight. The runs are prefixes of
    /// one another, so nothing here reads a different game from the one it used to.
    ///
    /// Every promise in this suite is made of *every* play of its kind in the run it
    /// takes, not of a play the run has to contain, so the size is a question of how much
    /// evidence rather than of what the draw held: four games hold about six hundred snaps
    /// and eight about twelve hundred, and the thinnest thing any of them looks at is the
    /// interception, at 1.4 a game.
    private static let sample: [GameResult] = (UInt64(1)...8).map { TestWorld.game(seed: $0) }

    private func game(seed: UInt64 = 5) -> GameResult {
        Self.sample[Int(seed) - 1]
    }

    // MARK: - The causal chain

    /// Every slot a decision point names must be a player who was credited. A decision
    /// referencing somebody who was not on the play is a reason attached to nobody.
    /// The rules layer's points about the clock — the play clock a snap was taken
    /// against, a choice about the clock between downs — name nobody, and an empty
    /// slot is how a point says so.
    @Test("Every slot named in a decision is a credited participant", .tags(.contract))
    func decisionsNameRealPlayers() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays where !play.decisions.isEmpty {
                let credited = Set(play.outcome.participants.map(\.slot))
                for decision in play.decisions where !decision.primary.isNone {
                    #expect(
                        credited.contains(decision.primary),
                        "\(decision.kind) named slot \(decision.primary.rawValue), uncredited")
                    if !decision.secondary.isNone {
                        #expect(
                            credited.contains(decision.secondary),
                            "\(decision.kind) named slot \(decision.secondary.rawValue), uncredited"
                        )
                    }
                }
            }
        }
    }

    /// A sack must have a rusher who actually got there, and it must be *that* rusher.
    /// This is the example ADR-0012 uses, so it is the one to hold hardest.
    @Test("A sack is credited to the rusher whose pressure caused it", .tags(.contract))
    func sacksNameTheRusherWhoGotThere() {
        var sacks = 0
        for seed in UInt64(1)...6 {
            for play in game(seed: seed).plays where play.outcome.kind == .sack {
                sacks += 1
                guard
                    let decision = play.decisions.first(where: {
                        $0.kind == .throwDecision && $0.detail == ThrowDecision.sack.rawValue
                    })
                else {
                    Issue.record("a sack with no sack decision")
                    continue
                }
                let rusher = decision.secondary
                #expect(
                    play.decisions.contains {
                        $0.kind == .pressureAllowed && $0.secondary == rusher
                    },
                    "the sacking rusher never beat anybody")
                // Specifically as the tackler. Accepting either role here is what let a
                // silently dropped credit through: the rusher was still down as a pass
                // rusher from winning his rep, so the test passed while the league had
                // no sack leaders at all.
                #expect(
                    play.outcome.participants.contains {
                        $0.slot == rusher && $0.role == .tackler
                    },
                    "the sack was attributable to nobody")
            }
        }
        #expect(sacks > 0, "six games produced no sacks at all")
    }

    /// Every sack belongs to exactly one player. A sack nobody is credited with does
    /// not appear in a stat line, an award race, or a Hall of Fame case.
    @Test("Every sack is attributable to exactly one player", .tags(.contract))
    func sacksAreAttributable() {
        for seed in UInt64(1)...6 {
            for play in game(seed: seed).plays where play.outcome.kind == .sack {
                let tacklers = play.outcome.participants.filter { $0.role == .tackler }
                #expect(tacklers.count == 1, "\(tacklers.count) players credited with a sack")
                #expect(tacklers.first?.slot.isOffense == false, "the offence sacked itself")
            }
        }
    }

    /// An interception has to name the defender who took it, and the ending has to agree
    /// with the catch decision.
    @Test("An interception agrees with its catch decision", .tags(.contract))
    func interceptionsAgree() {
        var picks = 0
        for seed in UInt64(1)...8 {
            for play in game(seed: seed).plays where play.outcome.endedIn == .intercepted {
                picks += 1
                let attempt = play.decisions.first { $0.kind == .catchAttempt }
                #expect(
                    attempt?.detail == CatchResult.intercepted.rawValue,
                    "an interception whose catch decision says otherwise")
                #expect(play.outcome.finalSpot != nil, "an interception with no spot")
            }
        }
        #expect(picks > 0, "eight games produced no interceptions")
    }

    /// A completion names a receiver, and that receiver is the one the throw went to.
    @Test("A completion's target is the receiver the quarterback read to", .tags(.contract))
    func completionsNameTheirTarget() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays
            where play.outcome.kind == .pass && play.outcome.yards > 0 {
                guard
                    let thrown = play.decisions.first(where: {
                        $0.kind == .throwDecision && $0.detail == ThrowDecision.primary.rawValue
                    })
                else { continue }
                let target = thrown.secondary
                #expect(
                    play.decisions.contains { $0.kind == .ballArrival && $0.primary == target },
                    "the ball arrived to somebody else")
                #expect(
                    play.outcome.participants.contains { $0.slot == target },
                    "the target was not credited")
            }
        }
    }

    /// Decisions happen in order. A ball arriving before it was thrown is a causal chain
    /// nobody can read.
    @Test("Decisions are ordered in time", .tags(.contract))
    func decisionsAreOrdered() {
        for seed in UInt64(1)...4 {
            for play in game(seed: seed).plays {
                let throwTick = play.decisions.first { $0.kind == .throwDecision }?.tick
                let arrival = play.decisions.first { $0.kind == .ballArrival }?.tick
                if let throwTick, let arrival {
                    #expect(arrival > throwTick, "the ball arrived before the throw")
                }
                let katch = play.decisions.first { $0.kind == .catchAttempt }?.tick
                if let arrival, let katch {
                    #expect(katch >= arrival, "the catch resolved before the ball got there")
                }
            }
        }
    }

    // MARK: - Attribution

    /// Every snap credits real players, which is what M2's grades and awards have to
    /// work with.
    @Test("Every scrimmage play credits real players from the roster", .tags(.contract))
    func participantsAreRealPlayers() {
        let (setup, players) = world()
        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(setup)

        for play in result.plays where play.outcome.kind.isScrimmagePlay {
            #expect(
                play.outcome.participants.isEmpty == false, "play \(play.index) credited nobody")
            for participant in play.outcome.participants {
                #expect(players[participant.player] != nil, "credited a player who does not exist")
                #expect(
                    players[participant.player]?.position == participant.position,
                    "credited a player at somebody else's position")
            }
        }
    }

    /// Offence and defence live on opposite sides of the slot convention. A defender
    /// credited in an offensive slot would make every team-derived statistic wrong.
    ///
    /// A kick inverts it, and that is the sport rather than an exception to code around:
    /// the kicking team has possession, so the man carrying the ball is on the
    /// *defensive* side and the men chasing him are on the offensive one. Getting this
    /// backwards would put a punt return on the punting team's stat line.
    @Test("Participants sit on the correct side of the slot convention", .tags(.contract))
    func slotsMatchSides() {
        for play in game().plays {
            let kick = play.outcome.kind == .kickoff || play.outcome.kind == .punt

            for participant in play.outcome.participants {
                let hasTheBall: Bool
                switch participant.role {
                case .passer, .rusher, .receiver, .target, .blocker: hasTheBall = true
                case .returner: hasTheBall = true
                case .passRusher, .coverage, .tackler, .assistTackler, .runDefender:
                    hasTheBall = false
                default: continue
                }
                // The side with the ball is the offence, except on a kick.
                #expect(
                    participant.slot.isOffense == (kick ? !hasTheBall : hasTheBall),
                    "\(participant.role) in slot \(participant.slot.rawValue) on a \(play.outcome.kind)"
                )
            }
        }
    }

    /// Rotation means backups play. If the same eleven took every snap, depth on a
    /// roster would be invisible.
    ///
    /// One game, and one is the right number: the claim is about a single game's rotation,
    /// so a second would be a second instance of the same claim rather than more evidence
    /// for it. The floor is two starting elevens plus a few, which fires when nobody is
    /// rotating at all.
    @Test("More than a starting eleven appears over a game", .tags(.contract))
    func rotationReachesBackups() {
        let result = game()
        let appeared = Set(result.plays.flatMap { $0.outcome.participants.map(\.player) })
        #expect(appeared.count > 30, "only \(appeared.count) players took a snap")
    }

    // MARK: - Determinism

    @Test("The same seed resolves identically", .tags(.contract))
    func deterministic() {
        // Simulated twice on purpose, so this does not read the shared sample above: a
        // replay test served from a remembered result compares a value with itself.
        let first = TestWorld.game(seed: 12)
        let second = TestWorld.game(seed: 12)
        #expect(first.plays.map(\.outcome) == second.plays.map(\.outcome))
        #expect(first.plays.map(\.decisions) == second.plays.map(\.decisions))
    }
}

/// The shape of the contest curve is a design property, not an implementation detail.
///
/// If a slightly better player always won, football would be a lookup table. If an
/// enormously better player won no more often than a slightly better one, ratings at the
/// top of the league would be decoration.
@Suite("Contest curve")
struct ContestCurveTests {

    private let resolver = CrudeResolver()

    @Test("Equal players split their reps", .tags(.unit))
    func parityIsEven() {
        #expect(resolver.contest(80, 80) == 0.5)
        #expect(resolver.contest(45, 45) == 0.5)
    }

    /// A point of overall is a nudge, not a verdict.
    @Test("A one-point edge is a nudge", .tags(.unit))
    func smallEdgesAreSmall() {
        let edge = resolver.contest(81, 80)
        #expect(edge > 0.5)
        #expect(edge < 0.54, "one point of overall should not decide a matchup")
    }

    /// The property that failed: a ceiling made a ninety-nine no better than an
    /// eighty-one against the same man.
    @Test("Better is always better, all the way up", .tags(.unit))
    func strictlyMonotonic() {
        let ladder = [60.0, 70.0, 75.0, 81.0, 86.0, 90.0, 95.0, 99.0]
        let odds = ladder.map { resolver.contest($0, 70) }
        for (index, value) in odds.enumerated().dropFirst() {
            #expect(
                value > odds[index - 1],
                "\(Int(ladder[index])) is no better than \(Int(ladder[index - 1])) against a 70")
        }
    }

    /// Nobody is ever certain. The best pass rusher in the league is happy with two
    /// sacks in a game, not one every snap against a weaker tackle.
    @Test("Nobody wins or loses every rep", .tags(.unit))
    func neverCertain() {
        #expect(resolver.contest(99, 20) <= 0.93)
        #expect(resolver.contest(99, 20) < 0.9, "even a total mismatch loses reps")
        #expect(resolver.contest(20, 99) >= 0.07)
        #expect(resolver.contest(20, 99) > 0.1, "even a hopeless matchup wins some")
    }

    @Test("The curve is symmetric about parity", .tags(.unit))
    func symmetric() {
        for (a, b) in [(90.0, 70.0), (99.0, 40.0), (81.0, 80.0)] {
            let forward = resolver.contest(a, b)
            let reverse = resolver.contest(b, a)
            #expect(abs((forward + reverse) - 1.0) < 0.0001, "\(a) v \(b)")
        }
    }

    /// A situational edge shifts the whole curve without breaking any of the above.
    @Test("An edge shifts the curve and keeps it bounded", .tags(.unit))
    func edgesStayBounded() {
        #expect(resolver.contest(80, 80, edge: 0.35) > 0.5)
        #expect(resolver.contest(80, 80, edge: -0.35) < 0.5)
        #expect(resolver.contest(99, 20, edge: 0.9) <= 0.93)
        #expect(resolver.contest(20, 99, edge: -0.9) >= 0.07)
    }
}

/// Getting out of bounds is a decision the man with the ball makes, and the reason he
/// makes it is a clock rule.
///
/// A tackle used to end out of bounds at a flat 14% whatever the play was and whatever
/// the clock was doing, and a carrier who beat every tackler was out of bounds by
/// construction. So the two-minute drill had no lever for stopping the clock and the
/// offence protecting a lead had none for keeping it running.
@Suite("Out of bounds")
struct OutOfBoundsTests {

    private func context(seed: UInt64 = 12) -> PlayContext {
        let (_, chart, players) = TestWorld.team(seed: seed)
        let rotation = chart.rotation()
        return PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)
    }

    private static let neutral = Situation(
        quarter: 2, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
        possession: TeamID(1), scoreDifferential: 0, offensePersonnel: .eleven,
        defensePackage: .nickel)
    /// Two minutes, a score down: the sideline is where the clock stops.
    private static let trailingLate = Situation(
        quarter: 4, clockRemaining: 100, down: .first, distance: 10, ballOn: 65,
        possession: TeamID(1), scoreDifferential: -6, offensePersonnel: .eleven,
        defensePackage: .nickel)
    /// Late, a touchdown up: the sideline is the last place he wants to be.
    private static let leadingLate = Situation(
        quarter: 4, clockRemaining: 200, down: .first, distance: 10, ballOn: 65,
        possession: TeamID(1), scoreDifferential: 10, offensePersonnel: .eleven,
        defensePackage: .nickel)

    private func resolved(
        _ concept: PlayConcept, _ situation: Situation, count: Int = 3_000, seed: UInt64 = 41
    ) -> [(outcome: Outcome, decisions: [DecisionPoint])] {
        let context = context()
        let calls = Calls(
            offense: OffensiveCall(concept: concept), defense: .nickelTwoMan,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        var random = SplittableRandom(seed: seed)
        return (0..<count).map { _ in
            let onField = Lineup.onField(
                context, concept: concept, situation: situation, random: &random)
            return CrudeResolver().resolve(
                situation: situation, calls: calls, onField: onField, context: context,
                random: &random)
        }
    }

    /// Of the plays that ended with the man down somewhere on the field, the share that
    /// ended on the sideline.
    private func sidelineShare(
        _ plays: [(outcome: Outcome, decisions: [DecisionPoint])]
    ) -> Double {
        let down = plays.filter {
            $0.outcome.endedIn == .tackled || $0.outcome.endedIn == .outOfBounds
        }
        guard !down.isEmpty else { return 0 }
        return Double(down.filter { $0.outcome.endedIn == .outOfBounds }.count)
            / Double(down.count)
    }

    /// The clock rule that makes the sideline worth reaching, and the same rule read from
    /// the other bench.
    ///
    /// 2025 rulebook, 4-3-2-a: a runner going out of bounds on a scrimmage down leaves
    /// the clock to restart on the referee's ready signal — **except** that it starts on the
    /// snap after the two-minute warning of the first half and inside the last five
    /// minutes of the second. So late in a game the sideline is the only place a trailing
    /// offence's clock stays stopped, and it is the one place a leading offence must not
    /// go.
    ///
    /// The article gives the direction of that and nothing else. It says which way each
    /// bench wants the ball to end; it says nothing about how often either gets its way,
    /// and no season this repo has sourced does either. So the football claim here is the
    /// sign of the difference. How big the difference is is a modelling choice and is
    /// pinned separately.
    @Test(
        "football · Rule 4-3-2-a · a trailing offence inside two minutes reaches the sideline more often than one protecting a lead late",
        .tags(.football))
    func theSidelineIsAClockDecision() {
        let trailing = sidelineShare(resolved(.quickPass, Self.trailingLate))
        let leading = sidelineShare(resolved(.quickPass, Self.leadingLate))
        #expect(
            trailing > leading,
            "trailing \(trailing) against leading \(leading): the clock is not a lever")
    }

    /// How big that lever is, which is ours and not the rulebook's.
    ///
    /// Nothing in 4-3-2-a, and no sourced season, says a two-minute drill ends a fifth of
    /// its tackles out of bounds or that an offence killing the clock ends fewer than a
    /// tenth of them there. Those three numbers are conventions, chosen when the lever was
    /// built. They are pinned rather than dropped because a lever that quietly shrank to
    /// nothing would still satisfy the football test above, and a two-minute offence that
    /// cannot get out of bounds is the bug this suite was written for.
    @Test(
        "pin: the size of the sideline lever — trailing late over twice leading late, above 20% against under 10%, all three conventions rather than sourced",
        .tags(.pin))
    func theSidelineLeverKeepsItsSize() {
        let trailing = sidelineShare(resolved(.quickPass, Self.trailingLate))
        let leading = sidelineShare(resolved(.quickPass, Self.leadingLate))
        #expect(
            trailing > leading * 2,
            "trailing \(trailing) against leading \(leading): the lever shrank")
        #expect(trailing > 0.20, "a two-minute drill that cannot get out of bounds: \(trailing)")
        #expect(leading < 0.10, "a clock-burning offence still running to the sideline: \(leading)")
    }

    /// Where the ball ends is drawn, never assumed.
    ///
    /// A carrier who beat all three men chasing him used to end out of bounds by
    /// construction — the ending was written into the code rather than drawn — so a
    /// breakaway could not finish any other way. It is a rare carry, about one in a
    /// thousand, which is why the probe counts them explicitly rather than trusting a
    /// share to show it.
    ///
    /// **Both floors here rest on a handful of carries, and widening is not cheap.**
    /// Eight thousand outside runs produce 3 of them on this stream, all 3 in bounds;
    /// resampled the counts average about 2 and about 1.5, so each floor of one sits
    /// inside two standard errors of firing on a run that is not this one — at two
    /// breakaways the chance of finding none at all is about one in seven. Forty thousand
    /// runs produce 16 and 12, which would clear both floors comfortably, and cost about
    /// nineteen seconds of a suite whose total is the budget's to spend. So the margin is
    /// written down rather than bought: **the next reader should treat a red here as a
    /// question about the sample before treating it as a question about the engine.**
    ///
    /// The cheap fix is not a bigger sample but a forced one — a carrier whose contact
    /// balance against this pursuit makes breaking all three ordinary rather than rare, so
    /// the path is exercised tens of times for nothing. That is a fixture rather than a
    /// comment and it is not built here.
    @Test(
        "A carrier who breaks every tackle is not out of bounds by construction",
        .tags(.contract))
    func breakawaysAreNotSidelineByConstruction() {
        let breakaways = resolved(.outsideRun, Self.neutral, count: 8_000).filter { play in
            let attempts = play.decisions.filter { $0.kind == .tackleAttempt }
            guard attempts.count == 3,
                attempts.allSatisfy({ $0.detail == TackleResult.broken.rawValue })
            else { return false }
            return play.outcome.endedIn == .tackled || play.outcome.endedIn == .outOfBounds
        }
        #expect(breakaways.count > 0, "no carry beat everybody: the case was never exercised")
        let inBounds = breakaways.filter { $0.outcome.endedIn == .tackled }.count
        #expect(
            inBounds > 0,
            "all \(breakaways.count) breakaways ended out of bounds — construction, not a draw")
    }

    /// A run outside the tackles is already headed for the sideline; one between them is
    /// twenty-odd yards from it.
    @Test("An outside run reaches the sideline more often than an inside run", .tags(.unit))
    func theSidelineDependsOnTheCall() {
        let outside = sidelineShare(resolved(.outsideRun, Self.neutral))
        let inside = sidelineShare(resolved(.insideRun, Self.neutral))
        #expect(
            outside > inside * 2,
            "outside \(outside) against inside \(inside): the call makes no difference")
    }
}

/// What a carry looks like, rather than what it averages.
///
/// A mean is not a distribution. An engine can put four and a half yards a carry on the
/// board by handing every back four and a half yards, or by stuffing half of them and
/// springing the rest, and neither is the sport. These assert the shape: that the
/// ordinary carry — through the line, into the second level, three to nine yards — is
/// the largest part of the run game, and that the long run is something the carrier did
/// rather than something the blocking bought.
@Suite("The shape of a carry")
struct CarryShapeTests {

    /// Every designed carry of the shared corpus. Scrambles are a different play and the
    /// record gives them their own kind, exactly as the sourced shares below exclude
    /// them.
    private static let carries: [PlayRecord] =
        TestWorld.corpus.flatMap { $0.plays }.filter { $0.outcome.kind == .rush }

    private static func share(_ test: (Int) -> Bool) -> Double {
        let yards = carries.map { Int($0.outcome.yards) }
        return Double(yards.filter(test).count) / Double(max(1, yards.count)) * 100
    }

    /// The middle of the run distribution, and the claim that it is the largest part of
    /// it.
    ///
    /// Nothing sources the share of carries gaining three to nine directly, so it is
    /// derived from the two sourced shares either side of it (2023-24, nflverse
    /// play-by-play; `row:carries2orFewer` and `row:carries10plus` in
    /// `docs/reference/calibration-sources.md`). Every carry falls in exactly one of the
    /// three, so
    ///
    ///     three to nine = 100 − (two or fewer) − (ten or more)
    ///
    /// and with two or fewer sourced at 40.6–46.5 and ten or more at 9.6–11.2, the middle
    /// share lies between **42.3 and 49.8** however the two sourced shares fall inside
    /// their own bands.
    ///
    /// **The 42.3 floor is not asserted here, because forty games cannot resolve it and
    /// the harness already grades it.** The corpus reads 45.04% of 2,440 carries, and the
    /// leave-one-game-out jackknife standard error of that share is 1.46 — a margin of 1.9
    /// errors, so the test was deciding on which forty games it drew rather than on where
    /// the engine was. The precise claim is the conjunction of the two sourced ceilings,
    /// and both of those are graded rows: `row:carries2orFewer` at or under 46.5 and
    /// `row:carries10plus` at or under 11.2 *is* three-to-nine at or over 42.3, by the
    /// arithmetic above and nothing else. Those two rows are graded over four hundred
    /// games at two seeds, which is ten times this corpus, and the harness prints the
    /// derived middle beside them. A second, weaker copy of a sourced rate in the suite
    /// buys nothing and costs the suite-time budget.
    ///
    /// **What forty games can resolve, both read off the sourced bands rather than off
    /// the engine:**
    ///
    /// - **The middle is at least an even share of the three parts.** There are exactly
    ///   three, so an even share is 33.3%, and the bands put the middle at 42.3% at their
    ///   worst corner — nine points of room. The corpus reads 45.04% against a jackknife
    ///   error of 1.46: **8.0 errors clear**. Its worst single game reads 26.7%, which is
    ///   why the claim is made of the corpus and not of a game.
    /// - **The middle is larger than the ten-or-more share.** The bands put that gap at
    ///   31.1 points at their worst corner (42.3 against 11.2), so a gap of any size at all
    ///   has thirty-one points of room. The corpus reads 33.20 against a jackknife error of
    ///   1.51: **22 errors clear**, worst single game 15.6.
    ///
    /// It deliberately does **not** assert that the middle is larger than the two-or-fewer
    /// share. That holds at the midpoints of the two bands, 46.0 against 43.6, but not at
    /// every corner, so it is a reading of where the bands centre rather than something
    /// they imply, and it is written down here instead of being asserted. The corpus reads
    /// 45.04 against 43.11 — under two points, and less than the gap's own sampling error.
    @Test(
        "football · nflverse play-by-play 2023-24 · the middle of the run game is at least an even third of it and beats the long carry",
        .tags(.football))
    func theMiddleIsTheLargestPartOfTheRunGame() {
        let middle = Self.share { $0 >= 3 && $0 <= 9 }
        let long = Self.share { $0 >= 10 }
        #expect(
            middle >= 100.0 / 3.0,
            "carries of three to nine are \(middle)% of \(Self.carries.count), floor 33.3%")
        #expect(
            middle > long,
            "carries of three to nine are \(middle)% against \(long)% of ten or more")
    }

    /// A long run is a man beaten, not a hole measured.
    ///
    /// The engine's own promise about its run game: a carry that goes twenty yards or
    /// more has a broken tackle in front of it in the same record. Nothing about the
    /// blocking alone may produce one, because a distribution whose tail is drawn rather
    /// than earned puts the yards on the offensive line and leaves the back's contact
    /// balance worth nothing.
    @Test("Every carry of twenty or more has a broken tackle in front of it", .tags(.contract))
    func aBreakawayIsAlwaysABrokenTackle() {
        let long = Self.carries.filter { $0.outcome.yards >= 20 }
        #expect(long.count > 0, "no carry reached twenty: the case was never exercised")
        let unearned = long.filter { play in
            !play.decisions.contains {
                $0.kind == .tackleAttempt && $0.detail == TackleResult.broken.rawValue
            }
        }.count
        #expect(
            unearned == 0,
            "\(unearned) of \(long.count) carries of twenty or more broke no tackle")
    }

    /// Yards rise with the hole the carry came through.
    ///
    /// The record publishes the hole as a `.holeQuality` point, so this reads the engine's
    /// own number rather than inferring one. The scale pays twelve a block — twelve for a
    /// block won or lost at the point of attack, twelve for a defender the offence had no
    /// blocker for — so the bins below are a block wide, and the claim is that a carry
    /// through a better hole is not worth fewer yards on average than one through a worse.
    ///
    /// Against each bin's own sampling error rather than a fixed yard, because a carry's
    /// length is a wide distribution and the best holes are the thinnest bins: the top of
    /// the range holds a few hundred carries whose mean moves half a yard on the draw
    /// alone. A fixed tolerance either passes a real inversion at the bottom or fails on
    /// noise at the top.
    @Test("A carry's yards rise with the hole it came through", .tags(.contract))
    func yardsRiseWithTheHole() {
        var byBin: [Int: [Int]] = [:]
        for play in Self.carries {
            guard
                let hole = play.decisions.first(where: {
                    $0.kind == .holeQuality && $0.primary == SlotLayout.back
                })
            else { continue }
            byBin[Int(hole.value) / 12, default: []].append(Int(play.outcome.yards))
        }
        // A bin too thin to have a mean says nothing either way.
        let bins = byBin.filter { $0.value.count >= 100 }.keys.sorted()
        #expect(bins.count >= 5, "only \(bins.count) bins had enough carries to read")
        var previous: (bin: Int, mean: Double, error: Double)?
        for bin in bins {
            let yards = byBin[bin]!.map(Double.init)
            let mean = yards.reduce(0, +) / Double(yards.count)
            let spread = yards.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(yards.count)
            let error = (spread / Double(yards.count)).squareRoot()
            if let below = previous {
                let tolerance = 2 * (below.error + error)
                let message =
                    "bin \(bin * 12) averaged \(mean) against \(below.mean) for bin "
                    + "\(below.bin * 12), a fall of more than \(tolerance)"
                #expect(mean >= below.mean - tolerance, "\(message)")
            }
            previous = (bin, mean, error)
        }
    }
}

/// Whose incompletion it was.
///
/// `CatchResult` is the only field that says why a pass fell incomplete, and everything
/// downstream — a drop rate, a pass-defensed leaderboard, the narrative layer's sentence
/// about the play — repeats whatever it says. So the label has to name the man who
/// actually caused it: the receiver on a ball he could have caught, the defender on a
/// ball he got to, and the passer on a ball he put where it could not be caught.
///
/// **These are promises the record makes about its own vocabulary, not claims about the
/// rules.** The sport has no article on what a drop is — a drop is charting vocabulary
/// rather than a rule, and nothing in this repository sources a drop rate — so they are
/// `.contract` under CLAUDE.md rule 11 rather than `.football` with a citation that would
/// have to be stretched to fit. What the rules *do* say about a ball nobody could catch
/// is asserted in `PenaltyTests`, from 8-5-3-c.
@Suite("The catch, and whose incompletion it was")
struct CatchVocabularyTests {

    /// The shared forty-game corpus: 2,505 catch attempts and 662 incompletions on the
    /// tree this was written against, which is two orders more than either assertion
    /// below needs and costs nothing, because six other suites have already played it.
    private struct Attempt {
        let placement: BallPlacement
        let result: CatchResult
        let separation: Int
        let wasInterfered: Bool
    }

    private static let attempts: [Attempt] =
        TestWorld.corpus.flatMap(\.plays).compactMap { play in
            guard let attempt = play.decisions(ofKind: .catchAttempt).last,
                let result = attempt.catchResult,
                let placement = play.decisions(ofKind: .ballArrival).last?.ballPlacement
            else { return nil }
            return Attempt(
                placement: placement, result: result, separation: Int(attempt.value),
                wasInterfered: play.outcome.penalties.contains {
                    $0.foul == .defensivePassInterference
                })
        }

    /// A drop is a catchable ball the receiver did not catch.
    ///
    /// The engine used to call every failed catch with the receiver open a drop, whatever
    /// the ball's placement was, so a throw the quarterback put where nobody could be
    /// expected to catch it was charged to the man it was thrown at. `BallPlacement` is
    /// already on the record one decision earlier and says which kind of throw it was.
    @Test(
        "contract: a drop is only ever recorded on a ball the receiver could have caught",
        .tags(.contract))
    func dropsAreOnCatchableBalls() {
        let drops = Self.attempts.filter { $0.result == .dropped }
        #expect(drops.count > 50, "only \(drops.count) drops in the corpus: nothing to check")
        let uncatchable = drops.filter {
            $0.placement == .poor || $0.placement == .uncatchable
        }.count
        #expect(
            uncatchable == 0,
            "\(uncatchable) of \(drops.count) drops were charged to the receiver on a ball placed poor or uncatchable"
        )
    }

    /// A break-up is the defender's act, so he has to have been able to make it.
    ///
    /// Either he was inside the contested distance and knocked it away, or he committed
    /// interference and the flag is the reason the ball was not caught — which is the
    /// one way a receiver with separation ends the play with no catch and the defender
    /// named for it (2025 rulebook, 8-5-1).
    ///
    /// Green before the change and after it, and it is the second half that needs it: a
    /// break-up drawn from a flag lands on a receiver who was open by construction, since
    /// the foul is drawn on separation. Without the second clause this would fail the
    /// moment interference starts causing incompletions.
    @Test(
        "contract: a break-up is recorded only where the defender was in reach or fouled the receiver",
        .tags(.contract))
    func breakUpsAreTheDefendersAct() {
        let brokenUp = Self.attempts.filter { $0.result == .brokenUp }
        #expect(brokenUp.count > 20, "only \(brokenUp.count) break-ups in the corpus")
        let unexplained = brokenUp.filter { $0.separation >= 110 && !$0.wasInterfered }.count
        #expect(
            unexplained == 0,
            "\(unexplained) of \(brokenUp.count) break-ups were credited to a defender who was neither in reach nor flagged"
        )
    }

    /// And the passer's incompletions are his: a ball placed poorly that is not caught is
    /// nobody's failure at the catch point.
    ///
    /// Written without naming the case that carries it, because *which* case does is a
    /// vocabulary question — a new one, or the existing `.uncatchable` widened — and the
    /// promise is the same either way: the two labels that name a player at the catch
    /// point are not the ones a poor ball gets. Which case the engine actually uses is
    /// pinned by `VocabularyCoverageTests`' register and printed by `gamelog`.
    ///
    /// The exception is the defender's foul, and it is the same one the break-up test
    /// carries. A poor ball is still a catchable one — 8-5-3-c exempts only the throw
    /// nobody could reach — so a defender who spoiled the receiver's chance at it caused
    /// the incompletion whatever the placement was, and the record names him.
    @Test(
        "contract: an uncaught poor ball is recorded against the throw, not against either player at the catch point",
        .tags(.contract))
    func poorBallsAreTheThrowsOwn() {
        let poor = Self.attempts.filter { $0.placement == .poor }
        #expect(poor.count > 100, "only \(poor.count) poor balls in the corpus")
        let uncaught = poor.filter {
            $0.result != .caught && $0.result != .contestedCatch && $0.result != .intercepted
        }
        #expect(uncaught.count > 50, "only \(uncaught.count) uncaught poor balls")
        let blamedAtTheCatchPoint = uncaught.filter {
            ($0.result == .dropped || $0.result == .brokenUp) && !$0.wasInterfered
        }.count
        #expect(
            blamedAtTheCatchPoint == 0,
            "\(blamedAtTheCatchPoint) of \(uncaught.count) uncaught poor balls were charged to the receiver or the defender"
        )
    }
}

/// What the record says about the pocket, and when it is entitled to say it.
///
/// The engine used to flag pressure the moment a rusher beat his blocker, which made
/// three of every four dropbacks pressured and a screen as pressured as a deep drop.
/// Winning a rep and getting to the quarterback are two different things, and only the
/// second is what the statistic means.
@Suite("The pocket")
struct PocketTests {

    private func context(seed: UInt64 = 12) -> PlayContext {
        let (_, chart, players) = TestWorld.team(seed: seed)
        let rotation = chart.rotation()
        return PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)
    }

    /// First and ten near midfield, nothing about the clock or the score pulling on the
    /// call: the pocket is the only thing under test.
    private static let neutral = Situation(
        quarter: 2, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
        possession: TeamID(1), scoreDifferential: 0, offensePersonnel: .eleven,
        defensePackage: .nickel)

    private func resolved(
        _ concept: PlayConcept, _ situation: Situation, count: Int = 3_000, seed: UInt64 = 41
    ) -> [(outcome: Outcome, decisions: [DecisionPoint])] {
        let context = context()
        let calls = Calls(
            offense: OffensiveCall(concept: concept), defense: .nickelTwoMan,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        var random = SplittableRandom(seed: seed)
        return (0..<count).map { _ in
            let onField = Lineup.onField(
                context, concept: concept, situation: situation, random: &random)
            return CrudeResolver().resolve(
                situation: situation, calls: calls, onField: onField, context: context,
                random: &random)
        }
    }

    /// Every pass concept the resolver knows, so a claim about the pocket is made across
    /// the whole range of how long the ball is held rather than on one route.
    private static let passConcepts: [PlayConcept] = [
        .screen, .quickPass, .mediumPass, .playAction, .deepPass,
    ]

    /// Pressure is a rusher getting there *before the ball is out*, not a rusher winning.
    ///
    /// The statistic this engine is calibrated against is Next Gen Stats' pressure flag
    /// over attempts, sacks and scrambles (2023-24; `row:pressureRate`, source S2 in
    /// `docs/reference/calibration-sources.md`). It marks the dropbacks on which the
    /// passer was got to. A rusher who beat his blocker a beat after the ball had gone
    /// did not get to anybody: the rep was lost and the throw was clean, and those are
    /// two different facts about the same snap. The resolver records the first as a
    /// `.blockResult` and only the second as `.pressureAllowed`.
    ///
    /// This is the claim, and it is checked against the record's own throw time rather
    /// than against a constant, so it stays true if the pocket's timings are ever retuned.
    @Test(
        "football · pressure per S2 2023-24 · a rusher who arrives after the ball is gone did not pressure the passer",
        .tags(.football))
    func pressureMeansTheRusherGotThereFirst() {
        var lateFlags = 0
        var checkedPressures = 0
        var lostReps = 0
        var sample = ""
        for concept in Self.passConcepts {
            for play in resolved(concept, Self.neutral, count: 2_000) {
                lostReps +=
                    play.decisions.filter {
                        $0.kind == .blockResult && $0.blockResultValue == .lost
                    }.count
                // A throw the quarterback made to his read carries the moment the ball
                // came out. A sack or a scramble has no such moment — the ball never
                // left — so those snaps cannot answer this question and are skipped.
                guard
                    let ballOut = play.decisions.first(where: {
                        $0.kind == .throwDecision && $0.detail == ThrowDecision.primary.rawValue
                    })?.value
                else { continue }
                for point in play.decisions where point.kind == .pressureAllowed {
                    checkedPressures += 1
                    if point.value >= ballOut {
                        lateFlags += 1
                        if sample.isEmpty {
                            sample =
                                "\(concept): pressure at \(point.value)ms, ball out at \(ballOut)ms"
                        }
                    }
                }
            }
        }
        #expect(lostReps > 0, "ten thousand dropbacks and no blocker ever lost: nothing to check")
        #expect(checkedPressures > 0, "ten thousand dropbacks and no pressure at all")
        #expect(
            lateFlags == 0,
            "\(lateFlags) of \(checkedPressures) recorded pressures arrived after the throw — \(sample)"
        )
    }

    /// The rosters the pooled pocket measurement draws from, and how many dropbacks each
    /// contributes to every concept.
    ///
    /// Seven generated leagues rather than one — every roster either probe in this suite
    /// has ever drawn on. A chain of inequalities measured on a single roster is a single
    /// draw: each share is a property of that roster's line and front as much as of the
    /// pocket, so a chain that happens to come out ordered on the one roster a probe drew
    /// says nothing about whether the engine orders it.
    private static let pocketRosterSeeds: [UInt64] = [1, 5, 7, 11, 12, 23, 41]
    private static let dropbacksPerRoster = 350
    /// The stream every dropback in the pooled sample is split out of.
    private static let pocketFixtureSeed: UInt64 = 41

    /// One dropback, drawn from a stream that depends on the roster and the play index
    /// and on nothing else.
    ///
    /// This is what makes the comparison below a *paired* one, and it is what lets a
    /// chain across concepts be read at all. Everything the pocket is decided from — who
    /// is on the field, which rusher beat which blocker, and when he arrived — is drawn
    /// before the concept's route depth is first consulted, so two concepts handed the
    /// same stream see the same eleven men and the same rush on the same snap. Their
    /// verdicts then differ only where the hold differs, which is the thing under test.
    /// Resampling each concept independently instead leaves every comparison carrying the
    /// noise of two fresh draws, and that is what let one roster's luck decide the answer.
    ///
    /// `split` depends on the root seed and its labels and never on how far a stream has
    /// been advanced, so the pairing holds at every index rather than only the first.
    private func coupledDropback(
        _ concept: PlayConcept, context: PlayContext, rosterSeed: UInt64, index: Int
    ) -> [DecisionPoint] {
        let calls = Calls(
            offense: OffensiveCall(concept: concept), defense: .nickelTwoMan,
            offensiveCaller: .automatic, defensiveCaller: .automatic)
        var random = SplittableRandom(seed: Self.pocketFixtureSeed)
            .split(rosterSeed, UInt64(index))
        let onField = Lineup.onField(
            context, concept: concept, situation: Self.neutral, random: &random)
        return CrudeResolver().resolve(
            situation: Self.neutral, calls: calls, onField: onField, context: context,
            random: &random
        ).decisions
    }

    /// What the pooled sample says about each pass concept, in the order they hold the
    /// ball: the hold its record reports, whether each snap came back pressured, and when
    /// the first rusher got home on that snap — the last so the pairing can be checked
    /// rather than assumed.
    private func pooledPocket() -> [(
        concept: PlayConcept, hold: Int, pressured: [Bool], firstArrival: [Int]
    )] {
        let rosters = Self.pocketRosterSeeds.map { (seed: $0, context: context(seed: $0)) }
        return Self.passConcepts.map { concept in
            var hold = 0
            var pressured: [Bool] = []
            var firstArrival: [Int] = []
            for roster in rosters {
                for index in 0..<Self.dropbacksPerRoster {
                    let decisions = coupledDropback(
                        concept, context: roster.context, rosterSeed: roster.seed, index: index)
                    pressured.append(decisions.contains { $0.kind == .pressureAllowed })
                    // The hold is the same on every snap of a concept, and only a snap the
                    // protection survived reports it: a pressured snap was over before the
                    // hold was up, so its record carries the arrival instead.
                    if let held = decisions.first(where: { $0.kind == .pressureHeld }) {
                        hold = Int(held.value)
                    }
                    let arrivals = decisions.filter {
                        $0.kind == .blockResult && $0.blockResultValue == .lost
                    }.map { Int($0.value) }
                    firstArrival.append(arrivals.min() ?? -1)
                }
            }
            return (concept, hold, pressured, firstArrival)
        }
    }

    /// The other half of the same claim: how long the ball is held is what decides how
    /// much of the rush gets home.
    ///
    /// **This is a promise the engine makes about itself, and it is deliberately not a
    /// football test.** The claim it used to make was: pressure rises *strictly* from
    /// each concept to the next, screen through deep pass. Four of those links, one
    /// sentence, and nothing sourced any of them. What the references band is pressure
    /// per dropback pooled over all of them — `row:pressureRate`, 27.8-32.3%, 2023-24,
    /// source S2 in docs/reference/calibration-sources.md, which the harness grades — and
    /// neither that file nor the playing rules splits it by concept, by pass depth, or by
    /// the time the quarterback held the ball. A split is a rate, so the rulebook has
    /// nothing to say about it; it is a sourcing gap, and it is recorded as one under
    /// *what a generated world claims and nothing sources*. Asserting a chain of
    /// inequalities nothing sources, as football, is the thing this project most wants
    /// not to do, so the chain is made against the resolver's own definition of pressure
    /// instead — which is exactly what a `.contract` is for.
    ///
    /// What the resolver promises, then. Pressure is the first rusher home arriving
    /// *before the ball is out*. The arrival is a fact about two men and is drawn before
    /// the concept's route is ever consulted, so for one rush the verdict is a threshold
    /// on the hold and nothing else: lengthen the hold and a snap can only turn from
    /// clean to pressured, never back. That is asserted here snap by snap, on the paired
    /// draw above, so it holds exactly rather than on average — no tolerance, no sampling
    /// error, and no roster able to decide the answer.
    ///
    /// **The last link is flat, and that is the engine and not the sample.** A beaten
    /// blocker is beaten between 1,500 ms and 2,899 ms; play action asks for 3,000 and a
    /// deep drop for 3,400. Both sit past the latest a rusher can arrive, so the verdict
    /// cannot tell them apart and returns the same 0.5559 on the same snaps — measured
    /// over 2,450 paired dropbacks each, identical to the last snap, not merely close.
    /// A strict inequality there was green on one roster's luck. Whether the sport
    /// separates those two is the unsourced question above; if it is ever sourced and it
    /// does, the fix is the hold in `routeDepth`, and this assertion is already the shape
    /// that would catch it going the wrong way.
    ///
    /// The span is the other half, because a superset claim is satisfied by a pocket with
    /// no clock at all: if pressure were the lost rep again, all five concepts would be
    /// pressured on exactly the same snaps and every link would pass. So the ends of the
    /// chain are also held apart. A tenth is far under the 0.5559 the engine spreads them
    /// by, so it pins nothing about the clock's shape, and far over the nothing a
    /// clockless pocket would produce — under the pairing that null has no sampling
    /// spread at all, since the two ends would be the same snaps.
    @Test(
        "A longer hold is never pressured less often than a shorter one, off the same rush",
        .tags(.contract))
    func pressureNeverFallsAsTheHoldGrows() {
        let measured = pooledPocket()
        let share = { (entry: [Bool]) in
            Double(entry.filter { $0 }.count) / Double(entry.count)
        }
        for (earlier, later) in zip(measured, measured.dropFirst()) {
            // The pairing, before anything is read off it: the same roster and the same
            // index must have produced the same rush under both concepts, or what follows
            // compares two samples rather than two holds.
            #expect(
                earlier.firstArrival == later.firstArrival,
                "\(earlier.concept) and \(later.concept) did not see the same rush on the same snaps"
            )
            // And the chain really is in hold order, read off the records rather than
            // assumed from the order the concepts happen to be listed in.
            #expect(
                earlier.hold < later.hold,
                "\(earlier.concept) holds \(earlier.hold)ms against \(later.concept) at \(later.hold)ms: the chain is not ordered by the hold"
            )
            let clearedByWaitingLonger = zip(earlier.pressured, later.pressured).filter {
                $0 && !$1
            }.count
            #expect(
                clearedByWaitingLonger == 0,
                "\(clearedByWaitingLonger) of \(earlier.pressured.count) snaps were pressured holding \(earlier.hold)ms and clean holding \(later.hold)ms, off the same rush"
            )
        }
        guard let shortest = measured.first, let longest = measured.last else {
            Issue.record("no pass concepts to chain")
            return
        }
        let span = share(longest.pressured) - share(shortest.pressured)
        #expect(
            span > 0.1,
            "\(shortest.concept) at \(shortest.hold)ms is pressured \(share(shortest.pressured)) of the time and \(longest.concept) at \(longest.hold)ms \(share(longest.pressured)): the pocket is not on a clock"
        )
    }

    /// The window the rush arrives in has to span the holds it is compared against, or
    /// the comparison is not a comparison.
    ///
    /// Pressure is one inequality: did the first man home get there before the ball came
    /// out. The arrival is drawn once per beaten blocker, the hold is a property of the
    /// concept, and the verdict is the two read against each other. An inequality whose
    /// two sides cannot cross is not an inequality — it is a constant wearing one — and
    /// that is the failure this asserts against.
    ///
    /// It bites at both ends. A hold **under the earliest arrival** is never pressured,
    /// whatever the rush did and whoever is blocking: the concept is un-pressurable by
    /// construction rather than hard to pressure. A hold **over the latest arrival** is
    /// pressured on every snap a rep was lost, so the hold stops being read at all — and
    /// any two such holds are then pressured on exactly the same snaps, which makes them
    /// the same concept however far apart their numbers look. Both are silent: the shares
    /// come out plausible, and nothing in them says the dial is dead.
    ///
    /// So four things, all measured off the paired sample above and none of them a
    /// statement about a constant, so that a hold moved out of the window fails this
    /// rather than the next person to wonder why a parameter does nothing:
    ///
    /// 1. the **earliest** first arrival is sooner than the shortest hold any concept
    ///    asks for, so the quickest ball in the game can still be beaten;
    /// 2. the **latest** first arrival is later than the longest hold, so the deepest
    ///    drop in the game can still be protected;
    /// 3. no concept's verdict is a constant — every one of them is pressured on some
    ///    snaps and clean on others;
    /// 4. no two concepts are pressured on the *same* snaps — waiting longer has to turn
    ///    at least one clean snap into a pressured one, or the extra hold bought nothing.
    ///
    /// The fourth is the exact complement of the superset in the test above: that one
    /// says a longer hold is never pressured *less*, this one says it is pressured
    /// *more*. Together they are what makes the hold a dial rather than a label.
    @Test(
        "The rush's arrival window spans every route hold, so every hold is read",
        .tags(.contract))
    func theArrivalWindowSpansTheRouteHolds() {
        let measured = pooledPocket()
        guard let shortest = measured.first, let longest = measured.last else {
            Issue.record("no pass concepts to span")
            return
        }
        // The first man home, on the snaps anybody got home at all. This is the quantity
        // the hold is compared against, so it is the one that has to span them — a later
        // rusher on the same snap never decides anything.
        let arrivals = shortest.firstArrival.filter { $0 > 0 }
        #expect(arrivals.count > 0, "no rusher ever got home: nothing to span")
        let earliest = arrivals.min() ?? 0
        let latest = arrivals.max() ?? 0
        #expect(
            earliest < shortest.hold,
            "the earliest arrival in \(arrivals.count) rushes is \(earliest)ms and the shortest hold is \(shortest.concept) at \(shortest.hold)ms: that concept cannot be pressured at all"
        )
        #expect(
            latest > longest.hold,
            "the latest arrival in \(arrivals.count) rushes is \(latest)ms and the longest hold is \(longest.concept) at \(longest.hold)ms: that concept is pressured whenever any rep is lost, so its hold is never read"
        )
        for entry in measured {
            let pressured = entry.pressured.filter { $0 }.count
            #expect(
                pressured > 0 && pressured < entry.pressured.count,
                "\(entry.concept) at \(entry.hold)ms came back pressured on \(pressured) of \(entry.pressured.count) snaps: its verdict is a constant, not a comparison"
            )
        }
        for (earlier, later) in zip(measured, measured.dropFirst()) {
            let boughtByWaiting = zip(earlier.pressured, later.pressured).filter { !$0 && $1 }
                .count
            #expect(
                boughtByWaiting > 0,
                "\(earlier.concept) at \(earlier.hold)ms and \(later.concept) at \(later.hold)ms were pressured on exactly the same snaps: \(later.hold - earlier.hold)ms of extra hold changed nothing"
            )
        }
    }

    /// What a dropback records about its pocket, once, whatever happened in it.
    ///
    /// One `.blockResult` per rep resolved — the fact of the matchup — and then exactly
    /// one verdict on the pocket: `.pressureAllowed` if somebody got there before the
    /// ball was out, `.pressureHeld` if nobody did. A reader asking *was he pressured?*
    /// gets one answer per snap, which is what makes the question answerable from the
    /// stream at all.
    ///
    /// A snap the defence fielded no edge or interior lineman on has no rep to resolve
    /// and gets no verdict, rather than a verdict naming a slot nobody is standing in.
    /// That is rare, and it is the reason the count is tied to the reps rather than
    /// asserted flat.
    ///
    /// **The bound is the spread and not one draw.** It read "under 2%", which was this
    /// sample's share at the seed the probe happens to use. The share is a property of
    /// the lineup draw rather than of anything in the pocket, and it moves with the
    /// stream: measured over six seeds — 1, 5, 7, 11, 23 and the probe's own 41 — it is
    /// 1.4% to 2.8% on the tree the bound was written on and 1.9% to 2.5% here, so four
    /// of those six seeds break a 2% bound on the tree that set it. Four percent is above
    /// every one of the twelve and still an order below anything a mechanism change would
    /// produce: a defence that stopped fielding linemen would not land at five.
    @Test("A dropback records one verdict on its pocket", .tags(.contract))
    func everyDropbackHasOnePocketVerdict() {
        var withoutARep = 0
        var total = 0
        for concept in Self.passConcepts {
            for play in resolved(concept, Self.neutral, count: 500) {
                total += 1
                let reps = play.decisions.filter { $0.kind == .blockResult }.count
                let allowed = play.decisions.filter { $0.kind == .pressureAllowed }.count
                let held = play.decisions.filter { $0.kind == .pressureHeld }.count
                if reps == 0 { withoutARep += 1 }
                #expect(
                    allowed + held == (reps > 0 ? 1 : 0),
                    "\(concept): \(reps) reps, \(allowed) pressures and \(held) held verdicts on one snap"
                )
                // A sack or a scramble is pressure by construction: the quarterback went
                // down or took off because somebody got there.
                let kind: PlayKind = play.outcome.kind
                if kind == .sack || kind == .scramble {
                    #expect(allowed == 1, "\(concept): a \(kind.rawValue) with a clean pocket")
                }
            }
        }
        #expect(
            withoutARep * 25 < total,
            "\(withoutARep) of \(total) dropbacks had no pass-rush rep at all")
    }
}
