import FMCore
import Testing

@testable import FMSimulation

/// Every `DecisionKind`, swept against the contract its own doc comment states.
///
/// The sweep exists because the contract used to be a doc comment and nothing else. A
/// producer that wanted one more byte than its kind described could take it — `detail` and
/// `value` are eight and sixteen bits of anything — and four kinds had, each in a way no
/// build and no test could see: a pocket verdict carrying a block result the enum never
/// mentioned, a catch attempt carrying the separation a reader had to guess the unit of, a
/// block result carrying the milliseconds its own factory had no parameter for. Every one
/// of them was found by reading the enum beside its producers, which is a thing that
/// happens once and then stops happening.
///
/// Two promises, and between them they are the mechanism rather than the list:
///
/// 1. **Every point is reproducible through its kind's factory from the fields the kind
///    documents.** A factory that cannot express what a point carries is a contract the
///    record has already outgrown, and a point the factory reproduces differently is a
///    field somebody set behind the contract's back.
/// 2. **Every point's slots, `detail` and `value` mean what the kind says they mean** —
///    the actor first, the man opposite second or nobody, a `detail` that decodes to a
///    real case, and a `value` in the one unit the kind names.
///
/// The `switch` is exhaustive with no `default` on purpose: a kind added to the enum
/// without a factory arm here is a compile error, which is the only form of this check
/// that survives the next kind.
@Suite("The decision point contract")
struct DecisionContractTests {

    /// Rebuild a point through the factory for its kind, passing only the fields that
    /// kind's doc comment says it carries. `nil` where a `detail` byte decodes to no case
    /// of the enum it is documented as holding, which is its own failure and reported as
    /// one.
    private static func throughItsFactory(_ point: DecisionPoint) -> DecisionPoint? {
        switch point.kind {
        case .pressureAllowed:
            return .pressureAllowed(
                tick: point.tick, blocker: point.primary, rusher: point.secondary,
                afterMilliseconds: point.value)
        case .pressureHeld:
            guard let rep = point.pocketRepResult else { return nil }
            return .pressureHeld(
                tick: point.tick, blocker: point.primary, rusher: point.secondary,
                forMilliseconds: point.value, closestRep: rep)
        case .readProgression:
            return .readProgression(
                tick: point.tick, passer: point.primary, receiver: point.secondary,
                index: point.detail, separationCentimetres: point.value)
        case .throwDecision:
            guard let decision = point.throwDecisionValue else { return nil }
            return .throwDecision(
                tick: point.tick, passer: point.primary, oppositeNumber: point.secondary,
                decision: decision, atMilliseconds: point.value)
        case .ballArrival:
            guard let placement = point.ballPlacement else { return nil }
            return .ballArrival(
                tick: point.tick, receiver: point.primary, defender: point.secondary,
                placement: placement, separationCentimetres: point.value)
        case .catchAttempt:
            guard let result = point.catchResult else { return nil }
            return .catchAttempt(
                tick: point.tick, receiver: point.primary, defender: point.secondary,
                result: result, separationCentimetres: point.value)
        case .tackleAttempt:
            guard let result = point.tackleResult else { return nil }
            return .tackleAttempt(
                tick: point.tick, defender: point.primary, carrier: point.secondary,
                result: result)
        case .blockResult:
            guard let result = point.blockResultValue else { return nil }
            return .blockResult(
                tick: point.tick, blocker: point.primary, defender: point.secondary,
                result: result, atMilliseconds: point.value)
        case .holeQuality:
            guard let insideRun = point.holeWasInsideRun else { return nil }
            return .holeQuality(
                tick: point.tick, back: point.primary, insideRun: insideRun, quality: point.value)
        case .coverageAssignment:
            guard let technique = point.coverageTechnique else { return nil }
            return .coverageAssignment(
                tick: point.tick, defender: point.primary, receiver: point.secondary,
                technique: technique, separationCentimetres: point.value)
        case .playClock:
            guard let reading = point.playClockReading else { return nil }
            return .playClock(seconds: reading.seconds, remaining: reading.remaining)
        case .clockElection:
            guard let election = point.clockElectionValue else { return nil }
            return .clockElection(election)
        case .timeout:
            guard let byOffense = point.timeoutByOffense else { return nil }
            return .timeout(byOffense: byOffense)
        case .twoMinuteWarning:
            return .twoMinuteWarning
        case .returnLane:
            return .returnLane(tick: point.tick, returner: point.primary, yards: point.value)
        case .catchInSpace:
            return .catchInSpace(
                tick: point.tick, receiver: point.primary, separationCentimetres: point.value)
        case .coinToss:
            guard let wonByTheKicker = point.coinTossWonByTheSideKickingOff else { return nil }
            return .coinToss(wonByTheSideKickingOff: wonByTheKicker)
        case .tossElectionByTheWinner:
            guard let election = point.tossElectionByTheWinner else { return nil }
            return .tossElection(byTheWinner: election)
        case .tossElectionByTheLoser:
            guard let election = point.tossElectionByTheLoser else { return nil }
            return .tossElection(byTheLoser: election)
        }
    }

    /// The first promise: no point in the corpus carries anything its kind's factory
    /// cannot express, and none carries it differently from what the factory would write.
    ///
    /// A mismatch is the drift itself, caught at the byte: the producer put something on
    /// the record that the contract does not describe, so nothing downstream can read it
    /// and nothing upstream can stop it.
    @Test(
        "contract: every decision point is reproducible through its kind's factory",
        .tags(.contract))
    func everyDecisionPointIsReproducibleThroughItsFactory() {
        var seen: Set<DecisionKind> = []
        for result in TestWorld.corpus {
            for play in result.plays {
                for point in play.decisions {
                    seen.insert(point.kind)
                    let at = "a \(point.kind) on play \(play.index) of game \(result.game)"
                    guard let rebuilt = Self.throughItsFactory(point) else {
                        Issue.record("\(at): detail byte \(point.detail) decodes to no case")
                        continue
                    }
                    let wrote = "detail \(point.detail), value \(point.value)"
                    let factory = "detail \(rebuilt.detail), value \(rebuilt.value)"
                    #expect(
                        rebuilt == point,
                        "\(at): the producer wrote \(wrote) where the factory writes \(factory)")
                }
            }
        }
        #expect(
            seen == Set(DecisionKind.allCases),
            "the corpus never produced \(Set(DecisionKind.allCases).subtracting(seen))")
    }

    /// The second promise: the slots, the `detail` and the unit of `value` are what the
    /// kind says they are.
    ///
    /// `primary` is the man whose act the point records on every kind that names a man,
    /// and `secondary` is the man on the other side of it or nobody at all — the rule the
    /// enum states once and every case keeps, so a query reading `primary` for the actor
    /// never has to ask which kind it holds. A kind that names no man leaves both empty:
    /// the play clock and the two-minute warning are the rules' and not a player's.
    @Test(
        "contract: every decision point's slots and units are its kind's", .tags(.contract))
    func everyDecisionPointsSlotsAndUnitsAreItsKinds() {
        for result in TestWorld.corpus {
            for play in result.plays {
                for point in play.decisions {
                    let at = "a \(point.kind) on play \(play.index) of game \(result.game)"
                    switch point.kind {
                    // The kinds that name two men.
                    case .pressureAllowed, .pressureHeld, .readProgression, .ballArrival,
                        .catchAttempt, .tackleAttempt, .blockResult, .coverageAssignment:
                        // Both men, and not which side either is on: a slot is a place in
                        // this play's formation, so on a kick return the coverage unit
                        // occupies the offence's slots and a tackle attempt names two of
                        // them.
                        #expect(!point.primary.isNone, "\(at): no actor")
                        #expect(!point.secondary.isNone, "\(at): no man opposite")
                    // The one kind whose second man depends on its detail, and which
                    // names nobody on a throwaway; the pairing itself is
                    // `throwDecisionsNameTheManTheDecisionWasAbout`.
                    case .throwDecision:
                        #expect(!point.primary.isNone, "\(at): no passer")
                    // The kinds that record space rather than a matchup.
                    case .holeQuality, .returnLane, .catchInSpace:
                        #expect(!point.primary.isNone, "\(at): no actor")
                        #expect(
                            point.secondary.isNone,
                            "\(at): names slot \(point.secondary.rawValue) opposite space")
                    // The rules layer's, where there is no player to name. The toss and
                    // its elections are a captain's rather than a player's, and a
                    // captain is not a slot in a formation: the side they name is the
                    // side in possession at the kick, or the other.
                    case .playClock, .clockElection, .timeout, .twoMinuteWarning, .coinToss,
                        .tossElectionByTheWinner, .tossElectionByTheLoser:
                        #expect(point.primary.isNone, "\(at): the rules named a player")
                        #expect(point.secondary.isNone, "\(at): the rules named a player")
                    }

                    switch point.kind {
                    // Milliseconds from the snap, and `tick` is the same moment divided
                    // down — so a value left at its filler, or in any other unit,
                    // separates the two.
                    case .pressureAllowed, .pressureHeld, .throwDecision:
                        #expect(point.value > 0, "\(at): no moment recorded")
                        #expect(
                            Int(point.tick) == Int(point.value) / 100,
                            "\(at): tick \(point.tick) is not millisecond \(point.value)")
                    // Centimetres of separation, which is a distance and never negative.
                    case .readProgression, .ballArrival, .catchAttempt, .coverageAssignment,
                        .catchInSpace:
                        #expect(point.value >= 0, "\(at): separation \(point.value)")
                    // A carry's quality score, on the scale that pays twelve a block.
                    case .holeQuality:
                        #expect(
                            point.value > -200 && point.value < 200,
                            "\(at): \(point.value) is off the twelve-a-block scale")
                    // Yards of return, which cannot exceed the field. The floor is below
                    // zero because a lane can be: a returner met at the catch is on for
                    // less than nothing, and a few yards is as far back as that goes.
                    case .returnLane:
                        #expect(
                            point.value > -20 && point.value <= 100,
                            "\(at): a lane of \(point.value) yards")
                    // Milliseconds on a dropback, where the rep is against the pocket's
                    // clock; a run's rep resolves at the handoff and carries no moment.
                    case .blockResult:
                        #expect(
                            point.value >= 0, "\(at): a rep that lasted \(point.value)")
                    // The seconds the play clock read at the snap, against the clock in
                    // force; zero is the delay of game (2025 rulebook, 4-6-1, 4-6-4).
                    case .playClock:
                        guard let reading = point.playClockReading else {
                            Issue.record("\(at): reads as no play clock at all")
                            continue
                        }
                        #expect(
                            reading.seconds == 40 || reading.seconds == 30
                                || reading.seconds == 25,
                            "\(at): a play clock of \(reading.seconds) seconds")
                        #expect(
                            reading.remaining <= reading.seconds,
                            "\(at): \(reading.remaining) left of \(reading.seconds)")
                    // Kinds whose whole content is the discriminant: a value on one is a
                    // byte no reader has been told how to read.
                    case .tackleAttempt, .clockElection, .timeout, .twoMinuteWarning, .coinToss,
                        .tossElectionByTheWinner, .tossElectionByTheLoser:
                        #expect(point.value == 0, "\(at): carries a value of \(point.value)")
                    }

                    // The deferral is the winner's alone (2025 rulebook, 4-2-2): the
                    // loser is given the other privilege, never the choice the winner
                    // declined to make. Nothing in the byte says so — `detail` decodes
                    // the same enum on both kinds — so it is asserted where the rest of
                    // each kind's contract is.
                    if point.kind == .tossElectionByTheLoser {
                        #expect(
                            point.tossElectionByTheLoser != .deferred,
                            "\(at): the captain who lost the toss deferred")
                    }
                }
            }
        }
    }
}
