import FMCore
import FMRandom

extension GameSimulator {

    /// The game as it stands, and every rule about how it moves.
    ///
    /// Nothing here draws a random number. Every branch is the rules applied to what the
    /// resolver reported, which is what makes the state machine testable on its own and
    /// what lets it survive the resolver being replaced.
    struct State {

        let setup: GameSetup

        var clock: GameClock
        var possession: TeamID
        var ballOn: UInt8
        var down: Down
        var distance: UInt8
        var homeScore: Int16 = 0
        var awayScore: Int16 = 0
        var homeTimeouts: UInt8
        var awayTimeouts: UInt8

        /// A try is owed before anything else can happen.
        var pendingTry = false
        var pendingKickoff = false
        /// Whether the clock was stopped coming into this snap, which decides whether
        /// the huddle costs anything.
        var previousBehavior: ClockBehavior = .stopsUntilSnap

        var plays: [PlayRecord] = []
        var isOver = false

        /// Who receives the second-half kickoff — the team that did not receive first.
        private let secondHalfReceiver: TeamID
        /// Which teams have had the ball in overtime, for the both-teams-touch rule.
        private var overtimePossessors: Set<TeamID> = []

        init(setup: GameSetup) {
            self.setup = setup
            clock = .start(setup.rules)
            homeTimeouts = setup.rules.timeoutsPerHalf
            awayTimeouts = setup.rules.timeoutsPerHalf

            // The away team receives to open. A coin toss is a real event and belongs in
            // the stream when there is a stream to put it in; hard-coding it here keeps
            // the opening deterministic and visible rather than buried in a draw.
            possession = setup.home.id
            secondHalfReceiver = setup.away.id
            ballOn = setup.rules.ballOnFromOwnYard(setup.rules.kickoffFromOwnYard)
            down = .first
            distance = setup.rules.yardsToGain
            pendingKickoff = true
        }

        var defending: TeamID { possession == setup.home.id ? setup.away.id : setup.home.id }

        var scoreDifferential: Int16 {
            possession == setup.home.id ? homeScore - awayScore : awayScore - homeScore
        }

        func situation() -> Situation {
            Situation(
                quarter: clock.quarter,
                clockRemaining: clock.secondsRemaining,
                down: down,
                distance: distance,
                ballOn: ballOn,
                possession: possession,
                scoreDifferential: scoreDifferential,
                offenseTimeouts: possession == setup.home.id ? homeTimeouts : awayTimeouts,
                defenseTimeouts: possession == setup.home.id ? awayTimeouts : homeTimeouts,
                weather: setup.weather)
        }

        func context() -> PlayContext {
            let offense = possession == setup.home.id ? setup.home : setup.away
            let defense = possession == setup.home.id ? setup.away : setup.home
            return PlayContext(
                offense: offense.id,
                defense: defense.id,
                offenseRotation: offense.rotation(),
                defenseRotation: defense.rotation(),
                players: setup.players,
                offenseScheme: offense.scheme,
                defenseScheme: defense.scheme,
                rules: setup.rules)
        }

        // MARK: - Applying a play

        mutating func apply(_ outcome: Outcome, calls: Calls, decisions: [DecisionPoint]) {
            let before = situation()
            let rules = setup.rules

            var effective = outcome
            var advancement: Advancement

            // A flag is resolved before anything else: the play that stands is whichever
            // branch the non-offending team took.
            if let penalty = outcome.penalties.first {
                let decision = rules.enforce(
                    penalty, on: before, outcome: outcome,
                    offendingTeamHadBall: penalty.offendingTeam == possession)
                advancement = decision.advancement
                effective.penalties = [decision.penalty]
            } else {
                advancement = rules.advance(from: before, outcome: outcome)
            }

            record(effective, calls: calls, decisions: decisions, situation: before)
            score(advancement)
            runClock(effective, tempo: calls.offense.tempo)
            reposition(advancement)
            checkForEnd(scored: advancement.scoring)
        }

        private mutating func record(
            _ outcome: Outcome, calls: Calls, decisions: [DecisionPoint], situation: Situation
        ) {
            plays.append(
                PlayRecord(
                    game: setup.game,
                    index: UInt16(plays.count),
                    situation: situation,
                    calls: calls,
                    decisions: decisions,
                    outcome: outcome))
        }

        private mutating func score(_ advancement: Advancement) {
            guard let scoring = advancement.scoring, advancement.points != 0 else { return }

            // A safety and a defensive touchdown pay the team that did *not* have the
            // ball. Paying the wrong side is the scoreboard bug this exists to prevent.
            let scorer: TeamID
            switch scoring {
            case .safety, .defensiveTouchdown: scorer = defending
            case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: scorer = possession
            }

            if scorer == setup.home.id {
                homeScore += advancement.points
            } else {
                awayScore += advancement.points
            }
        }

        private mutating func runClock(_ outcome: Outcome, tempo: Tempo) {
            let behavior = setup.rules.clockBehavior(
                after: outcome.endedIn, quarter: clock.quarter,
                clockRemaining: clock.secondsRemaining)

            // A kickoff or a try is untimed for our purposes: the clock is stopped
            // through the whole sequence.
            let elapsed: UInt16
            if pendingKickoff || pendingTry {
                elapsed = 0
            } else {
                elapsed =
                    GameClock.elapsed(
                        playDuration: outcome.clockRunoff > 0 ? outcome.clockRunoff : 6,
                        tempo: tempo,
                        previousBehavior: previousBehavior
                    ).total
            }

            let warningTaken = clock.run(elapsed, rules: setup.rules)
            previousBehavior = warningTaken ? .stopsUntilSnap : behavior
        }

        private mutating func reposition(_ advancement: Advancement) {
            if advancement.possessionChanged {
                possession = defending
            }
            if clock.quarter > setup.rules.quarters && !pendingKickoff {
                overtimePossessors.insert(possession)
            }

            ballOn = advancement.ballOn
            down = advancement.down
            distance = advancement.distance

            // Order matters: a try is owed before the kickoff that follows it.
            if pendingTry {
                pendingTry = false
                pendingKickoff = true
                ballOn = setup.rules.ballOnFromOwnYard(setup.rules.kickoffFromOwnYard)
            } else if pendingKickoff {
                pendingKickoff = false
            } else if advancement.requiresTry {
                pendingTry = true
            } else if advancement.requiresKickoff {
                pendingKickoff = true
            }
        }

        // MARK: - Ending periods and the game

        private mutating func checkForEnd(scored: Scoring?) {
            let rules = setup.rules

            // Overtime: both teams get a possession *unless the defence scores*. A
            // safety or a return touchdown ends it where the offence scoring does not,
            // which is the whole point of that clause.
            if clock.quarter > rules.quarters {
                if let scored, scored == .safety || scored == .defensiveTouchdown {
                    isOver = true
                    return
                }
                let bothHaveHadIt = overtimePossessors.count >= 2
                if bothHaveHadIt && homeScore != awayScore && !pendingTry {
                    isOver = true
                    return
                }
                if clock.isExpired {
                    isOver = true
                }
                return
            }

            guard clock.isExpired else { return }

            if clock.quarter == rules.quarters {
                if homeScore != awayScore {
                    isOver = true
                    return
                }
                if rules.mayEndInATie(isPostseason: setup.isPostseason) {
                    isOver = true
                    return
                }
            }

            guard let next = clock.advancingPeriod(rules: rules, isPostseason: setup.isPostseason)
            else {
                isOver = true
                return
            }
            clock = next

            // Halftime and overtime both restart with a kickoff and fresh timeouts.
            let startsHalf = next.quarter == (rules.quarters / 2) + 1
            let startsOvertime = next.quarter > rules.quarters
            if startsHalf || startsOvertime {
                homeTimeouts = rules.timeoutsPerHalf
                awayTimeouts = rules.timeoutsPerHalf
                possession = startsHalf ? secondHalfReceiver : possession
                ballOn = rules.ballOnFromOwnYard(rules.kickoffFromOwnYard)
                down = .first
                distance = rules.yardsToGain
                pendingKickoff = true
                pendingTry = false
                if startsOvertime { overtimePossessors.removeAll() }
            }
            previousBehavior = .stopsUntilSnap
        }

        func result() -> GameResult {
            let winner: TeamID?
            if homeScore > awayScore {
                winner = setup.home.id
            } else if awayScore > homeScore {
                winner = setup.away.id
            } else {
                winner = nil
            }
            return GameResult(
                game: setup.game, plays: plays, homeScore: homeScore, awayScore: awayScore,
                winner: winner)
        }
    }
}
