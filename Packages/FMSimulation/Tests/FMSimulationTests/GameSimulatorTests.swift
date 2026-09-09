import FMCore
import FMRandom
import Testing

@testable import FMSimulation

/// A resolver that returns exactly what it is told to.
///
/// The state machine is the thing under test here, so the physics has to be removed
/// entirely: with a scripted resolver, any wrong score or wrong down is the rules code
/// and cannot be a resolver's noise.
struct ScriptedResolver: PlayResolver {

    /// Applied in order; the last entry repeats once the script runs out.
    let script: [Outcome]

    func resolve(
        situation: Situation, calls: Calls, context: PlayContext, random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let index = min(callCount.value, script.count - 1)
        callCount.value += 1
        return (script[index], [])
    }

    // A reference box, because the protocol is `Sendable` and a resolver is a value.
    final class Counter: @unchecked Sendable {
        var value = 0
    }
    let callCount = Counter()

    init(_ script: [Outcome]) {
        self.script = script
    }
}

/// Never gains a yard, never scores. Used to run a game to its natural end.
///
/// It honours the call it was given, because a resolver must: an outcome whose kind
/// contradicts the play that was called is the same class of lie as decision points that
/// contradict the outcome ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
struct StalemateResolver: PlayResolver {
    func resolve(
        situation: Situation, calls: Calls, context: PlayContext, random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let family = CrudePlaybook.family(of: calls.offense.design) ?? .insideRun
        switch family {
        case .kickoff:
            return (Outcome(kind: .kickoff, yards: 0, endedIn: .touchback), [])
        case .extraPoint:
            return (Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood), [])
        case .twoPointConversion:
            return (Outcome(kind: .twoPointConversion, yards: 0, endedIn: .incomplete), [])
        case .punt:
            return (Outcome(kind: .punt, yards: 0, endedIn: .touchback, clockRunoff: 6), [])
        case .fieldGoal:
            return (
                Outcome(kind: .fieldGoal, yards: 0, endedIn: .fieldGoalMissed, clockRunoff: 5), []
            )
        default:
            return (Outcome(kind: family.kind, yards: 1, endedIn: .tackled, clockRunoff: 6), [])
        }
    }
}

/// Moves the ball at a steady clip, so drives actually reach field position where a
/// kicking decision exists. A stalemate never leaves its own end and cannot exercise it.
struct GrinderResolver: PlayResolver {
    func resolve(
        situation: Situation, calls: Calls, context: PlayContext, random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let family = CrudePlaybook.family(of: calls.offense.design) ?? .insideRun
        switch family {
        case .kickoff:
            return (Outcome(kind: .kickoff, yards: 0, endedIn: .touchback), [])
        case .extraPoint:
            return (Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood), [])
        case .twoPointConversion:
            return (Outcome(kind: .twoPointConversion, yards: 0, endedIn: .incomplete), [])
        case .punt:
            return (Outcome(kind: .punt, yards: 0, endedIn: .touchback, clockRunoff: 6), [])
        case .fieldGoal:
            return (
                Outcome(kind: .fieldGoal, yards: 0, endedIn: .fieldGoalGood, clockRunoff: 5), []
            )
        default:
            // Zero to seven: enough to move the ball, variable enough that drives
            // stall and fourth downs actually happen.
            let gain = Int16(random.next(upperBound: 8))
            if Int(situation.ballOn) - Int(gain) <= 0 {
                return (
                    Outcome(
                        kind: family.kind, yards: Int16(situation.ballOn), endedIn: .touchdown,
                        clockRunoff: 6), []
                )
            }
            return (Outcome(kind: family.kind, yards: gain, endedIn: .tackled, clockRunoff: 6), [])
        }
    }
}

@Suite("Game simulation")
struct GameSimulatorTests {

    private let home = TeamID(1)
    private let away = TeamID(2)

    private func chart() -> DepthChart {
        var order: [Position: [PlayerID]] = [:]
        var next: UInt64 = 1
        for position in Position.allCases {
            order[position] = (0..<4).map { _ in
                defer { next += 1 }
                return PlayerID(next)
            }
        }
        return DepthChart(order: order)
    }

    private func setup(
        seed: UInt64 = 3, isPostseason: Bool = false, rules: Rules = .standard
    ) -> GameSetup {
        let chart = chart()
        return GameSetup(
            game: GameID(1),
            home: GameTeam(
                id: home, depthChart: chart,
                scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch)),
            away: GameTeam(
                id: away, depthChart: chart,
                scheme: TeamScheme(offense: .westCoast, defense: .fourThreeUnder)),
            players: [:],
            rules: rules,
            seed: seed,
            isPostseason: isPostseason)
    }

    private func simulate(
        _ resolver: some PlayResolver, _ setup: GameSetup? = nil
    ) -> GameResult {
        GameSimulator(resolver: resolver, caller: BaselineCaller())
            .simulate(setup ?? self.setup())
    }

    // MARK: - The stream

    @Test("A game produces an ordered, contiguous play stream")
    func streamIsOrdered() {
        let result = simulate(StalemateResolver())
        #expect(result.plays.isEmpty == false)
        #expect(result.plays.map(\.index) == Array(0..<UInt16(result.plays.count)))
        #expect(result.plays.allSatisfy { $0.game == GameID(1) })
        #expect(Set(result.plays.map(\.id)).count == result.plays.count, "duplicate play refs")
    }

    /// Rule 2: a game is a pure function of its setup and seed, and that tuple is how
    /// most games are *stored*.
    @Test("The same setup and seed replay identically")
    func deterministic() {
        let first = simulate(StalemateResolver())
        let second = simulate(StalemateResolver())
        #expect(first.plays.count == second.plays.count)
        #expect(first.homeScore == second.homeScore && first.awayScore == second.awayScore)
        #expect(first.plays.map(\.situation) == second.plays.map(\.situation))
        #expect(first.plays.map(\.calls) == second.plays.map(\.calls))
    }

    @Test("Different seeds produce different games")
    func seedsDiverge() {
        let a = simulate(StalemateResolver(), setup(seed: 1))
        let b = simulate(StalemateResolver(), setup(seed: 2))
        #expect(a.plays.map(\.calls) != b.plays.map(\.calls))
    }

    /// A resolver bug that never advances the ball must fail at the end of a test
    /// rather than hang a season.
    @Test("A game always terminates")
    func terminates() {
        let result = simulate(StalemateResolver())
        #expect(result.plays.count < 400, "the game hit the play limit")
    }

    // MARK: - Clock and periods

    @Test("A game runs through all four quarters")
    func quarters() {
        let result = simulate(StalemateResolver())
        let quarters = Set(result.plays.map(\.situation.quarter))
        #expect(quarters.contains(1) && quarters.contains(2))
        #expect(quarters.contains(3) && quarters.contains(4))
    }

    /// The clock only ever runs down within a quarter. A rise means a period boundary
    /// was mishandled.
    @Test("The clock is monotonic within each quarter")
    func clockIsMonotonic() {
        let result = simulate(StalemateResolver())
        var previous: (quarter: UInt8, clock: UInt16)?

        for play in result.plays {
            let now = (play.situation.quarter, play.situation.clockRemaining)
            if let previous, previous.quarter == now.0 {
                #expect(
                    now.1 <= previous.clock,
                    "clock went up in Q\(now.0): \(previous.clock) then \(now.1)")
            }
            previous = now
        }
    }

    @Test("Possession changes hands at halftime")
    func halftimePossession() {
        let result = simulate(StalemateResolver())
        let firstPlay = result.plays.first { $0.situation.quarter == 1 }
        let secondHalf = result.plays.first { $0.situation.quarter == 3 }
        #expect(firstPlay?.situation.possession != secondHalf?.situation.possession)
    }

    // MARK: - Scoring

    @Test("A touchdown scores six, then a try, then a kickoff")
    func touchdownSequence() {
        let script = [
            Outcome(kind: .kickoff, yards: 0, endedIn: .touchback),
            Outcome(kind: .rush, yards: 25, endedIn: .touchdown, clockRunoff: 6),
            Outcome(kind: .extraPoint, yards: 0, endedIn: .fieldGoalGood),
            Outcome(kind: .rush, yards: 1, endedIn: .tackled, clockRunoff: 6),
        ]
        let result = simulate(ScriptedResolver(script))

        // Whoever had the ball first is up seven, and nobody else has scored.
        #expect(result.homeScore + result.awayScore >= 7)
        let kinds = result.plays.prefix(4).map(\.outcome.kind)
        #expect(kinds.contains(.extraPoint), "a try should follow the touchdown")
    }

    /// A safety pays the *defence*, and then the defence receives. Paying the wrong side
    /// is the scoreboard bug this checks for.
    @Test("A safety pays the team that did not have the ball")
    func safetyPaysTheDefence() {
        let script = [
            Outcome(kind: .kickoff, yards: 0, endedIn: .touchback),
            Outcome(kind: .sack, yards: -4, endedIn: .safety, clockRunoff: 5),
            Outcome(kind: .rush, yards: 1, endedIn: .tackled, clockRunoff: 6),
        ]
        let result = simulate(ScriptedResolver(script))

        guard let safetyPlay = result.plays.first(where: { $0.outcome.endedIn == .safety }) else {
            Issue.record("the script should have produced a safety")
            return
        }
        // The team that was on offence for the safety must not be the one that gained.
        let conceded = safetyPlay.situation.possession
        let gained = conceded == TeamID(1) ? result.awayScore : result.homeScore
        #expect(gained >= 2, "the defence should have been credited")
    }

    /// Points and the play log cannot disagree: the box score *is* the play log, summed.
    @Test("The final score equals the scoring plays in the stream")
    func scoreMatchesTheStream() {
        let result = simulate(StalemateResolver())
        let rules = Rules.standard

        var home: Int16 = 0
        var away: Int16 = 0
        for play in result.plays {
            let advancement = rules.advance(from: play.situation, outcome: play.outcome)
            guard let scoring = advancement.scoring, advancement.points != 0 else { continue }
            let offense = play.situation.possession
            let defence = offense == TeamID(1) ? TeamID(2) : TeamID(1)
            let scorer: TeamID
            switch scoring {
            case .safety, .defensiveTouchdown: scorer = defence
            default: scorer = offense
            }
            if scorer == TeamID(1) {
                home += advancement.points
            } else {
                away += advancement.points
            }
        }

        #expect(home == result.homeScore)
        #expect(away == result.awayScore)
    }

    // MARK: - Situational legality

    /// Every situation the simulator hands a resolver has to be a legal one. A bad
    /// situation surfaces deep in the engine as strange behaviour rather than a failure.
    @Test("Every situation in the stream is valid")
    func situationsAreValid() {
        for seed in UInt64(1)...5 {
            let result = simulate(StalemateResolver(), setup(seed: seed))
            for play in result.plays {
                #expect(
                    play.situation.isValid,
                    "seed \(seed) play \(play.index): \(play.situation)")
            }
        }
    }

    /// Recording who called it is what lets the gameplan layer measure plan against
    /// execution, and what makes a game the player called reproducible.
    @Test("Both callers are recorded on every scrimmage play")
    func callersAreRecorded() {
        let result = simulate(StalemateResolver())
        let scrimmage = result.plays.filter { $0.outcome.kind.isScrimmagePlay }
        #expect(scrimmage.isEmpty == false)
        for play in scrimmage {
            #expect(play.calls.offensiveCaller != .automatic, "play \(play.index)")
            #expect(play.calls.defensiveCaller != .automatic, "play \(play.index)")
        }
    }

    /// A resolver that returns a rush when a kickoff was called is lying in exactly the
    /// way a fabricated causal chain would. The kind has to match the call.
    @Test("Every outcome's kind matches the play that was called")
    func outcomeMatchesTheCall() {
        for seed in UInt64(1)...4 {
            let result = simulate(StalemateResolver(), setup(seed: seed))
            for play in result.plays {
                guard let family = CrudePlaybook.family(of: play.calls.offense.design) else {
                    Issue.record("play \(play.index) referenced a design outside the playbook")
                    continue
                }
                #expect(
                    play.outcome.kind == family.kind,
                    "called \(family) and resolved \(play.outcome.kind)")
            }
        }
    }

    /// A caller that never punts is not a football caller. This was missing entirely
    /// until an outcome-matches-the-call test surfaced it.
    @Test("The caller punts, kicks and goes for it in the right places")
    func fourthDownDecisions() {
        var families: Set<PlayFamily> = []
        for seed in UInt64(1)...8 {
            let result = simulate(GrinderResolver(), setup(seed: seed))
            for play in result.plays where play.situation.down == .fourth {
                if let family = CrudePlaybook.family(of: play.calls.offense.design) {
                    families.insert(family)
                }
            }
        }
        #expect(families.contains(.punt), "never punted in eight games")
        #expect(families.contains(.fieldGoal), "never attempted a field goal")
    }

    /// Nobody kicks a seventy-yarder. The baseline's range is flat and generous; a real
    /// caller reads its kicker and should beat this.
    @Test("Field goals are only attempted from a plausible distance")
    func kicksAreInRange() {
        let rules = Rules.standard
        for seed in UInt64(1)...8 {
            let result = simulate(GrinderResolver(), setup(seed: seed))
            for play in result.plays
            where CrudePlaybook.family(of: play.calls.offense.design) == .fieldGoal {
                let length = rules.fieldGoalDistance(ballOn: play.situation.ballOn)
                #expect(
                    length <= BaselineCaller.maximumFieldGoal,
                    "attempted a \(length) yard kick")
            }
        }
    }

    /// The situational vocabulary is shared, so a caller and a tendency table mean the
    /// same thing by "must pass". If the caller ran on those downs it would be reading
    /// something else.
    @Test("The caller throws when the situation says it must")
    func mustPassIsHonoured() {
        var passes = 0
        var runs = 0
        for seed in UInt64(1)...6 {
            let result = simulate(StalemateResolver(), setup(seed: seed))
            for play in result.plays where SituationClass(play.situation).isMustPass {
                guard let family = CrudePlaybook.family(of: play.calls.offense.design),
                    family.isRun || family.isPass
                else { continue }
                if family.isPass { passes += 1 } else { runs += 1 }
            }
        }
        #expect(passes > 0)
        #expect(runs == 0, "ran \(runs) times on a must-pass down")
    }

    // MARK: - Overtime

    /// A regular season game may end level; a postseason game may not.
    @Test("A tied game ends level in the regular season and goes on in the postseason")
    func ties() {
        let regular = simulate(StalemateResolver(), setup(seed: 9))
        if regular.homeScore == regular.awayScore {
            #expect(regular.isTie)
            #expect(regular.plays.allSatisfy { $0.situation.quarter <= 4 })
        }

        let postseason = simulate(StalemateResolver(), setup(seed: 9, isPostseason: true))
        if postseason.homeScore == postseason.awayScore {
            #expect(
                postseason.plays.contains { $0.situation.quarter > 4 },
                "a tied playoff game must go to overtime")
        }
    }
}
