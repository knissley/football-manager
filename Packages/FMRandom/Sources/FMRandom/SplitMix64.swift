/// The SplitMix64 mixing function, used to expand a single 64-bit seed into the
/// wider state `SplittableRandom` needs, and to derive child stream seeds.
///
/// Not exposed as a generator in its own right — everything in the simulation
/// draws from `SplittableRandom`.
enum SplitMix64 {

    /// The golden-ratio increment. Any odd constant works; this is the
    /// conventional one and changing it would invalidate every golden test.
    static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Avalanche a 64-bit value so that neighbouring inputs produce unrelated
    /// outputs. Pure integer arithmetic, so it is bit-identical everywhere.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The four state words for a generator seeded with `seed`.
    static func expand(seed: UInt64) -> (UInt64, UInt64, UInt64, UInt64) {
        var state = seed
        func nextWord() -> UInt64 {
            state = state &+ gamma
            return mix(state)
        }
        let s0 = nextWord()
        let s1 = nextWord()
        let s2 = nextWord()
        let s3 = nextWord()

        // xoshiro cannot escape an all-zero state. Reaching it from SplitMix64
        // is not believed possible, but the cost of the guard is one comparison
        // at construction and the cost of being wrong is a dead generator.
        if s0 == 0 && s1 == 0 && s2 == 0 && s3 == 0 {
            let fallback = mix(gamma)
            return (fallback, fallback, fallback, fallback)
        }
        return (s0, s1, s2, s3)
    }
}
