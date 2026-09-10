import Testing

@testable import FMRandom

/// Known-answer tests. These lock the generator's output forever.
///
/// If one of these fails, the change is not a refactor — it rewrites every
/// stored game in every save, because games are replayed from their seed rather
/// than stored (ADR-0003). The expected values were produced by an independent
/// reference implementation, not by capturing this code's output.
@Suite("Known answers")
struct KnownAnswerTests {

    @Test("Seed 42 produces its fixed sequence", .tags(.unit))
    func seed42() {
        var random = SplittableRandom(seed: 42)
        let expected: [UInt64] = [
            0x1578_0b2e_0c2e_c716,
            0x6104_d986_6d11_3a7e,
            0xae17_5332_39e4_99a1,
            0xecb8_ad47_03b3_60a1,
            0xfde6_dc7f_e2ec_5e64,
            0xc50d_a531_0179_5238,
            0xb821_5485_5a65_ddb2,
            0xd99a_2743_ebe6_0087,
        ]
        for (index, value) in expected.enumerated() {
            #expect(random.next() == value, "draw \(index) diverged")
        }
    }

    /// Seeding xoshiro256** from SplitMix64(0) is the canonical published
    /// example, so this vector also confirms the algorithm itself is right
    /// rather than merely self-consistent.
    @Test("Seed 0 matches the published xoshiro256** reference", .tags(.unit))
    func seed0() {
        var random = SplittableRandom(seed: 0)
        let expected: [UInt64] = [
            0x99ec_5f36_cb75_f2b4,
            0xbf6e_1f78_4956_452a,
            0x1a5f_849d_4933_e6e0,
            0x6aa5_94f1_262d_2d2c,
        ]
        for value in expected {
            #expect(random.next() == value)
        }
    }

    @Test("Split streams have fixed first draws", .tags(.unit))
    func splitVectors() {
        var byLabel7 = SplittableRandom(seed: 42).split(7)
        #expect(byLabel7.next() == 0xd156_fe7b_a6b2_616e)

        var byLabel8 = SplittableRandom(seed: 42).split(8)
        #expect(byLabel8.next() == 0x5b0d_6836_049f_a585)

        var byPair = SplittableRandom(seed: 42).split(3, 4)
        #expect(byPair.next() == 0xb570_35a3_bad3_e7cc)
    }
}

@Suite("Reproducibility")
struct ReproducibilityTests {

    @Test("The same seed always produces the same sequence", .tags(.contract))
    func sameSeedSameSequence() {
        var a = SplittableRandom(seed: 12345)
        var b = SplittableRandom(seed: 12345)
        for _ in 0..<1000 {
            #expect(a.next() == b.next())
        }
    }

    @Test("Different seeds diverge immediately", .tags(.unit))
    func differentSeedsDiverge() {
        var a = SplittableRandom(seed: 1)
        var b = SplittableRandom(seed: 2)
        var identical = 0
        for _ in 0..<100 where a.next() == b.next() {
            identical += 1
        }
        #expect(identical == 0)
    }

    @Test("A seed of zero produces a live generator", .tags(.unit))
    func zeroSeedIsUsable() {
        var random = SplittableRandom(seed: 0)
        let draws = (0..<20).map { _ in random.next() }
        #expect(Set(draws).count == 20)
    }

    @Test("rootSeed is preserved as the generator advances", .tags(.unit))
    func rootSeedStable() {
        var random = SplittableRandom(seed: 99)
        for _ in 0..<500 { _ = random.next() }
        #expect(random.rootSeed == 99)
    }
}

@Suite("Splitting")
struct SplittingTests {

    /// The property the whole replay design leans on: a play's stream does not
    /// depend on what was simulated before it.
    @Test("Splitting does not depend on how far the parent has advanced", .tags(.contract))
    func splitIgnoresAdvancement() {
        let fresh = SplittableRandom(seed: 42)
        var advanced = SplittableRandom(seed: 42)
        for _ in 0..<10_000 { _ = advanced.next() }

        var a = fresh.split(7)
        var b = advanced.split(7)
        for _ in 0..<100 {
            #expect(a.next() == b.next())
        }
    }

    @Test("Different labels produce different streams", .tags(.unit))
    func labelsAreIndependent() {
        let parent = SplittableRandom(seed: 42)
        var firstDraws: Set<UInt64> = []
        for label in 0..<256 {
            var child = parent.split(UInt64(label))
            firstDraws.insert(child.next())
        }
        #expect(firstDraws.count == 256)
    }

    @Test("Paired labels are distinct across a grid", .tags(.unit))
    func pairedLabelsAreIndependent() {
        let parent = SplittableRandom(seed: 7)
        var firstDraws: Set<UInt64> = []
        for game in 0..<32 {
            for play in 0..<32 {
                var child = parent.split(UInt64(game), UInt64(play))
                firstDraws.insert(child.next())
            }
        }
        #expect(firstDraws.count == 1024)
    }

    @Test("Children of different parents differ", .tags(.unit))
    func parentsAreIndependent() {
        var a = SplittableRandom(seed: 1).split(5)
        var b = SplittableRandom(seed: 2).split(5)
        #expect(a.next() != b.next())
    }

    @Test("A child is a full generator that can split again", .tags(.unit))
    func childrenSplit() {
        let child = SplittableRandom(seed: 42).split(1)
        var grandchildA = child.split(1)
        var grandchildB = child.split(2)
        #expect(grandchildA.next() != grandchildB.next())
    }
}
