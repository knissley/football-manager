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

    private func game(seed: UInt64 = 5) -> GameResult {
        TestWorld.game(seed: seed)
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
    @Test("More than a starting eleven appears over a game", .tags(.contract))
    func rotationReachesBackups() {
        let result = game()
        let appeared = Set(result.plays.flatMap { $0.outcome.participants.map(\.player) })
        #expect(appeared.count > 30, "only \(appeared.count) players took a snap")
    }

    // MARK: - Determinism

    @Test("The same seed resolves identically", .tags(.contract))
    func deterministic() {
        let first = game(seed: 12)
        let second = game(seed: 12)
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
