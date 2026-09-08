public enum DefensiveCallSubject {}
public typealias DefensiveCallID = Identifier<DefensiveCallSubject>

/// A player's position within a single play, 0..<22.
///
/// Decision points reference slots rather than `PlayerID`s. A slot is one byte
/// where an identifier is eight, which is what keeps a decision point at eight
/// bytes and a play record at roughly a hundred and thirty. `Outcome.participants`
/// maps slots back to players.
///
/// It also mirrors how the engine works: flat arrays indexed by slot, which is
/// what the tick-loop budget requires.
public struct PlayerSlot: Sendable, Hashable, Codable, Comparable {

    public static let none = PlayerSlot(rawValue: 255)
    public static let count = 22

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(_ index: Int) {
        precondition(index >= 0 && index < Self.count, "slot out of range")
        rawValue = UInt8(index)
    }

    public var isNone: Bool { rawValue == Self.none.rawValue }

    /// Slots 0...10 are the offence and 11...21 the defence.
    ///
    /// Fixing the convention here means a participation record does not have to
    /// store a `TeamID` it can derive, which matters: participants dominate the
    /// size of a play record.
    public var isOffense: Bool { rawValue < 11 }

    public static func < (lhs: PlayerSlot, rhs: PlayerSlot) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kind of observable moment a decision point records.
///
/// Every case is something a very good film-study analyst could determine. The
/// engine's own internals — which trait moved which threshold, what the
/// underlying rolls were — are deliberately absent: if they were recorded here
/// every observer would see them and per-observer trait discovery would collapse
/// (see docs/play-record.md).
public enum DecisionKind: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// A blocker lost. `value` is milliseconds from the snap.
    case pressureAllowed = 0
    /// A blocker held through the play. `value` is milliseconds sustained.
    case pressureHeld = 1
    /// The quarterback worked to a read. `detail` is the progression index,
    /// `value` is the receiver's separation in centimetres.
    case readProgression = 2
    /// What the quarterback did with the ball. `detail` is a `ThrowDecision`.
    case throwDecision = 3
    /// The ball reached the receiver. `value` is separation in centimetres,
    /// `detail` is a `BallPlacement`.
    case ballArrival = 4
    /// A catch was attempted. `detail` is a `CatchResult`.
    case catchAttempt = 5
    /// A tackle was attempted. `detail` is a `TackleResult`.
    case tackleAttempt = 6
    /// A block resolved. `detail` is a `BlockResult`.
    case blockResult = 7
    /// A running lane opened or did not. `detail` is the gap, `value` is a
    /// quality score.
    case holeQuality = 8
    /// A defender's assignment. `detail` is a `CoverageTechnique`.
    case coverageAssignment = 9
}

public enum ThrowDecision: UInt8, Sendable, Hashable, Codable {
    case primary = 0
    case checkdown = 1
    case throwaway = 2
    case scramble = 3
    case sack = 4
}

public enum BallPlacement: UInt8, Sendable, Hashable, Codable {
    case onTarget = 0
    case slightlyOff = 1
    case poor = 2
    case uncatchable = 3
}

public enum CatchResult: UInt8, Sendable, Hashable, Codable {
    case caught = 0
    case contestedCatch = 1
    case dropped = 2
    case brokenUp = 3
    case intercepted = 4
    case uncatchable = 5
}

public enum TackleResult: UInt8, Sendable, Hashable, Codable {
    case madeTackle = 0
    case assisted = 1
    case broken = 2
    case missed = 3
    case forcedFumble = 4
}

public enum BlockResult: UInt8, Sendable, Hashable, Codable {
    case won = 0
    case stalemate = 1
    case lost = 2
    case pancake = 3
    case whiffed = 4
}

public enum CoverageTechnique: UInt8, Sendable, Hashable, Codable {
    case press = 0
    case offMan = 1
    case zoneFlat = 2
    case zoneDeep = 3
    case bracket = 4
    case spy = 5
}

/// One observable moment inside a play.
///
/// Deliberately packed into eight bytes: a play carries perhaps a dozen of
/// these, a game two thousand, a league season half a million. The meaning of
/// `detail` and `value` depends on `kind` and is documented on each case; the
/// static factories below are the intended way to build one.
public struct DecisionPoint: Sendable, Hashable, Codable {

    /// Ticks since the snap.
    public var tick: UInt16
    /// A quantity whose unit depends on `kind` — milliseconds, centimetres, or
    /// a score.
    public var value: Int16
    public var kind: DecisionKind
    public var primary: PlayerSlot
    public var secondary: PlayerSlot
    /// A small enumerated discriminant whose meaning depends on `kind`.
    public var detail: UInt8

    public init(
        tick: UInt16,
        kind: DecisionKind,
        primary: PlayerSlot,
        secondary: PlayerSlot = .none,
        detail: UInt8 = 0,
        value: Int16 = 0
    ) {
        self.tick = tick
        self.value = value
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
        self.detail = detail
    }
}

extension DecisionPoint {

    public static func pressureAllowed(
        tick: UInt16, blocker: PlayerSlot, rusher: PlayerSlot, afterMilliseconds: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .pressureAllowed, primary: blocker, secondary: rusher,
            value: afterMilliseconds)
    }

    public static func pressureHeld(
        tick: UInt16, blocker: PlayerSlot, rusher: PlayerSlot, forMilliseconds: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .pressureHeld, primary: blocker, secondary: rusher,
            value: forMilliseconds)
    }

    public static func readProgression(
        tick: UInt16, receiver: PlayerSlot, index: UInt8, separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .readProgression, primary: receiver, detail: index,
            value: separationCentimetres)
    }

    public static func throwDecision(
        tick: UInt16, passer: PlayerSlot, target: PlayerSlot = .none, decision: ThrowDecision
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .throwDecision, primary: passer, secondary: target,
            detail: decision.rawValue)
    }

    public static func ballArrival(
        tick: UInt16, receiver: PlayerSlot, defender: PlayerSlot,
        placement: BallPlacement, separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .ballArrival, primary: receiver, secondary: defender,
            detail: placement.rawValue, value: separationCentimetres)
    }

    public static func catchAttempt(
        tick: UInt16, receiver: PlayerSlot, defender: PlayerSlot, result: CatchResult
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .catchAttempt, primary: receiver, secondary: defender,
            detail: result.rawValue)
    }

    public static func tackleAttempt(
        tick: UInt16, defender: PlayerSlot, carrier: PlayerSlot, result: TackleResult
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .tackleAttempt, primary: defender, secondary: carrier,
            detail: result.rawValue)
    }

    public static func blockResult(
        tick: UInt16, blocker: PlayerSlot, defender: PlayerSlot, result: BlockResult
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .blockResult, primary: blocker, secondary: defender,
            detail: result.rawValue)
    }

    public static func coverageAssignment(
        tick: UInt16, defender: PlayerSlot, receiver: PlayerSlot, technique: CoverageTechnique
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .coverageAssignment, primary: defender, secondary: receiver,
            detail: technique.rawValue)
    }

    // Typed reads. Each returns `nil` when the point is not of that kind, so a
    // mis-typed query is caught rather than silently reinterpreting a byte.

    public var throwDecisionValue: ThrowDecision? {
        kind == .throwDecision ? ThrowDecision(rawValue: detail) : nil
    }
    public var catchResult: CatchResult? {
        kind == .catchAttempt ? CatchResult(rawValue: detail) : nil
    }
    public var tackleResult: TackleResult? {
        kind == .tackleAttempt ? TackleResult(rawValue: detail) : nil
    }
    public var blockResultValue: BlockResult? {
        kind == .blockResult ? BlockResult(rawValue: detail) : nil
    }
    public var ballPlacement: BallPlacement? {
        kind == .ballArrival ? BallPlacement(rawValue: detail) : nil
    }
    public var coverageTechnique: CoverageTechnique? {
        kind == .coverageAssignment ? CoverageTechnique(rawValue: detail) : nil
    }
}
