/// Draws built on `SplittableRandom`.
///
/// Everything here is exact integer arithmetic or IEEE-754 basic operations
/// (`+ - * /`), which are precisely specified and identical across platforms.
/// Nothing calls `log`, `exp` or a trigonometric function — those come from
/// libm, whose implementations differ between platforms, and a one-ulp
/// difference compounded over a season's draws is a divergent universe.
extension SplittableRandom {

    // MARK: - Integers

    /// A value in `0..<upperBound`, without modulo bias.
    ///
    /// Lemire's multiply-and-reject method. The rejection loop is entered rarely
    /// and terminates with probability 1.
    public mutating func next(upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0, "upperBound must be positive")

        var product = next().multipliedFullWidth(by: upperBound)
        if product.low < upperBound {
            let threshold = (0 &- upperBound) % upperBound
            while product.low < threshold {
                product = next().multipliedFullWidth(by: upperBound)
            }
        }
        return product.high
    }

    /// A value in `range`.
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) &+ 1
        return range.lowerBound + Int(next(upperBound: span))
    }

    /// A value in `range`.
    public mutating func nextInt(in range: Range<Int>) -> Int {
        precondition(!range.isEmpty, "range must not be empty")
        return range.lowerBound + Int(next(upperBound: UInt64(range.count)))
    }

    // MARK: - Doubles

    /// A value in `[0, 1)`, with 53 bits of resolution.
    ///
    /// Built by scaling an integer by a power of two, so the result is exact and
    /// reproducible rather than dependent on a conversion path.
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// A value in `[lower, upper)`.
    public mutating func nextDouble(in range: Range<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    /// `true` with the given probability.
    public mutating func nextBool(probability: Double) -> Bool {
        if probability <= 0 { return false }
        if probability >= 1 { return true }
        return nextDouble() < probability
    }

    // MARK: - Normal distribution

    /// A draw from a standard normal distribution, approximated by the
    /// Irwin–Hall construction: twelve uniforms summed, minus six.
    ///
    /// Mean 0 and variance exactly 1, and accurate through the range that
    /// matters for generating bounded attributes. It is deliberately *not* the
    /// Box–Muller transform, which needs `log`, `sqrt` and `cos` and would put
    /// platform-dependent libm results into a value that must be reproducible
    /// forever.
    ///
    /// The cost is truncated tails — draws are bounded to ±6 and slightly thin
    /// beyond about ±3. For player attributes, which are clamped into 0...99
    /// anyway, that is the right trade. If a system ever needs faithful tails,
    /// replace this with a precomputed inverse-CDF table behind the same
    /// signature; do not reach for `log`.
    public mutating func nextGaussian() -> Double {
        var sum = 0.0
        for _ in 0..<12 {
            sum += nextDouble()
        }
        return sum - 6.0
    }

    /// A normal draw with the given mean and standard deviation.
    public mutating func nextGaussian(mean: Double, standardDeviation: Double) -> Double {
        mean + nextGaussian() * standardDeviation
    }

    // MARK: - Collections

    /// A uniformly chosen element, or `nil` if `elements` is empty.
    ///
    /// Named to avoid `randomElement()`, which is banned in simulation code
    /// because it reaches for the system generator.
    public mutating func pick<T>(from elements: [T]) -> T? {
        guard !elements.isEmpty else { return nil }
        return elements[Int(next(upperBound: UInt64(elements.count)))]
    }

    /// Fisher–Yates, descending. Replaces `shuffle()`, which is banned in
    /// simulation code for the same reason as `randomElement()`.
    public mutating func shuffle<T>(_ elements: inout [T]) {
        guard elements.count > 1 else { return }
        for i in stride(from: elements.count - 1, to: 0, by: -1) {
            let j = Int(next(upperBound: UInt64(i + 1)))
            if i != j { elements.swapAt(i, j) }
        }
    }

    /// A shuffled copy.
    public mutating func shuffled<T>(_ elements: [T]) -> [T] {
        var copy = elements
        shuffle(&copy)
        return copy
    }

    /// An index chosen in proportion to `weights`.
    ///
    /// Negative weights are a programming error. An all-zero set of weights
    /// falls back to a uniform choice rather than trapping, because a play
    /// caller with no attractive options should still call something.
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        guard !weights.isEmpty else { return nil }

        var total = 0.0
        for weight in weights {
            precondition(weight >= 0, "weights must not be negative")
            total += weight
        }
        guard total > 0 else {
            return Int(next(upperBound: UInt64(weights.count)))
        }

        let target = nextDouble() * total
        var cumulative = 0.0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if target < cumulative { return index }
        }
        // Only reachable through floating-point accumulation error.
        return weights.count - 1
    }
}
