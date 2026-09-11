import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// Which parts of the event vocabulary the engine can actually reach.
///
/// `PlayKind.scramble` sat in `FMCore` for a while with nothing able to produce it: the
/// case existed, the box score knew how to count it, and no snap ever was one. A unit
/// test cannot catch that, because every unit involved is correct on its own — the type
/// is fine, the resolver is fine, and the gap is that they never meet.
///
/// So this suite asserts the *join*: sim a batch of games and check what came out
/// against the vocabulary that exists. It is deliberately two-directional. A case the
/// engine cannot yet produce has to be named in the register below with a reason, and
/// the moment one of those *starts* being produced the test fails too, so the register
/// cannot quietly rot into a list of things that used to be true.
///
/// See `docs/roadmap.md` — "Audit owed at the end of M1".
@Suite("Vocabulary coverage")
struct VocabularyCoverageTests {

    /// Cases the crude engine is knowingly unable to produce, and why.
    ///
    /// Every entry is a real gap, not an excuse: each names the milestone that closes
    /// it. Deleting an entry is how a milestone reports that it landed.
    static let unreachableKinds: [PlayKind: String] = [:]

    static let unreachableEndings: [PlayEnding: String] = [
        .blocked: "M3 — no rush lane exists on a kick, so nothing can get a hand up."
    ]

    /// Which two clubs of the eight-team world play the *n*-th game.
    ///
    /// It used to be team 0 against team 1 in every one of the ninety, which was fine
    /// while a seed re-rolled the whole league: ninety seeds meant ninety different
    /// grounds. Since [decision 215](../../../../docs/design-decisions.md) the
    /// franchises are curated, so that would be the same fixture in the same stadium
    /// ninety times over, and a sample of one building is thinner than it looks — a punt
    /// downed inside the ten is the sort of thing noise, altitude and a roof all reach.
    /// Walking the pairing visits all eight grounds, both domes among them.
    private static func pairing(_ seed: UInt64) -> (home: Int, away: Int) {
        let teams = UInt64(TestWorld.shape.totalTeams)
        // One ahead by at least one and at most `teams - 1`, so the away side is never
        // the home side and the fixture list is not eight repeats of the same rotation.
        let home = seed % teams
        return (Int(home), Int((home + 1 + (seed / teams) % (teams - 1)) % teams))
    }

    private static func result(seed: UInt64) -> GameResult {
        let (home, away) = pairing(seed)
        return TestWorld.game(seed: seed, home: home, away: away)
    }

    /// Enough games that a rare-but-reachable case is not a coin flip.
    ///
    /// A safety happens about three times in a hundred team-games, so forty games left
    /// roughly a one-in-eleven chance of seeing none — and this suite duly went red for
    /// it once field position improved enough to make being backed up rare. Simulated
    /// once and shared, because six assertions over one stream costs what one used to.
    ///
    /// Ninety was not comfortable for the rarest cases in here, and two of them are
    /// rarer than illegal touching. Illegal touching needs a punt that is downed or run
    /// out of bounds — about 1.1 a game — and then a 1.8% roll on top, so ninety games
    /// expect two of them and see none about one time in six.
    ///
    /// The blindside block is thinner still. It is one fifth of the downfield-block
    /// draw, which is itself about a 1.4% roll on a run that got into space or a kick
    /// that got returned: measured over 400 games of this fixture walk, sixty-one
    /// downfield-block fouls, of which eleven were blindside blocks — about one every
    /// thirty-six games. Ninety of them is a coin flip that any change to the play mix
    /// re-tosses, and this suite duly went red on it. Two hundred and forty is where the
    /// expected count is comfortably above one. (The eleven were not evenly spread
    /// across the four hundred, which nothing here explains and which is worth a look of
    /// its own; a dedicated fixture that forces the draw would settle it for good, and
    /// is what this sample should eventually be replaced by for the rare cases.)
    private static let sampled: [PlayRecord] = (UInt64(1)...240).flatMap { result(seed: $0).plays }

    private static func plays() -> [PlayRecord] { sampled }

    @Test("Every play kind the engine claims to model actually occurs", .tags(.contract))
    func everyKindIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.kind))
        for kind in PlayKind.allCases where Self.unreachableKinds[kind] == nil {
            #expect(seen.contains(kind), "no snap in ninety games was a \(kind)")
        }
    }

    @Test("Every play ending the engine claims to model actually occurs", .tags(.contract))
    func everyEndingIsReachable() {
        let seen = Set(Self.plays().map(\.outcome.endedIn))
        for ending in PlayEnding.allCases where Self.unreachableEndings[ending] == nil {
            #expect(seen.contains(ending), "no play in ninety games ended in \(ending)")
        }
    }

    /// The other direction, and the one that keeps the register honest: when a milestone
    /// makes one of these reachable, this fails and the entry has to come out.
    @Test("The unreachable register describes the engine as it is", .tags(.contract))
    func registerIsCurrent() {
        let plays = Self.plays()
        let kinds = Set(plays.map(\.outcome.kind))
        let endings = Set(plays.map(\.outcome.endedIn))

        for (kind, reason) in Self.unreachableKinds {
            #expect(
                !kinds.contains(kind),
                "\(kind) is produced now — take it out of the register (was: \(reason))")
        }
        for (ending, reason) in Self.unreachableEndings {
            #expect(
                !endings.contains(ending),
                "\(ending) is produced now — take it out of the register (was: \(reason))")
        }
    }

    /// Fouls that are reachable but too rare for a ninety-game sample to decide, and are
    /// therefore asserted against the draw that produces them instead.
    ///
    /// **Measured, not assumed.** The three downfield-block fouls share one draw and the
    /// engine reaches it about a tenth of a game: twelve times in ninety games, nine of
    /// them the block in the back. The other two are a fifth and a seventh of that draw,
    /// so whether either turns up is close to a coin flip — and over 260 games of a later
    /// sample, twenty-one draws produced neither. A sample cannot settle a case at that
    /// rate; enlarging it only moves the coin flip.
    ///
    /// So the join this suite exists to check is still checked here for
    /// `.illegalBlockInTheBack`, which shares the draw, comes from real games and appears;
    /// and the two rarer branches of the same draw are checked where the branch is taken,
    /// in `everyBranchOfTheRareDrawsIsReachable`. What is left unasserted is only that a
    /// game *reaches* that draw, and the block in the back asserts exactly that.
    ///
    /// **How rare the draw is, is a calibration matter and not this suite's.** A tenth of
    /// a game is well under the sport's rate for these fouls; the retune owns it
    /// ([#49](https://github.com/knissley/football-manager/issues/49)).
    static let tooRareToSample: [Foul: String] = [
        .illegalBlindsideBlock: "a fifth of the downfield-block draw, which fires 0.13 a game",
        .lowBlock: "a seventh of the same draw",
    ]

    /// Fouls are the same question as play kinds, and the answer was worse: `Foul` has
    /// thirty-three cases, every one of them with its yardage, its side and its
    /// automatic-first-down rule already settled in `FMCore`, and the engine threw twelve
    /// of them. There was no offensive pass interference in the league, nobody was ever
    /// called for lining up wrong, and a kicker could be run over with impunity.
    @Test("Every foul the rules define actually gets called", .tags(.contract))
    func everyFoulIsCalled() {
        // Nothing. Every foul in the book gets thrown.
        let unreachable: [Foul: String] = [:]

        let called = Set(Self.plays().flatMap(\.outcome.penalties).map(\.foul))
        for foul in Foul.allCases
        where unreachable[foul] == nil && Self.tooRareToSample[foul] == nil {
            #expect(called.contains(foul), "\(foul) was never called in ninety games")
        }
        for (foul, reason) in unreachable {
            #expect(!called.contains(foul), "\(foul) is called now (was: \(reason))")
        }
    }

    /// The other half of `tooRareToSample`: the branches a ninety-game sample cannot
    /// decide, taken against the draw that decides them.
    ///
    /// It is the same claim — the engine can produce this foul — asserted where it is
    /// settled rather than where it is diluted. A branch that stopped being reachable
    /// fails here immediately instead of after a resample.
    @Test("Every branch of a draw too rare to sample is still reachable", .tags(.contract))
    func everyBranchOfTheRareDrawsIsReachable() {
        let context = TestWorld.context(seed: 5)
        var setUp = SplittableRandom(seed: 1)
        let personnel = Lineup.onField(
            context, concept: .punt,
            situation: Situation(
                quarter: 1, clockRemaining: 900, down: .fourth, distance: 10, ballOn: 60,
                possession: context.offense),
            random: &setUp)

        var drawn: Set<Foul> = []
        var root = SplittableRandom(seed: 99)
        for index in 0..<20_000 {
            var stream = root.split(UInt64(index))
            if let foul = Penalties.onDownfieldBlock(
                blockers: SlotLayout.catchPursuit.map(\.0), onOffense: false,
                personnel: personnel, context: context, random: &stream)
            {
                drawn.insert(foul.foul)
            }
        }

        for (foul, reason) in Self.tooRareToSample {
            #expect(drawn.contains(foul), "\(foul) is unreachable in its own draw (\(reason))")
        }
        #expect(
            drawn.contains(.illegalBlockInTheBack),
            "the draw these share no longer produces the one the game sample sees")
    }

    /// A dead-ball foul is drawn after a play worth reacting to, and for a long time "a
    /// play" meant a run: `afterThePlay` was called from the run path alone, so no
    /// completion and no sack in the league ever drew a word afterwards. Two thirds of a
    /// team's snaps are dropbacks, so two thirds of the sport's shoving matches could not
    /// happen.
    @Test("Conduct fouls are drawn after passes and sacks, not only after runs", .tags(.contract))
    func conductFoulsFollowThePassingGame() {
        let conduct: Set<Foul> = [.unsportsmanlikeConduct, .taunting]
        var afterADropback = 0
        var afterARun = 0
        for play in Self.plays()
        where play.outcome.penalties.contains(where: { conduct.contains($0.foul) }) {
            if play.outcome.kind == .pass || play.outcome.kind == .sack { afterADropback += 1 }
            if play.outcome.kind == .rush { afterARun += 1 }
        }
        #expect(afterARun > 0, "no conduct foul followed a run in ninety games")
        #expect(afterADropback > 0, "no conduct foul followed a pass or a sack in ninety games")
    }

    /// The mirror of an unreachable case: a credit handed to somebody who did not earn
    /// it. Coverage tests cannot see this one — the role *is* produced — so it needs its
    /// own assertion, and the shape that catches it is who the credits land on.
    ///
    /// Every run play used to credit all four defensive linemen with a tackle in the
    /// blocking loop, before anybody had touched the ball. The role looked healthy and
    /// the leaderboard was nonsense.
    @Test("Tackles are spread across the defence, not banked by the front", .tags(.contract))
    func tacklesReachTheWholeDefense() {
        let tackles = Self.plays()
            .flatMap(\.outcome.participants)
            .filter { $0.role == .tackler }

        var byGroup: [PositionGroup: Int] = [:]
        for tackle in tackles { byGroup[tackle.position.group, default: 0] += 1 }
        let total = tackles.count

        #expect(total > 0)
        let front = (byGroup[.edge] ?? 0) + (byGroup[.defensiveInterior] ?? 0)
        let secondLevel = byGroup[.linebacker] ?? 0
        let secondary = (byGroup[.cornerback] ?? 0) + (byGroup[.safety] ?? 0)
        let levels = [
            ("front", front), ("linebackers", secondLevel), ("secondary", secondary),
        ]
        for (name, count) in levels {
            #expect(
                Double(count) / Double(total) > 0.1,
                "the \(name) made \(count) of \(total) tackles")
        }

        // Roughly one tackle per snap that ends in contact. Well over that means
        // somebody is being credited for being on the field.
        let contactPlays = Self.plays().filter { $0.outcome.kind.isScrimmagePlay }.count
        #expect(
            Double(total) / Double(contactPlays) < 1.1,
            "\(total) tackles across \(contactPlays) plays from scrimmage")
    }

    /// And the same question one level down: a position that exists, is generated onto
    /// every roster, and never takes a snap.
    ///
    /// This is how the kicking game was found out. Every team had a kicker, a punter and
    /// a long snapper, and none of them had ever been on the field — the resolver read
    /// kick accuracy and punt power off the *quarterback's* slot, so a team's kicker had
    /// no bearing on whether it made kicks.
    @Test("Every position on a roster gets on the field", .tags(.contract))
    func everyPositionPlays() {
        // Nothing. Every position a team carries takes a snap: the specialists on kicks,
        // the fullback in a heavy grouping and on the coverage units, the third
        // linebacker when the defence is in base. It was three positions short of this
        // before the kicking game and personnel substitution were wired in.
        let unreachable: [Position: String] = [:]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.position))
        for position in Position.allCases where unreachable[position] == nil {
            #expect(seen.contains(position), "no \(position) took a snap in ninety games")
        }
        for (position, reason) in unreachable {
            #expect(
                !seen.contains(position),
                "\(position) plays now — take it out of the register (was: \(reason))")
        }
    }

    /// Roles are the same shape of gap: a role nothing ever credits is a hole in every
    /// query built on top of it. `.tackler` went missing on sacks exactly this way.
    @Test("Every play role gets credited to somebody", .tags(.contract))
    func everyRoleIsCredited() {
        let unreachable: [PlayRole: String] = [
            .assistTackler: "M5 — the crude resolver credits a single tackler."
        ]
        let seen = Set(Self.plays().flatMap(\.outcome.participants).map(\.role))
        for role in PlayRole.allCases where unreachable[role] == nil {
            #expect(seen.contains(role), "nobody in ninety games was credited as \(role)")
        }
        for (role, reason) in unreachable {
            #expect(
                !seen.contains(role),
                "\(role) is credited now — take it out of the register (was: \(reason))")
        }
    }

    // MARK: - The detail behind a decision point

    /// The enums behind `DecisionPoint.detail`, which are the cases play-record.md says
    /// the spatial engine must emit with the same meaning — so a case the crude engine
    /// cannot reach is a case nothing downstream has ever seen. Each register names the
    /// cases the engine cannot produce today and the issue that will make them reachable,
    /// and each test reads both directions: an unregistered case never seen fails, and a
    /// registered case that turns up fails too, so the register cannot rot.
    ///
    /// Measured with every register empty: the engine reaches 3 of 5 throw decisions,
    /// 2 of 5 tackle results, 2 of 5 block results and 2 of 6 coverage techniques, and
    /// every catch result and ball placement. The issue that closes each gap is the one
    /// named beside it, and deleting an entry is how it reports that it landed.
    static let unreachableThrowDecisions: [ThrowDecision: String] = [
        .checkdown:
            "C3 (#44) — the quarterback throws to the best-separated read on the field; he never takes the checkdown.",
        .throwaway:
            "C3 (#44) — pressure becomes a sack, a scramble or a throw; nothing is ever thrown away.",
    ]
    static let unreachableCatchResults: [CatchResult: String] = [:]
    static let unreachableTackleResults: [TackleResult: String] = [
        .assisted: "C4 (#39) — the crude resolver credits a single tackler, so nobody assists.",
        .missed:
            "C4 (#39) — a tackle is made or broken; a defender never misses a man who was not carrying the ball past him.",
        .forcedFumble:
            "C4 (#39) — a fumble is drawn in Fumbles after the tackle decision is written, so the decision never says it was forced.",
    ]
    static let unreachableBlockResults: [BlockResult: String] = [
        .stalemate: "C4 (#39) — a block is won or lost; there is no stalemate.",
        .pancake: "C4 (#39) — a block is won or lost; nobody is put on the ground.",
        .whiffed: "C4 (#39) — a block is won or lost; nobody misses his man entirely.",
    ]
    static let unreachableCoverageTechniques: [CoverageTechnique: String] = [
        .press: "C4 (#39) — man coverage is recorded as off-man whatever the call's alignment.",
        .zoneFlat: "C4 (#39) — zone coverage is recorded as deep zone whatever the drop.",
        .bracket: "C4 (#39) — every receiver is covered by one defender.",
        .spy: "C4 (#39) — nobody is ever assigned to the quarterback.",
    ]
    static let unreachableBallPlacements: [BallPlacement: String] = [:]

    /// Every value of one detail enum the sample's decision points carry, read through
    /// the typed accessor so a byte belonging to another kind is never reinterpreted.
    private static func details<Detail: Hashable>(
        _ read: (DecisionPoint) -> Detail?
    ) -> Set<Detail> {
        Set(plays().flatMap(\.decisions).compactMap(read))
    }

    private func checkRegister<Detail: Hashable & CaseIterable>(
        _ name: String, seen: Set<Detail>, register: [Detail: String]
    ) {
        for detail in Detail.allCases where register[detail] == nil {
            #expect(seen.contains(detail), "no decision in ninety games carried \(name).\(detail)")
        }
        for (detail, reason) in register {
            #expect(
                !seen.contains(detail),
                "\(name).\(detail) is produced now — take it out of the register (was: \(reason))")
        }
    }

    @Test("Every throw decision is reached, and the register says which are not", .tags(.contract))
    func everyThrowDecisionIsReachable() {
        checkRegister(
            "ThrowDecision", seen: Self.details(\.throwDecisionValue),
            register: Self.unreachableThrowDecisions)
    }

    @Test("Every catch result is reached, and the register says which are not", .tags(.contract))
    func everyCatchResultIsReachable() {
        checkRegister(
            "CatchResult", seen: Self.details(\.catchResult),
            register: Self.unreachableCatchResults)
    }

    @Test("Every tackle result is reached, and the register says which are not", .tags(.contract))
    func everyTackleResultIsReachable() {
        checkRegister(
            "TackleResult", seen: Self.details(\.tackleResult),
            register: Self.unreachableTackleResults)
    }

    @Test("Every block result is reached, and the register says which are not", .tags(.contract))
    func everyBlockResultIsReachable() {
        checkRegister(
            "BlockResult", seen: Self.details(\.blockResultValue),
            register: Self.unreachableBlockResults)
    }

    @Test(
        "Every coverage technique is reached, and the register says which are not",
        .tags(.contract))
    func everyCoverageTechniqueIsReachable() {
        checkRegister(
            "CoverageTechnique", seen: Self.details(\.coverageTechnique),
            register: Self.unreachableCoverageTechniques)
    }

    @Test("Every ball placement is reached, and the register says which are not", .tags(.contract))
    func everyBallPlacementIsReachable() {
        checkRegister(
            "BallPlacement", seen: Self.details(\.ballPlacement),
            register: Self.unreachableBallPlacements)
    }
}
