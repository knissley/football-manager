import FMCore
import FMRandom
import Synchronization
import Testing

@testable import FMSimulation

// A game whose plays a scenario dictates, so that what is left to observe is the rules
// layer: the clock, the downs, possession, scoring, enforcement and overtime.
//
// The resolver is a closure over the snap it is asked to resolve, and the caller is a
// handful of closures with plain defaults, so a scenario reads as football — *when it is
// the fourth quarter, inside a minute, and this side trails by seven: a touchdown as time
// expires* — and never as an index into a script. Every play the scenario does not care
// about honours the call it was given and changes nothing worth noticing.
//
// Nothing in here draws a random number. The world comes from `TestWorld` at a seed, and
// the sim's own stream is never read, so a scenario replays identically every time.

// MARK: - One snap, as a scenario sees it

/// One snap, as the scenario's resolver sees it.
///
/// The situation and the calls are what `PlayResolver` receives. `clockIsRunning` is the
/// one fact from the context worth surfacing: it is the rules layer's own verdict on the
/// play before, and it is what every clock scenario asserts on. `previous` is the snap
/// before this one and `huddle` the offence's measured tempo, for the scenarios that
/// stage a play to end at a particular second.
struct Snap: Sendable {

    let index: Int
    let situation: Situation
    let calls: Calls
    let offense: TeamID
    let defense: TeamID
    let clockIsRunning: Bool
    let previous: Previous?

    /// The snap before this one, and what the scenario made of it.
    struct Previous: Sendable {
        let situation: Situation
        let outcome: Outcome
    }

    var quarter: UInt8 { situation.quarter }
    var clock: UInt16 { situation.clockRemaining }
    var down: Down { situation.down }
    var distance: UInt8 { situation.distance }
    var ballOn: UInt8 { situation.ballOn }
    var possession: TeamID { situation.possession }
    /// The score from the possessing team's point of view.
    var differential: Int16 { situation.scoreDifferential }

    var family: PlayFamily? { CrudePlaybook.family(of: calls.offense.design) }

    var isScrimmage: Bool {
        guard let family else { return false }
        return PlayFamily.scrimmage.contains(family) || family == .kneel || family == .spike
    }
    var isTry: Bool { family == .extraPoint || family == .twoPointConversion }
    var isKickoff: Bool { family == .kickoff || family == .onsideKick }

    /// The seconds the offence takes between the end of one play and the snap of the
    /// next when the clock is running — its tempo — measured from the plays so far rather
    /// than assumed. `nil` until two snaps have shown it.
    ///
    /// The engine records a play's situation at the moment the previous play ended and
    /// charges the huddle at the snap, so a play snapped with the clock running ends at
    /// `clock - huddle - clockRunoff`. A scenario that needs a play to end at a particular
    /// second stretches its runoff by this.
    let huddle: UInt16?
}

// MARK: - The vocabulary of scripted outcomes

extension Snap {

    /// Honours the call and changes nothing worth noticing.
    var neutral: Outcome {
        switch family {
        case .kickoff: return .kickoffTouchback
        case .onsideKick: return .onsideKick(lostAtOwn: 45)
        case .punt: return .puntTouchback
        case .fieldGoal: return .fieldGoal(good: true)
        case .extraPoint: return .extraPoint(good: true)
        case .twoPointConversion: return .twoPoint(converted: false)
        case .kneel: return Outcome(kind: .kneel, yards: -1, endedIn: .tackled, clockRunoff: 2)
        case .spike: return .spike
        default:
            // A one-yard gain of whatever kind was called, tackled in bounds: the ball
            // moves, the clock runs, and the down changes hands on downs every four plays.
            return Outcome(
                kind: family?.kind ?? .rush, yards: 1, endedIn: .tackled, clockRunoff: 6)
        }
    }

    /// The ball carried into the end zone from wherever it was spotted.
    func touchdown(seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .rush, yards: Int16(ballOn), endedIn: .touchdown, clockRunoff: seconds)
    }

    /// A touchdown on a play that runs the period's clock to zero.
    func touchdownAsTimeExpires() -> Outcome {
        Outcome(
            kind: .rush, yards: Int16(ballOn), endedIn: .touchdown, clockRunoff: max(1, clock))
    }

    /// The ball carrier tackled in his own end zone.
    func safety(seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .sack, yards: -(100 - Int16(ballOn)), endedIn: .safety, clockRunoff: seconds)
    }

    /// A flag before the snap. No play happens; the record carries the foul and nothing
    /// else, which is the contract the crude resolver honours for the same event.
    func preSnapFoul(_ foul: Foul) -> Outcome {
        Outcome(
            kind: .penaltyOnly, yards: 0, endedIn: .penaltyEnforced,
            penalties: [record(foul)], clockRunoff: 0)
    }

    /// A run that ends in a flag on the man who made the tackle, or on a blocker.
    func rush(_ yards: Int16, foulBy foul: Foul, seconds: UInt16 = 6) -> Outcome {
        Outcome(
            kind: .rush, yards: yards, endedIn: .tackled, penalties: [record(foul)],
            clockRunoff: seconds)
    }

    /// A pass that falls incomplete because a defender interfered, `depth` yards past
    /// the line of scrimmage. Interference is measured rather than fixed, and the
    /// resolver's contract carries the spot in the offence's frame, with zero meaning
    /// the end zone.
    func incompletion(interferenceAt depth: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .pass, yards: 0, endedIn: .incomplete,
            penalties: [
                PenaltyRecord(
                    foul: .defensivePassInterference, offender: PlayerSlot(11),
                    offendingTeam: defense, yards: min(depth, ballOn), wasAccepted: false,
                    enforcementSpot: UInt8(max(0, Int(ballOn) - Int(depth))))
            ],
            clockRunoff: seconds)
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
    static func rush(
        _ yards: Int16, seconds: UInt16 = 6, endedIn: PlayEnding = .tackled
    )
        -> Outcome
    {
        Outcome(kind: .rush, yards: yards, endedIn: endedIn, clockRunoff: seconds)
    }

    static func incompletion(seconds: UInt16 = 5) -> Outcome {
        Outcome(kind: .pass, yards: 0, endedIn: .incomplete, clockRunoff: seconds)
    }

    static let spike = Outcome(kind: .spike, yards: 0, endedIn: .incomplete, clockRunoff: 1)

    /// Picked off and returned to `spot`, in the throwing team's frame: 100 is the
    /// interceptor's own goal line crossed the other way, a touchdown.
    static func interception(to spot: UInt8, seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .pass, yards: 0, endedIn: .intercepted, finalSpot: spot, clockRunoff: seconds)
    }

    static let pickSix = interception(to: 100, seconds: 12)

    /// A fumble the defence comes up with, at `spot` in the fumbling team's frame.
    static func fumble(lostAt spot: UInt8, seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .rush, yards: 0, endedIn: .fumbleLost, finalSpot: spot, clockRunoff: seconds)
    }

    /// A fumble the offence falls on, `yards` past the line.
    static func fumble(recoveredAfter yards: Int16, seconds: UInt16 = 6) -> Outcome {
        Outcome(kind: .rush, yards: yards, endedIn: .fumbleRecovered, clockRunoff: seconds)
    }

    static let kickoffTouchback = Outcome(kind: .kickoff, yards: 0, endedIn: .touchback)

    /// Fielded and brought out to the returner's own `yard` line, which is the same
    /// number in the kicking team's frame.
    static func kickoffReturn(toOwn yard: UInt8, seconds: UInt16 = 8) -> Outcome {
        Outcome(kind: .kickoff, yards: 0, endedIn: .tackled, finalSpot: yard, clockRunoff: seconds)
    }

    static let kickoffReturnTouchdown = Outcome(
        kind: .kickoff, yards: 0, endedIn: .touchdown, finalSpot: 100, clockRunoff: 14)

    /// The kicking team falls on its own kick, `ballOn` from the goal it is attacking.
    /// `.fumbleRecovered` on a kickoff is how the contract says the kick did not change
    /// hands.
    static func onsideKick(recoveredAt ballOn: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(
            kind: .kickoff, yards: 0, endedIn: .fumbleRecovered, finalSpot: ballOn,
            clockRunoff: seconds)
    }

    /// The receiving team falls on it at its own `yard` line.
    static func onsideKick(lostAtOwn yard: UInt8, seconds: UInt16 = 5) -> Outcome {
        Outcome(kind: .kickoff, yards: 0, endedIn: .tackled, finalSpot: yard, clockRunoff: seconds)
    }

    static let puntTouchback = Outcome(kind: .punt, yards: 0, endedIn: .touchback, clockRunoff: 6)

    /// A punt that ends at the receiving team's own `yard` line, however it ended there.
    static func punt(
        toOwn yard: UInt8, endedIn: PlayEnding = .fairCatch, seconds: UInt16 = 6
    )
        -> Outcome
    {
        Outcome(kind: .punt, yards: 0, endedIn: endedIn, finalSpot: yard, clockRunoff: seconds)
    }

    static func fieldGoal(good: Bool) -> Outcome {
        Outcome(
            kind: .fieldGoal, yards: 0, endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
            clockRunoff: 5)
    }

    static func extraPoint(good: Bool) -> Outcome {
        Outcome(
            kind: .extraPoint, yards: 0, endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
            clockRunoff: 0)
    }

    static func twoPoint(converted: Bool) -> Outcome {
        Outcome(
            kind: .twoPointConversion, yards: converted ? 2 : 0,
            endedIn: converted ? .touchdown : .incomplete, clockRunoff: 0)
    }
}

// MARK: - A caller that does what the scenario says

/// A caller with no opinions of its own.
///
/// Every decision is a closure over the situation with a plain default: an inside run on
/// every scrimmage down, at normal tempo, no timeouts, a kick after every touchdown and
/// a deep kickoff. A scenario overrides the one or two that matter to it, so a rules
/// scenario is never at the mercy of the baseline caller's judgement.
struct ScriptedCaller: FMSimulation.PlayCaller {

    var offensiveFamily: @Sendable (Situation) -> PlayFamily = { _ in .insideRun }
    var offensiveTempo: @Sendable (Situation) -> Tempo = { _ in .normal }
    var timeoutDecision: @Sendable (_ situation: Situation, _ isOffense: Bool) -> Bool = {
        _, _ in false
    }
    var twoPointDecision: @Sendable (Situation) -> Bool = { _ in false }
    var onsideDecision: @Sendable (Situation) -> Bool = { _ in false }

    func offensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> OffensiveCall {
        CrudePlaybook.call(offensiveFamily(situation), tempo: offensiveTempo(situation))
    }

    func defensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> DefensiveCall {
        .baseCoverThree
    }

    func callsTimeout(
        for situation: Situation, classified: SituationClass, isOffense: Bool,
        context: PlayContext
    ) -> Bool {
        timeoutDecision(situation, isOffense)
    }

    func goesForTwo(situation: Situation, classified: SituationClass) -> Bool {
        twoPointDecision(situation)
    }

    func kicksOnside(situation: Situation, classified: SituationClass) -> Bool {
        onsideDecision(situation)
    }

    func personnel(
        for family: PlayFamily, situation: Situation, classified: SituationClass,
        random: inout SplittableRandom
    ) -> PersonnelGroup {
        .eleven
    }

    func package(
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
    let log: Log

    /// The sim resolves plays one at a time, in order, so the entry count is the play
    /// index. Behind a mutex only because the protocol is `Sendable`.
    final class Log: Sendable {
        private let state = Mutex<State>(State())

        struct Entry: Sendable {
            let clockIsRunning: Bool
            let situation: Situation
            let outcome: Outcome
        }

        private struct State {
            var entries: [Entry] = []
            var huddle: UInt16?
        }

        var clockRunning: [Bool] { state.withLock { $0.entries.map(\.clockIsRunning) } }

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

    func resolve(
        situation: Situation, calls: Calls, context: PlayContext, random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let snap = Snap(
            index: log.count(), situation: situation, calls: calls,
            offense: context.offense, defense: context.defense,
            clockIsRunning: context.clockIsRunning, previous: log.previous(), huddle: log.huddle)
        let outcome = script(snap)
        log.append(
            .init(clockIsRunning: context.clockIsRunning, situation: situation, outcome: outcome))
        return (outcome, [])
    }
}

// MARK: - The game

/// A game whose plays the scenario dictates.
struct ScriptedGame {

    var seed: UInt64
    var rules: Rules
    var isPostseason: Bool
    var caller: ScriptedCaller
    var play: @Sendable (Snap) -> Outcome

    init(
        seed: UInt64 = 1,
        rules: Rules = .standard,
        isPostseason: Bool = false,
        caller: ScriptedCaller = ScriptedCaller(),
        play: @escaping @Sendable (Snap) -> Outcome
    ) {
        self.seed = seed
        self.rules = rules
        self.isPostseason = isPostseason
        self.caller = caller
        self.play = play
    }

    func run() -> Trace {
        run(with: caller)
    }

    /// The same scripted plays under a different caller, for the scenarios about what a
    /// caller does rather than what the rules do with it.
    func run(with caller: some FMSimulation.PlayCaller) -> Trace {
        let setup = TestWorld.setup(seed: seed, rules: rules, isPostseason: isPostseason)
        let log = ScenarioResolver.Log()
        let result = GameSimulator(
            resolver: ScenarioResolver(script: play, log: log), caller: caller
        )
        .simulate(setup)
        return Trace(
            result: result, clockRunning: log.clockRunning, huddle: log.huddle,
            home: setup.home.id, away: setup.away.id)
    }
}

// MARK: - What happened, and the assertions over it

/// A scripted game's stream, with the clock facts alongside it and the assertions a
/// rules scenario makes.
struct Trace {

    let result: GameResult
    /// Whether the clock was running into each snap, by play index.
    let clockRunning: [Bool]
    /// The offence's tempo between plays on a running clock, measured; see `Snap.huddle`.
    let huddle: UInt16?
    let home: TeamID
    let away: TeamID

    var plays: [PlayRecord] { result.plays }

    subscript(index: Int) -> PlayRecord? {
        plays.indices.contains(index) ? plays[index] : nil
    }

    func clockRunning(into index: Int) -> Bool? {
        clockRunning.indices.contains(index) ? clockRunning[index] : nil
    }

    func opponent(of team: TeamID) -> TeamID {
        team == home ? away : home
    }

    func score(of team: TeamID) -> Int16 {
        team == home ? result.homeScore : result.awayScore
    }

    /// The first play satisfying the predicate, with its index.
    func first(where predicate: (PlayRecord) -> Bool) -> (index: Int, play: PlayRecord)? {
        plays.firstIndex(where: predicate).map { ($0, plays[$0]) }
    }

    /// The number of plays satisfying the predicate.
    func count(where predicate: (PlayRecord) -> Bool) -> Int {
        plays.filter(predicate).count
    }

    // MARK: Assertions

    /// One play, checked against every fact the scenario names. A `nil` fact is not
    /// checked. A missing play is one failure, not ten.
    func expectPlay(
        _ index: Int,
        kind: PlayKind? = nil,
        endedIn: PlayEnding? = nil,
        possession: TeamID? = nil,
        quarter: UInt8? = nil,
        clock: UInt16? = nil,
        down: Down? = nil,
        distance: UInt8? = nil,
        ballOn: UInt8? = nil,
        clockRunning: Bool? = nil,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let play = self[index] else {
            Issue.record(
                "no play \(index): the game had \(plays.count) — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
            return
        }
        let at = "play \(index)"
        if let kind {
            #expect(
                play.outcome.kind == kind, "\(at) kind — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let endedIn {
            #expect(
                play.outcome.endedIn == endedIn, "\(at) ending — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let possession {
            #expect(
                play.situation.possession == possession,
                "\(at) possession — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let quarter {
            #expect(
                play.situation.quarter == quarter,
                "\(at) quarter — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let clock {
            #expect(
                play.situation.clockRemaining == clock,
                "\(at) clock — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let down {
            #expect(
                play.situation.down == down, "\(at) down — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let distance {
            #expect(
                play.situation.distance == distance,
                "\(at) distance — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let ballOn {
            #expect(
                play.situation.ballOn == ballOn,
                "\(at) ball on — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
        if let clockRunning {
            #expect(
                self.clockRunning(into: index) == clockRunning,
                "\(at) clock running into the snap — \(comment?.description ?? "")",
                sourceLocation: sourceLocation)
        }
    }

    func expectScore(
        _ team: TeamID, _ points: Int16, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            score(of: team) == points,
            "score of \(team == home ? "home" : "away") — \(comment?.description ?? "")",
            sourceLocation: sourceLocation)
    }

    func expectScore(
        home homePoints: Int16, away awayPoints: Int16, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        expectScore(home, homePoints, comment, sourceLocation: sourceLocation)
        expectScore(away, awayPoints, comment, sourceLocation: sourceLocation)
    }

    /// The kinds of the plays from `index` on, in order.
    func expectSequence(
        _ kinds: [PlayKind], from index: Int, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = plays.dropFirst(index).prefix(kinds.count).map(\.outcome.kind)
        #expect(
            Array(actual) == kinds,
            "plays from \(index) — \(comment?.description ?? "")", sourceLocation: sourceLocation)
    }

    func expectWinner(
        _ team: TeamID?, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(result.winner == team, comment, sourceLocation: sourceLocation)
    }

    /// The game's last play is the one at `index`: nothing was played after it.
    func expectLastPlay(
        _ index: Int, _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            plays.count == index + 1,
            "the game went on for \(plays.count - index - 1) more plays — \(comment?.description ?? "")",
            sourceLocation: sourceLocation)
    }
}
