import FMCore
import Testing

@testable import FMSimulation

/// The same seed must produce the same game — in a different process, on a different day,
/// after a rebuild.
///
/// Every determinism test in this repo used to compare two runs *inside one process*, and
/// that is exactly the check a hash-order bug walks through: Swift randomises its hash
/// seed per process, so two runs in one process agree with each other and disagree with
/// yesterday's. `SchemeFit.effectiveOverall` summed its weights while iterating a
/// dictionary, floating-point addition is not associative, and the sum was rounded to a
/// whole overall point — so a player near a boundary was a point better in one process and
/// a point worse in the next, and the same seed produced a different season.
///
/// A checked-in constant is the only form of this test that can fail for that reason,
/// which is why the number below is written down rather than computed twice.
/// ([ADR-0003](../../../../docs/adr/0003-deterministic-seeded-simulation.md))
///
/// The game is built by `TestWorld`, which is
/// `WorldGenerator.generate(seed:shape:franchises:season:)` — so this pins the whole path
/// from seed to final whistle, world generation included, and not merely the engine's
/// half of it.
@Suite("Golden seed")
struct GoldenSeedTests {

    /// FNV-1a. Deliberately *not* `Hasher`, whose seed is randomised per process — using
    /// it here would make this test unable to detect the thing it exists to detect.
    private struct Checksum {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func mix(_ number: UInt64) {
            for shift in stride(from: 0, through: 56, by: 8) {
                value ^= UInt64((number >> UInt64(shift)) & 0xff)
                value = value &* 0x100_0000_01b3
            }
        }

        mutating func mix(_ number: some BinaryInteger) { mix(UInt64(bitPattern: Int64(number))) }
    }

    private func checksum(seed: UInt64) -> UInt64 {
        let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
            .simulate(TestWorld.setup(seed: seed))
        var sum = Checksum()
        sum.mix(result.homeScore)
        sum.mix(result.awayScore)
        sum.mix(result.plays.count)
        for play in result.plays {
            sum.mix(play.schemaVersion)
            sum.mix(play.calls.offense.concept.rawValue)
            sum.mix(play.situation.ballOn)
            sum.mix(play.situation.distance)
            sum.mix(play.situation.down.rawValue)
            sum.mix(play.situation.offensePersonnel.code)
            sum.mix(play.situation.defensePackage.rawValue)
            sum.mix(play.outcome.kind.rawValue)
            sum.mix(play.outcome.endedIn.rawValue)
            sum.mix(play.outcome.yards)
            sum.mix(play.outcome.clockRunoff)
            sum.mix(play.outcome.finalSpot ?? 200)
            sum.mix(play.outcome.passResult?.rawValue ?? 200)
            sum.mix(play.outcome.pointsScored)
            for entry in play.onField { sum.mix(entry) }
            for participant in play.outcome.participants {
                sum.mix(participant.player.rawValue)
                sum.mix(participant.role.rawValue)
                sum.mix(participant.slot.rawValue)
            }
            for decision in play.decisions {
                sum.mix(decision.kind.rawValue)
                sum.mix(decision.value)
                sum.mix(decision.tick)
            }
        }
        for injury in result.injuries {
            sum.mix(injury.player.rawValue)
            sum.mix(injury.gamesOut)
            sum.mix(injury.occurredOn.index)
        }
        return sum.value
    }

    /// Regenerating these to make a red test pass is forbidden: if the engine changed on
    /// purpose, they are regenerated in the same commit and the behaviour change is
    /// described in the message. If it did not, the engine is non-deterministic and that
    /// is the bug.
    @Test(
        "A seed produces the same game in every process", .tags(.contract),
        arguments: [
            // Moved by #69, and by the world rather than by the engine: nothing in
            // `FMSimulation` changed. `TestWorld` is `WorldGenerator.generate`, so the
            // eight clubs it plays between are now `FranchiseSet`'s curated ones
            // ([decision 215](../../../../docs/design-decisions.md)). Three things the
            // engine reads moved with them — the ground the game is played in (roof,
            // surface, noise and altitude are curated now, and the home side's stadium
            // is the one this game is played in), the schemes, which are still drawn but
            // from a league substream that no longer spends draws on identities, and
            // therefore the rosters, because a roster is built for the scheme its club
            // inherited. A game between two different clubs in a different building is a
            // different game.
            //
            // And moved again by #67, again by the world and not by the engine: nothing in
            // `FMSimulation` changed. The age a generated player is drawn at was clamped
            // into 21...38 and is now redrawn when it falls outside, and a reserve's centre
            // is floored two seasons above the entry age rather than landing on it. Age is
            // what `PlayerGenerator.currentOverall` measures a man's progress toward his
            // ceiling along, so every rating on both rosters moved — an older league is a
            // slightly better one — and a game between two rosters of different players is
            // a different game.
            //
            // And moved by the record rather than by the game: the twenty-two roster
            // indices of `PlayRecord.onField` are mixed in from here on, so the same
            // three games hash differently. Nothing a play produced changed — the lineup
            // is drawn by the simulator immediately before the snap is resolved, where
            // the resolver used to draw it, so every stream is spent in the same order —
            // and `Tools/gamelog` prints the same game before and after.
            //
            // And by the record again: `Outcome.passResult` and `Outcome.pointsScored`
            // are mixed in from here on. A resolver writes the first and the game the
            // second, neither reads either, and no play produced anything different;
            // `Tools/gamelog` prints the same game before and after.
            //
            // And by the record a third time: `PlayRecord.schemaVersion`, which is 1,
            // and the concept the offence called, now held by value as
            // `OffensiveCall.concept` rather than pointed at through a stand-in design
            // identifier, are mixed in from here on. The concept was always on the
            // record — the identifier was its raw value plus one — so this is the same
            // fact hashed under a different name, and nothing a play produced changed;
            // `Tools/gamelog` prints the same game before and after.
            //
            // And moved by the play clock, this time by the engine. Every play now records
            // the play clock it was snapped against (2025 rulebook, 4-6) as a decision
            // point, and the checksum mixes every decision point, so every checksum moves
            // for that reason alone. The football moved less: a delay of game is now the
            // play clock expiring — drawn against the slack the tempo leaves on the clock
            // in force rather than at a flat rate — so a snap on the twenty-five after a
            // change of possession is a little likelier to be one, a flag that flies costs
            // the whole play clock rather than the huddle, and a huddle after a runoff or a
            // penalty enforcement is charged against the thirty or the twenty-five it was
            // really taken against.
            //
            // The play clock and the record changes met in a merge, and the constants
            // below are the union: the play clock's games, hashed with the record's
            // schema version, concept, presence, pass result and points mixed in. Neither
            // side's constants could survive, because each was computed without the
            // other's mechanism; `Tools/gamelog` prints the play clock's game before and
            // after the merge.
            //
            // And by the record a fourth time: what happened while the ball was dead
            // before a snap — a charged timeout with the side that took it, the
            // two-minute warning — is a rules-layer decision point on the next snap's
            // record, and the checksum mixes every decision point. Where a kick was
            // fielded and where possession was lost went on the record with it, but
            // neither is hashed. Nothing a play produced changed: the same timeouts are
            // spent at the same moments and the clock runs as it did, and `Tools/gamelog`
            // prints the same plays before and after, with the dead ball now written
            // above them and a kick's gross and return beside it.
            //
            // And moved again when every player came to carry every key — by the world,
            // and by what the engine reads of it. Nothing in the rules layer changed, but a
            // rating a position does not train is now present and low rather than absent,
            // so the resolver's fallback for an absent key — the player's overall — has
            // nothing left to fall back from. A receiver breaks tackles and holds the ball
            // on his own breakTackle and carrying instead of his overall, a corner strips
            // on his own hit power, a back in 21 personnel runs his route on his own route
            // running, a lineman covering a kick pursues on his own pursuit. Each of those
            // was a number in the sixties or seventies that is now in the twenties or
            // thirties, so a game between the same men is a different game. The men
            // themselves did not move: every trained rating is byte-identical.
            //
            // The constants below are every mechanism above together, regenerated on the
            // merged tree: the play clock on every play, the dead ball before it, the
            // record's own fields, and the untrained keys on every man. No subset of them
            // reproduces these numbers.
            (UInt64(1), UInt64(3_356_912_127_761_341_806)),
            (UInt64(5), UInt64(5_553_166_993_840_887_049)),
            (UInt64(12), UInt64(3_965_614_626_697_509_682)),
        ])
    func goldenChecksums(seed: UInt64, expected: UInt64) {
        #expect(checksum(seed: seed) == expected)
    }
}
