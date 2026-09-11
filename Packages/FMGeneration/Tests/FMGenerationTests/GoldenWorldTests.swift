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
        "A seed produces the same world in every process", .tags(.contract),
        arguments: [
            // All three moved for the last time they can move for this reason in #69,
            // which took the initial world off the identity pools: the thirty-two clubs,
            // their cities, colours, markets and grounds are now `FranchiseSet`'s curated
            // table rather than a draw, and the checksum reads every one of those fields.
            // Two consequences beyond the names. The league is dealt from the front of
            // each region rather than popped off the back, so which franchise is which
            // team identifier changed; and a team no longer draws its identity, so the
            // league substream reaches the scheme draw in a different place — schemes
            // moved, and with them the roster each club was built for. From here a seed
            // moves the rosters, the strengths and the schemes, and nothing moves the
            // franchises ([decision 215](../../../../docs/design-decisions.md)).
            //
            // And all three once more in review of #69, which found real marks in eight
            // cells of that table: six stadium names that were a real arena, two real
            // bowl games, a demolished venue, an 1860s ballpark and a corporate sponsor,
            // and two abbreviations that are corporate marks holding real stadium naming
            // rights (rule 8, [ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md)).
            // Renamed, and nothing else about the identity touched. Every one of the
            // eight is a string the engine never reads — `GoldenSeedTests` did not move
            // — but the world checksum covers the identity, so it did.
            //
            // And all three once more in #82, which finished that identity: the league's
            // own name was still a per-seed draw from `StructurePools.leagueNames`, so
            // two careers opened in identically named clubs under differently named
            // leagues. It is now one line beside the table, `FranchiseSet.leagueName`,
            // and the checksum mixes `league.name` — so every curated world moved by
            // exactly that string and nothing else. The randomiser keeps its draw. Like
            // the renames above, the league's name is a string no snap reads:
            // `GoldenSeedTests` did not move, and the harness rows below its header are
            // byte-identical at seeds 7 and 11.
            //
            // And all three in #67, which changed how old a generated league is. The age
            // draw was clamped into 21...38, so every draw under twenty-one came back as
            // twenty-one; it is now redrawn, which is the same distribution truncated
            // rather than folded onto its own edge, and the centre for a reserve is floored
            // two seasons above the entry age instead of landing on it. Ages feed
            // `currentOverall`, so every rating in every world moved with them, and the
            // rejection loop draws a variable number of times from the roster stream, so
            // everything drawn after an age moved too. The checksum also mixes one new
            // field: whether a man has a first season at all, now that a prospect has none.
            //
            // And all three once more when every player came to carry every key. A rating
            // a position does not train — a tackle's throwing, a kicker's coverage — used
            // to be absent and is now present and low, drawn from
            // `PlayerGenerator.untrainedTable` on a substream split on the man's
            // identifier. The checksum mixes every key of every man, so every world moved,
            // and nothing else about anybody did: the untrained draws come from a stream
            // of their own, so every trained rating, build, name and hidden attribute is
            // byte-identical to what it was, and the league's own-position overall mean
            // and spread at seed 7 are unchanged to the last digit, which
            // `CrossPositionTests.ownPositionMomentsAreUnmoved` holds them to.
            //
            // And all three once more when a receiver and a tight end came to train ball
            // security. Carrying and break tackle are among the keys both positions draw
            // around their own quality now, where they were filled in from the untrained
            // table's ball-carrying row: the two draws moved from the identifier-split
            // untrained substream to the trained stream, so both positions' numbers moved
            // — carrying from 24.6 and 24.9 to 69.5 and 69.4 at seed 7 — and, because the
            // trained stream is shared with everything a player is built from after his
            // ratings, so did his build, his combine, his name, his college and every man
            // drawn after him. The checksum reads all of it, so all three worlds moved.
            (UInt64(1), UInt64(7_442_122_549_048_341_096)),
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
            //
            // And all three once more when `WorldGenerator.strengthSpread` stopped being
            // eight — a number with no source — and became the width the sport's own
            // between-club spread of point differential implies. Every club's offset is a
            // different number, so every roster is built to a different ceiling and every
            // man drawn after the first is a different man; the checksum reads all of it.
            // This is generation changing, not coverage widening: the leagues really are
            // different leagues. The width is 2.55 and not the 3.17 first computed, because
            // the floor and the slope it is solved from are properties of the engine and
            // the engine's run game changed underneath it — see the constant's own comment.
            (UInt64(5), UInt64(692_888_930_132_378_538)),
            (UInt64(7), UInt64(2_821_482_571_461_767_012)),
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
