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

    /// The standard corpus, whose size is derived where it is defined.
    ///
    /// **It used to be twenty, and twenty was too few for the one thing here that has to
    /// occur.** `conceptAgreesWithTheOutcome` below requires every concept in the book to
    /// have been called, and the thinnest of them is a two-point run at a quarter of a
    /// game: twenty games expect five and miss altogether about seven times in a
    /// thousand, with the two-point pass and the onside kick not far behind at 0.28 each.
    /// Forty expect ten and miss about five times in a hundred thousand. The other two
    /// tests are promises about every record in the sample and hold at any size.
    private static let sample: [GameResult] = TestWorld.corpus

    /// The literal is here so the version cannot move by accident: a bump is a deliberate
    /// act and this is what makes it one. It reads 2 since a coverage assignment began
    /// carrying the separation the matchup produced, which in a version-1 record is zero
    /// on every one of them.
    @Test("Every record carries the current schema version", .tags(.contract))
    func everyRecordIsVersioned() {
        #expect(PlayRecord.currentSchemaVersion == 2)
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

    /// How many snaps of each concept the sweep below resolves.
    ///
    /// Four hundred is enough to walk every exit of a concept that has a handful of
    /// them. A two-point try gets five times that because its rarest exit is the one
    /// this suite could not see: measured on the resolver, the defence intercepts
    /// **3.2%** of two-point tries (127 of 4,000 at seed 88), so four hundred would
    /// expect about thirteen and two thousand expects about sixty-three — a margin wide
    /// enough that the coverage assertion below is a guard rather than a coin flip. The
    /// game-level sample cannot reach this at all: a try is called in about a quarter of
    /// games and 3.2% of those is one intercepted try per sixty-odd games, which is why
    /// twenty games saw none.
    private static func sweepSize(_ concept: PlayConcept) -> Int {
        concept.kind == .twoPointConversion ? 2_000 : 400
    }

    /// The concept↔kind contract, over the resolver's own exits rather than over
    /// whatever a handful of games happened to call.
    ///
    /// `conceptAgreesWithTheOutcome` below asserts the same promise on real games, and
    /// it **passed for as long as it did because of which twenty games it drew**: an
    /// intercepted two-point try came back labelled an ordinary pass, and twenty games
    /// contained none. A sample that has to contain a rare ending is the wrong shape of
    /// test when the rare ending is one snap in a few hundred; resolving the snap itself,
    /// thousands of times, reaches every exit in a couple of seconds and can say what it
    /// reached.
    @Test(
        "Every exit of every concept returns a kind the concept promised", .tags(.contract))
    func everyExitAgreesWithTheConcept() {
        for concept in PlayConcept.allCases {
            let resolutions = TestWorld.resolved(concept, count: Self.sweepSize(concept))
            var endings: Set<PlayEnding> = []
            for resolution in resolutions {
                let kind = resolution.outcome.kind
                guard kind != .penaltyOnly else { continue }
                endings.insert(resolution.outcome.endedIn)
                let agrees = concept.kind == .pass ? kind.isDropback : kind == concept.kind
                #expect(
                    agrees,
                    "\(concept) resolved \(kind), ending \(resolution.outcome.endedIn)")
            }
            #expect(endings.isEmpty == false, "\(concept) never resolved to a play at all")
        }
    }

    /// The rare ending the sweep exists for, asserted separately so that a sweep which
    /// stopped reaching it fails loudly rather than passing on the endings it still has.
    ///
    /// A try the defence takes away is the try (2025 rulebook, 11-3-1, 11-3-2-e), so the
    /// record has to say the play was a two-point try — a box score, a grade or a
    /// tendency query summing `PlayKind == .twoPointConversion` is the only thing that
    /// will ever ask, and under ADR-0007 the stream is the whole of what it can ask.
    @Test(
        "The two-point sweep reaches the interception, and it is recorded as a two-point try",
        .tags(.contract))
    func theTwoPointSweepReachesTheInterception() {
        let resolutions = TestWorld.resolved(
            .twoPointPass, count: Self.sweepSize(.twoPointPass))
        let picks = resolutions.filter { $0.outcome.endedIn == .intercepted }
        #expect(
            picks.count >= 20,
            "\(picks.count) intercepted two-point tries in \(resolutions.count): the sweep no longer reaches the ending it exists for"
        )
        for pick in picks {
            #expect(
                pick.outcome.kind == .twoPointConversion,
                "an intercepted two-point try was recorded as \(pick.outcome.kind)")
            #expect(
                pick.outcome.passResult == .intercepted,
                "an intercepted two-point try has no pass result")
        }
    }

    /// The concept is what was called, held by value, and the outcome is a play of that
    /// concept's kind unless a flag before the snap wiped it out. A called pass is a
    /// dropback, and a dropback ends as a pass, a sack or a scramble — the first form of
    /// this test asked for a pass and was red on every sack, which was the test's error
    /// and not the engine's.
    ///
    /// A corpus of games is a sample of what a *caller* calls, and it is kept for that:
    /// it is the only check here that the concepts a game reaches are the concepts the
    /// record carries. It is not a sample of what a *resolver* returns, and it never was —
    /// the exhaustive form of this promise is `everyExitAgreesWithTheConcept` above, which
    /// walks the exits instead of hoping to draw them.
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
            "forty games never called \(Set(PlayConcept.allCases).subtracting(concepts))")
    }
}
