import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030
private let seeds: [UInt64] = [1, 5, 7, 11]

/// Every man on every roster in a generated league. `world.teams` is ordered by
/// identifier, so the walk is stable.
private func everyone(seed: UInt64) -> [Player] {
    guard let world = try? WorldGenerator.generate(seed: seed, season: season).get() else {
        return []
    }
    return world.teams.flatMap { world.roster(of: $0.id) }
}

private func ageHistogram(seed: UInt64) -> [Int: Int] {
    var histogram: [Int: Int] = [:]
    for player in everyone(seed: seed) {
        histogram[player.age(in: season), default: 0] += 1
    }
    return histogram
}

/// How old a generated league is.
///
/// The age of a man in the initial league is drawn once, at world creation, and everything
/// else about him follows from it: how far short of his ceiling he starts, how long he has
/// been in the league, whether this is his first season. So a mistake in the draw is not a
/// cosmetic one — it is a mistake about who is on the roster.
///
/// The mistake this suite exists for was a clamp. The age was drawn around a centre four
/// years under the position group's peak and then *clamped* into 21...38, so every draw the
/// Gaussian put under twenty-one came back as twenty-one: at seed 7, 266 of 1,696 players
/// were twenty-one against 118 who were twenty-two, and because nobody can have entered the
/// league before he was twenty-one, every one of them was a rookie. A quarter of every
/// roster was in its first season ([#67](https://github.com/knissley/football-manager/issues/67)).
@Suite("The ages of a generated league")
struct RosterAgeTests {

    /// A floor a distribution is *clamped* to is a bin that collects everything under it; a
    /// floor its support *starts* at is not. This is how the two are told apart from the
    /// outside, and it is the shape of the histogram rather than any one number: the
    /// youngest age in the league cannot be a spike.
    ///
    /// A factor of two either way is deliberately loose. It is not a claim about how many
    /// twenty-one-year-olds a roster holds — that is the first-season band in
    /// `DraftHistoryTests` — only that the youngest age is drawn like the ages beside it.
    @Test(
        "contract: no age piles up on the floor — 21 is within a factor of two of 22",
        .tags(.contract), arguments: seeds)
    func floorIsNotASpike(seed: UInt64) {
        let histogram = ageHistogram(seed: seed)
        let atFloor = histogram[21] ?? 0
        let above = histogram[22] ?? 0
        #expect(atFloor > 0, "seed \(seed) has nobody at twenty-one")
        #expect(above > 0, "seed \(seed) has nobody at twenty-two")
        #expect(
            atFloor <= 2 * above,
            "seed \(seed) piles up at the floor: \(atFloor) at 21 against \(above) at 22")
        #expect(
            above <= 2 * atFloor,
            "seed \(seed) has a hole at the floor: \(atFloor) at 21 against \(above) at 22")
    }

    /// Two numbers that must be the same number. The age draw's floor is not a bound of its
    /// own: it is the youngest age anybody enters the league at, because a league cannot
    /// hold a man younger than that. Moving one without the other puts men in the league who
    /// arrived before they could have, or leaves a hole at the bottom of the histogram.
    @Test(
        "contract: the youngest a generated player can be is the youngest age anybody enters at",
        .tags(.contract))
    func theFloorIsTheEntryAge() {
        #expect(RosterGenerator.youngestAge == DraftHistory.youngestEntryAge)

        var random = SplittableRandom(seed: 9)
        for _ in 0..<5_000 {
            #expect(DraftHistory.entryAge(using: &random) >= DraftHistory.youngestEntryAge)
        }

        for seed in seeds {
            let young = everyone(seed: seed).filter {
                $0.age(in: season) < DraftHistory.youngestEntryAge
            }
            #expect(young.isEmpty, "seed \(seed) has \(young.count) men under the entry age")
        }
    }

    /// The same claim about the draw itself rather than about a league built from it, at the
    /// youngest slot any roster has: the third cornerback, whose group peaks at
    /// twenty-six and who is drawn four years under it.
    ///
    /// Twenty thousand draws so the shape is the distribution's and not the sample's.
    @Test(
        "unit: the age draw's support starts at the floor rather than folding onto it",
        .tags(.unit))
    func theDrawItselfDoesNotPileUp() {
        var random = SplittableRandom(seed: 4)
        var histogram: [Int: Int] = [:]
        for _ in 0..<20_000 {
            let age = RosterGenerator.age(depth: 2, position: .cornerback, using: &random)
            histogram[age, default: 0] += 1
        }
        #expect(histogram.keys.allSatisfy { $0 >= 21 && $0 <= 38 }, "a draw left the range")
        let atFloor = histogram[21] ?? 0
        let above = histogram[22] ?? 0
        #expect(atFloor > 0 && above > 0)
        #expect(atFloor <= 2 * above, "\(atFloor) at 21 against \(above) at 22")
    }
}
