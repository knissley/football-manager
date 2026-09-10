import FMCore
import FMRandom
import Testing

@testable import FMGeneration

@Suite("Name generation")
struct NameGeneratorTests {

    /// The whole world is regenerable from its seed, names included. If this
    /// fails, a saved career cannot be reconstructed.
    @Test("The same seed produces the same names", .tags(.contract))
    func deterministic() {
        var a = SplittableRandom(seed: 4242)
        var b = SplittableRandom(seed: 4242)
        for _ in 0..<500 {
            #expect(NameGenerator.personName(using: &a) == NameGenerator.personName(using: &b))
        }
    }

    @Test("Different seeds produce different names", .tags(.contract))
    func seedsDiverge() {
        var a = SplittableRandom(seed: 1)
        var b = SplittableRandom(seed: 2)
        let first = (0..<50).map { _ in NameGenerator.personName(using: &a).full }
        let second = (0..<50).map { _ in NameGenerator.personName(using: &b).full }
        #expect(first != second)
    }

    @Test("Names are never empty or malformed", .tags(.unit))
    func wellFormed() {
        var random = SplittableRandom(seed: 7)
        for _ in 0..<2000 {
            let name = NameGenerator.personName(using: &random)
            #expect(!name.given.isEmpty)
            #expect(!name.family.isEmpty)
            #expect(name.full.contains(" "))
            #expect(!name.full.hasPrefix(" "))
            #expect(!name.full.hasSuffix(" "))
        }
    }

    @Test("Short form is an initial and a surname", .tags(.unit))
    func shortForm() {
        let name = PersonName(given: "Marcus", family: "Whitfield")
        #expect(name.short == "M. Whitfield")
        #expect(name.full == "Marcus Whitfield")

        let suffixed = PersonName(given: "Marcus", family: "Whitfield", suffix: "Jr.")
        #expect(suffixed.full == "Marcus Whitfield Jr.")
        #expect(suffixed.short == "M. Whitfield")
    }

    @Test("Suffixes are rare rather than absent", .tags(.unit))
    func suffixRate() {
        var random = SplittableRandom(seed: 11)
        var suffixed = 0
        let draws = 20_000
        for _ in 0..<draws where NameGenerator.personName(using: &random).suffix != nil {
            suffixed += 1
        }
        let rate = Double(suffixed) / Double(draws)
        #expect(rate > 0.02 && rate < 0.07, "suffix rate was \(rate)")
    }

    /// A roster of 1,700 that never repeats a name would feel more synthetic,
    /// not less — real leagues have duplicates. What matters is that the pool is
    /// wide enough that repeats are occasional rather than constant.
    @Test("The name space is wide enough for a league", .tags(.unit))
    func variety() {
        var random = SplittableRandom(seed: 13)
        var names: Set<String> = []
        for _ in 0..<1700 {
            names.insert(NameGenerator.personName(using: &random).full)
        }
        // Under 5% collisions across a full league's worth of players.
        #expect(names.count > 1_615, "only \(names.count) distinct names in 1700")
    }

    @Test("Both pools are actually drawn from", .tags(.unit))
    func poolsAreExercised() {
        var random = SplittableRandom(seed: 17)
        var givenSeen: Set<String> = []
        var familySeen: Set<String> = []
        for _ in 0..<20_000 {
            let name = NameGenerator.personName(using: &random)
            givenSeen.insert(name.given)
            familySeen.insert(name.family)
        }
        #expect(givenSeen.count == NamePools.given.count)
        #expect(familySeen.count == NamePools.family.count)
    }
}

@Suite("College generation")
struct CollegeGeneratorTests {

    @Test("Colleges are deterministic and well formed", .tags(.contract))
    func wellFormed() {
        var a = SplittableRandom(seed: 99)
        var b = SplittableRandom(seed: 99)
        for _ in 0..<300 {
            let first = NameGenerator.college(using: &a)
            let second = NameGenerator.college(using: &b)
            #expect(first == second)
            #expect(!first.name.isEmpty)
            #expect(first.name.contains(" "))
        }
    }

    /// Most prospects come from programmes with tape on them; the minority who
    /// do not are where scouting gets genuinely hard.
    @Test("Programme profiles are weighted toward well-scouted schools", .tags(.unit))
    func profileWeighting() {
        var random = SplittableRandom(seed: 23)
        var counts: [CollegeProfile: Int] = [:]
        let draws = 20_000
        for _ in 0..<draws {
            counts[NameGenerator.college(using: &random).profile, default: 0] += 1
        }
        let power = Double(counts[.powerProgram] ?? 0) / Double(draws)
        let small = Double(counts[.smallSchool] ?? 0) / Double(draws)
        #expect(power > 0.40 && power < 0.50)
        #expect(small > 0.15 && small < 0.25)
    }

    @Test("Small schools carry more scouting noise", .tags(.unit))
    func noiseMultipliers() {
        #expect(
            CollegeProfile.smallSchool.scoutingNoiseMultiplier
                > CollegeProfile.midMajor.scoutingNoiseMultiplier)
        #expect(
            CollegeProfile.midMajor.scoutingNoiseMultiplier
                > CollegeProfile.powerProgram.scoutingNoiseMultiplier)
    }

    @Test("A college pool has the requested size and distinct names", .tags(.unit))
    func pool() {
        var random = SplittableRandom(seed: 31)
        let pool = NameGenerator.collegePool(count: 120, using: &random)
        #expect(pool.count == 120)
        #expect(Set(pool.map(\.name)).count == 120)
    }

    @Test("Pool generation terminates even when asked for more than it can make", .tags(.unit))
    func poolSaturates() {
        var random = SplittableRandom(seed: 37)
        let pool = NameGenerator.collegePool(count: 100_000, using: &random)
        #expect(pool.count > 0)
        #expect(pool.count < 100_000)
        #expect(Set(pool.map(\.name)).count == pool.count)
    }
}

@Suite("Name pools")
struct NamePoolTests {

    /// Overlap between the pools produces "Sterling Sterling", which reads as a
    /// generator failure rather than as a person.
    @Test("Given names and surnames do not overlap", .tags(.unit))
    func poolsAreDisjoint() {
        let overlap = Set(NamePools.given).intersection(Set(NamePools.family))
        #expect(overlap.isEmpty, "shared between pools: \(overlap.sorted())")
    }

    @Test("Neither pool contains duplicates", .tags(.unit))
    func poolsAreUnique() {
        #expect(Set(NamePools.given).count == NamePools.given.count)
        #expect(Set(NamePools.family).count == NamePools.family.count)
    }

    @Test("Pools are large enough that a league is not repetitive", .tags(.unit))
    func poolsAreWide() {
        #expect(NamePools.given.count >= 100)
        #expect(NamePools.family.count >= 150)
    }

    @Test("Every entry is a plausible name rather than a placeholder", .tags(.unit))
    func entriesAreWellFormed() {
        for name in NamePools.given + NamePools.family {
            #expect(!name.isEmpty)
            #expect(!name.contains(" "))
            #expect(name.first?.isUppercase == true)
        }
    }
}
