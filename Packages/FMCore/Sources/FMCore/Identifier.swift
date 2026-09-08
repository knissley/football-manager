/// A typed identifier.
///
/// The phantom `Subject` parameter means a `TeamID` cannot be passed where a
/// `PlayerID` is expected, which is the entire point — raw integers in a domain
/// this size get transposed eventually, and the compiler is better at noticing
/// than any of us.
///
/// Backed by `UInt64` and allocated from a counter in the world, never a `UUID`.
/// UUIDs draw on system randomness and a clock, both of which are banned in the
/// simulation because they would break replay (ADR-0003).
public struct Identifier<Subject>: Hashable, Sendable, Comparable, Codable {

    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension Identifier: CustomStringConvertible {
    public var description: String {
        "\(Subject.self)#\(rawValue)"
    }
}

// Uninhabited tag types. They exist only to distinguish identifier types at
// compile time and are never instantiated.
public enum PlayerSubject {}
public enum TeamSubject {}
public enum LeagueSubject {}
public enum ConferenceSubject {}
public enum DivisionSubject {}
public enum GameSubject {}
public enum PlaySubject {}
public enum ContractSubject {}
public enum StaffSubject {}
public enum AgentSubject {}
public enum ScoutSubject {}
public enum TraitSubject {}
public enum CareerSubject {}
public enum SeasonSubject {}
public enum DraftPickSubject {}

public typealias PlayerID = Identifier<PlayerSubject>
public typealias TeamID = Identifier<TeamSubject>
public typealias LeagueID = Identifier<LeagueSubject>
public typealias ConferenceID = Identifier<ConferenceSubject>
public typealias DivisionID = Identifier<DivisionSubject>
public typealias GameID = Identifier<GameSubject>
public typealias PlayID = Identifier<PlaySubject>
public typealias ContractID = Identifier<ContractSubject>
public typealias StaffID = Identifier<StaffSubject>
public typealias AgentID = Identifier<AgentSubject>
public typealias ScoutID = Identifier<ScoutSubject>
public typealias TraitID = Identifier<TraitSubject>
public typealias CareerID = Identifier<CareerSubject>
public typealias SeasonID = Identifier<SeasonSubject>
public typealias DraftPickID = Identifier<DraftPickSubject>

/// Hands out identifiers in order.
///
/// Deterministic by construction: the same sequence of allocations always
/// produces the same identifiers, which is what lets a world be regenerated from
/// its seed and compare equal.
public struct IdentifierSequence<Subject>: Sendable {

    private var next: UInt64

    public init(startingAt first: UInt64 = 1) {
        next = first
    }

    /// The next identifier. Starts at 1, so 0 is available as a sentinel.
    public mutating func allocate() -> Identifier<Subject> {
        defer { next &+= 1 }
        return Identifier<Subject>(next)
    }

    /// How many identifiers have been handed out.
    public var allocatedCount: UInt64 {
        next - 1
    }
}
