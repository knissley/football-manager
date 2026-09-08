import FMCore
import FMRandom
import Testing

@testable import FMGeneration

@Suite("Depth chart generation")
struct DepthChartGenerationTests {

    private func roster(seed: UInt64 = 17) -> [Player] {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 40, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var identifiers = IdentifierSequence<PlayerSubject>()
        return RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &identifiers, using: &random)
    }

    @Test("Every position on the roster appears on the chart, best first")
    func chartCoversTheRoster() {
        let players = roster()
        let chart = RosterGenerator.depthChart(from: players)
        let byID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })

        for position in chart.positions {
            let ranked = chart[position].compactMap { byID[$0] }
            #expect(ranked.isEmpty == false)
            #expect(ranked.allSatisfy { $0.position == position })
            #expect(
                ranked.map(\.overall) == ranked.map(\.overall).sorted(by: >),
                "\(position) is not ordered best first")
        }
    }

    @Test("Every player on the roster is somewhere on the chart")
    func nobodyIsLost() {
        let players = roster()
        let chart = RosterGenerator.depthChart(from: players)
        #expect(players.allSatisfy { chart.contains($0.id) })
    }

    /// Ties break on identifier, so a chart never depends on the order players happened
    /// to arrive in.
    @Test("The same roster always produces the same chart")
    func deterministic() {
        let players = roster()
        #expect(
            RosterGenerator.depthChart(from: players) == RosterGenerator.depthChart(from: players))
        #expect(
            RosterGenerator.depthChart(from: players.reversed())
                == RosterGenerator.depthChart(from: players))
    }

    /// A generated 53 has to be able to field a team. If a position group came up empty
    /// the roster generator is wrong, and it would surface as a game with ten men.
    @Test("A generated roster can field every position")
    func rosterFieldsEveryPosition() {
        for seed in UInt64(1)...6 {
            let chart = RosterGenerator.depthChart(from: roster(seed: seed))
            #expect(chart.unmannedPositions().isEmpty, "seed \(seed) cannot field a position")
        }
    }

    /// The rotation is what turns 53 players into a box score. If the starters take
    /// everything, depth on the roster is invisible.
    @Test("Backups take a real share of the snaps")
    func backupsPlay() {
        let chart = RosterGenerator.depthChart(from: roster())
        let rotation = chart.rotation()

        let playing = Set(rotation.map(\.player))
        #expect(playing.count > 22, "only \(playing.count) players see the field")

        let backups = rotation.filter { $0.depth > 0 }
        #expect(backups.isEmpty == false)
        #expect(
            backups.contains { $0.snapShare > 0.3 },
            "no backup plays a meaningful share of the snaps")
    }
}
