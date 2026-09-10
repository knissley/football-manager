import FMCore
import FMGeneration
import Testing

@testable import simharness

/// The world the calibration run is played in, and the line that names it.
///
/// `scripts/harness-reach.sh` reads that line out of two builds and, when the numbers
/// agree and no engine source moved, reports that a change cannot reach the harness — so
/// a reviewer skips four hundred games twice at two seeds on the strength of it. These
/// are the promises that makes honest.
@Suite("Harness world")
struct HarnessWorldTests {

    private func hexDigits(of line: String) -> Substring? {
        let prefix = "world checksum "
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count)
    }

    /// Tautological only while the implementation stays one line, which is the point: the
    /// harness must not grow a checksum of its own. The number in its header is
    /// `FMGeneration`'s `WorldChecksum` — the function `GoldenWorldTests` pins to a
    /// checked-in constant — applied to the world the games are played in, and nothing
    /// else. A private copy here would drift from the golden silently and take the reach
    /// script with it.
    @Test("contract: the header's number is FMGeneration's checksum of the world played in")
    func theLineCarriesTheSharedChecksum() throws {
        let world = try HarnessWorld.generate(seed: 7).get()
        let expected = WorldChecksum.hex(WorldChecksum.of(world))
        #expect(hexDigits(of: HarnessWorld.checksumLine(for: world)) == expected[...])
    }

    @Test("contract: the line is the shape scripts/harness-reach.sh parses")
    func theLineIsParseable() throws {
        let world = try HarnessWorld.generate(seed: 7).get()
        let line = HarnessWorld.checksumLine(for: world)
        let digits = try #require(hexDigits(of: line))
        #expect(digits.count == 16)
        #expect(digits.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!line.contains("\n"))
        // The script takes the third whitespace-separated field, so the two words before
        // it are load-bearing.
        #expect(line.split(separator: " ").count == 3)
    }

    @Test("contract: a seed names one league, and two seeds do not name the same one")
    func seedsAreDistinguished() throws {
        let seven = try HarnessWorld.generate(seed: 7).get()
        let sevenAgain = try HarnessWorld.generate(seed: 7).get()
        let eleven = try HarnessWorld.generate(seed: 11).get()
        #expect(HarnessWorld.checksumLine(for: seven) == HarnessWorld.checksumLine(for: sevenAgain))
        #expect(HarnessWorld.checksumLine(for: seven) != HarnessWorld.checksumLine(for: eleven))
    }

    /// The case the reach script exists for. Rivalry generation was a hundred lines that
    /// no calibration row could see (#64), and the reason it could not is here: the
    /// harness never generates one.
    @Test("contract: the harness world holds no draft pipeline and no rivalries")
    func optionalPartsAreAbsent() throws {
        let world = try HarnessWorld.generate(seed: 7).get()
        #expect(world.draftPipeline.isEmpty)
        #expect(world.rivalries.isEmpty)
        #expect(!world.teams.isEmpty)
        #expect(!world.roster(of: world.teams[0].id).isEmpty)
    }
}
