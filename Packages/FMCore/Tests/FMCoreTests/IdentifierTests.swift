import Testing

@testable import FMCore

@Suite("Identifiers")
struct IdentifierTests {

    @Test("Identifiers wrap their raw value and compare by it")
    func rawValues() {
        #expect(PlayerID(7).rawValue == 7)
        #expect(PlayerID(1) < PlayerID(2))
        #expect(PlayerID(3) == PlayerID(3))
        #expect(PlayerID(3) != PlayerID(4))
    }

    @Test("Identifiers of the same raw value hash together")
    func hashing() {
        let ids: Set<PlayerID> = [PlayerID(1), PlayerID(1), PlayerID(2)]
        #expect(ids.count == 2)
    }

    @Test("Sorting is by raw value, which keeps iteration order stable")
    func sorting() {
        let sorted = [TeamID(5), TeamID(1), TeamID(3)].sorted()
        #expect(sorted.map(\.rawValue) == [1, 3, 5])
    }

    @Test("Sequences allocate in order starting at one")
    func allocation() {
        var sequence = IdentifierSequence<PlayerSubject>()
        #expect(sequence.allocate() == PlayerID(1))
        #expect(sequence.allocate() == PlayerID(2))
        #expect(sequence.allocate() == PlayerID(3))
        #expect(sequence.allocatedCount == 3)
    }

    @Test("Zero is never allocated, so it stays usable as a sentinel")
    func zeroReserved() {
        var sequence = IdentifierSequence<TeamSubject>()
        for _ in 0..<100 {
            #expect(sequence.allocate() != TeamID(0))
        }
    }

    @Test("The same allocation sequence reproduces the same identifiers")
    func deterministicAllocation() {
        var first = IdentifierSequence<PlayerSubject>()
        var second = IdentifierSequence<PlayerSubject>()
        let a = (0..<50).map { _ in first.allocate() }
        let b = (0..<50).map { _ in second.allocate() }
        #expect(a == b)
    }
}

@Suite("Positions")
struct PositionTests {

    @Test("Every position has exactly one side")
    func sides() {
        let offense = Position.allCases.filter { $0.side == .offense }
        let defense = Position.allCases.filter { $0.side == .defense }
        let special = Position.allCases.filter { $0.side == .specialTeams }
        #expect(offense.count + defense.count + special.count == Position.allCases.count)
        #expect(offense.count == 10)
        #expect(defense.count == 5)
        #expect(special.count == 3)
    }

    @Test("Exactly five positions are offensive line")
    func offensiveLine() {
        #expect(Position.allCases.filter(\.isOffensiveLine).count == 5)
    }

    @Test("Eligible receivers are the skill positions only")
    func eligibleReceivers() {
        let eligible = Set(Position.allCases.filter(\.isEligibleReceiver))
        #expect(eligible == [.runningBack, .fullback, .wideReceiver, .tightEnd])
    }

    @Test("Every position belongs to exactly one group, and groups round-trip")
    func groups() {
        for position in Position.allCases {
            #expect(position.group.positions.contains(position))
        }
        let grouped = PositionGroup.allCases.flatMap(\.positions)
        #expect(Set(grouped) == Set(Position.allCases))
        #expect(grouped.count == Position.allCases.count)
    }

    @Test("Quarterback is the most valuable position by a distance")
    func positionalValue() {
        let others = Position.allCases.filter { $0 != .quarterback }
        for position in others {
            #expect(position.positionalValue < Position.quarterback.positionalValue)
        }
        // Premium positions separate clearly from the interior and the backfield.
        #expect(Position.edge.positionalValue > Position.linebacker.positionalValue)
        #expect(Position.leftTackle.positionalValue > Position.leftGuard.positionalValue)
        #expect(Position.cornerback.positionalValue > Position.safety.positionalValue)
        #expect(Position.wideReceiver.positionalValue > Position.runningBack.positionalValue)
    }

    @Test("Raw values are stable, because saved players index by them")
    func stableRawValues() {
        #expect(Position.quarterback.rawValue == 0)
        #expect(Position.allCases.count == 18)
        #expect(Set(Position.allCases.map(\.rawValue)).count == 18)
    }
}
