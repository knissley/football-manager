import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// The read progression table, pinned.
///
/// Nothing in here is a claim about the sport: a read order is coaching design and the
/// reference has no article for it (C27, #169). What these pin is the table's own
/// arithmetic and the two anchoring rules the design was written to — so that a break
/// time drifting past the hold the family had, or a role named twice, fails here rather
/// than in a harness row three issues later.
@Suite("The read progression")
struct ReadProgressionTests {

    /// The five families, in the order they hold the ball.
    private static let families: [PlayConcept] = [
        .screen, .quickPass, .mediumPass, .playAction, .deepPass,
    ]

    /// The hold and the depth each family had before the table existed, as `routeDepth`
    /// held them: the fixed points both anchoring rules are measured against.
    private static let before: [PlayConcept: (hold: Int, depth: Int)] = [
        .screen: (1_400, -1), .quickPass: (1_700, 4), .mediumPass: (2_600, 10),
        .playAction: (3_000, 12), .deepPass: (3_400, 20),
    ]

    @Test(
        "pin: every pass family has an order and nothing else does, because a run with reads in it would be read",
        .tags(.pin))
    func onlyPassFamiliesHaveReads() {
        for concept in PlayConcept.allCases {
            let progression = ReadProgression.of(concept)
            let expectsReads = Self.families.contains(concept) || concept == .twoPointPass
            #expect(
                progression.reads.isEmpty == !expectsReads,
                "\(concept) has \(progression.reads.count) reads")
        }
    }

    @Test(
        "pin: no family names a role twice, and the checkdown is not one of the numbered reads",
        .tags(.pin))
    func rolesAreNamedOnce() {
        for concept in Self.families + [.twoPointPass] {
            let progression = ReadProgression.of(concept)
            let roles = progression.reads.map(\.role)
            #expect(Set(roles).count == roles.count, "\(concept) names a role twice")
            if let checkdown = progression.checkdown {
                #expect(!roles.contains(checkdown.role), "\(concept)'s checkdown is also a read")
            }
        }
    }

    /// The first anchoring rule: the ball can only come out earlier than it did.
    @Test(
        "pin: breaks are non-decreasing and the last is the hold the family had, so the ball never comes out later than before",
        .tags(.pin))
    func breaksAreOrderedAndAnchoredToTheOldHold() {
        for concept in Self.families {
            let progression = ReadProgression.of(concept)
            let breaks = progression.reads.map(\.breakMillis)
            #expect(breaks == breaks.sorted(), "\(concept)'s breaks run backwards: \(breaks)")
            #expect(
                progression.holdMillis == Self.before[concept]?.hold,
                "\(concept) holds \(progression.holdMillis)ms; it held \(Self.before[concept]?.hold ?? 0)"
            )
        }
    }

    /// The second anchoring rule: the family's depth is the first read's, so the yardage
    /// rows move for the reads that were added and not for the one that was there.
    @Test(
        "pin: the first read's depth is the depth the family had", .tags(.pin))
    func firstReadKeepsTheOldDepth() {
        for concept in Self.families {
            let first = ReadProgression.of(concept).reads.first?.depthYards
            #expect(
                first == Self.before[concept]?.depth,
                "\(concept)'s first read is \(first ?? 0) yards; the family was \(Self.before[concept]?.depth ?? 0)"
            )
        }
    }

    /// The pocket's arrival window starts at 1,000 ms and the shortest hold it was built
    /// to span is the screen's 1,400. A break under the screen's is a read no rusher can
    /// beat, which is the un-pressurable-by-construction failure
    /// `theArrivalWindowSpansTheRouteHolds` exists to catch; keeping every break at or
    /// above the screen's keeps that test's premise true of every read, not only the last.
    @Test("pin: no read breaks before the screen's 1,400 ms", .tags(.pin))
    func noBreakBeforeTheScreens() {
        let floor = ReadProgression.of(.screen).holdMillis
        for concept in Self.families + [.twoPointPass] {
            for read in ReadProgression.of(concept).reads {
                #expect(
                    read.breakMillis >= floor,
                    "\(concept) judges \(read.role) at \(read.breakMillis)ms, under the screen's \(floor)"
                )
            }
        }
    }

    @Test(
        "pin: the screen is one read and no checkdown; every other family checks down to the back",
        .tags(.pin))
    func theScreenIsTheBackAndNothingElse() {
        let screen = ReadProgression.of(.screen)
        #expect(screen.reads.count == 1 && screen.reads.first?.role == .back)
        #expect(screen.checkdown == nil)
        for concept in Self.families where concept != .screen {
            #expect(
                ReadProgression.of(concept).checkdown?.role == .back,
                "\(concept) has no checkdown to the back")
        }
    }

    @Test("pin: the try inherits the quick game's order", .tags(.pin))
    func theTryInheritsTheQuickOrder() {
        let quick = ReadProgression.of(.quickPass).reads.map(\.role)
        let tryOrder = ReadProgression.of(.twoPointPass).reads.map(\.role)
        #expect(quick == tryOrder)
    }

    /// The five pairs `routeDepth` held are the derivation's fixed points, so a family
    /// thrown to on its first read flies for exactly as long and is rated on exactly the
    /// accuracy it always was.
    @Test(
        "pin: flight and the accuracy key derived from depth reproduce the five pairs routeDepth held",
        .tags(.pin))
    func derivedFlightAndAccuracyKeepTheOldPairs() {
        let pairs: [(depth: Int, flight: Int, key: RatingKey)] = [
            (-1, 3, .throwAccuracyShort), (4, 4, .throwAccuracyShort),
            (10, 7, .throwAccuracyMedium), (12, 8, .throwAccuracyMedium),
            (20, 12, .throwAccuracyDeep),
        ]
        for pair in pairs {
            #expect(
                ReadProgression.flightTicks(forDepth: pair.depth) == pair.flight,
                "\(pair.depth) yards flies \(ReadProgression.flightTicks(forDepth: pair.depth)) ticks, not \(pair.flight)"
            )
            #expect(
                ReadProgression.accuracyKey(forDepth: pair.depth) == pair.key,
                "\(pair.depth) yards is rated on \(ReadProgression.accuracyKey(forDepth: pair.depth))"
            )
        }
        // Flight never falls as the ball goes deeper, and never drops under a screen's.
        var last = 0
        for depth in -5...40 {
            let flight = ReadProgression.flightTicks(forDepth: depth)
            #expect(flight >= 3 && flight >= last, "flight fell at \(depth) yards")
            last = flight
        }
    }

    /// Every grouping the caller sends out, against every family: a role nobody fills is
    /// skipped rather than resolved to an empty slot, the man a read names plays the
    /// position the role means, and an empty backfield has no checkdown.
    @Test(
        "contract: a read resolves to the man in the role or to nobody, in every grouping the caller uses",
        .tags(.contract))
    func rolesResolveAgainstEveryGrouping() {
        let groupings: [PersonnelGroup] = [
            .eleven, .twelve, .thirteen, .twentyOne, .twentyTwo, .ten, .empty,
        ]
        let context = TestWorld.context(seed: 12)
        var random = SplittableRandom(seed: 3)
        for grouping in groupings {
            let situation = Situation(
                quarter: 2, clockRemaining: 800, down: .first, distance: 10, ballOn: 65,
                possession: TeamID(1), scoreDifferential: 0, offensePersonnel: grouping,
                defensePackage: .nickel)
            for concept in Self.families {
                let lineup = Lineup.onField(
                    context, concept: concept, situation: situation, random: &random)
                let progression = ReadProgression.of(concept)
                let resolved = progression.resolvedReads(in: lineup)
                // Present roles resolve, absent ones are skipped, and the order closes up.
                let present = progression.reads.filter { $0.role.slot(in: lineup) != nil }
                #expect(
                    resolved.map(\.read) == present,
                    "\(concept) in \(grouping.code): the order did not close up")
                for entry in resolved {
                    #expect(
                        lineup[entry.receiver] != nil,
                        "\(concept) in \(grouping.code) read an empty slot")
                    let position = lineup.position(at: entry.receiver)
                    switch entry.read.role {
                    case .firstReceiver, .secondReceiver, .thirdReceiver:
                        #expect(position == .wideReceiver)
                    case .tightEnd:
                        #expect(position == .tightEnd)
                    case .back:
                        #expect(position == .runningBack || position == .fullback)
                    }
                }
                // Who is missing, by the grouping's own arithmetic.
                let receivers = Int(grouping.wideReceivers)
                let hasTightEnd = grouping.tightEnds > 0
                let hasBack = grouping.runningBacks > 0
                for read in progression.reads {
                    let expected: Bool
                    switch read.role {
                    case .firstReceiver: expected = receivers >= 1
                    case .secondReceiver: expected = receivers >= 2
                    case .thirdReceiver: expected = receivers >= 3
                    case .tightEnd: expected = hasTightEnd
                    case .back: expected = hasBack
                    }
                    #expect(
                        (read.role.slot(in: lineup) != nil) == expected,
                        "\(concept) in \(grouping.code): \(read.role) resolved \(read.role.slot(in: lineup) != nil ? "to somebody" : "to nobody")"
                    )
                }
                if let checkdown = progression.resolvedCheckdown(in: lineup) {
                    #expect(
                        hasBack,
                        "\(concept) in \(grouping.code) checked down with no back on the field")
                    #expect(lineup[checkdown.receiver] != nil)
                } else if progression.checkdown != nil {
                    #expect(!hasBack, "\(concept) in \(grouping.code) has a back and no checkdown")
                }
            }
        }
    }
}
