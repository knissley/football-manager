import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// Who a team sends out, and whether it makes any difference.
///
/// `PersonnelGroup` and `DefensivePackage` were complete, tested `FMCore` types that
/// nothing in the engine ever set. Every snap of every game was eleven personnel against
/// base — except that the "base" layout had two linebackers and three corners, which is
/// nickel. So the sport's most common substitution never happened, a goal-line stand had
/// five defensive backs on it, and third and fifteen had no extra one.
@Suite("Lineup")
struct PersonnelTests {

    private func world() -> (rotation: [DepthChart.Rotation], players: [PlayerID: Player]) {
        let (_, chart, players) = TestWorld.team(seed: 12)
        return (chart.rotation(), players)
    }

    private func onField(
        _ group: PersonnelGroup, _ package: DefensivePackage, seed: UInt64 = 5
    ) -> Lineup {
        let (rotation, players) = world()
        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)
        let situation = Situation(
            quarter: 1, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
            possession: TeamID(1), offensePersonnel: group, defensePackage: package)
        var random = SplittableRandom(seed: seed)
        return Lineup.onField(
            context, concept: .insideRun, situation: situation, random: &random)
    }

    /// Eleven men, whoever they are. A grouping that fields ten is a bug that shows up as
    /// an unblocked rusher rather than as an error.
    @Test(
        "Every grouping and package fields eleven", .tags(.contract),
        arguments: [
            PersonnelGroup.eleven, .twelve, .thirteen, .twentyOne, .twentyTwo, .ten, .empty,
        ])
    func groupingsFieldEleven(group: PersonnelGroup) {
        for package in DefensivePackage.allCases {
            let personnel = onField(group, package)
            let offense = personnel.occupied.filter(\.isOffense).count
            let defense = personnel.occupied.filter { !$0.isOffense }.count
            #expect(offense == 11, "\(group.code) personnel fielded \(offense)")
            #expect(defense == 11, "\(package) fielded \(defense)")
        }
    }

    /// The grouping decides what the offence can do: an extra tight end is an extra
    /// blocker, and an empty set is five men running routes.
    @Test("A heavy grouping blocks more and an empty one runs more routes", .tags(.unit))
    func groupingChangesTheOffense() {
        let heavy = onField(.twentyTwo, .base)
        let spread = onField(.empty, .dime)
        let normal = onField(.eleven, .nickel)

        #expect(heavy.blockers(includingEligibles: true).count == 8, "two tight ends and a back")
        #expect(normal.blockers(includingEligibles: true).count == 6)
        #expect(spread.blockers(includingEligibles: true).count == 5, "nobody stays in")

        // Every grouping has five eligibles; what changes is who they are. An empty set
        // has five receivers running routes, a heavy one has a receiver and a crowd of
        // blockers who happen to be eligible.
        func wideReceivers(_ lineup: Lineup) -> Int {
            lineup.routeRunners().filter { lineup.position(at: $0) == .wideReceiver }.count
        }
        #expect(wideReceivers(spread) == 5)
        #expect(wideReceivers(normal) == 3)
        #expect(wideReceivers(heavy) == 1)
    }

    /// And the package decides what the defence can do. The box count is the number a run
    /// is measured against, and the coverage count the number a pass is.
    @Test("The package trades the box for the secondary", .tags(.unit))
    func packageTradesBoxForCoverage() {
        let base = onField(.twelve, .base)
        let nickel = onField(.eleven, .nickel)
        let dime = onField(.ten, .dime)
        let goalLine = onField(.twentyTwo, .goalLine)

        #expect(base.boxCount == 7)
        #expect(nickel.boxCount == 6)
        #expect(dime.boxCount == 5)
        #expect(goalLine.boxCount == 8)

        // Seven men are off the ball in all of them — a package does not change how many
        // are in coverage, it changes *who*. Trading a linebacker for a defensive back is
        // the whole substitution.
        func corners(_ lineup: Lineup) -> Int {
            lineup.coverageDefenders.filter { lineup.position(at: $0) == .cornerback }.count
        }
        #expect(corners(dime) > corners(nickel))
        #expect(corners(nickel) > corners(base))
    }

    /// Corners cover receivers. The old fixed coverage list put whoever sat in slot 17 on
    /// the number one receiver, which in a base defence is a linebacker.
    @Test("The best cover men take the receivers", .tags(.unit))
    func cornersCoverFirst() {
        for package in [DefensivePackage.base, .nickel, .dime] {
            let personnel = onField(.eleven, package)
            let first = personnel.coverageDefenders.first
            #expect(
                personnel.position(at: first ?? .none) == .cornerback,
                "\(package) put a \(personnel.position(at: first ?? .none).map { "\($0)" } ?? "nobody") on the number one"
            )
        }
    }

    /// The mechanism, held still. Across a whole season this is unreadable — heavy
    /// personnel is called in short yardage where a carry is short by construction — so
    /// it is asserted on one situation with only the package changing.
    @Test("Running into a stacked box gains less than running into a light one", .tags(.unit))
    func theCountDecidesTheRun() {
        func averageGain(against package: DefensivePackage) -> Double {
            let (rotation, players) = world()
            let context = PlayContext(
                offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
                defenseRotation: rotation, players: players,
                offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
                defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
                rules: .standard)
            let situation = Situation(
                quarter: 1, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
                possession: TeamID(1), offensePersonnel: .eleven, defensePackage: package)
            let calls = Calls(
                offense: OffensiveCall(concept: .insideRun), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic)

            var random = SplittableRandom(seed: 88)
            var total = 0
            let carries = 4_000
            for _ in 0..<carries {
                let onField = Lineup.onField(
                    context, concept: .insideRun, situation: situation, random: &random)
                let resolved = CrudeResolver().resolve(
                    situation: situation, calls: calls, onField: onField, context: context,
                    random: &random)
                total += Int(resolved.outcome.yards)
            }
            return Double(total) / Double(carries)
        }

        let againstDime = averageGain(against: .dime)
        let againstNickel = averageGain(against: .nickel)
        let againstBase = averageGain(against: .base)
        let againstGoalLine = averageGain(against: .goalLine)

        #expect(
            againstDime > againstNickel,
            "five in the box: \(againstDime) against nickel's \(againstNickel)")
        #expect(
            againstNickel > againstBase,
            "six in the box: \(againstNickel) against base's \(againstBase)")
        #expect(
            againstBase > againstGoalLine,
            "seven in the box: \(againstBase) against the goal line's \(againstGoalLine)")
    }

    // MARK: - Rotation follows the sport

    /// Forty games, the way the probe counts them: every pairing of one world's eight
    /// clubs, over five seeds.
    private static func fortyGames() -> [GameResult] {
        (1...5).flatMap { seed in
            (0..<8).map { home in
                TestWorld.game(
                    seed: UInt64(seed), game: GameID(UInt64(home + 1)), home: home,
                    away: (home + 1) % 8)
            }
        }
    }

    /// A quarterback leaves the field because he is hurt, and for no other reason.
    ///
    /// Drawing every slot against a snap share on every snap made the backup's 2% share a
    /// 2% chance *per snap*: he took a dropback mid-drive, gave it back on the next one,
    /// and the starter's day was interrupted more than a hundred times in forty games
    /// with nothing having happened to him.
    @Test(
        "The quarterback does not change between dropbacks unless he was hurt",
        .tags(.contract))
    func quarterbackDoesNotRotate() {
        var changes = 0
        for result in Self.fortyGames() {
            let hurt = Set(result.injuries.filter(\.leavesTheGame).map(\.player))
            var lastTaker: [TeamID: PlayerID] = [:]
            for play in result.plays {
                let kind = play.outcome.kind
                guard kind.isDropback || kind == .kneel || kind == .spike else { continue }
                guard
                    let taker = play.outcome.participants.first(where: {
                        $0.slot == SlotLayout.quarterback
                    })
                else { continue }
                let team = play.situation.possession
                defer { lastTaker[team] = taker.player }
                guard let previous = lastTaker[team], previous != taker.player else { continue }
                guard !hurt.contains(previous), !hurt.contains(taker.player) else { continue }
                changes += 1
            }
        }
        #expect(changes == 0, "\(changes) quarterback changes with nobody hurt")
    }

    /// Lineups drawn from one club's chart, with whoever is named unavailable removed.
    private func lineups(
        _ count: Int, group: PersonnelGroup = .eleven, package: DefensivePackage = .nickel,
        unavailable: Set<PlayerID> = [], seed: UInt64 = 5
    ) -> [Lineup] {
        let (_, chart, players) = TestWorld.team(seed: 12)
        let rotation = chart.rotation(unavailable: unavailable)
        let context = PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: rotation,
            defenseRotation: rotation, players: players,
            offenseScheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder),
            defenseScheme: TeamScheme(offense: .airRaid, defense: .nickelMatch),
            rules: .standard)
        let situation = Situation(
            quarter: 1, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
            possession: TeamID(1), offensePersonnel: group, defensePackage: package)
        var random = SplittableRandom(seed: seed)
        return (0..<count).map { _ in
            Lineup.onField(context, concept: .insideRun, situation: situation, random: &random)
        }
    }

    /// The five line spots, the quarterback and the specialists are one man's job until he
    /// cannot do it. The groups the sport rotates go on rotating.
    @Test("A starter-only position plays its starter, and next man up when he is out", .tags(.unit))
    func starterOnlyPositionsDoNotRotate() {
        let (_, chart, _) = TestWorld.team(seed: 12)
        let leftTackle = chart.starter(at: .leftTackle)
        let quarterback = chart.starter(at: .quarterback)
        let drawn = lineups(400)

        #expect(
            drawn.allSatisfy { $0[PlayerSlot(6)] == leftTackle },
            "the left tackle came off the field")
        #expect(
            drawn.allSatisfy { $0[SlotLayout.quarterback] == quarterback },
            "the quarterback came off the field")

        // Next man up, and nobody else: the share behind a starter-only spot says who
        // inherits it, not how often he plays.
        let backup = chart[.leftTackle].dropFirst().first
        let depleted = lineups(200, unavailable: Set([leftTackle].compactMap { $0 }))
        #expect(
            depleted.allSatisfy { $0[PlayerSlot(6)] == backup },
            "the backup left tackle did not inherit every snap")

        // And the groups that do rotate still do, which is the other half of the claim.
        #expect(Set(drawn.compactMap { $0[PlayerSlot(11)] }).count > 1, "the edge stopped rotating")
        #expect(Set(drawn.compactMap { $0[PlayerSlot(1)] }).count > 1, "the backs stopped rotating")
    }

    // MARK: - The mix is the sport's

    /// The corpus, paired with the roster table its snap counts have to be read through.
    /// Forty games is the shared corpus, whose size is derived where it is defined; a
    /// package share is a property of every snap, so the evidence here is about five
    /// thousand of them rather than forty.
    private static let sampled: [(result: GameResult, players: [PlayerID: Player])] =
        (UInt64(1)...40).map { seed in
            (
                TestWorld.corpus[Int(seed) - 1],
                TestWorld.setup(seed: seed, game: GameID(seed)).players
            )
        }

    /// Snaps from scrimmage, which is what every participation row is measured over.
    private static var scrimmage: [PlayRecord] {
        sampled.flatMap { $0.result.plays.filter { $0.outcome.kind.isScrimmagePlay } }
    }

    /// Five defensive backs, not four, is what a defence lines up in.
    ///
    /// `row:packageNickel` puts five defensive backs on 61.6–69.2% of snaps and
    /// `row:packageBase` four on 20.2–25.0% (S2, the source's participation feed, 2023–24;
    /// `docs/reference/calibration-sources.md`). The two bands do not overlap and nickel's
    /// floor is above half of all snaps. Two things follow from that pair *whatever the
    /// rate turns out to be inside those bands*, and those two are what this asserts:
    /// nickel is most of the snaps played, and it outnumbers the four-back front by a
    /// distance. Nickel is the defence a team plays; base is the substitution.
    ///
    /// **The precise rate is not asserted here, and deliberately.** It is graded by
    /// `row:packageNickel` over four hundred games at two harness seeds, and CLAUDE.md is
    /// explicit that a harness band with a sourced season *is* the football test for a
    /// rate. This suite cannot make that claim as well, and used to try: it asserted
    /// `61.6 ≤ share ≤ 69.2` over the forty-game corpus, which is a band the corpus cannot
    /// resolve. Measured on that corpus, the between-game standard deviation of the nickel
    /// share is 3.86 points, so the mean of forty carries a standard error of **0.61**; the
    /// engine has read 68.85% and 69.36% either side of the same edit, which is 0.35 under
    /// the ceiling and 0.16 over it. Both readings are inside the instrument's own noise, so
    /// the old assertion passed or failed on which forty games it drew rather than on where
    /// the engine was. It is rewritten rather than deleted, and rewritten *upward* in what
    /// it can support: the claims below are ones the sample can actually make.
    ///
    /// **The bounds, and why they are these.** Both are implied by the two sourced bands
    /// with room left over, and both sit many standard errors from anything the corpus
    /// produces — which is the test the old bound failed.
    ///
    /// - *Nickel is most of the snaps.* The source's floor for it is 61.6%, so a half is
    ///   11.6 points inside the sourced claim. The corpus reads 69.36%, which is 31 standard
    ///   errors clear of the bound, and its **worst single game** is 60.3% — no game in
    ///   forty comes near it.
    /// - *Nickel outnumbers base by twenty-five points.* The bands do not overlap, so the
    ///   narrowest gap the source permits is 61.6 − 25.0 = 36.6 points; twenty-five is
    ///   11.6 inside that. The gap's own between-game standard deviation is 6.70, so the
    ///   mean of forty carries a standard error of 1.06, and the corpus reads 46.70 — 20
    ///   standard errors clear. Its worst single game is 33.1 points.
    ///
    /// Neither bound pins the engine's level: both would survive the rate moving anywhere
    /// inside its sourced band, which is what leaves `row:packageNickel` free to set it.
    /// What they do not survive is the defence going back to answering three receivers from
    /// its four-back front, which is the shape this exists to keep out.
    ///
    /// Base's own band is still not asserted. The engine is above it, and what is left of
    /// that gap after the package rule is a calibration residual rather than a rule — it is
    /// recorded on the retune issue, with the mechanism, rather than pinned by a test that
    /// would have to be wrong to pass.
    @Test(
        "Nickel is most snaps and outnumbers base by a distance (row:packageNickel, row:packageBase, S2 2023-24)",
        .tags(.football))
    func nickelIsTheDefenceATeamPlays() {
        let snaps = Self.scrimmage
        let nickel = Double(snaps.filter { $0.situation.defensePackage == .nickel }.count)
        let base = Double(snaps.filter { $0.situation.defensePackage == .base }.count)
        let nickelShare = nickel / Double(snaps.count) * 100
        let baseShare = base / Double(snaps.count) * 100
        #expect(
            nickelShare > 50,
            "nickel on \(nickelShare)% of \(snaps.count) snaps: it is not the defence being played"
        )
        #expect(
            nickelShare - baseShare > 25,
            "nickel on \(nickelShare)% of \(snaps.count) snaps and base on \(baseShare)%, \(nickelShare - baseShare) points apart: the four-back front is not the substitution"
        )
    }

    /// A second tight end, where the engine had a fourth receiver.
    ///
    /// Two sourced rows bound this between them (S2, 2023–24;
    /// `docs/reference/calibration-sources.md`): `row:snaps.tightEnd` is 77.1–87.2 tight
    /// end player-snaps per team-game, and `row:snaps.quarterback` is 58.9–66.8, one a
    /// snap by construction and therefore the plays from scrimmage a team runs. The
    /// fewest tight ends per snap any pairing of the two admits is 77.1 over 66.8, so the
    /// sport puts more than one tight end on the average snap however the bands are read.
    ///
    /// This is the sourced form of the claim that the offence spends about a snap in five
    /// in twelve personnel: the repository sources no share for twelve itself, and the
    /// tight end count is the figure it does source. The measured share is reported
    /// alongside so a reader can see it.
    @Test(
        "More than one tight end on the average snap (row:snaps.tightEnd over row:snaps.quarterback, S2 2023-24)",
        .tags(.football))
    func aSecondTightEndIsOnTheFieldWhereTheSportPutsOne() {
        // The least favourable corner of the two bands, computed here rather than typed
        // as a quotient so the derivation is on the page.
        let floor = 77.1 / 66.8

        var tightEnds = 0
        var snaps = 0
        var twelve = 0
        for (result, players) in Self.sampled {
            for play in result.plays where play.outcome.kind.isScrimmagePlay {
                snaps += 1
                if play.situation.offensePersonnel.code == 12 { twelve += 1 }
                for index in 0..<PlayerSlot.count {
                    guard let player = play.player(at: PlayerSlot(index), rosters: result.rosters),
                        players[player]?.position.group == .tightEnd
                    else { continue }
                    tightEnds += 1
                }
            }
        }
        let perSnap = Double(tightEnds) / Double(snaps)
        #expect(
            perSnap > floor,
            "\(perSnap) tight ends a snap over \(snaps) snaps, against a floor of \(floor); twelve personnel on \(Double(twelve) / Double(snaps) * 100)% of them"
        )
    }

    /// The four-back front's own band, which the package rule has to land inside rather
    /// than merely clear.
    ///
    /// `row:packageBase` puts four defensive backs on 20.2-25.0% of snaps (S2, the
    /// source's participation feed, 2023-24; `docs/reference/calibration-sources.md`).
    /// Read against `row:personnel11`'s 62.3-71.9%, a grouping that is not eleven
    /// personnel is on 28.1-37.7% of snaps, and the smallest that share can be is 28.1
    /// against the four-back front's largest 25.0. The two bands therefore say, on their
    /// own and at their least favourable corners, that base cannot be the answer to
    /// every grouping that is not eleven personnel: some of those snaps are answered
    /// with a fifth defensive back.
    ///
    /// This is the band the previous package rule cleared by six points and that its
    /// test deliberately did not assert, because a rule that answered every heavier
    /// grouping from base could not reach it.
    @Test(
        "Base takes 20.2-25.0% of snaps (row:packageBase, S2 2023-24)",
        .tags(.football))
    func baseIsTheSubstitutionAndNotTheAnswerToEveryHeavierGrouping() {
        let snaps = Self.scrimmage
        let base = Double(snaps.filter { $0.situation.defensePackage == .base }.count)
        let share = base / Double(snaps.count) * 100
        let heavier = Double(
            snaps.filter { $0.situation.offensePersonnel.code != 11 }.count)
        #expect(
            share >= 20.2 && share <= 25.0,
            "base on \(share)% of \(snaps.count) snaps, against \(heavier / Double(snaps.count) * 100)% of them in a grouping that is not eleven personnel"
        )
    }

    /// A two-tight-end grouping draws the fifth defensive back sometimes, and the
    /// four-back front most of the time.
    ///
    /// **A pin, not football.** What is sourced is `row:packageBase` above, which bounds
    /// the four-back front over *every* snap and forces the rule to exist; nothing in the
    /// repository bands how a defence answers a two-tight-end grouping in particular, and
    /// the two bounds here are that sourced band carried onto a narrower population than
    /// it covers. Base's ceiling of 25.0 against a non-eleven share of at least 28.1 is
    /// what makes the share above zero; base's floor of 20.2 against a non-eleven share
    /// of at most 37.7 leaves the four-back front at least 53.6% of those snaps, which is
    /// what makes it a minority. Carrying either onto twelve personnel alone assumes the
    /// heavier groupings are where the non-eleven snaps are, which is the engine's mix
    /// rather than a figure, so this is tagged for what it is.
    ///
    /// First and ten, which is where the grouping is a choice rather than a situation:
    /// the short-yardage and goal-line branches never reach it, and a defence that has to
    /// answer a two-tight-end grouping on an ordinary down is the thing being pinned.
    @Test(
        "Pins that twelve personnel on first and ten draws nickel sometimes and base mostly",
        .tags(.pin))
    func twelvePersonnelDrawsNickelSometimesOnAnOrdinaryDown() {
        let ordinary = Self.scrimmage.filter {
            $0.situation.offensePersonnel.code == 12 && $0.situation.down == .first
                && $0.situation.distance == 10
        }
        let nickel = Double(ordinary.filter { $0.situation.defensePackage == .nickel }.count)
        let share = nickel / Double(max(1, ordinary.count)) * 100
        #expect(
            share > 0 && share < 50,
            "nickel answered \(share)% of \(ordinary.count) first-and-ten snaps in twelve personnel"
        )
    }
}
