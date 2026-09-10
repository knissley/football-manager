import FMCore
import Testing

@testable import FMSimulation

/// The record is versioned, and the concept it was called with is on it by value.
///
/// play-record.md said the stream was versioned from day one, and there was no version
/// field. `OffensiveCall.design` pointed into `CrudePlaybook`, an identifier space built
/// from `PlayFamily.rawValue + 1` that would dangle the day a real playbook existed — so
/// the M1 stream could not have been read by the M6 engine, and the contract that is
/// supposed not to move would have moved. Now a record says which version of the shape
/// it is, and what was called is a `PlayConcept` stored on the call, with the design's
/// identifier `nil` until a playbook exists to point into.
@Suite("The record's version and its concept")
struct SchemaAndConceptTests {

    private static let sample: [GameResult] = (UInt64(1)...20).map {
        TestWorld.game(seed: $0, game: GameID($0))
    }

    @Test("Every record carries the current schema version", .tags(.contract))
    func everyRecordIsVersioned() {
        #expect(PlayRecord.currentSchemaVersion == 1)
        for result in Self.sample {
            for play in result.plays {
                #expect(
                    play.schemaVersion == PlayRecord.currentSchemaVersion,
                    "play \(play.index) of game \(result.game) is version \(play.schemaVersion)")
            }
        }
    }

    /// The Done-when: no fake design identifiers appear in any record. Until M6 there is
    /// no playbook, so there is nothing a design identifier could honestly name.
    @Test("No record points at a design, because no playbook exists yet", .tags(.contract))
    func noRecordNamesADesign() {
        for result in Self.sample {
            for play in result.plays {
                #expect(
                    play.calls.offense.design == nil,
                    "play \(play.index) of game \(result.game) names design \(String(describing: play.calls.offense.design))"
                )
            }
        }
    }

    /// The concept is what was called, held by value, and the outcome is a play of that
    /// concept's kind unless a flag before the snap wiped it out. A called pass is a
    /// dropback, and a dropback ends as a pass, a sack or a scramble — the first form of
    /// this test asked for a pass and was red on every sack, which was the test's error
    /// and not the engine's.
    @Test("The concept on the record agrees with the outcome's kind", .tags(.contract))
    func conceptAgreesWithTheOutcome() {
        var concepts: Set<PlayConcept> = []
        for result in Self.sample {
            for play in result.plays {
                let concept = play.calls.offense.concept
                concepts.insert(concept)
                guard play.outcome.kind != .penaltyOnly else { continue }
                let agrees =
                    concept.kind == .pass
                    ? play.outcome.kind.isDropback
                    : play.outcome.kind == concept.kind
                #expect(
                    agrees, "play \(play.index): called \(concept), resolved \(play.outcome.kind)")
            }
        }
        #expect(
            concepts == Set(PlayConcept.allCases),
            "twenty games never called \(Set(PlayConcept.allCases).subtracting(concepts))")
    }
}
