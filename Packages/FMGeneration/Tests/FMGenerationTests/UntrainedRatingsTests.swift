import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030

/// The mean of one key over a run of generated players at a position.
private func mean(
    of key: RatingKey, at position: Position, count: Int = 200, seed: UInt64
) throws -> Double {
    var random = SplittableRandom(seed: seed)
    var total = 0.0
    for index in 0..<count {
        // A different man each time. His untrained keys are drawn on his identifier,
        // so two hundred men on one identifier would be one draw two hundred times.
        let player = PlayerGenerator.player(
            id: PlayerID(UInt64(index + 1)), position: position, targetCeiling: 75, age: 27,
            season: season, colleges: [], using: &random)
        total += Double(try #require(player.ratings[key], "\(position) carries no \(key)"))
    }
    return total / Double(count)
}

/// A rating a position does not train is present and low, never absent.
///
/// The promise these hold the generator to: every man carries every key, and the keys
/// his position does not train are drawn from an untrained distribution rather than
/// left out. Leaving them out let `overall(at:)` skip the weight of anything missing and
/// renormalise over the rest, so a receiver evaluated at quarterback was scored on his
/// awareness and speed alone and came out a *better* quarterback than a receiver.
@Suite("Untrained ratings")
struct UntrainedRatingsTests {

    @Test("contract: every generated player carries every rating key", .tags(.contract))
    func everyKeyIsPresent() {
        var random = SplittableRandom(seed: 88)
        for position in Position.allCases {
            for age in [22, 27, 33] {
                let player = PlayerGenerator.player(
                    id: PlayerID(1), position: position, targetCeiling: 75, age: age,
                    season: season, colleges: [], using: &random)
                #expect(
                    player.ratings.count == RatingKey.allCases.count,
                    "\(position) at \(age) carries \(player.ratings.count) of \(RatingKey.allCases.count) keys"
                )
                for key in RatingKey.allCases {
                    #expect(player.ratings.has(key), "\(position) at \(age) has no \(key)")
                }
            }
        }
    }

    /// Nobody but a quarterback throws, and nobody but a specialist kicks. The centres
    /// here are the untrained table's, and the bounds sit two spreads above them.
    @Test(
        "contract: a key the position does not train is present and low", .tags(.contract))
    func untrainedKeysAreLow() throws {
        // A tackle throws like a man who has never thrown.
        #expect(try mean(of: .throwAccuracyShort, at: .leftTackle, seed: 1) < 40)
        #expect(try mean(of: .throwPower, at: .leftTackle, seed: 2) < 40)
        // A kicker covers nobody.
        #expect(try mean(of: .manCoverage, at: .kicker, seed: 3) < 35)
        #expect(try mean(of: .zoneCoverage, at: .kicker, seed: 4) < 35)
        // A guard has never kicked.
        #expect(try mean(of: .kickPower, at: .leftGuard, seed: 5) < 30)
        #expect(try mean(of: .puntPower, at: .leftGuard, seed: 6) < 30)
        // A corner has never rushed the passer, and a receiver has never shed a block.
        #expect(try mean(of: .powerMove, at: .cornerback, seed: 7) < 40)
        #expect(try mean(of: .blockShedding, at: .wideReceiver, seed: 8) < 40)
    }

    /// The table is not flat: a job that sometimes asks for something sits above one
    /// that never does. A safety catches what is thrown at him; a kicker has punted; a
    /// receiver has been asked to block.
    @Test(
        "contract: a job that sometimes asks for a skill sits above one that never does",
        .tags(.contract))
    func sometimesSitsAboveNever() throws {
        let safetyHands = try mean(of: .catching, at: .safety, seed: 11)
        let guardHands = try mean(of: .catching, at: .leftGuard, seed: 12)
        #expect(safetyHands > guardHands + 8, "safety \(safetyHands), guard \(guardHands)")

        let kickerPunting = try mean(of: .puntPower, at: .kicker, seed: 13)
        let guardPunting = try mean(of: .puntPower, at: .leftGuard, seed: 14)
        #expect(kickerPunting > guardPunting + 20, "kicker \(kickerPunting), guard \(guardPunting)")

        let receiverBlocking = try mean(of: .runBlock, at: .wideReceiver, seed: 15)
        let quarterbackBlocking = try mean(of: .runBlock, at: .quarterback, seed: 16)
        #expect(
            receiverBlocking > quarterbackBlocking + 2,
            "receiver \(receiverBlocking), quarterback \(quarterbackBlocking)")

        let tackleZone = try mean(of: .zoneCoverage, at: .defensiveTackle, seed: 17)
        let tackleMan = try mean(of: .manCoverage, at: .defensiveTackle, seed: 18)
        #expect(tackleZone > tackleMan + 5, "zone \(tackleZone), man \(tackleMan)")
    }

    /// The table's own well-formedness: every key a position does not train resolves to a
    /// row, so the floor in `fillUntrained` is never what a generated player carries.
    @Test("unit: every untrained key at every position has a row", .tags(.unit))
    func everyUntrainedKeyHasARow() {
        for position in Position.allCases {
            let trained = Set(RatingKey.keys(for: position))
            for key in RatingKey.allCases where !trained.contains(key) {
                if [.elusiveness, .pursuit, .hitPower].contains(key) { continue }
                #expect(
                    PlayerGenerator.untrainedRow(for: key, at: position) != nil,
                    "\(position) has no row for \(key)")
            }
        }
    }

    /// Three untrained keys follow the athlete rather than a table: elusiveness is half
    /// his agility, pursuit half his speed and ten, hit power half his strength. So a
    /// safety who has never carried the ball is still harder to catch than a guard who
    /// has not either, and a tackle hits harder than a corner.
    @Test("contract: elusiveness, pursuit and hit power follow the athlete", .tags(.contract))
    func derivedKeysFollowTheAthlete() throws {
        let safety = try mean(of: .elusiveness, at: .safety, seed: 21)
        let guardElusiveness = try mean(of: .elusiveness, at: .leftGuard, seed: 22)
        #expect(safety > guardElusiveness + 10, "safety \(safety), guard \(guardElusiveness)")

        let receiverPursuit = try mean(of: .pursuit, at: .wideReceiver, seed: 23)
        let guardPursuit = try mean(of: .pursuit, at: .leftGuard, seed: 24)
        #expect(
            receiverPursuit > guardPursuit + 15,
            "receiver \(receiverPursuit), guard \(guardPursuit)")

        let tackleHit = try mean(of: .hitPower, at: .leftTackle, seed: 25)
        let cornerHit = try mean(of: .hitPower, at: .cornerback, seed: 26)
        #expect(tackleHit > cornerHit + 10, "tackle \(tackleHit), corner \(cornerHit)")
    }
}

/// Where a whole league's men rate away from their own positions.
///
/// One world, seed 7, every roster. Both suites below read the same world so the two
/// claims — that a mover is honestly worse than a native, and that filling the keys he
/// lacked moved nobody at his own position — are made of the same men.
@Suite("Out of position, at seed 7")
struct CrossPositionTests {

    private static let world = try? WorldGenerator.generate(
        seed: 7, shape: .standard, season: 2030
    ).get()

    private func rosters() throws -> [Player] {
        let world = try #require(Self.world, "seed 7 did not produce a world")
        var players: [Player] = []
        for team in world.teams { players += world.roster(of: team.id) }
        return players
    }

    private func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(max(1, values.count))
    }

    /// A receiver at quarterback, a kicker at quarterback, a running back at linebacker
    /// and a tight end at left tackle each rate at least five points under the men who
    /// play there, on average, and none of them out-rates the best native.
    ///
    /// Before every key was filled, `overall(at:)` dropped the weight of any rating a
    /// mover lacked and renormalised over what he had, which scored a receiver at
    /// quarterback on his awareness and speed alone: receivers averaged 66.7 there against
    /// 62.2 at receiver, kickers rated a 64 quarterback, and backs rated 65.9 at linebacker
    /// against natives at 61.6.
    @Test(
        "contract: a mover rates at least five points under the natives, on average",
        .tags(.contract))
    func moversRateUnderNatives() throws {
        let players = try rosters()
        let rows: [(from: Position, to: Position)] = [
            (.wideReceiver, .quarterback),
            (.kicker, .quarterback),
            (.runningBack, .linebacker),
            (.tightEnd, .leftTackle),
        ]
        for row in rows {
            let movers = players.filter { $0.position == row.from }
            let natives = players.filter { $0.position == row.to }
            let moved = mean(movers.map { Double($0.overall(at: row.to)) })
            let native = mean(natives.map { Double($0.overall) })
            let bestNative = natives.map(\.overall).max() ?? 0
            let outrating = movers.filter { $0.overall(at: row.to) > bestNative }.count
            #expect(moved <= native - 5, "\(row.from) at \(row.to): \(moved) against \(native)")
            #expect(
                outrating <= movers.count / 50,
                "\(outrating) of \(movers.count) \(row.from)s out-rate the best \(row.to)")
        }
    }

    /// The audit's two probes. A receiver is a poor quarterback because he cannot throw,
    /// and a kicker is a worse one still.
    @Test(
        "contract: receivers rate well below their own overall at quarterback, and kickers under 35",
        .tags(.contract))
    func receiversAndKickersAtQuarterback() throws {
        let players = try rosters()
        let receivers = players.filter { $0.position == .wideReceiver }
        let atReceiver = mean(receivers.map { Double($0.overall) })
        let atQuarterback = mean(receivers.map { Double($0.overall(at: .quarterback)) })
        #expect(
            atQuarterback <= atReceiver - 10,
            "receivers average \(atQuarterback) at quarterback against \(atReceiver) at receiver")

        let kickers = players.filter { $0.position == .kicker }
        let kickersAtQuarterback = mean(kickers.map { Double($0.overall(at: .quarterback)) })
        #expect(kickersAtQuarterback < 35, "kickers average \(kickersAtQuarterback) at quarterback")
    }

    /// Filling the keys a man does not train must not move him at the position he does.
    ///
    /// The two moments were measured on the tree at 1043fa0, before any untrained key
    /// existed, over every roster man at seed 7 — 1,696 of them — with the standard
    /// deviation taken over the population. They are written in rather than recomputed so
    /// that a change to how the trained keys are drawn, or to what `overall` does with a
    /// weight, fails here instead of quietly re-centring the league.
    @Test(
        "contract: own-position overall at seed 7 is unmoved — mean 66.09, sd 10.66, within 0.5",
        .tags(.contract))
    func ownPositionMomentsAreUnmoved() throws {
        let overalls = try rosters().map { Double($0.overall) }
        let count = Double(overalls.count)
        let mean = overalls.reduce(0, +) / count
        let variance = overalls.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        let deviation = variance.squareRoot()

        #expect(overalls.count == 1_696, "seed 7 has \(overalls.count) roster men")
        #expect(abs(mean - 66.09) < 0.5, "league mean overall is \(mean) against 66.09")
        #expect(abs(deviation - 10.66) < 0.5, "league overall spread is \(deviation) against 10.66")
    }
}
