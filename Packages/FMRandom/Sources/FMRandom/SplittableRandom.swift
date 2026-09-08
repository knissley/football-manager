/// The only source of randomness in the simulation.
///
/// `xoshiro256**` seeded through `SplitMix64`. Deterministic and bit-identical
/// on every platform: the algorithm uses nothing but integer arithmetic, so a
/// seed produces the same sequence on arm64 and x86_64, today and in ten years.
///
/// That guarantee is load-bearing rather than convenient. A game is stored as
/// `(initialState, seed, sliderConfig, decisionLog)` and replayed on demand, so
/// a drift in this type corrupts saved history rather than merely failing a
/// test. See ADR-0003.
///
/// ## Splitting
///
/// `split(_:)` derives a child stream from the **root seed and a label only** —
/// never from how far this generator has advanced. So the generator for play 37
/// is identical whether the whole game ran before it or it was constructed
/// directly, which is what makes a single play debuggable in isolation and what
/// lets a week of games simulate concurrently without changing any outcome.
///
/// ## A caution about the standard library
///
/// This type conforms to `RandomNumberGenerator` for interoperability, but
/// simulation code must use the methods defined here rather than stdlib helpers
/// such as `Int.random(in:using:)`. Those are seeded correctly, but the standard
/// library does not guarantee its *algorithm* is stable across Swift versions —
/// and an algorithm change would silently rewrite history.
public struct SplittableRandom: RandomNumberGenerator, Sendable {

    /// The seed this stream was constructed from. Child streams derive from it,
    /// which is what makes splitting independent of advancement.
    public let rootSeed: UInt64

    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    public init(seed: UInt64) {
        rootSeed = seed
        (s0, s1, s2, s3) = SplitMix64.expand(seed: seed)
    }

    public mutating func next() -> UInt64 {
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 &<< 17

        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = rotl(s3, 45)

        return result
    }

    /// An independent stream identified by `label`.
    ///
    /// Depends only on `rootSeed` and `label`, never on this generator's current
    /// position, so it is safe to call at any point and always returns the same
    /// stream for the same label.
    public func split(_ label: UInt64) -> SplittableRandom {
        SplittableRandom(seed: SplitMix64.mix(rootSeed &+ ((label &+ 1) &* SplitMix64.gamma)))
    }

    /// An independent stream identified by a pair of labels — typically
    /// `(gameID, playIndex)` or `(playIndex, participantIndex)`.
    public func split(_ a: UInt64, _ b: UInt64) -> SplittableRandom {
        split(SplitMix64.mix(a &+ (b &* SplitMix64.gamma)))
    }

    private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x &<< k) | (x &>> (64 &- k))
    }
}
