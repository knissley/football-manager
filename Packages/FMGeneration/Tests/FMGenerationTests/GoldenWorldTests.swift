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
/// branches' worlds and mean by it exactly what this test means. It is FNV-1a and
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
        "A seed produces the same world in every process", .tags(.contract),
        arguments: [
            // What moves these numbers, and what must not. The checksum covers the whole
            // world — structure, identity, every roster and its draft history, strengths,
            // the draft pipeline and the rivalries — so a constant moves both when
            // generation really changed and when the *coverage* of the checksum widened.
            // Those are not the same claim: widening leaves `GoldenSeedTests` and the
            // harness byte-identical, a generation change does not. Say which in the
            // commit message.
            //
            // The traps, all of which have bitten. A draw whose *count* varies — a
            // rejection loop — moves everything drawn after it, not only its own field. A
            // stream shared between two stages carries a change across them, while a
            // substream split on a player identifier does not. And a field the engine
            // never reads — a club's name, the league's title — still moves this number,
            // because the identity is checksummed; that is the case where these move and
            // `GoldenSeedTests` does not.
            //
            // Regenerating any of them to make a red test pass is forbidden (CLAUDE.md
            // rule 9). What each past move was is in the git log.
            (UInt64(1), UInt64(10_261_439_880_186_297_053)),
            // Seed 5 is the one world of the three with a bitter rivalry pair in it, so a
            // change aimed at seeded rivalry heat moves this constant and leaves seeds 1
            // and 7 where they are. That asymmetry is evidence rather than noise: a
            // rivalry ceiling that moved all three would be reaching pairs it is not
            // aimed at.
            //
            // `WorldGenerator.strengthSpread` is the widest lever on these numbers: every
            // club's offset changes with it, so every roster is built to a different
            // ceiling and every man drawn after the first is a different man. See the
            // constant's own comment, and the rule in `calibration-sources.md` for when a
            // re-measurement is worth acting on.
            (UInt64(5), UInt64(13_874_155_947_617_604_630)),
            (UInt64(7), UInt64(12_647_015_549_021_856_984)),
        ])
    func goldenWorlds(seed: UInt64, expected: UInt64) {
        #expect(worldChecksum(seed: seed) == expected)
    }

    /// Two runs in one process, which is the weaker check — but it distinguishes "the
    /// world moved because generation changed" from "the world moves every time", which
    /// is the first question to ask when the constants above go red.
    @Test("contract: a world is identical to itself, seed by seed", .tags(.contract))
    func selfConsistent() {
        for seed in UInt64(1)...4 {
            #expect(worldChecksum(seed: seed) == worldChecksum(seed: seed))
        }
    }
}
