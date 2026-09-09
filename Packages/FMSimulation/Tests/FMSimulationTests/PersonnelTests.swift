import FMCore
import FMGeneration
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
        var random = SplittableRandom(seed: 12)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let roster = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        var players: [PlayerID: Player] = [:]
        for player in roster { players[player.id] = player }
        return (RosterGenerator.depthChart(from: roster).rotation(), players)
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
            context, family: .insideRun, situation: situation, random: &random)
    }

    /// Eleven men, whoever they are. A grouping that fields ten is a bug that shows up as
    /// an unblocked rusher rather than as an error.
    @Test(
        "Every grouping and package fields eleven",
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
    @Test("A heavy grouping blocks more and an empty one runs more routes")
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
    @Test("The package trades the box for the secondary")
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
    @Test("The best cover men take the receivers")
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
    @Test("Running into a stacked box gains less than running into a light one")
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
                offense: CrudePlaybook.call(.insideRun), defense: .baseCoverThree,
                offensiveCaller: .automatic, defensiveCaller: .automatic)

            var random = SplittableRandom(seed: 88)
            var total = 0
            let carries = 4_000
            for _ in 0..<carries {
                let resolved = CrudeResolver().resolve(
                    situation: situation, calls: calls, context: context, random: &random)
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
}
