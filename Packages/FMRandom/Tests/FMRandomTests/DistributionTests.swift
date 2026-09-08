import Testing

@testable import FMRandom

/// Statistical tests here are *deterministic*: every one runs from a fixed seed,
/// so a passing test passes forever and a failing one fails identically. There
/// are no flaky tests in this file, by construction.
@Suite("Bounded integers")
struct BoundedIntegerTests {

    @Test("Draws stay inside the bound")
    func withinBounds() {
        var random = SplittableRandom(seed: 1)
        for bound in [1, 2, 3, 7, 32, 53, 1000] as [UInt64] {
            for _ in 0..<2000 {
                #expect(random.next(upperBound: bound) < bound)
            }
        }
    }

    @Test("A bound of one is always zero")
    func degenerateBound() {
        var random = SplittableRandom(seed: 2)
        for _ in 0..<100 {
            #expect(random.next(upperBound: 1) == 0)
        }
    }

    /// A bound that does not divide 2^64 is where modulo bias would show up.
    /// 53 is deliberately awkward, and happens to be a roster size.
    @Test("An awkward bound stays close to uniform")
    func noModuloBias() {
        var random = SplittableRandom(seed: 3)
        let bound: UInt64 = 53
        let draws = 530_000
        var counts = [Int](repeating: 0, count: Int(bound))
        for _ in 0..<draws {
            counts[Int(random.next(upperBound: bound))] += 1
        }

        let expected = Double(draws) / Double(bound)
        let chiSquare = counts.reduce(0.0) { total, count in
            let delta = Double(count) - expected
            return total + delta * delta / expected
        }
        // 52 degrees of freedom; the 99.9th percentile is about 93.
        #expect(chiSquare < 93.0, "chi-square \(chiSquare) suggests bias")
    }

    @Test("Closed and half-open ranges respect their bounds")
    func integerRanges() {
        var random = SplittableRandom(seed: 4)
        var sawLower = false
        var sawUpper = false
        for _ in 0..<5000 {
            let closed = random.nextInt(in: -3...3)
            #expect(closed >= -3 && closed <= 3)
            if closed == -3 { sawLower = true }
            if closed == 3 { sawUpper = true }

            let halfOpen = random.nextInt(in: 0..<10)
            #expect(halfOpen >= 0 && halfOpen < 10)
        }
        #expect(sawLower && sawUpper, "closed range must be able to hit both ends")
    }

    @Test("A single-value closed range is constant")
    func singletonRange() {
        var random = SplittableRandom(seed: 5)
        for _ in 0..<50 {
            #expect(random.nextInt(in: 7...7) == 7)
        }
    }
}

@Suite("Doubles")
struct DoubleTests {

    @Test("Doubles land in [0, 1)")
    func unitInterval() {
        var random = SplittableRandom(seed: 6)
        for _ in 0..<100_000 {
            let value = random.nextDouble()
            #expect(value >= 0.0 && value < 1.0)
        }
    }

    @Test("Doubles are roughly uniform across the interval")
    func uniformity() {
        var random = SplittableRandom(seed: 7)
        var buckets = [Int](repeating: 0, count: 10)
        let draws = 100_000
        for _ in 0..<draws {
            buckets[min(9, Int(random.nextDouble() * 10))] += 1
        }
        for count in buckets {
            #expect(abs(count - draws / 10) < draws / 100)
        }
    }

    @Test("Ranged doubles respect their bounds")
    func rangedDoubles() {
        var random = SplittableRandom(seed: 8)
        for _ in 0..<10_000 {
            let value = random.nextDouble(in: -2.5..<4.0)
            #expect(value >= -2.5 && value < 4.0)
        }
    }

    @Test("Probabilities behave at and between the extremes")
    func booleans() {
        var random = SplittableRandom(seed: 9)
        for _ in 0..<100 {
            #expect(random.nextBool(probability: 0) == false)
            #expect(random.nextBool(probability: 1) == true)
            #expect(random.nextBool(probability: -0.5) == false)
            #expect(random.nextBool(probability: 1.5) == true)
        }

        var trues = 0
        let draws = 100_000
        for _ in 0..<draws where random.nextBool(probability: 0.3) {
            trues += 1
        }
        #expect(abs(Double(trues) / Double(draws) - 0.3) < 0.01)
    }
}

@Suite("Normal distribution")
struct GaussianTests {

    @Test("Mean and standard deviation come out right")
    func moments() {
        var random = SplittableRandom(seed: 10)
        let draws = 200_000
        var sum = 0.0
        var sumOfSquares = 0.0
        for _ in 0..<draws {
            let value = random.nextGaussian()
            sum += value
            sumOfSquares += value * value
        }
        let mean = sum / Double(draws)
        let variance = sumOfSquares / Double(draws) - mean * mean

        #expect(abs(mean) < 0.01, "mean was \(mean)")
        #expect(abs(variance - 1.0) < 0.02, "variance was \(variance)")
    }

    @Test("Scaled draws match the requested mean and spread")
    func scaled() {
        var random = SplittableRandom(seed: 11)
        let draws = 100_000
        var sum = 0.0
        for _ in 0..<draws {
            sum += random.nextGaussian(mean: 70, standardDeviation: 12)
        }
        #expect(abs(sum / Double(draws) - 70) < 0.2)
    }

    /// Documented consequence of the Irwin–Hall construction. Asserted so that
    /// swapping in another algorithm has to confront the change deliberately.
    @Test("Draws are bounded to plus or minus six")
    func boundedTails() {
        var random = SplittableRandom(seed: 12)
        for _ in 0..<200_000 {
            let value = random.nextGaussian()
            #expect(value > -6.0 && value < 6.0)
        }
    }

    @Test("The bulk of the distribution has the right shape")
    func shape() {
        var random = SplittableRandom(seed: 13)
        let draws = 200_000
        var withinOne = 0
        var withinTwo = 0
        for _ in 0..<draws {
            let value = abs(random.nextGaussian())
            if value < 1.0 { withinOne += 1 }
            if value < 2.0 { withinTwo += 1 }
        }
        #expect(abs(Double(withinOne) / Double(draws) - 0.6827) < 0.01)
        #expect(abs(Double(withinTwo) / Double(draws) - 0.9545) < 0.01)
    }
}

@Suite("Collections")
struct CollectionTests {

    @Test("Shuffling permutes without losing or duplicating elements")
    func shufflePermutes() {
        var random = SplittableRandom(seed: 14)
        for _ in 0..<200 {
            var elements = Array(0..<53)
            random.shuffle(&elements)
            #expect(elements.sorted() == Array(0..<53))
        }
    }

    @Test("Shuffling is reproducible from a seed")
    func shuffleIsDeterministic() {
        var a = SplittableRandom(seed: 15)
        var b = SplittableRandom(seed: 15)
        #expect(a.shuffled(Array(0..<100)) == b.shuffled(Array(0..<100)))
    }

    @Test("Shuffling actually reorders")
    func shuffleReorders() {
        var random = SplittableRandom(seed: 16)
        let original = Array(0..<50)
        var unchanged = 0
        for _ in 0..<100 where random.shuffled(original) == original {
            unchanged += 1
        }
        #expect(unchanged == 0)
    }

    @Test("Empty and single-element collections are handled")
    func degenerateCollections() {
        var random = SplittableRandom(seed: 17)

        var empty: [Int] = []
        random.shuffle(&empty)
        #expect(empty.isEmpty)

        var single = [42]
        random.shuffle(&single)
        #expect(single == [42])

        #expect(random.pick(from: [Int]()) == nil)
        #expect(random.pick(from: [9]) == 9)
    }

    @Test("Picking covers every element")
    func pickIsUniform() {
        var random = SplittableRandom(seed: 18)
        let elements = Array(0..<11)
        var counts = [Int](repeating: 0, count: 11)
        for _ in 0..<110_000 {
            guard let picked = random.pick(from: elements) else {
                Issue.record("pick returned nil for a non-empty collection")
                return
            }
            counts[picked] += 1
        }
        for count in counts {
            #expect(abs(count - 10_000) < 500)
        }
    }

    @Test("Weighted choice follows its weights")
    func weightedChoice() {
        var random = SplittableRandom(seed: 19)
        let weights = [0.5, 0.3, 0.2]
        var counts = [Int](repeating: 0, count: 3)
        let draws = 100_000
        for _ in 0..<draws {
            guard let index = random.weightedIndex(weights) else {
                Issue.record("weightedIndex returned nil for non-empty weights")
                return
            }
            counts[index] += 1
        }
        for (index, weight) in weights.enumerated() {
            let observed = Double(counts[index]) / Double(draws)
            #expect(abs(observed - weight) < 0.01, "index \(index) drew \(observed)")
        }
    }

    @Test("Zero-weight options are never chosen")
    func zeroWeightsExcluded() {
        var random = SplittableRandom(seed: 20)
        for _ in 0..<10_000 {
            #expect(random.weightedIndex([1.0, 0.0, 1.0]) != 1)
        }
    }

    @Test("Degenerate weights fall back rather than trapping")
    func degenerateWeights() {
        var random = SplittableRandom(seed: 21)
        #expect(random.weightedIndex([]) == nil)
        #expect(random.weightedIndex([2.0]) == 0)

        // All-zero weights choose uniformly instead of failing: a play caller
        // with no attractive options still has to call something.
        var seen: Set<Int> = []
        for _ in 0..<500 {
            if let index = random.weightedIndex([0.0, 0.0, 0.0]) { seen.insert(index) }
        }
        #expect(seen == [0, 1, 2])
    }
}
