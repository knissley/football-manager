import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// The same seed must produce the same game — in a different process, on a different day,
/// after a rebuild.
///
/// Every determinism test in this repo used to compare two runs *inside one process*, and
/// that is exactly the check a hash-order bug walks through: Swift randomises its hash
/// seed per process, so two runs in one process agree with each other and disagree with
/// yesterday's. `SchemeFit.effectiveOverall` summed its weights while iterating a
/// dictionary, floating-point addition is not associative, and the sum was rounded to a
/// whole overall point — so a player near a boundary was a point better in one process and
/// a point worse in the next, and the same seed produced a different season.
///
/// A checked-in constant is the only form of this test that can fail for that reason,
/// which is why the number below is written down rather than computed twice.
/// ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md))
@Suite("Golden seed")
struct GoldenSeedTests {

    /// FNV-1a. Deliberately *not* `Hasher`, whose seed is randomised per process — using
    /// it here would make this test unable to detect the thing it exists to detect.
    private struct Checksum {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(_ number: UInt64) {
            for shift in stride(from: 0, through: 56, by: 8) {
                value ^= UInt64((number >> UInt64(shift)) & 0xff)
                value = value &* 0x100_0000_01b3
            }
        }

        mutating func mix(_ number: some BinaryInteger) { mix(UInt64(bitPattern: Int64(number))) }
    }

    private func setup(seed: UInt64) -> GameSetup {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 20, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var ids = IdentifierSequence<PlayerSubject>()
        let home = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        let away = RosterGenerator.roster(
            season: 2030, colleges: colleges, ids: &ids, using: &random)
        var players: [PlayerID: Player] = [:]
        for player in home + away { players[player.id] = player }

        return GameSetup(
            game: GameID(1),
            home: GameTeam(
                id: TeamID(1), depthChart: RosterGenerator.depthChart(from: home),
                scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
            away: GameTeam(
                id: TeamID(2), depthChart: RosterGenerator.depthChart(from: away),
                scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
            players: players, seed: seed)
    }

    private func checksum(seed: UInt64) -> UInt64 {
        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(setup(seed: seed))
        var sum = Checksum()
        sum.mix(result.homeScore)
        sum.mix(result.awayScore)
        sum.mix(result.plays.count)
        for play in result.plays {
            sum.mix(play.situation.ballOn)
            sum.mix(play.situation.distance)
            sum.mix(play.situation.down.rawValue)
            sum.mix(play.situation.offensePersonnel.code)
            sum.mix(play.situation.defensePackage.rawValue)
            sum.mix(play.outcome.kind.rawValue)
            sum.mix(play.outcome.endedIn.rawValue)
            sum.mix(play.outcome.yards)
            sum.mix(play.outcome.clockRunoff)
            sum.mix(play.outcome.finalSpot ?? 200)
            for participant in play.outcome.participants {
                sum.mix(participant.player.rawValue)
                sum.mix(participant.role.rawValue)
                sum.mix(participant.slot.rawValue)
            }
            for decision in play.decisions {
                sum.mix(decision.kind.rawValue)
                sum.mix(decision.value)
                sum.mix(decision.tick)
            }
        }
        for injury in result.injuries {
            sum.mix(injury.player.rawValue)
            sum.mix(injury.gamesOut)
            sum.mix(injury.occurredOn.index)
        }
        return sum.value
    }

    /// Regenerating these to make a red test pass is forbidden: if the engine changed on
    /// purpose, they are regenerated in the same commit and the behaviour change is
    /// described in the message. If it did not, the engine is non-deterministic and that
    /// is the bug.
    @Test(
        "A seed produces the same game in every process",
        arguments: [
            (UInt64(1), UInt64(8_506_620_023_489_985_209)),
            (UInt64(5), UInt64(8_841_975_023_701_611_735)),
            (UInt64(12), UInt64(15_584_503_308_422_963_415)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
