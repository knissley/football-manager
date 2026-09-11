import FMCore
import FMRandom
import FMSimulation
import Synchronization

// A game whose plays a scenario dictates, so that what is left to observe is the rules
// layer: the clock, the downs, possession, scoring, enforcement and overtime.
//
// The resolver is a closure over the snap it is asked to resolve, and the caller is a
// handful of closures with plain defaults, so a scenario reads as football — *when it is
// the fourth quarter, inside a minute, and this side trails by seven: a touchdown as time
// expires* — and never as an index into a script. Every play the scenario does not care
// about honours the call it was given and changes nothing worth noticing.
//
// Nothing in here draws a random number. The world comes from `ScenarioWorld` at a seed,
// and the sim's own stream is never read, so a scenario replays identically every time.
//
// This is the *pure* half of the scenario machinery, and it is a library rather than test
// support so that a tool can link it: `gamelog --scenario <name>` walks one of these
// games through the same printer a seeded game goes through. The assertions over a
// `Trace` — `expectPlay` and the rest — stay in the test target, which is the only place
// that may import Swift Testing.

// MARK: - One snap, as a scenario sees it

/// One snap, as the scenario's resolver sees it.
///
/// The situation and the calls are what `PlayResolver` receives. `clockIsRunning` is the
/// one fact from the context worth surfacing: it is the rules layer's own verdict on the
/// play before, and it is what every clock scenario asserts on. `previous` is the snap
/// before this one and `huddle` the offence's measured tempo, for the scenarios that
/// stage a play to end at a particular second.
public struct Snap: Sendable {

    public let index: Int
    public let situation: Situation
    public let calls: Calls
    public let offense: TeamID
    public let defense: TeamID
    public let clockIsRunning: Bool
    public let previous: Previous?

    /// The snap before this one, and what the scenario made of it.
    public struct Previous: Sendable {
        public let situation: Situation
        public let outcome: Outcome
    }

    public var quarter: UInt8 { situation.quarter }
    public var clock: UInt16 { situation.clockRemaining }
    public var down: Down { situation.down }
    public var distance: UInt8 { situation.distance }
    public var ballOn: UInt8 { situation.ballOn }
    public var possession: TeamID { situation.possession }
    /// The score from the possessing team's point of view.
    public var differential: Int16 { situation.scoreDifferential }

    public var concept: PlayConcept { calls.offense.concept }

    public var isScrimmage: Bool {
        PlayConcept.scrimmage.contains(concept) || concept == .kneel || concept == .spike
    }
    public var isTry: Bool {
        concept == .extraPoint || concept == .twoPointPass || concept == .twoPointRun
    }
    /// Every free kick, however it was aimed: a scenario scripts what the kick *did*, and
    /// which of the three the coordinator called is not its business.
    public var isKickoff: Bool {
        concept == .kickoff || concept == .onsideKick || concept == .deepKickoff
    }

    /// The seconds the offence takes between the end of one play and the snap of the
    /// next when the clock is running — its tempo — measured from the plays so far rather
    /// than assumed. `nil` until two snaps have shown it.
    ///
    /// The resolver is asked about a snap with the clock as the previous play left it,
    /// because the tempo the caller chose is what decides how long the interval to the
    /// snap will be; the rules layer then charges that interval and records the down with
    /// the clock it was really snapped on. So a play the clock ran into is snapped at
    /// `clock - huddle` and ends `clockRunoff` after that, and a scenario that needs a
    /// play to end at a particular second stretches its runoff by this.
    public let huddle: UInt16?
}

// MARK: - The vocabulary of scripted outcomes

extension Snap {

    /// Honours the call and changes nothing worth noticing.
    public var neutral: Outcome {
        switch concept {
        case .kickoff, .deepKickoff: return .kickoffTouchback
        case .onsideKick: return .onsideKick(lostAtOwn: 45)
        case .punt: return .puntTouchback
        case .fieldGoal: return .fieldGoal(good: true)
        case .extraPoint: return .extraPoint(good: true)
        case .twoPointPass, .twoPointRun: return .twoPoint(converted: false)
        case .kneel: return Outcome(kind: .kneel, yards: -1, endedIn: .tackled, clockRunoff: 2)
        case .spike: return .spike
        // Exhaustive with no `default`, for the reason the free-kick switches in
        // `gamelog` are: a kicking concept that falls through to a one-yard gain scripts
        // the wrong football and says nothing about it.
        case .insideRun, .outsideRun, .quickPass, .mediumPass, .deepPass, .screen, .playAction:
            // A one-yard gain of whatever kind was called, tackled in bounds: the ball
            // moves, the clock runs, and the down changes hands on downs every four plays.
            return Outcome(kind: concept.kind, yards: 1, endedIn: .tackled, clockRunoff: 6)
        }
    }

    /// The ball carried into the end zone from wherever it was spotted.
    public func touchdown(seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .rush, yards: Int16(ballOn), endedIn: .touchdown, clockRunoff: seconds)
    }

    /// A touchdown on a play that runs the period's clock to zero.
    public func touchdownAsTimeExpires() -> Outcome {
        Outcome(
            kind: .rush, yards: Int16(ballOn), endedIn: .touchdown, clockRunoff: max(1, clock))
    }

    /// The ball carrier tackled in his own end zone.
    public func safety(seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .sack, yards: -(100 - Int16(ballOn)), endedIn: .safety, clockRunoff: seconds)
    }

    /// A flag before the snap. No play happens; the record carries the foul and nothing
    /// else, which is the contract the crude resolver honours for the same event.
    public func preSnapFoul(_ foul: Foul) -> Outcome {
        Outcome(
            kind: .penaltyOnly, yards: 0, endedIn: .penaltyEnforced,
            penalties: [record(foul)], clockRunoff: 0)
    }

    /// A run that ends in a flag on the man who made the tackle, or on a blocker.
    public func rush(_ yards: Int16, foulBy foul: Foul, seconds: UInt16 = 6) -> Outcome {
        Outcome(
            kind: .rush, yards: yards, endedIn: .tackled, penalties: [record(foul)],
            clockRunoff: seconds)
    }

    /// A run of `yards` with a flag on it, at the end of which the ball comes loose and
    /// the other side gets it and takes it back to `spot` in the offence's frame.
    ///
    /// The fumble is where the run ended, so that is where possession was lost, and on a
    /// gain that is also the basic spot for the flag: a run followed by a change of
    /// possession takes the spot where possession went (2025 rulebook, 14-3-5-b). On a
    /// loss it is not — a basic spot behind the line puts a defensive foul back on the
    /// previous spot (14-3-6, the exception for the defence). The offence's own gain is
    /// nothing once it no longer has the ball, which is the contract the crude resolver
    /// honours for the same event.
    public func rush(
        _ yards: Int16, fumbledAndReturnedTo spot: UInt8, foulBy foul: Foul, seconds: UInt16 = 7
    ) -> Outcome {
        Outcome(
            kind: .rush, yards: 0, endedIn: .fumbleLost, penalties: [record(foul)],
            finalSpot: spot, possessionLostAt: UInt8(max(1, Int(ballOn) - Int(yards))),
            clockRunoff: seconds)
    }

    /// The quarterback sacked `yards` behind the line — `yards` is negative — and stripped
    /// as he goes down, with a flag on the defence during the down; the other side gets
    /// the ball and takes it back to `spot` in the offence's frame.
    ///
    /// The ball comes loose behind the line, which is the case the strip sack makes
    /// common and the case the three-and-one method sends back to the previous spot: a
    /// basic spot behind the line of scrimmage puts a defensive foul on the previous spot
    /// wherever the foul itself was (2025 rulebook, 14-3-6, the exception for the
    /// defence; 14-4-6-b for a foul during the fumble). The kind is a sack and the yards
    /// are nothing, which is what the crude resolver writes for the same event.
    public func sack(
        _ yards: Int16, fumbledAndReturnedTo spot: UInt8, foulBy foul: Foul, seconds: UInt16 = 7
    ) -> Outcome {
        Outcome(
            kind: .sack, yards: 0, endedIn: .fumbleLost, penalties: [record(foul)],
            finalSpot: spot, possessionLostAt: UInt8(max(1, Int(ballOn) - Int(yards))),
            clockRunoff: seconds)
    }

    /// A pass intercepted `depth` yards past the line and returned to `spot` in the
    /// offence's frame, with a flag on the defence during the down.
    ///
    /// Where possession was lost is on the record because every takeaway carries it, not
    /// because the flag is enforced from there: until a forward pass from behind the line
    /// is over, a flag on either side comes off the previous spot (2025 rulebook, 14-4-5),
    /// and a defensive personal foul before the catch comes off the better of two spots
    /// for the offence — where it snapped, or where the ball was dead (14-4-5-d). The record
    /// says nothing about *when* in the down a flag flew, so this is one scripted play and
    /// not two: a foul before the catch and a foul by the intercepting team on its own
    /// return are the same record.
    public func interception(
        caught depth: UInt8, returnedTo spot: UInt8, foulBy foul: Foul, seconds: UInt16 = 8
    ) -> Outcome {
        Outcome(
            kind: .pass, yards: 0, endedIn: .intercepted, passResult: .intercepted,
            penalties: [record(foul)], finalSpot: spot,
            possessionLostAt: UInt8(max(1, Int(ballOn) - Int(depth))), clockRunoff: seconds)
    }

    /// A pass that falls incomplete because a defender interfered, `depth` yards past
    /// the line of scrimmage. Interference is measured rather than fixed, and the
    /// resolver's contract carries the spot in the offence's frame, with zero meaning
    /// the end zone.
    public func incompletion(interferenceAt depth: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .pass, yards: 0, endedIn: .incomplete, passResult: .incomplete,
            penalties: [
                PenaltyRecord(
                    foul: .defensivePassInterference, offender: PlayerSlot(11),
                    offendingTeam: defense, yards: min(depth, ballOn), wasAccepted: false,
                    enforcementSpot: UInt8(max(0, Int(ballOn) - Int(depth))))
            ],
            clockRunoff: seconds)
    }

    /// A place kick that went where it was told to, with a flag on it.
    public func kick(
        _ concept: PlayConcept, good: Bool, foulBy foul: Foul, seconds: UInt16 = 5
    )
        -> Outcome
    {
        Outcome(
            kind: concept == .extraPoint ? .extraPoint : .fieldGoal, yards: 0,
            endedIn: good ? .fieldGoalGood : .fieldGoalMissed, penalties: [record(foul)],
            clockRunoff: concept == .extraPoint ? 0 : seconds)
    }

    private func record(_ foul: Foul) -> PenaltyRecord {
        let byOffense = foul.committedBy == .offense
        return PenaltyRecord(
            foul: foul,
            offender: byOffense ? PlayerSlot(1) : PlayerSlot(11),
            offendingTeam: byOffense ? offense : defense,
            yards: foul.yards,
            wasAccepted: false)
    }
}

extension Outcome {

    /// A carry, tackled in bounds unless told otherwise.
    public static func rush(
        _ yards: Int16, seconds: UInt16 = 6, endedIn: PlayEnding = .tackled
    )
        -> Outcome
    {
        Outcome(kind: .rush, yards: yards, endedIn: endedIn, clockRunoff: seconds)
    }

    public static func incompletion(seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .pass, yards: 0, endedIn: .incomplete, passResult: .incomplete,
            clockRunoff: seconds)
    }

    public static let spike = Outcome(
        kind: .spike, yards: 0, endedIn: .incomplete, passResult: .incomplete, clockRunoff: 1)

    /// Picked off and returned to `spot`, in the throwing team's frame: 100 is the
    /// interceptor's own goal line crossed the other way, a touchdown.
    public static func interception(to spot: UInt8, seconds: UInt16 = 6) -> Outcome {
        Outcome(
            kind: .pass, yards: 0, endedIn: .intercepted, passResult: .intercepted,
            finalSpot: spot, clockRunoff: seconds)
    }

    public static let pickSix = interception(to: 100, seconds: 12)

    /// A fumble the defence comes up with and falls on, at `spot` in the fumbling team's
    /// frame — so that is both where possession was lost and where the ball came to rest.
    public static func fumble(lostAt spot: UInt8, seconds: UInt16 = 6) -> Outcome {
        Outcome(
            kind: .rush, yards: 0, endedIn: .fumbleLost, finalSpot: spot, possessionLostAt: spot,
            clockRunoff: seconds)
    }

    /// A fumble the offence falls on, `yards` past the line.
    public static func fumble(recoveredAfter yards: Int16, seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .rush, yards: yards, endedIn: .fumbleRecovered, clockRunoff: seconds)
    }

    public static let kickoffTouchback = Outcome(kind: .kickoff, yards: 0, endedIn: .touchback)

    /// Fielded at the goal line and brought out to the returner's own `yard` line, which
    /// is the same number in the kicking team's frame.
    public static func kickoffReturn(toOwn yard: UInt8, seconds: UInt16 = 8) -> Outcome {
        Outcome(
            kind: .kickoff, yards: 0, endedIn: .tackled, finalSpot: yard, fieldedAt: 0,
            clockRunoff: seconds)
    }

    public static let kickoffReturnTouchdown = Outcome(
        kind: .kickoff, yards: 0, endedIn: .touchdown, finalSpot: 100, clockRunoff: 14)

    /// A kickoff fielded two yards deep, fumbled by the returner, and carried into the
    /// receivers' end zone by the kicking team. The resting spot is the receivers' goal
    /// line — zero in the kicking team's frame — which is how a kickoff touchdown says
    /// the kickers scored it.
    public static let kickoffFumbledAndReturnedByTheKickers = Outcome(
        kind: .kickoff, yards: 0, endedIn: .touchdown, finalSpot: 0, fieldedAt: -2,
        clockRunoff: 14)

    /// Signalled for and fair caught at the returner's own `yard` line.
    public static func kickoffFairCaught(atOwn yard: UInt8, seconds: UInt16 = 4) -> Outcome {
        Outcome(
            kind: .kickoff, yards: 0, endedIn: .fairCatch, finalSpot: yard,
            fieldedAt: Int8(clamping: yard), clockRunoff: seconds)
    }

    /// Fallen on by the kicking team, `ballOn` from the goal it is attacking: the same
    /// contract as an onside kick the kickers recover. The record does not say whether
    /// the receivers muffed it first, so the clock reads it as untouched (4-3-1-b).
    public static func kickoffRecoveredByTheKickers(
        at ballOn: UInt8, seconds: UInt16 = 5
    )
        -> Outcome
    {
        onsideKick(recoveredAt: ballOn, seconds: seconds)
    }

    /// The kicking team falls on its own kick, `ballOn` from the goal it is attacking.
    /// `.fumbleRecovered` on a kickoff is how the contract says the kick did not change
    /// hands.
    public static func onsideKick(recoveredAt ballOn: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .kickoff, yards: 0, endedIn: .fumbleRecovered, finalSpot: ballOn,
            clockRunoff: seconds)
    }

    /// The receiving team falls on it at its own `yard` line.
    public static func onsideKick(lostAtOwn yard: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(kind: .kickoff, yards: 0, endedIn: .tackled, finalSpot: yard, clockRunoff: seconds)
    }

    public static let puntTouchback = Outcome(
        kind: .punt, yards: 0, endedIn: .touchback, clockRunoff: 6)

    /// A punt that ends at the receiving team's own `yard` line, however it ended there.
    /// One that was not returned was fielded where it ended; where a returned one was
    /// fielded, the script does not say.
    public static func punt(
        toOwn yard: UInt8, endedIn: PlayEnding = .fairCatch, seconds: UInt16 = 6
    )
        -> Outcome
    {
        let returned = endedIn == .tackled || endedIn == .touchdown
        return Outcome(
            kind: .punt, yards: 0, endedIn: endedIn, finalSpot: yard,
            fieldedAt: returned ? nil : Int8(clamping: yard), clockRunoff: seconds)
    }

    public static func fieldGoal(good: Bool) -> Outcome {
        Outcome(
            kind: .fieldGoal, yards: 0, endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
            clockRunoff: 5)
    }

    public static func extraPoint(good: Bool) -> Outcome {
        Outcome(
            kind: .extraPoint, yards: 0, endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
            clockRunoff: 0)
    }

    /// A two-point pass, caught in the end zone or not.
    public static func twoPoint(converted: Bool) -> Outcome {
        Outcome(
            kind: .twoPointConversion, yards: converted ? 2 : 0,
            endedIn: converted ? .touchdown : .incomplete,
            passResult: converted ? .complete : .incomplete, clockRunoff: 0)
    }

    /// A two-point pass the defence intercepts at the front of the end zone and returns
    /// to `spot`, in the frame of the team that snapped it like every other spot on the
    /// record.
    ///
    /// The kind is the try and not the pass. A try is one scrimmage down, and the whistle
    /// closes it out whether or not anybody scored (2025 rulebook, 11-3-1, 11-3-2-e), so
    /// the down is the try
    /// whoever ends up with the ball — and the kind is what the rules layer reads to know
    /// that a kickoff and not a first down comes next (11-3-4).
    public static func twoPointIntercepted(returnedTo spot: UInt8) -> Outcome {
        Outcome(
            kind: .twoPointConversion, yards: 0, endedIn: .intercepted,
            passResult: .intercepted, finalSpot: spot, possessionLostAt: 1, clockRunoff: 0)
    }
}

// MARK: - A caller that does what the scenario says

/// A caller with no opinions of its own.
///
/// Every decision is a closure over the situation with a plain default: an inside run on
/// every scrimmage down, at normal tempo, no timeouts, a kick after every touchdown and
/// a deep kickoff. A scenario overrides the one or two that matter to it, so a rules
/// scenario is never at the mercy of the baseline caller's judgement.
public struct ScriptedCaller: FMSimulation.PlayCaller {

    public var offensiveConcept: @Sendable (Situation) -> PlayConcept = { _ in .insideRun }
    public var offensiveTempo: @Sendable (Situation) -> Tempo = { _ in .normal }
    public var timeoutDecision: @Sendable (_ situation: Situation, _ isOffense: Bool) -> Bool = {
        _, _ in false
    }
    /// Whether the offence spends one to beat a play clock it is not going to beat.
    ///
    /// Separate from `timeoutDecision`, and the only timeout question that reads the
    /// context: whether the ball is about to stay dead for a delay of game (2025
    /// rulebook, 4-6-4) is a fact about this snap rather than about the situation, so a
    /// scenario that wants to answer it has to see `PlayContext.playClockExpired`.
    /// Nobody does, unless the scenario says so.
    public var timeoutOnThePlayClock:
        @Sendable (_ situation: Situation, _ context: PlayContext) ->
            Bool = { _, _ in false }
    public var twoPointDecision: @Sendable (Situation) -> Bool = { _ in false }
    public var onsideDecision: @Sendable (Situation) -> Bool = { _ in false }
    /// The first choice of 4-2-2's privileges, when it is this side's: receive, unless
    /// the scenario says kick.
    public var receiveDecision: @Sendable (Situation) -> Bool = { _ in true }

    public init(
        offensiveConcept: @escaping @Sendable (Situation) -> PlayConcept = { _ in .insideRun },
        offensiveTempo: @escaping @Sendable (Situation) -> Tempo = { _ in .normal },
        timeoutDecision: @escaping @Sendable (_ situation: Situation, _ isOffense: Bool) -> Bool = {
            _, _ in false
        },
        timeoutOnThePlayClock:
            @escaping @Sendable (_ situation: Situation, _ context: PlayContext)
            -> Bool = { _, _ in false },
        twoPointDecision: @escaping @Sendable (Situation) -> Bool = { _ in false },
        onsideDecision: @escaping @Sendable (Situation) -> Bool = { _ in false },
        receiveDecision: @escaping @Sendable (Situation) -> Bool = { _ in true }
    ) {
        self.offensiveConcept = offensiveConcept
        self.offensiveTempo = offensiveTempo
        self.timeoutDecision = timeoutDecision
        self.timeoutOnThePlayClock = timeoutOnThePlayClock
        self.twoPointDecision = twoPointDecision
        self.onsideDecision = onsideDecision
        self.receiveDecision = receiveDecision
    }

    public func offensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> OffensiveCall {
        OffensiveCall(concept: offensiveConcept(situation), tempo: offensiveTempo(situation))
    }

    public func defensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> DefensiveCall {
        .baseCoverThree
    }

    public func callsTimeout(
        for situation: Situation, classified: SituationClass, isOffense: Bool,
        context: PlayContext
    ) -> Bool {
        if isOffense, timeoutOnThePlayClock(situation, context) { return true }
        return timeoutDecision(situation, isOffense)
    }

    public func goesForTwo(situation: Situation, classified: SituationClass) -> Bool {
        twoPointDecision(situation)
    }

    public func kicksOnside(situation: Situation, classified: SituationClass) -> Bool {
        onsideDecision(situation)
    }

    public func electsToReceive(situation: Situation, classified: SituationClass) -> Bool {
        receiveDecision(situation)
    }

    public func personnel(
        for concept: PlayConcept, situation: Situation, classified: SituationClass,
        random: inout SplittableRandom
    ) -> PersonnelGroup {
        .eleven
    }

    public func package(
        for situation: Situation, classified: SituationClass, random: inout SplittableRandom
    ) -> DefensivePackage {
        .base
    }
}

// MARK: - The resolver

/// Answers every snap with whatever the scenario's closure says, and keeps the one fact
/// the record does not carry: whether the clock was running into each snap.
struct ScenarioResolver: PlayResolver {

    let script: @Sendable (Snap) -> Outcome
    /// Whether the play clock in force runs out before this snap (2025 rulebook, 4-6-1,
    /// 4-6-2). Never, unless the scenario says so: a scripted game has no offence to be
    /// late, so the clock is the one thing a scenario about the play clock has to state.
    let playClockExpires: @Sendable (Snap) -> Bool
    /// Which side, if either, has a player hurt on the snap — the scenario's say, read
    /// off the snap and the outcome the script gave it, and kept in the log so that the
    /// game's injury draw can hand the rules layer a real player of that side.
    let injury: @Sendable (Snap, Outcome) -> Side?
    let log: Log

    /// The sim resolves plays one at a time, in order, so the entry count is the play
    /// index. Behind a mutex only because the protocol is `Sendable`.
    final class Log: Sendable {
        private let state = Mutex<State>(State())

        struct Entry: Sendable {
            let clockIsRunning: Bool
            let situation: Situation
            let outcome: Outcome
            let injured: Side?
        }

        private struct State {
            var entries: [Entry] = []
            var huddle: UInt16?
        }

        /// Whether the clock was running into each **recorded** snap.
        ///
        /// The resolver is asked about a down before the rules layer knows whether the
        /// down happened: a period the interval before the snap exhausts ends there and
        /// nothing is snapped or written (2025 rulebook, 4-8-1). So there is one entry
        /// per question and one play per answer that counted, and the two are paired
        /// here by the period they belong to — the only entry that can go unanswered is
        /// one at the end of a period, and the play that follows it is in the next.
        func clockRunning(alignedTo plays: [PlayRecord]) -> [Bool] {
            state.withLock { state in
                var aligned: [Bool] = []
                var index = state.entries.startIndex
                for play in plays {
                    while index < state.entries.endIndex,
                        state.entries[index].situation.quarter != play.situation.quarter
                    {
                        index += 1
                    }
                    guard index < state.entries.endIndex else { break }
                    aligned.append(state.entries[index].clockIsRunning)
                    index += 1
                }
                return aligned
            }
        }

        /// The offence's tempo, from the first pair of snaps in one period that showed
        /// it: the clock ran into the first, and the second came later than the first
        /// play's own duration accounts for.
        var huddle: UInt16? { state.withLock { $0.huddle } }

        fileprivate func previous() -> Snap.Previous? {
            state.withLock {
                $0.entries.last.map { Snap.Previous(situation: $0.situation, outcome: $0.outcome) }
            }
        }

        fileprivate func count() -> Int { state.withLock { $0.entries.count } }

        /// The side the scenario had a player hurt on the snap just resolved, if any.
        ///
        /// The last entry and not the play's index: the injury draw runs immediately
        /// after the snap the resolver was last asked about, and a down the clock never
        /// reached leaves an entry with no play, so the two numberings part company.
        fileprivate func injuredOnTheLastSnap() -> Side? {
            state.withLock { $0.entries.last?.injured }
        }

        fileprivate func append(_ entry: Entry) {
            state.withLock { state in
                if state.huddle == nil, let last = state.entries.last, last.clockIsRunning,
                    last.situation.quarter == entry.situation.quarter
                {
                    let elapsed =
                        Int(last.situation.clockRemaining) - Int(last.outcome.clockRunoff)
                        - Int(entry.situation.clockRemaining)
                    if elapsed > 0 { state.huddle = UInt16(elapsed) }
                }
                state.entries.append(entry)
            }
        }
    }

    /// The snap as the scenario's closures see it, built from what the resolver is
    /// handed. Nothing is logged here: the log is the record of snaps that were
    /// resolved, and this is also built for the questions asked before one is.
    private func snap(_ situation: Situation, _ calls: Calls, _ context: PlayContext) -> Snap {
        Snap(
            index: log.count(), situation: situation, calls: calls,
            offense: context.offense, defense: context.defense,
            clockIsRunning: context.clockIsRunning, previous: log.previous(), huddle: log.huddle)
    }

    func resolve(
        situation: Situation, calls: Calls, onField: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let snap = self.snap(situation, calls, context)
        // A play clock the scenario said would expire: the ball stays dead and the
        // whistle is the foul (4-6-4), so there is no play for the script to describe.
        let outcome = playClockExpires(snap) ? snap.preSnapFoul(.delayOfGame) : script(snap)
        log.append(
            .init(
                clockIsRunning: context.clockIsRunning, situation: situation, outcome: outcome,
                injured: injury(snap, outcome)))
        return (outcome, [])
    }

    /// The injury the scenario dictated on `play`, if any, as the game's injury draw:
    /// the first man of that side's rotation, hurt on the play and back for the next
    /// one — the stoppage is the point, not the absence.
    func scriptedInjury(
        on play: PlayRecord, context: PlayContext
    ) -> InjuryEvent? {
        guard let side = log.injuredOnTheLastSnap() else { return nil }
        let rotation = side == .offense ? context.offenseRotation : context.defenseRotation
        guard let hurt = rotation.first?.player else { return nil }
        return InjuryEvent(player: hurt, occurredOn: play.id, cause: .contact, gamesOut: 0)
    }
}

// MARK: - The game

/// A game whose plays the scenario dictates.
public struct ScriptedGame {

    public var seed: UInt64
    public var rules: Rules
    public var isPostseason: Bool
    public var caller: ScriptedCaller
    /// Which side, if either, has a player hurt on a snap, given the snap and what the
    /// script made of it. Nobody, unless the scenario says so: a scripted outcome
    /// credits no participants, so the game's own injury draw never fires.
    public var injury: @Sendable (Snap, Outcome) -> Side?
    /// Whether the offence fails to get this snap away before the play clock in force
    /// expires (2025 rulebook, 4-6-1, 4-6-2). Never, unless the scenario says so.
    ///
    /// It states the *cause*, not the consequence: what an expired play clock costs —
    /// five yards, the down replayed (4-6-4, 14-4-1), or nothing at all because
    /// somebody stopped the clock first (4-3-2) — is the rules layer's and the benches',
    /// which is exactly what a scenario about the play clock is there to observe.
    public var playClockExpires: @Sendable (Snap) -> Bool
    public var play: @Sendable (Snap) -> Outcome

    public init(
        seed: UInt64 = 1,
        rules: Rules = .standard,
        isPostseason: Bool = false,
        caller: ScriptedCaller = ScriptedCaller(),
        injury: @escaping @Sendable (Snap, Outcome) -> Side? = { _, _ in nil },
        playClockExpires: @escaping @Sendable (Snap) -> Bool = { _ in false },
        play: @escaping @Sendable (Snap) -> Outcome
    ) {
        self.seed = seed
        self.rules = rules
        self.isPostseason = isPostseason
        self.caller = caller
        self.injury = injury
        self.playClockExpires = playClockExpires
        self.play = play
    }

    public func run() -> Trace {
        run(with: caller)
    }

    /// The same scripted plays under a different caller, for the scenarios about what a
    /// caller does rather than what the rules do with it.
    public func run(with caller: some FMSimulation.PlayCaller) -> Trace {
        let setup = ScenarioWorld.setup(seed: seed, rules: rules, isPostseason: isPostseason)
        let log = ScenarioResolver.Log()
        let resolver = ScenarioResolver(
            script: play, playClockExpires: playClockExpires, injury: injury, log: log)
        let result = GameSimulator(
            resolver: resolver, caller: caller,
            injuries: { play, context, _ in resolver.scriptedInjury(on: play, context: context) }
        )
        .simulate(setup)
        return Trace(
            result: result, clockRunning: log.clockRunning(alignedTo: result.plays),
            huddle: log.huddle,
            home: setup.home.id, away: setup.away.id)
    }
}

// MARK: - What happened, and the assertions over it

/// A scripted game's stream, with the clock facts alongside it.
///
/// The assertions a rules scenario makes over one of these live in the test target, as an
/// extension: this type is what a printer walks and what a test asserts on, and only the
/// second of those may import Swift Testing.
public struct Trace {

    public let result: GameResult
    /// Whether the clock was running into each snap, by play index.
    public let clockRunning: [Bool]
    /// The offence's tempo between plays on a running clock, measured; see `Snap.huddle`.
    public let huddle: UInt16?
    public let home: TeamID
    public let away: TeamID

    public var plays: [PlayRecord] { result.plays }

    public subscript(index: Int) -> PlayRecord? {
        plays.indices.contains(index) ? plays[index] : nil
    }

    public func clockRunning(into index: Int) -> Bool? {
        clockRunning.indices.contains(index) ? clockRunning[index] : nil
    }

    public func opponent(of team: TeamID) -> TeamID {
        team == home ? away : home
    }

    public func score(of team: TeamID) -> Int16 {
        team == home ? result.homeScore : result.awayScore
    }

    /// The first play satisfying the predicate, with its index.
    public func first(where predicate: (PlayRecord) -> Bool) -> (index: Int, play: PlayRecord)? {
        plays.firstIndex(where: predicate).map { ($0, plays[$0]) }
    }

    /// The number of plays satisfying the predicate.
    public func count(where predicate: (PlayRecord) -> Bool) -> Int {
        plays.filter(predicate).count
    }
}
