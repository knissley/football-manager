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
/// So this suite asserts the *join*, and it asserts it in two pieces, because the join
/// has two halves and only one of them is a question about games.
///
/// **Can the engine produce this at all** is settled by `TestWorld.coverageSweep()`, a
/// forced draw: every concept from its own spot, the backed-up spot that is the only
/// place a safety can happen, a man-coverage call, and punts at volume. The rarest
/// branches of the rarest draws are asserted one level lower still, against the draw
/// itself. None of it depends on which games came up.
///
/// **Does a real game reach it** is settled by a small sample of games, which is the only
/// thing a sample is good for and is kept for exactly that. What the sample may be asked
/// is bounded by what it is big enough to see, and the table in `sampled` says what that
/// is.
///
/// This suite used to ask both questions of one batch of games, and the batch grew from
/// forty to ninety to two hundred and forty chasing cases a sample cannot settle: a
/// blindside block turns up about once every thirty-six games, so ninety of them was a
/// coin flip that any change to the play mix re-tossed. Doubling a sample halves the
/// chance of missing a rare case; it never makes the answer certain, and it costs the
/// runtime forever.
///
/// It is deliberately two-directional throughout. A case the engine cannot yet produce
/// has to be named in the register below with a reason, and the moment one of those
/// *starts* being produced the test fails too, so the register cannot quietly rot into a
/// list of things that used to be true.
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

    /// The forced draw. Constructed once and shared, because every assertion below reads
    /// the same sweep.
    private static let forced: [TestWorld.Resolution] = TestWorld.coverageSweep()

    // MARK: - The smoke sample

    /// Which two clubs of the eight-team world play the *n*-th game.
    ///
    /// It used to be team 0 against team 1 in every one of them, which was fine while a
    /// seed re-rolled the whole league: ninety seeds meant ninety different grounds.
    /// Since [decision 215](../../../../docs/design-decisions.md) the franchises are
    /// curated, so that would be the same fixture in the same stadium over and over, and
    /// a sample of one building is thinner than it looks — a punt downed inside the ten
    /// is the sort of thing noise, altitude and a roof all reach. Walking the pairing
    /// visits all eight grounds, both domes among them.
    private static func pairing(_ seed: UInt64) -> (home: Int, away: Int) {
        let teams = UInt64(TestWorld.shape.totalTeams)
        // One ahead by at least one and at most `teams - 1`, so the away side is never
        // the home side and the fixture list is not eight repeats of the same rotation.
        let home = seed % teams
        return (Int(home), Int((home + 1 + (seed / teams) % (teams - 1)) % teams))
    }

    /// Twenty games, and what twenty games can be asked.
    ///
    /// This is the "does it happen in a real game" sample, and its size is the rate of
    /// the rarest thing asserted over it. Measured over 240 games of this same walk, per
    /// game: the kickoff 10.9, the pass 62.7, the rush 60.2, a play that was nothing but
    /// a flag 6.2, the punt 8.6, the try-kick 5.4, the field goal 3.4, the sack 4.2, the
    /// scramble 3.2, the kneel 2.5, the two-point try 0.54. Twenty games expect at least
    /// ten of the thinnest of those and miss one altogether about five times in a hundred
    /// thousand.
    ///
    /// Two kinds are left out of `everydayKinds` below because twenty games cannot carry
    /// them, and neither is re-admitted by making the sample bigger: the spike at 0.2 a
    /// game would want thirty-five, and a safety at 0.067 a game would want a hundred
    /// and four. Both are asserted against the sweep, where they are constructed rather
    /// than waited for.
    private static let sampled: [PlayRecord] = (UInt64(1)...20).flatMap { seed -> [PlayRecord] in
        let (home, away) = pairing(seed)
        return TestWorld.game(seed: seed, home: home, away: away).plays
    }

    /// The vocabulary a fixture between two ordinary clubs reaches several times over, so
    /// that a sample of twenty games is a fair instrument for it. Every rate in the list
    /// above is at least half an occurrence a game.
    private static let everydayKinds: [PlayKind] = [
        .rush, .pass, .sack, .scramble, .punt, .fieldGoal, .extraPoint, .twoPointConversion,
        .kickoff, .kneel, .penaltyOnly,
    ]

    @Test("A real game reaches the everyday vocabulary", .tags(.contract))
    func aGameReachesTheEverydayVocabulary() {
        let kinds = Set(Self.sampled.map(\.outcome.kind))
        for kind in Self.everydayKinds {
            #expect(kinds.contains(kind), "no snap in twenty games was a \(kind)")
        }
        // The other direction of the same claim: the sample is what the engine plays, so
        // a kind it should never call in a normal game must not be in it either.
        for (kind, reason) in Self.unreachableKinds {
            #expect(
                !kinds.contains(kind),
                "\(kind) is produced now — take it out of the register (was: \(reason))")
        }
    }

    // MARK: - What the engine can produce at all

    @Test("Every play kind the engine claims to model actually occurs", .tags(.contract))
    func everyKindIsReachable() {
        let seen = Set(Self.forced.map(\.outcome.kind))
        for kind in PlayKind.allCases where Self.unreachableKinds[kind] == nil {
            #expect(seen.contains(kind), "no cell of the sweep produced a \(kind)")
        }
    }

    @Test("Every play ending the engine claims to model actually occurs", .tags(.contract))
    func everyEndingIsReachable() {
        let seen = Set(Self.forced.map(\.outcome.endedIn))
        for ending in PlayEnding.allCases where Self.unreachableEndings[ending] == nil {
            #expect(seen.contains(ending), "no cell of the sweep ended in \(ending)")
        }
    }

    /// The other direction, and the one that keeps the register honest: when a milestone
    /// makes one of these reachable, this fails and the entry has to come out.
    ///
    /// Read over the sweep *and* the sample, because a register entry is a claim that
    /// nothing anywhere produces the case — and the sweep is the wider net of the two.
    @Test("The unreachable register describes the engine as it is", .tags(.contract))
    func registerIsCurrent() {
        let kinds = Set(Self.forced.map(\.outcome.kind))
            .union(Self.sampled.map(\.outcome.kind))
        let endings = Set(Self.forced.map(\.outcome.endedIn))
            .union(Self.sampled.map(\.outcome.endedIn))

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

    // MARK: - Fouls, at the draw that decides them

    /// Every foul in the book, asserted against the draw that produces it.
    ///
    /// `Foul` has thirty-four cases, every one with its yardage, its side and its
    /// automatic-first-down rule already settled in `FMCore`, and the engine threw twelve
    /// of them: there was no offensive pass interference in the league, nobody was ever
    /// called for lining up wrong, and a kicker could be run over with impunity. That is
    /// what this test was written for.
    ///
    /// It used to ask a batch of games, and could not honestly ask about half of them.
    /// The three downfield-block fouls share one draw the engine reaches about a tenth of
    /// a game; a fifth of those are the blindside block, so it lands once every thirty-six
    /// games and ninety games was a coin flip that a change to the play mix re-tossed. A
    /// register of "too rare to sample" grew up around that, and the entries in it were
    /// asserted against their own draw instead — which is what every foul is now, because
    /// the distinction was never about the foul. It was about the instrument.
    ///
    /// Each entry drives one of the resolver's penalty draws directly, many times, and
    /// names the branches of `Foul` that draw can return. Between them they account for
    /// all thirty-four: a foul in `Foul.allCases` that no entry claims fails below, so a
    /// new case cannot be added without saying which draw throws it.
    ///
    /// The counts are not arbitrary. `Penalties.preSnap` gets forty thousand because its
    /// thinnest branch is a substitution that did not beat the whistle — under a tenth of
    /// one per cent of snaps at a normal tempo, sixteen in forty thousand measured — and
    /// the rest get twenty thousand, where the thinnest branch anywhere is the chop block
    /// at thirteen and the low block at fourteen. Every branch is expected in double
    /// figures or close to it; none is a coin flip.
    @Test("Every foul the rules define actually gets called", .tags(.contract))
    func everyFoulIsCalled() {
        var drawn: Set<Foul> = []
        var claimed: Set<Foul> = []
        for (name, expected, draws) in Self.foulDraws {
            claimed.formUnion(expected)
            for foul in expected {
                #expect(draws.contains(foul), "\(name) never returned \(foul)")
            }
            drawn.formUnion(draws)
        }

        for foul in Foul.allCases {
            #expect(
                claimed.contains(foul),
                "no draw claims \(foul): a foul nothing in here throws is a foul nothing throws")
            #expect(drawn.contains(foul), "\(foul) is unreachable in every draw that can throw it")
        }
    }

    /// One row per draw: what it is, which fouls it is the only source of, and what it
    /// actually returned when it was run.
    ///
    /// Built once because `everyFoulIsCalled` is the only reader; it is here rather than
    /// inline so that the claim — *these draws between them are the whole of `Foul`* —
    /// reads as a table.
    private static let foulDraws: [(name: String, expected: [Foul], drawn: Set<Foul>)] = {
        let context = TestWorld.context(seed: 5)
        // The same snap with the interval already lost, which is what the rules layer
        // hands a resolver once nobody has stopped the clock (4-6-4).
        let lostThePlayClock = TestWorld.context(seed: 5, playClockExpired: true)
        var setUp = SplittableRandom(seed: 1)
        let midfield = Situation(
            quarter: 1, clockRemaining: 900, down: .first, distance: 10, ballOn: 50,
            possession: context.offense)
        let dropback = Lineup.onField(
            context, concept: .mediumPass, situation: midfield, random: &setUp)
        let kick = Lineup.onField(
            context, concept: .punt,
            situation: Situation(
                quarter: 1, clockRemaining: 900, down: .fourth, distance: 10, ballOn: 60,
                possession: context.offense),
            random: &setUp)

        func sweep(_ count: Int, _ draw: (inout SplittableRandom) -> PenaltyRecord?) -> Set<Foul> {
            var found: Set<Foul> = []
            var root = SplittableRandom(seed: 99)
            for index in 0..<count {
                var stream = root.split(UInt64(index))
                if let penalty = draw(&stream) { found.insert(penalty.foul) }
            }
            return found
        }

        // Hurry-up with a man in motion, because three of the procedural branches are
        // gated on exactly that: the tempo the defence cannot substitute against and the
        // shifting that is how a formation gets called wrong.
        let tempo = Calls(
            offense: OffensiveCall(concept: .mediumPass, tempo: .hurryUp, usedMotion: true),
            defense: .manFreeBlitz, offensiveCaller: .automatic, defensiveCaller: .automatic)

        return [
            (
                "Penalties.preSnap",
                [
                    .falseStart, .illegalFormation, .illegalMotion, .illegalShift,
                    .illegalSubstitution, .offside, .neutralZoneInfraction, .encroachment,
                    .tooManyMenOnField,
                ],
                sweep(40_000) { random in
                    Penalties.preSnap(
                        situation: midfield, calls: tempo, context: context, personnel: dropback,
                        random: &random)
                }
            ),
            (
                // Two steps, because the foul is two things: the interval beating the
                // offence, which `overrunsThePlayClock` draws, and the ball staying dead
                // for it, which `preSnap` reports off a context the rules layer has
                // already stamped (2025 rulebook, 4-6-4). The draw is run at its own rate
                // and the report is only asked where the draw fired, so the row measures
                // the path a game takes rather than the report on its own.
                "Penalties.overrunsThePlayClock, reported by Penalties.preSnap",
                [.delayOfGame],
                sweep(40_000) { random in
                    guard
                        Penalties.overrunsThePlayClock(
                            calls: tempo, context: context, random: &random)
                    else { return nil }
                    return Penalties.preSnap(
                        situation: midfield, calls: tempo, context: lostThePlayClock,
                        personnel: dropback, random: &random)
                }
            ),
            (
                "Penalties.whenBeatenBlocking",
                [.offensiveHolding, .illegalUseOfHands, .tripping, .chopBlock],
                sweep(20_000) { random in
                    Penalties.whenBeatenBlocking(
                        blocker: PlayerSlot(6), personnel: dropback, context: context,
                        random: &random)
                }
            ),
            (
                "Penalties.whenBeatenInCoverage",
                [.defensiveHolding, .illegalContact],
                sweep(20_000) { random in
                    Penalties.whenBeatenInCoverage(
                        defender: PlayerSlot(18), receiver: PlayerSlot(2),
                        separationCentimetres: 300, personnel: dropback, context: context,
                        random: &random)
                }
            ),
            (
                "Penalties.onTheThrow",
                [.defensivePassInterference, .offensivePassInterference],
                sweep(20_000) { random in
                    Penalties.onTheThrow(
                        defender: PlayerSlot(18), receiver: PlayerSlot(2),
                        separationCentimetres: 300, routeDepth: 14, catchPoint: 30,
                        personnel: dropback, context: context, random: &random)
                }
            ),
            (
                "Penalties.whenThrowingItAway",
                [.intentionalGrounding],
                sweep(20_000) { random in
                    Penalties.whenThrowingItAway(
                        passer: PlayerSlot(0), personnel: dropback, context: context,
                        random: &random)
                }
            ),
            (
                "Penalties.onContact, on the quarterback",
                [.roughingThePasser],
                sweep(20_000) { random in
                    Penalties.onContact(
                        tackler: PlayerSlot(11), isQuarterback: true, personnel: dropback,
                        context: context, random: &random)
                }
            ),
            (
                "Penalties.onContact, on a ball carrier",
                [.unnecessaryRoughness, .facemask, .illegalUseOfHelmet, .horseCollarTackle],
                sweep(20_000) { random in
                    Penalties.onContact(
                        tackler: PlayerSlot(11), isQuarterback: false, personnel: dropback,
                        context: context, random: &random)
                }
            ),
            (
                "Penalties.onDownfieldBlock",
                [.illegalBlockInTheBack, .illegalBlindsideBlock, .lowBlock],
                sweep(20_000) { random in
                    Penalties.onDownfieldBlock(
                        blockers: SlotLayout.catchPursuit.map(\.0), onOffense: false,
                        personnel: kick, context: context, random: &random)
                }
            ),
            (
                "Penalties.onLineRelease, on a screen",
                [.ineligibleReceiverDownfield, .illegalManDownfield],
                sweep(20_000) { random in
                    Penalties.onLineRelease(
                        blockers: dropback.blockers(includingEligibles: false), isScreen: true,
                        personnel: dropback, context: context, random: &random)
                }
            ),
            (
                "Penalties.onKick",
                [.roughingTheKicker, .runningIntoTheKicker],
                sweep(20_000) { random in
                    Penalties.onKick(
                        rushers: kick.front, personnel: kick, context: context, random: &random)
                }
            ),
            (
                "Penalties.afterThePlay, after a sack",
                [.unsportsmanlikeConduct, .taunting],
                sweep(20_000) { random in
                    Penalties.afterThePlay(
                        Outcome(kind: .sack, yards: -7, endedIn: .tackled), personnel: dropback,
                        context: context, random: &random)
                }
            ),
            (
                // The one foul the resolver draws itself rather than through `Penalties`:
                // a cover man touching a punt before the returner does. It has no
                // function to call, so the sweep's punt cell is its draw.
                "CrudeResolver, a cover man first to a punt",
                [.illegalTouching],
                Set(forced.flatMap(\.outcome.penalties).map(\.foul))
                    .intersection([.illegalTouching])
            ),
        ]
    }()

    /// A dead-ball foul is drawn after a play worth reacting to, and for a long time "a
    /// play" meant a run: `afterThePlay` was called from the run path alone, so no
    /// completion and no sack in the league ever drew a word afterwards. Two thirds of a
    /// team's snaps are dropbacks, so two thirds of the sport's shoving matches could not
    /// happen.
    ///
    /// **This one reads the standard corpus rather than the sweep or the walk**, and the
    /// reason is the run half. The draw is only offered a play worth reacting to — a sack,
    /// or a gain of fourteen — and a run goes fourteen about one time in eighty, so a
    /// conduct foul after a run is 0.2 a game: eight across the corpus's forty, measured,
    /// against thirty-three after a dropback. Twenty games of the walk above would expect
    /// four of them, which is the kind of margin that goes red on a nudge; forty thousand
    /// swept runs would cost several seconds to say the same thing. The corpus is forty
    /// games that six other suites have already paid for, so reading it here costs nothing
    /// and is the widest sample available.
    ///
    /// **Both floors are thin and the run half is the thinner.** Leave-one-game-out
    /// jackknife over the forty: eight after a run with a standard error of 2.86, and
    /// thirty-three after a dropback with 5.20 — margins of 2.8 and 6.3 errors. A change
    /// that halved the run half would leave `afterARun > 0` green about one time in fifty.
    @Test("Conduct fouls are drawn after passes and sacks, not only after runs", .tags(.contract))
    func conductFoulsFollowThePassingGame() {
        let conduct: Set<Foul> = [.unsportsmanlikeConduct, .taunting]
        var afterADropback = 0
        var afterARun = 0
        for play in TestWorld.corpus.flatMap(\.plays)
        where play.outcome.penalties.contains(where: { conduct.contains($0.foul) }) {
            let kind = play.outcome.kind
            if kind == .pass || kind == .sack { afterADropback += 1 }
            if kind == .rush { afterARun += 1 }
        }
        #expect(afterARun > 0, "no conduct foul followed a run in forty games")
        #expect(afterADropback > 0, "no conduct foul followed a pass or a sack in forty games")
    }

    // MARK: - Who is credited, and for what

    /// The mirror of an unreachable case: a credit handed to somebody who did not earn
    /// it. Coverage tests cannot see this one — the role *is* produced — so it needs its
    /// own assertion, and the shape that catches it is who the credits land on.
    ///
    /// Every run play used to credit all four defensive linemen with a tackle in the
    /// blocking loop, before anybody had touched the ball. The role looked healthy and
    /// the leaderboard was nonsense.
    ///
    /// This one stays on games rather than on the sweep, and it is the one test in here
    /// that should: it is a claim about *proportions* across a real play mix, and the
    /// sweep's mix is whatever its cells happen to add up to. Nothing here has to occur,
    /// so nothing here can be missed by a draw — every assertion is a share of a total
    /// that twenty games make large. Measured over 240 games of this walk, a game holds
    /// about 123 tackles, so twenty hold some two and a half thousand, and the tolerance
    /// below is a tenth of them.
    @Test("Tackles are spread across the defence, not banked by the front", .tags(.contract))
    func tacklesReachTheWholeDefense() {
        let tackles = Self.sampled
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
        let contactPlays = Self.sampled.filter { $0.outcome.kind.isScrimmagePlay }.count
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
    ///
    /// The long snapper is why this reads the sweep. He is credited only when he does
    /// something on a kick, which is ten times in two hundred and forty games — one game
    /// in twenty-four — so a sample that happened to contain one of them was reporting
    /// its luck. The sweep snaps four thousand punts and does not have to be lucky.
    @Test("Every position on a roster gets on the field", .tags(.contract))
    func everyPositionPlays() {
        // Nothing. Every position a team carries takes a snap: the specialists on kicks,
        // the fullback in a heavy grouping and on the coverage units, the third
        // linebacker when the defence is in base. It was three positions short of this
        // before the kicking game and personnel substitution were wired in.
        let unreachable: [Position: String] = [:]
        let seen = Set(Self.forced.flatMap(\.outcome.participants).map(\.position))
        for position in Position.allCases where unreachable[position] == nil {
            #expect(seen.contains(position), "no \(position) took a snap in the sweep")
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
        let seen = Set(Self.forced.flatMap(\.outcome.participants).map(\.role))
            .union(Self.sampled.flatMap(\.outcome.participants).map(\.role))
        for role in PlayRole.allCases where unreachable[role] == nil {
            #expect(seen.contains(role), "nobody in the sweep was credited as \(role)")
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
    /// Measured with every register empty: the engine reached 3 of 5 throw decisions,
    /// 2 of 5 tackle results, 2 of 5 block results and 2 of 6 coverage techniques, and
    /// every catch result and ball placement. The issue that closes each gap is the one
    /// named beside it, and deleting an entry is how it reports that it landed — the
    /// checkdown and the throwaway came off the register with C3 (#44), which is where
    /// the quarterback learned to take one and to throw the other.
    static let unreachableThrowDecisions: [ThrowDecision: String] = [:]
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

    /// Every value of one detail enum the sweep's decision points carry, read through the
    /// typed accessor so a byte belonging to another kind is never reinterpreted.
    private static func details<Detail: Hashable>(
        _ read: (DecisionPoint) -> Detail?
    ) -> Set<Detail> {
        Set(forced.flatMap(\.decisions).compactMap(read))
    }

    private func checkRegister<Detail: Hashable & CaseIterable>(
        _ name: String, seen: Set<Detail>, register: [Detail: String]
    ) {
        for detail in Detail.allCases where register[detail] == nil {
            #expect(seen.contains(detail), "no decision in the sweep carried \(name).\(detail)")
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
