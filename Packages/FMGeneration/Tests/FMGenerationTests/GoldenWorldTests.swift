import FMCore
import FMRandom
import Testing

@testable import FMGeneration

/// A world generated from a seed must be the same world tomorrow.
///
/// The companion to `FMSimulation`'s golden seed test, and here for the same reason: the
/// bug that motivated both was a floating-point sum taken while iterating a dictionary,
/// and Swift randomises its hash seed per process — so every test that compares two runs
/// *inside one process* agrees with itself and disagrees with yesterday. Only a
/// checked-in constant can fail that way.
///
/// Checksummed over the *whole* world rather than one roster: the league's structure, its
/// teams, every roster and its draft history, the strength each team was drawn at, the
/// draft pipeline and the rivalries. A determinism bug in any stage of `WorldGenerator`
/// fails here, and a change in the *order* the stages draw in fails here too.
///
/// The checksum itself is `WorldChecksum` in `FMGeneration`, not a private copy in this
/// file, because `simharness` prints the same number in its header: the goldens pin the
/// function and the harness reports it, so `scripts/harness-reach.sh` can compare two
/// branches' worlds and mean by it exactly what this test means (#72). It is FNV-1a and
/// deliberately not `Hasher`, whose per-process seed would make it unable to detect the
/// drift it exists to detect.
@Suite("Golden world")
struct GoldenWorldTests {

    private func worldChecksum(seed: UInt64) -> UInt64 {
        guard
            let world = try? WorldGenerator.generate(
                seed: seed, shape: .standard, season: 2030
            ).get()
        else {
            Issue.record("seed \(seed) did not produce a world")
            return 0
        }
        return WorldChecksum.of(world)
    }

    /// Regenerating these to make a red test pass is forbidden. If generation changed on
    /// purpose they are regenerated in the same commit with the change described; if it
    /// did not, generation is non-deterministic and that is the bug.
    @Test(
        "A seed produces the same world in every process",
        arguments: [
            (UInt64(1), UInt64(14_214_372_360_801_669_875)),
            // Moved by #64, which caps seeded rivalry heat: seed 5's world opened with a
            // bitter rivalry, and that pair loses the smallest single event that brings it
            // under the band — its 2026 player poaching, 67.195 to 63.541. Seeds 1 and 7
            // have no bitter pair in them and did not move, which is the evidence that the
            // ceiling reaches nothing but the pairs it is aimed at.
            //
            // All three moved again in #72, when the checksum stopped being private to
            // this file: it now covers what the engine reads and this file did not — the
            // stadium beyond its name and noise, both schemes in full rather than their
            // pass lean, secondary positions, the hidden attributes, traits and status —
            // and terminates each string so two adjacent fields cannot slide.
            //
            // And once more in review of #72, which found two ways the checksum still
            // called two different leagues one league: it read the rosters but not
            // `world.players`, the map the engine is actually handed, and it concatenated
            // variable-length groups without their lengths, so a depth chart repartitioned
            // over the same men was invisible. Both are now covered, both had moved the
            // harness by hundreds of lines in the reviewer's repro. Wider
            // coverage, not different generation: no world changed, and the run before
            // and after is byte-identical.
            (UInt64(5), UInt64(739_023_233_666_568_453)),
            (UInt64(7), UInt64(16_728_311_166_745_480_593)),
        ])
    func goldenWorlds(seed: UInt64, expected: UInt64) {
        #expect(worldChecksum(seed: seed) == expected)
    }

    /// Two runs in one process, which is the weaker check — but it distinguishes "the
    /// world moved because generation changed" from "the world moves every time", which
    /// is the first question to ask when the constants above go red.
    @Test("contract: a world is identical to itself, seed by seed")
    func selfConsistent() {
        for seed in UInt64(1)...4 {
            #expect(worldChecksum(seed: seed) == worldChecksum(seed: seed))
        }
    }
}
