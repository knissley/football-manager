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
}
