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
        /// The try as chosen: `nil` until the caller has been asked, then whether the
        /// scoring side goes for two. Chosen once, so a flag on the try replays it from
        /// the enforced spot rather than from the standard one.
        var tryGoesForTwo: Bool?
        /// A defensive foul has moved the try inside the two, which is a decision worth
        /// putting to the caller again: two from the one is a different question.
        var tryNeedsRedecision = false
        /// The other try option's yard line, as any penalty enforced on this try has
        /// moved it (2025 rulebook, 11-3-3): the spot the try moves to if the caller
        /// changes its mind after a flag.
        private var otherTrySpot: UInt8 = 0
        var pendingKickoff = false
        /// Whether the clock was stopped coming into this snap, which decides whether
        /// the huddle costs anything.
        var previousBehavior: ClockBehavior = .stopsUntilSnap
        /// Who is on the field for this snap. The offence declares by substituting and
        /// the defence answers, so these are set in that order before the snap and are
        /// part of the situation both callers and the resolver read.
        var offensePersonnel: PersonnelGroup = .eleven
        var defensePackage: DefensivePackage = .base

        var plays: [PlayRecord] = []
        var injuries: [InjuryEvent] = []
        /// Anyone who has left this game. Next man up follows from the depth chart, so
        /// nothing else has to change.
        var hurt: Set<PlayerID> = []
        var isOver = false

        /// Every player's day, drawn once when the game starts.
        private let form: [PlayerID: Double]

        /// Who receives the second-half kickoff — the team that did not receive first.
        private let secondHalfReceiver: TeamID
        /// How many opportunities to possess the ball have begun in overtime, capped at
        /// two because the rules only ever ask whether *both* sides have had one.
        ///
        /// A kickoff is the receiving team's opportunity, and a defence that takes the
        /// ball away has thereby had its own (2025 rulebook, 16-1-5-b, 16-1-5-c), so the
        /// count moves on every kickoff and every change of possession. Two means the
        /// game is in sudden death: the next score that separates the sides wins.
        private var overtimePossessions: UInt8 = 0

        init(setup: GameSetup) {
            self.setup = setup
            form = Form.table(
                for: setup.players.keys.sorted { $0.rawValue < $1.rawValue },
                game: setup.game, seed: setup.seed)
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
                offensePersonnel: offensePersonnel,
                defensePackage: defensePackage,
                weather: setup.weather)
        }

        func context() -> PlayContext {
            let offense = possession == setup.home.id ? setup.home : setup.away
            let defense = possession == setup.home.id ? setup.away : setup.home
            return PlayContext(
                offense: offense.id,
                defense: defense.id,
                offenseRotation: offense.depthChart.rotation(
                    unavailable: offense.unavailable.union(hurt)),
                defenseRotation: defense.depthChart.rotation(
                    unavailable: defense.unavailable.union(hurt)),
                players: setup.players,
                offenseScheme: offense.scheme,
                defenseScheme: defense.scheme,
                crowdNoise: setup.stadium.noise,
                altitudeFeet: setup.stadium.altitudeFeet,
                weather: setup.weather,
                offenseIsHome: possession == setup.home.id,
                clockIsRunning: previousBehavior == .keepsRunning,
                form: form,
                rules: setup.rules)
        }

        /// Spend a timeout, which stops the clock until the snap.
        ///
        /// A timeout is not a play, so it produces no `PlayRecord`. It does not need to:
        /// the next play's situation carries the counts, so *they burned their last one
        /// with a minute forty left* is a query over the stream rather than a new event
        /// type ([ADR-0007](../../../../docs/adr/0007-event-stream-contract.md)).
        mutating func spendTimeout(offense: Bool) {
            let team = offense ? possession : defending
            if team == setup.home.id {
                guard homeTimeouts > 0 else { return }
                homeTimeouts -= 1
            } else {
                guard awayTimeouts > 0 else { return }
                awayTimeouts -= 1
            }
            previousBehavior = .stopsUntilSnap
        }

        /// Choose the try, and put the ball where it is snapped from.
        ///
        /// The first time, the spot is the standard one for the choice — the fifteen
        /// for a kick, the two for a play (11-3-1). Asked again after a flag, a changed
        /// answer moves the try to the other option's yard line as the flag has already
        /// moved it (11-3-3); the same answer keeps the enforced spot.
        mutating func chooseTry(goingForTwo: Bool) {
            let rules = setup.rules
            if let chosen = tryGoesForTwo {
                if chosen != goingForTwo { swap(&ballOn, &otherTrySpot) }
            } else {
                ballOn = goingForTwo ? rules.twoPointSnapYard : rules.extraPointSnapYard
                otherTrySpot = goingForTwo ? rules.extraPointSnapYard : rules.twoPointSnapYard
            }
            tryGoesForTwo = goingForTwo
            tryNeedsRedecision = false
            down = .first
            distance = max(1, ballOn)
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
            let wasKickoff = pendingKickoff
            let replayed = effective.kind == .penaltyOnly
            reposition(advancement, replayed: replayed)
            if pendingTry, replayed, let penalty = effective.penalties.first {
                moveTheOtherTryOption(for: penalty, before: before, outcome: outcome)
            }
            checkForEnd(advancement, wasKickoff: wasKickoff)
        }

        /// A flag on a try moves both try options (11-3-3): the one being attempted has
        /// just been enforced by `reposition`, and the other follows the same walk-off
        /// from its own spot, so that a caller who changes its mind after the flag
        /// snaps from the right place. A defensive foul that leaves the ball inside the
        /// two is worth asking the caller about again.
        private mutating func moveTheOtherTryOption(
            for penalty: PenaltyRecord, before: Situation, outcome: Outcome
        ) {
            let rules = setup.rules
            var other = before
            other.ballOn = otherTrySpot
            other.distance = max(1, otherTrySpot)
            let byOffense = penalty.offendingTeam == possession
            otherTrySpot =
                rules.enforce(penalty, on: other, outcome: outcome, offendingTeamHadBall: byOffense)
                .advancement.ballOn
            if !byOffense && ballOn < rules.twoPointSnapYard {
                tryNeedsRedecision = true
            }
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

        private mutating func reposition(_ advancement: Advancement, replayed: Bool) {
            // A flag before the snap means the play never happened. The down is replayed
            // from the enforcement spot, and — the part that used to be wrong — a try or a
            // kickoff is still *owed*. Consuming the pending state on a snap that never
            // took place is why neither could draw a flag at all: a false start on a field
            // goal simply cancelled the kick.
            if replayed {
                ballOn = advancement.ballOn
                down = advancement.down
                distance = advancement.distance
                return
            }

            if advancement.possessionChanged {
                possession = defending
            }
            // Overtime counts opportunities to possess: the receiving team's on a kickoff,
            // whoever ends up with it, and the new possessor's on a change of possession
            // (16-1-5-b, 16-1-5-c).
            if clock.quarter > setup.rules.quarters, pendingKickoff || advancement.possessionChanged
            {
                overtimePossessions = min(2, overtimePossessions + 1)
            }

            ballOn = advancement.ballOn
            down = advancement.down
            distance = advancement.distance

            // Order matters: a try is owed before the kickoff that follows it.
            if pendingTry {
                pendingTry = false
                tryGoesForTwo = nil
                tryNeedsRedecision = false
                pendingKickoff = true
                ballOn = setup.rules.ballOnFromOwnYard(setup.rules.kickoffFromOwnYard)
                return
            }

            // A kickoff is consumed by the play that was the kickoff, and *then* the
            // advancement is read: a kick returned for a touchdown owes the returning
            // team its try (11-3-1) and a kickoff after it, like any other score. Reading
            // the kickoff flag as an alternative to the advancement is how that try was
            // swallowed and the returner kept the ball at the fifteen.
            if pendingKickoff {
                pendingKickoff = false
            }
            if advancement.requiresTry {
                pendingTry = true
            } else if advancement.requiresKickoff {
                pendingKickoff = true
            }
        }

        // MARK: - Ending periods and the game

        private mutating func checkForEnd(_ advancement: Advancement, wasKickoff: Bool) {
            let rules = setup.rules

            // A try is an untimed down of the period the touchdown ended: the period is
            // extended for it (4-8-2), so neither the period nor the game ends while one
            // is owed — unless it could not matter, in which case it is waived here and
            // the game ends below.
            if pendingTry {
                guard tryCannotMatter else { return }
                pendingTry = false
                pendingKickoff = true
            }

            if clock.quarter > rules.quarters {
                checkForOvertimeEnd(advancement, wasKickoff: wasKickoff)
                return
            }

            guard clock.isExpired else { return }

            // A level game at the end of regulation goes to overtime, in every kind of
            // game (4-1-1, 16-1-3): whether it may end level is a question for the end
            // of the overtime period, not this one.
            if clock.quarter == rules.quarters && homeScore != awayScore {
                isOver = true
                return
            }
            startNextPeriod()
        }

        /// Whether the try that is owed is waived (4-8-2-c): during sudden-death
        /// overtime once the touchdown has decided it, or when time has expired in the
        /// game's last period and no successful try could change who won.
        ///
        /// `scoreDifferential` is the scorer's: after a touchdown `possession` is the
        /// team owed the try, whoever had the ball at the snap. A try is worth at most
        /// the conversion, so leading by anything, or trailing by more than that, means
        /// the try cannot affect the outcome. Level or within it, the try is played.
        ///
        /// Whether "the game's last period" includes a regular-season overtime period
        /// expiring is a modelling reading of the article, which names the fourth
        /// period: the game is over at that expiry either way (16-1-3-d), so a try that
        /// could not change the winner is waived there on the same reasoning.
        private var tryCannotMatter: Bool {
            let rules = setup.rules
            let isOvertime = clock.quarter > rules.quarters
            if isOvertime && overtimePossessions >= 2 && scoreDifferential > 0 { return true }

            let gameEndsHere =
                clock.isExpired
                && (clock.quarter == rules.quarters
                    || (isOvertime && rules.mayEndInATie(isPostseason: setup.isPostseason)))
            guard gameEndsHere else { return false }
            return scoreDifferential > 0 || scoreDifferential < -rules.twoPointConversion
        }

        /// Overtime, as Rule 16 (2025) gives it. Regular season: one period, each side
        /// owed an opportunity to possess, and sudden death once both have had it; level
        /// at the end is a tie and the period is never extended (16-1-3). Postseason: the
        /// same possession rules, and another period whenever one ends undecided
        /// (16-1-4).
        private mutating func checkForOvertimeEnd(_ advancement: Advancement, wasKickoff: Bool) {
            let rules = setup.rules

            // A safety ends it whenever it comes: against the opening drive it is the one
            // named exception to each side getting a turn (16-1-3-a), and once both have
            // possessed any score that separates the sides wins (16-1-3-c).
            if advancement.scoring == .safety {
                isOver = true
                return
            }

            let suddenDeath = overtimePossessions >= 2
            // The play that starts a possession — the kickoff — is not the play that
            // ends one. A score, a change of possession, or the try that closes a
            // scoring sequence is.
            let possessionEnded =
                !wasKickoff
                && (advancement.possessionChanged || advancement.scoring != nil
                    || advancement.requiresKickoff)

            // Once both have possessed, the first score that separates the sides has
            // won, and the possession it came on is over (16-1-3-b, 16-1-3-c). A try
            // still owed to a scorer who is behind is held by `checkForEnd` before this
            // is reached.
            if suddenDeath && homeScore != awayScore && possessionEnded {
                isOver = true
                return
            }

            guard clock.isExpired else { return }

            // Regular season: the period is never extended, not for a second team that
            // has not possessed and not for a possession still running. Whoever leads
            // has won, and level is a tie (16-1-3-d).
            if rules.mayEndInATie(isPostseason: setup.isPostseason) {
                isOver = true
                return
            }

            // Postseason: another period, and play simply continues — no kickoff, the
            // ball where it was (16-1-4-d).
            guard let next = clock.advancingPeriod(rules: rules, isPostseason: setup.isPostseason)
            else {
                isOver = true
                return
            }
            clock = next
            previousBehavior = .stopsUntilSnap
        }

        /// The next period of regulation, or the first period of overtime.
        private mutating func startNextPeriod() {
            let rules = setup.rules
            guard let next = clock.advancingPeriod(rules: rules, isPostseason: setup.isPostseason)
            else {
                isOver = true
                return
            }
            clock = next

            // Halftime and the first overtime period both restart with a kickoff and
            // fresh timeouts. Later overtime periods do not come through here.
            let startsHalf = next.quarter == (rules.quarters / 2) + 1
            let startsOvertime = next.quarter == rules.quarters + 1
            if startsHalf || startsOvertime {
                homeTimeouts = rules.timeoutsPerHalf
                awayTimeouts = rules.timeoutsPerHalf
                possession = startsHalf ? secondHalfReceiver : possession
                ballOn = rules.ballOnFromOwnYard(rules.kickoffFromOwnYard)
                down = .first
                distance = rules.yardsToGain
                pendingKickoff = true
                if startsOvertime { overtimePossessions = 0 }
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
                game: setup.game, plays: plays, injuries: injuries, homeScore: homeScore,
                awayScore: awayScore, winner: winner)
        }
    }
}
