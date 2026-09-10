import FMCore
import FMGeneration

/// The world every calibration run is played in, and the one number that names it.
///
/// It lives here rather than inline in `main.swift` for two reasons. The harness's own
/// tests can reach it — nothing can reach top-level code — and the `world checksum` line
/// in the header is taken over *this* world, the one the games were played in, rather
/// than a second world generated in order to be checksummed. A checksum of a world
/// nobody played would be worse than no checksum at all, because
/// `scripts/harness-reach.sh` believes it (#72).
enum HarnessWorld {

    /// No draft pipeline and no rivalries: neither reaches a snap, and generating them
    /// would double the work before the first kickoff. This is exactly why the reach
    /// script exists — a change to either generator cannot move a single row here, and
    /// the checksum is what says so mechanically.
    static let parts: WorldGenerator.Parts = .teamsAndRosters

    /// Fewer colleges than a career world, because the pool only has to be wide enough
    /// that rosters do not all come from the same handful of schools.
    static let collegeCount = 80

    static let season = 2030

    static func generate(
        seed: UInt64
    ) -> Result<WorldGenerator.GeneratedWorld, WorldGenerator.GenerationFailure> {
        WorldGenerator.generate(
            seed: seed, shape: .standard, season: season, parts: parts,
            collegeCount: collegeCount)
    }

    /// `world checksum <sixteen hex digits>` — the line the header prints, the whole of
    /// what `--world-checksum-only` prints, and what `scripts/harness-reach.sh` reads.
    ///
    /// `WorldChecksum` is `FMGeneration`'s, the same function `GoldenWorldTests` pins to
    /// a checked-in constant. The number here is not that constant — the harness's world
    /// is generated without the optional parts and with a smaller college pool, so it is
    /// a different world — but it is the same function over it, which is what makes two
    /// branches' numbers comparable.
    static func checksumLine(for world: WorldGenerator.GeneratedWorld) -> String {
        "world checksum \(WorldChecksum.hex(WorldChecksum.of(world)))"
    }
}
