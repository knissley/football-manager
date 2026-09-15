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
///
/// **Who the two slots are, on every case that names two men.** `primary` is the man
/// whose act the point records and `secondary` is the man on the other side of it: the
/// blocker and the rusher he took, the defender and the receiver he covered, the
/// quarterback and the man he threw to. It is one rule and it holds across the enum, so
/// a query that wants the actor reads `primary` on any kind without asking which. The
/// cost of a case that disagrees is not a compile error but a wrong name in a stat line
/// — a leaderboard built on `primary` crediting a quarterback as a receiver — which is
/// why the factories below are the intended way to build one and the convention is
/// written here rather than only in their parameter names.
public enum DecisionKind: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// The verdict on a dropback's pocket: a rusher reached the quarterback before the
    /// ball was out. `primary` is the blocker he beat, `secondary` is the rusher, and
    /// `value` is milliseconds from the snap to his arrival. `detail` is that rep's
    /// `BlockResult`, read through `pocketRepResult`, and on this case it can only be
    /// `.lost`: a rusher who got home is a rusher whose blocker did not hold him. The
    /// factory writes it rather than taking it, because a producer given the choice
    /// could write a pressure allowed on a rep the blocker won. A dropback carries this
    /// or `pressureHeld`, never both and never two of either — which rep was lost is a
    /// different fact, recorded by `blockResult`.
    case pressureAllowed = 0
    /// The other verdict: the ball was out before any rusher arrived. `value` is the
    /// milliseconds the protection had to sustain, and the pair named is the rush that
    /// came closest. `detail` is that rush's `BlockResult`, the same byte
    /// `pressureAllowed` carries and read through the same `pocketRepResult`, and here
    /// it is not a constant: the man who came closest may have been held the whole way
    /// (`.won`) or may have beaten his blocker and still arrived after the ball was gone
    /// (`.lost`). Those are two different pockets and the verdict alone cannot tell them
    /// apart, which is why the byte is on it — the play's `blockResult` points carry
    /// every rep, but picking the closest out of them means repeating the tie-break the
    /// resolver used.
    case pressureHeld = 1
    /// The quarterback worked to a read. `primary` is the quarterback, `secondary` the
    /// receiver he read, `detail` is the progression index — the place in the play's own
    /// read order as worked on this snap, counting from one — and `value` is that
    /// receiver's separation in centimetres. `tick` is the moment he judged it: the break
    /// of the route the read is on, or later where the rush had already arrived by it.
    ///
    /// **Written for every read the quarterback worked, and for nothing else.** The
    /// order comes from the play — the pass family's read order until designs exist
    /// (`ReadProgression` in the crude resolver, decided on #169), a design's own from M6
    /// — and never from the order a loop happened to run in, which is not a thing on the
    /// film and so not a thing this enum may carry. A throw to a read follows its own
    /// read point, so the man thrown to is the last man read; the checkdown is a
    /// `throwDecision` of its own kind and writes no read point, because it is not a
    /// numbered read. Who was covering whom and how open he got are on the
    /// `.coverageAssignment` for the same receiver, which is emitted for every route
    /// runner whether or not the quarterback ever looked at him — which is what lets a
    /// reader say a man was open and never read, and now why.
    case readProgression = 2
    /// What the quarterback did with the ball. `primary` is the quarterback, `detail` is
    /// a `ThrowDecision`, `secondary` is the man that decision was about, and `value` is
    /// milliseconds from the snap to the moment `tick` names.
    ///
    /// **This is the one case where which man `secondary` is depends on `detail`**, because
    /// the decision itself does: he threw to a receiver, or he never got to, because a
    /// rusher was on him. He is still the man on the other side of the act `primary`
    /// records, so the enum's rule holds — but a reader that wants a receiver has to say
    /// which decisions he means.
    ///
    /// | `detail` | `secondary` | the moment `tick` and `value` carry |
    /// |---|---|---|
    /// | `.primary`, `.checkdown` | the receiver he threw to | the ball leaving his hand |
    /// | `.throwaway` | nobody: `PlayerSlot.none` | the ball leaving his hand |
    /// | `.scramble`, `.sack` | the rusher who got to him | that rusher's arrival |
    ///
    /// So target share, air yards and any target leaderboard read `secondary` on
    /// `.primary` and `.checkdown` and on nothing else. Ungated they credit a pass rusher
    /// with a target on every sack and every scramble — a sack on 6 to 7% of dropbacks
    /// (`row:sackRate`) and three or four scrambles a game (`row:scramblesPerGame`) — and
    /// nothing about the record would look wrong while they did. The `throwDecision`
    /// factory below is the only intended way to build one.
    case throwDecision = 3
    /// The ball reached the receiver. `value` is separation in centimetres,
    /// `detail` is a `BallPlacement`.
    case ballArrival = 4
    /// A catch was attempted. `primary` is the receiver, `secondary` the defender on
    /// him, `detail` is a `CatchResult` and `value` is the separation in **centimetres**
    /// the ball arrived with — the same number this catch's `ballArrival` carries, on
    /// the point that says what became of it, so a reader asking whether a drop was on a
    /// contested ball has both facts in one place. It is what decides a drop from a ball
    /// nobody could have caught, and it was on the record and in that use before it was
    /// on this comment.
    case catchAttempt = 5
    /// A tackle was attempted. `primary` is the defender, `secondary` the carrier and
    /// `detail` is a `TackleResult`. There is no quantity to carry, so `value` is zero.
    case tackleAttempt = 6
    /// A block resolved. `detail` is a `BlockResult`. On a dropback there is one per
    /// pass-rush rep and `value` is milliseconds from the snap: how long the blocker
    /// sustained, or when the rusher he lost to arrived. A run's reps are settled at the
    /// handoff against no clock, so `value` is zero on them and what they added up to is
    /// the same carry's `holeQuality`.
    case blockResult = 7
    /// The lane a carry was given, scored at the handoff. `primary` is the back,
    /// `detail` is the concept it was run on — `0` an inside run, `1` an outside run —
    /// and `value` is a **quality score** on the scale the resolver builds it on: twelve
    /// a block won or lost at the point of attack, twelve for a defender the offence had
    /// no blocker for, six for a blocker with nobody left to take. A score, not a
    /// distance: nothing converts it to yards, and a bin of it is a block wide.
    ///
    /// **Only a carry writes one, and that is the whole of this case.** A kick return's
    /// yardage and a catch made in space were written here too, each telling itself apart
    /// by a `detail` byte nothing stated, so `value` under one kind name held a score, a
    /// yardage and a centimetre count at once — and a fold that averaged the kind added
    /// all three and returned a plausible number. They are `returnLane` and
    /// `catchInSpace` below. The rule the split writes down is that the unit of `value`
    /// follows from `kind` alone, which is the only form of it a query can honour.
    case holeQuality = 8
    /// A defender's assignment, and what it was worth. `primary` is the defender,
    /// `secondary` the receiver he was on, `detail` is a `CoverageTechnique` and `value`
    /// is how far apart the two finished, in centimetres — the same quantity and the same
    /// unit `ballArrival` carries for the one matchup the ball went to, recorded here for
    /// every matchup whether it was thrown at or not. That is what lets a reader say a
    /// receiver was open and never got the ball.
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
    /// The lane a kick returner was given. `primary` is the man who fielded it — the deep
    /// returner, or the second returner where there was no deep man — and `value` is
    /// **yards**: what the return was worth as he cleared the first wave, before whoever
    /// caught him took the last yard or two off it. So it is the return `Outcome`'s own
    /// `fieldedAt` and `finalSpot` bracket, to within that pursuit, and not a second copy
    /// of it.
    ///
    /// One per return, on a punt and a kickoff alike, because the two are the same
    /// problem: a man with the ball in space and the coverage running at him. A fair
    /// catch, a touchback and a kick nobody fielded write none — there was no lane.
    case returnLane = 14
    /// The ball arrived with nobody in reach of the receiver, so what he does next is a
    /// footrace and not a tackle to break. `primary` is the receiver and `value` is
    /// **centimetres**: the separation he caught it with, which is the same quantity, in
    /// the same unit, that `ballArrival` carries for the same catch — the two agree on
    /// every play that has both.
    ///
    /// Written only where the catch was made in space, which is what makes it worth
    /// keeping: a long completion has two arithmetics behind it — a coverage beaten
    /// before the ball arrived, or tackles broken one at a time afterwards — and without
    /// this point the record cannot say which one produced the yards. A completion into
    /// coverage writes none.
    case catchInSpace = 15
    /// The coin was tossed, and this free kick is what it decided: before the game
    /// (2025 rulebook, 4-2-2), at the end of regulation (16-1-2), and again at the end of
    /// a fourth postseason overtime period (16-1-4-i). `detail` is the side that won it —
    /// 0 the side in possession at this snap, 1 the other — which is the frame `timeout`
    /// uses, and on a free kick the side in possession is the side kicking off. The rules
    /// layer's, so no player is named.
    ///
    /// A toss decides the half it opens *and* the half after that, so it is on the first
    /// of the two and on neither of the kickoffs a score owes: a reader walking back from
    /// a kickoff to the last `coinToss` before it has the toss that half answers to.
    case coinToss = 16
    /// What the captain who won that toss did with it (4-2-2): took one of the two
    /// privileges, or deferred his choice to the half the article gives him. `detail` is
    /// a `TossElection`. The rules layer's as well.
    case tossElectionByTheWinner = 17
    /// What the other captain did (4-2-2). `detail` is a `TossElection`, and never
    /// `.deferred`: the article gives the deferral to the winner alone.
    ///
    /// Which of the two captains chose *first* is the half's and not this kind's: the
    /// winner at a toss, the loser at the half after it unless the winner deferred
    /// (4-2-2, 16-1-4-e). So the two points sit in the order the captains answered, and
    /// each says whose it is whichever order that was.
    case tossElectionByTheLoser = 18
}

/// What one captain did with the coin toss (2025 rulebook, 4-2-2).
///
/// The two privileges are (a), which is whether this side receives the kickoff or kicks
/// off, and (b), the goal it defends. The winner takes one and the loser the other, unless
/// the winner defers his choice to the half the article names — the second half (4-2-2),
/// a third postseason overtime period (16-1-4-e) — where the captains answer again.
///
/// Only (a) reaches the field here: a spot is stored relative to whoever has the ball, so
/// there is no end of the field to choose (4-2-3). `goal` is on the record all the same,
/// because a reader asking what a captain did with the toss is owed the answer he gave
/// and not the answer the engine could act on.
public enum TossElection: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// Privilege (a), taken as the ball (4-2-2-a).
    case receive = 0
    /// Privilege (a), taken the other way (4-2-2-a).
    case kickOff = 1
    /// Privilege (b), the choice of goal to defend (4-2-2-b).
    case goal = 2
    /// Neither privilege yet: the winner's choice is deferred to the second half
    /// (4-2-2), or to a third postseason overtime period (16-1-4-e).
    case deferred = 3
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

/// How a throw ended at the catch point, and — for the three ways it can fail — which of
/// the three men it was down to.
///
/// The record carries no other field that says why a pass fell incomplete, so every
/// reader downstream repeats whatever this says: a drop rate, a pass-defensed
/// leaderboard, and the sentence the narrative layer writes about the play. A label that
/// names the wrong man is therefore not a cosmetic fault. The placement the ball arrived
/// at is on the record one decision earlier, in `ballArrival`, and the two together are
/// what let a reader tell a receiver's failure from a passer's.
public enum CatchResult: UInt8, CaseIterable, Sendable, Hashable, Codable {
    case caught = 0
    case contestedCatch = 1
    /// The receiver's: a ball he could have caught, and did not.
    case dropped = 2
    /// The defender's: he was in reach and knocked it away, or he interfered and the foul
    /// is the reason it was not caught (2025 rulebook, 8-5-1).
    case brokenUp = 3
    case intercepted = 4
    /// The passer's, at its worst: thrown where nobody could reach it, which is the throw
    /// 8-5-3-c makes contact on legal. `BallPlacement.uncatchable` is the same throw.
    case uncatchable = 5
    /// The passer's: a ball that reached the receiver and was not one he could be expected
    /// to catch. Distinct from `.uncatchable`, which nobody could have reached, and from
    /// `.dropped`, which was catchable — the three are the throw at its worst, the throw
    /// at fault, and the receiver at fault, and collapsing any two of them puts an
    /// incompletion on the wrong man.
    case offTarget = 6
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
    public let tick: UInt16
    /// A quantity whose unit depends on `kind` — milliseconds, centimetres, or
    /// a score.
    public let value: Int16
    public let kind: DecisionKind
    public let primary: PlayerSlot
    public let secondary: PlayerSlot
    /// A small enumerated discriminant whose meaning depends on `kind`.
    public let detail: UInt8

    /// **Internal, so that the factories below are the only way to build one.**
    ///
    /// It was public, and every producer outside this module used it: sixteen call sites
    /// naming a kind and then filling in whichever of `detail` and `value` they felt like
    /// filling in. Four kinds drifted from their own doc comments that way, each of them
    /// carrying a byte the comment did not mention and no accessor could read, and none
    /// of the four was anything a compiler or a suite could have objected to — `detail`
    /// is eight bits of anything at all. Behind this wall a producer gets the parameters
    /// its kind's contract allows and no others, so the contract is checked where it is
    /// written instead of being asserted in prose and hoped for.
    ///
    /// The fields are `let` for the same reason: a point that could be amended after the
    /// factory built it would put the hole straight back.
    init(
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

    /// The pocket lost: the pair is the blocker and the rusher who beat him, and
    /// `afterMilliseconds` is when he got there. The rep's `BlockResult` goes on the
    /// point as well, and is not a parameter because `.lost` is the only result this
    /// verdict can be written about.
    public static func pressureAllowed(
        tick: UInt16, blocker: PlayerSlot, rusher: PlayerSlot, afterMilliseconds: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .pressureAllowed, primary: blocker, secondary: rusher,
            detail: BlockResult.lost.rawValue, value: afterMilliseconds)
    }

    /// The pocket held: the pair is the rush that came closest, `forMilliseconds` is how
    /// long the protection had to last, and `closestRep` is how that rep itself finished
    /// — held all the way, or beaten and late. See `DecisionKind.pressureHeld` for why
    /// the last of those is on the verdict rather than left to be dug out of the play's
    /// block results.
    public static func pressureHeld(
        tick: UInt16, blocker: PlayerSlot, rusher: PlayerSlot, forMilliseconds: Int16,
        closestRep: BlockResult
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .pressureHeld, primary: blocker, secondary: rusher,
            detail: closestRep.rawValue, value: forMilliseconds)
    }

    /// A read is the quarterback's act, so he is `primary` and the man he read is
    /// `secondary` — the same pair, in the same order, as `throwDecision`. `index` is the
    /// place in the order as worked, counting from one; see `DecisionKind.readProgression`.
    public static func readProgression(
        tick: UInt16, passer: PlayerSlot, receiver: PlayerSlot, index: UInt8,
        separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .readProgression, primary: passer, secondary: receiver,
            detail: index, value: separationCentimetres)
    }

    /// The quarterback is `primary` and `oppositeNumber` is the man the decision was
    /// about — the receiver he threw to, or the rusher who got to him before he could,
    /// and nobody at all on a throwaway. The parameter is not named `target` because it
    /// is a target on two of the five decisions and a pass rusher on two others; see
    /// `DecisionKind.throwDecision` for the table. `atMilliseconds` is the same moment
    /// `tick` carries, in milliseconds from the snap.
    public static func throwDecision(
        tick: UInt16, passer: PlayerSlot, oppositeNumber: PlayerSlot = .none,
        decision: ThrowDecision, atMilliseconds: Int16 = 0
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .throwDecision, primary: passer, secondary: oppositeNumber,
            detail: decision.rawValue, value: atMilliseconds)
    }

    public static func ballArrival(
        tick: UInt16, receiver: PlayerSlot, defender: PlayerSlot,
        placement: BallPlacement, separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .ballArrival, primary: receiver, secondary: defender,
            detail: placement.rawValue, value: separationCentimetres)
    }

    /// What became of the ball, and how contested it was: `separationCentimetres` is the
    /// separation the throw arrived with, the same number this catch's `ballArrival`
    /// carries.
    public static func catchAttempt(
        tick: UInt16, receiver: PlayerSlot, defender: PlayerSlot, result: CatchResult,
        separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .catchAttempt, primary: receiver, secondary: defender,
            detail: result.rawValue, value: separationCentimetres)
    }

    public static func tackleAttempt(
        tick: UInt16, defender: PlayerSlot, carrier: PlayerSlot, result: TackleResult
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .tackleAttempt, primary: defender, secondary: carrier,
            detail: result.rawValue)
    }

    /// One rep, and how it finished. `atMilliseconds` is the moment `tick` names, in
    /// milliseconds from the snap — how long the blocker sustained, or when the rusher he
    /// lost to arrived. It defaults to none because a run's reps are settled at the
    /// handoff and there is no pocket clock for them to be read against; a dropback's
    /// carry it, and the pocket verdict is decided from them.
    public static func blockResult(
        tick: UInt16, blocker: PlayerSlot, defender: PlayerSlot, result: BlockResult,
        atMilliseconds: Int16 = 0
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .blockResult, primary: blocker, secondary: defender,
            detail: result.rawValue, value: atMilliseconds)
    }

    public static func coverageAssignment(
        tick: UInt16, defender: PlayerSlot, receiver: PlayerSlot, technique: CoverageTechnique,
        separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .coverageAssignment, primary: defender, secondary: receiver,
            detail: technique.rawValue, value: separationCentimetres)
    }

    /// The lane a carry was given: the back who ran it, the concept it was run on, and
    /// the resolver's score for the hole. `quality` is a score and nothing else — see
    /// `DecisionKind.holeQuality` for the scale, and for why a return's yardage and a
    /// catch made in space, which were once written as this kind in units of their own,
    /// are kinds of their own instead.
    public static func holeQuality(
        tick: UInt16, back: PlayerSlot, insideRun: Bool, quality: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .holeQuality, primary: back, detail: insideRun ? 0 : 1,
            value: quality)
    }

    /// The lane a kick returner was given, in yards, as he cleared the first wave. There
    /// is no man opposite: the coverage unit is on the play's tackle attempts, and who
    /// eventually got him is a different fact from the lane he was running in.
    public static func returnLane(
        tick: UInt16, returner: PlayerSlot, yards: Int16
    ) -> DecisionPoint {
        DecisionPoint(tick: tick, kind: .returnLane, primary: returner, value: yards)
    }

    /// A catch made with nobody in reach, and the separation in centimetres it was made
    /// with — the same number `ballArrival` carries for the same catch. The man who was
    /// beaten is on that play's `coverageAssignment` and its `ballArrival`, which is
    /// where a query asking who gave the space up should read him.
    public static func catchInSpace(
        tick: UInt16, receiver: PlayerSlot, separationCentimetres: Int16
    ) -> DecisionPoint {
        DecisionPoint(
            tick: tick, kind: .catchInSpace, primary: receiver, value: separationCentimetres)
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

    /// The toss, on the free kick it decided. `wonByTheSideKickingOff` is the record's
    /// frame for a side — the side in possession at this snap, which on a free kick is
    /// the side kicking off — so the winner resolves to a `TeamID` through the
    /// situation the point sits on and needs no eight bytes of its own.
    public static func coinToss(wonByTheSideKickingOff: Bool) -> DecisionPoint {
        DecisionPoint(
            tick: 0, kind: .coinToss, primary: .none, detail: wonByTheSideKickingOff ? 0 : 1)
    }

    /// What the captain who won the toss did with it (4-2-2).
    public static func tossElection(byTheWinner election: TossElection) -> DecisionPoint {
        DecisionPoint(
            tick: 0, kind: .tossElectionByTheWinner, primary: .none, detail: election.rawValue)
    }

    /// What the captain who lost it did (4-2-2). Never a deferral — see
    /// `DecisionKind.tossElectionByTheLoser` — which is a fact about the football rather
    /// than about the byte, so it is asserted over the corpus rather than taken out of
    /// the type the winner's election also uses.
    public static func tossElection(byTheLoser election: TossElection) -> DecisionPoint {
        DecisionPoint(
            tick: 0, kind: .tossElectionByTheLoser, primary: .none, detail: election.rawValue)
    }

    /// Whether the side kicking this free kick off is the side that won the toss, for a
    /// `.coinToss` point.
    public var coinTossWonByTheSideKickingOff: Bool? {
        kind == .coinToss ? detail == 0 : nil
    }
    public var tossElectionByTheWinner: TossElection? {
        kind == .tossElectionByTheWinner ? TossElection(rawValue: detail) : nil
    }
    public var tossElectionByTheLoser: TossElection? {
        kind == .tossElectionByTheLoser ? TossElection(rawValue: detail) : nil
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

    /// The result of the rep the pocket verdict was decided from, for a
    /// `.pressureAllowed` or a `.pressureHeld` point: the rusher who got home, or the one
    /// who came closest. `.lost` always on the first — the byte is the contract's
    /// constant there — and either result on the second, where it is the difference
    /// between a protection that held and one that was beaten and got away with it.
    public var pocketRepResult: BlockResult? {
        kind == .pressureAllowed || kind == .pressureHeld
            ? BlockResult(rawValue: detail) : nil
    }

    /// Whether the lane a `.holeQuality` point scored was run inside, for a point of that
    /// kind. The byte is the only thing that says so, and a reader that decodes it by
    /// hand is a reader that can decode another kind's byte by the same mistake.
    public var holeWasInsideRun: Bool? {
        kind == .holeQuality ? detail == 0 : nil
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
