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
    /// The play clock the snap was taken against (2025 rulebook, 4-6). `detail` is the
    /// seconds the clock started with — 40 after a play, 25 after an administrative
    /// stoppage, 30 after a runoff — and `value` is what it read at the snap. Zero means
    /// it expired with the ball not snapped, which is a delay of game (4-6-1, 4-6-4).
    /// The rules layer writes this one, not the resolver: which clock was in force is a
    /// rule, and a reader should not have to infer it from the play before.
    case playClock = 10
    /// A choice the rules put to one side about the clock between downs, as the referee
    /// announces it — the runoff and its alternatives (4-7-1), the last forty seconds
    /// (4-7-3), an injury timeout after the two-minute warning (4-5-4). `detail` is a
    /// `ClockElection`. The rules layer's as well.
    case clockElection = 11
    /// A charged team timeout taken before this snap (2025 rulebook, 4-5-1). `detail`
    /// is the side that took it — 0 the side in possession at the snap, 1 the other —
    /// so a timeout taken with the ball about to change hands is charged to a team and
    /// not inferred from two situations. A timeout that is the rules' consequence of the
    /// play before — the offence's alternative to a runoff, an injury timeout — is a
    /// `clockElection` on that play instead, where the referee announces it. The rules
    /// layer's.
    case timeout = 12
    /// The two-minute warning was taken before this snap (3-41): at the end of the last
    /// down snapped before 2:00, so it sits on the first snap taken with two minutes or
    /// less to play. The rules layer's.
    case twoMinuteWarning = 13
}

/// A choice the rules put to one side about the clock between downs (2025 rulebook,
/// Rule 4), recorded so that the stream explains a clock that lost ten seconds, waited
/// for a snap, or ran out with the ball dead — instead of leaving it to be inferred from
/// two consecutive situations.
public enum ClockElection: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// The offence's act conserved time and ten seconds came off (4-7-1 Item 1).
    case runoff = 0
    /// The offence spent a charged timeout instead of the runoff (4-7-1 Item 1).
    case timeoutInsteadOfRunoff = 1
    /// The defence declined the runoff and kept the yardage (4-7-1 Item 1).
    case runoffDeclined = 2
    /// After the defence's act, the offence had the clock wait for the snap rather than
    /// start on the ready-for-play signal (4-7-1 Item 2, 4-5-4 Note 1).
    case clockStartsOnTheSnap = 3
    /// After the defence's act, the offence let the clock start on the ready-for-play
    /// signal (4-7-1 Item 2, 4-5-4 Note 1).
    case clockStartsOnTheReady = 4
    /// In the last forty seconds of a half, the offence ended the half (4-7-3).
    case halfEnded = 5
    /// In the last forty seconds of a half, the offence chose to play on (4-7-3).
    case playedOn = 6
    /// An injury timeout after the two-minute warning was charged to the injured
    /// player's team as a team timeout (4-5-4-a).
    case injuryTimeoutCharged = 7
    /// An injury timeout after the two-minute warning for a team with none left: an
    /// excess timeout, with no runoff in question (4-5-4-b, 4-5-4 Note 1).
    case excessInjuryTimeout = 8
    /// An excess injury timeout against the team in possession, and the defence had ten
    /// seconds run off (4-5-4 Note 3).
    case injuryRunoff = 9
    /// The same, and the defence declined it (4-5-4 Note 3).
    case injuryRunoffDeclined = 10
}

public enum ThrowDecision: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case primary = 0
    case checkdown = 1
    case throwaway = 2
    case scramble = 3
    case sack = 4
}

public enum BallPlacement: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case onTarget = 0
    case slightlyOff = 1
    case poor = 2
    case uncatchable = 3
}

public enum CatchResult: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case caught = 0
    case contestedCatch = 1
    case dropped = 2
    case brokenUp = 3
    case intercepted = 4
    case uncatchable = 5
}

public enum TackleResult: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case madeTackle = 0
    case assisted = 1
    case broken = 2
    case missed = 3
    case forcedFumble = 4
}

public enum BlockResult: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case won = 0
    case stalemate = 1
    case lost = 2
    case pancake = 3
    case whiffed = 4
}

public enum CoverageTechnique: UInt8, CaseIterable, Sendable, Hashable, Codable {
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

    /// The play clock this snap was taken against, and what it read at the snap — zero
    /// when it expired with the ball not snapped. Written by the rules layer on every
    /// play; there is no player to name, so the slots are empty.
    public static func playClock(seconds: UInt8, remaining: UInt8) -> DecisionPoint {
        DecisionPoint(
            tick: 0, kind: .playClock, primary: .none, detail: seconds, value: Int16(remaining))
    }

    /// A choice one side made about the clock between downs, as the rules put it.
    public static func clockElection(_ election: ClockElection) -> DecisionPoint {
        DecisionPoint(tick: 0, kind: .clockElection, primary: .none, detail: election.rawValue)
    }

    // Typed reads. Each returns `nil` when the point is not of that kind, so a
    // mis-typed query is caught rather than silently reinterpreting a byte.

    /// The play clock in force and what it read at the snap, for a `.playClock` point.
    public var playClockReading: (seconds: UInt8, remaining: UInt8)? {
        guard kind == .playClock, value >= 0, value <= Int16(UInt8.max) else { return nil }
        return (detail, UInt8(value))
    }
    public var clockElectionValue: ClockElection? {
        kind == .clockElection ? ClockElection(rawValue: detail) : nil
    }

    /// A charged team timeout before the snap, by the side in possession or the other.
    public static func timeout(byOffense: Bool) -> DecisionPoint {
        DecisionPoint(tick: 0, kind: .timeout, primary: .none, detail: byOffense ? 0 : 1)
    }

    /// The two-minute warning, taken before the snap.
    public static let twoMinuteWarning = DecisionPoint(
        tick: 0, kind: .twoMinuteWarning, primary: .none)

    /// Which side took the timeout, for a `.timeout` point: `true` the side in
    /// possession at the snap.
    public var timeoutByOffense: Bool? {
        kind == .timeout ? detail == 0 : nil
    }

    public var isTwoMinuteWarning: Bool { kind == .twoMinuteWarning }

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
