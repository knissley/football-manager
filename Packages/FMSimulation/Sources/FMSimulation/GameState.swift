import FMCore
import FMRandom

extension GameSimulator {

    /// What the callers chose when a flag flew before the snap (2025 rulebook, 4-7-1).
    /// All three are asked; the rules layer reads the ones the foul makes relevant.
    struct DeadBallChoices: Sendable {
        /// The offence spends a charged timeout rather than take the runoff.
        var offenseTakesTimeout: Bool
        /// The defence declines the runoff and keeps the yardage.
        var defenseDeclinesRunoff: Bool
        /// After a defensive foul inside two minutes, the offence has the clock wait
        /// for the snap rather than start on the ready signal.
        var offenseStartsClockOnTheSnap: Bool
        /// In the last forty seconds, after a defensive foul that conserves time with
        /// the defence out of timeouts, the offence ends the half rather than play on
        /// (4-7-3).
        var offenseEndsTheHalf: Bool
    }

    /// What the callers chose about an injury timeout after the two-minute warning
    /// (2025 rulebook, 4-5-4). All three are asked; the rules layer reads the ones the
    /// injury makes relevant.
    struct InjuryChoices: Sendable {
        /// For an excess timeout against the team in possession, the defence has ten
        /// seconds run off (Note 3).
        var defenseTakesRunoff: Bool
        /// For an excess timeout against the defence, the offence has the clock wait
        /// for the snap rather than start on the ready (Note 1).
        var offenseStartsClockOnTheSnap: Bool
        /// For an excess timeout against the defence in the last forty seconds, the
        /// offence ends the half rather than play on (4-7-3).
        var offenseEndsTheHalf: Bool
    }

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
        /// Whether the conversion is carried rather than thrown (11-3-1 allows either),
        /// and the grouping sent out to do it. Decided once alongside the spot, for the
        /// same reason: a try replayed after a flag is the same try, and re-asking on
        /// every step would let the offence change the play between a flag and its
        /// replay without anybody deciding to.
        var tryRuns: Bool?
        /// A defensive foul has moved the try inside the two, which is a decision worth
        /// putting to the caller again: two from the one is a different question.
        var tryNeedsRedecision = false
        /// The other try option's yard line, as any penalty enforced on this try has
        /// moved it (2025 rulebook, 11-3-3): the spot the try moves to if the caller
        /// changes its mind after a flag.
        private var otherTrySpot: UInt8 = 0
        /// A foul on a play that scored, owed to the spot the rules put in play next
        /// (2025 rulebook, 14-2-3, 11-3-3).
        ///
        /// The rules layer cannot walk it off, because that spot does not exist when the
        /// flag is enforced: the try has not been chosen and the free kick has not been
        /// set up. So `Rules.enforce` says *where* it is owed and this holds it until the
        /// spot is built, which is `chooseTry` for a try and `reposition` for a free kick.
        private var owedEnforcement: (penalty: PenaltyRecord, spot: DeferredEnforcement)?
        var pendingKickoff = false
        /// What happened while the ball was dead since the last snap — a charged timeout
        /// with the side that took it, the two-minute warning — waiting to go on the
        /// record of the snap that follows, at the front of its decision points.
        var beforeTheSnap: [DecisionPoint] = []
        /// Whether the clock was stopped coming into this snap, which decides whether
        /// the huddle costs anything.
        var previousBehavior: ClockBehavior = .stopsUntilSnap
        /// The play clock the next snap is taken against (2025 rulebook, 4-6): forty
        /// from the end of an ordinary play, twenty-five from the whistle after an
        /// administrative stoppage, thirty after a runoff, forty on the ready after a
        /// defensive act that conserves time. Set by whatever stopped the clock, read
        /// by the resolver to know when it has expired, and written into every record.
        var playClock: PlayClock
        /// Whether a charged timeout is what put that clock where it is, either side's
        /// (2025 rulebook, 4-5-1, 4-6-3-a).
        ///
        /// The offence stands through a timeout with the ball, so the huddle has already
        /// happened when the twenty-five seconds start, and it comes to the snap set —
        /// which is the difference between a timeout and every other stoppage that
        /// leaves the same twenty-five. Set where a timeout is charged and cleared by
        /// the snap that spends it, or by a period that ends before one comes.
        var offenseIsSetFromATimeout = false
        /// Whether the two-minute warning has already ended the interval before this
        /// snap, at 2:00 with the rest of it free (3-41, 4-3-2).
        ///
        /// The warning is taken before the snap is prepared, because what it leaves on
        /// the play clock is the clock the snap is played against (4-6-2). So the game
        /// clock it costs has been charged by then too, and the interval the rules layer
        /// charges once the down is resolved must not charge it twice. Set where the
        /// warning is taken and spent by the interval that would otherwise re-run it.
        var intervalEndedAtTheWarning = false
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

        /// Each team's roster for the game, the table `PlayRecord.onField` indexes, and
        /// the index of every man in it. Both fixed before the first kickoff: a player
        /// who leaves hurt keeps his index, so the indices in an early play still mean
        /// what they meant.
        let rosters: [TeamID: [PlayerID]]
        private let rosterIndex: [TeamID: [PlayerID: UInt8]]

        /// The captain who lost the last coin toss, as the engine stands in for a toss
        /// it does not draw: the side that kicks off after one. The loser's first choice
        /// of 4-2-2's privileges comes two periods on — at the second half (4-2-2), and
        /// at a third postseason overtime period (16-1-4-e).
        private var tossLoser: TeamID
        /// A half has opened whose first choice is `tossLoser`'s, and the caller has not
        /// yet said which privilege it takes. Until it does, the loser has the ball to
        /// kick off with.
        private(set) var firstChoicePending = false
        /// How many opportunities to possess the ball have begun in overtime, capped at
        /// two because the rules only ever ask whether *both* sides have had one.
        ///
        /// A kickoff is the receiving team's opportunity, and a defence that takes the
        /// ball away has thereby had its own (2025 rulebook, 16-1-5-b, 16-1-5-c), so the
        /// count moves on every kickoff and every change of possession. A kick the
        /// kicking team recovers counts twice: the receivers have had their opportunity
        /// and the kickers now possess (16-1-5-c, A.R. 16.2). Two means the game is in
        /// sudden death: the next score that separates the sides wins.
        private var overtimePossessions: UInt8 = 0

        init(setup: GameSetup) {
            self.setup = setup
            form = Form.table(
                for: setup.players.keys.sorted { $0.rawValue < $1.rawValue },
                game: setup.game, seed: setup.seed)
            clock = .start(setup.rules)
            homeTimeouts = setup.rules.timeoutsPerHalf
            awayTimeouts = setup.rules.timeoutsPerHalf
            // The opening kickoff is a free kick, put in play on the whistle (4-6-2).
            playClock = setup.rules.playClockAfterAnAdministrativeStoppage

            rosters = [setup.home.id: setup.home.roster, setup.away.id: setup.away.roster]
            rosterIndex = rosters.mapValues { roster in
                // A roster is at most the men a club dresses, and `PlayRecord.vacant` is
                // the one index a man can never have.
                precondition(roster.count < Int(PlayRecord.vacant), "a roster too large to index")
                var index: [PlayerID: UInt8] = [:]
                for (position, player) in roster.enumerated() { index[player] = UInt8(position) }
                return index
            }

            // The away team receives to open. A coin toss is a real event and belongs in
            // the stream when there is a stream to put it in; hard-coding it here keeps
            // the opening deterministic and visible rather than buried in a draw. The
            // side that kicks off stands for the captain who lost the toss.
            possession = setup.home.id
            tossLoser = setup.home.id
            ballOn = setup.rules.ballOnFromOwnYard(setup.rules.kickoffFromOwnYard)
            down = .first
            distance = setup.rules.yardsToGain
            pendingKickoff = true
        }

        var defending: TeamID { possession == setup.home.id ? setup.away.id : setup.home.id }

        var scoreDifferential: Int16 {
            possession == setup.home.id ? homeScore - awayScore : awayScore - homeScore
        }

        /// The game as a snap sees it.
        ///
        /// Read inside `apply`, after the interval between downs has come off, this is
        /// the situation at the snap, and it is what the record carries. Read by the
        /// simulator before it asks its callers, it is the situation at the previous
        /// whistle — which is when a caller really chooses, since the tempo it picks is
        /// what decides how long the interval is.
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
                defensePackage: defensePackage)
        }

        /// The game as a resolver sees it.
        ///
        /// `playClockExpired` says whether the interval before this snap ran out with the
        /// ball not put in play (2025 rulebook, 4-6-4). It is decided above this, by the
        /// resolver and the benches together, and is false everywhere the question has
        /// not been asked yet.
        func context(playClockExpired: Bool = false) -> PlayContext {
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
                // "The clock runs into the interval before this snap": true after a play
                // that left it running and after a stoppage that ends on the
                // ready-for-play signal, false only when it waits for the snap.
                clockIsRunning: previousBehavior != .stopsUntilSnap,
                playClock: playClock,
                playClockExpired: playClockExpired,
                offenseIsSetFromATimeout: offenseIsSetFromATimeout,
                form: form,
                rules: setup.rules)
        }

        /// The lineup as the record carries it: twenty-two roster indices in slot order,
        /// the offensive slots into the possessing team's roster and the defensive slots
        /// into the other's.
        ///
        /// Every man `Lineup.fill` can place comes from a rotation that is a subset of
        /// the roster this table was built from, so a lookup cannot fail by
        /// construction; `vacant` is written for an empty slot and for nothing else.
        func rosterIndices(of lineup: Lineup) -> [UInt8] {
            (0..<PlayerSlot.count).map { index in
                let slot = PlayerSlot(index)
                guard let player = lineup[slot] else { return PlayRecord.vacant }
                let team = slot.isOffense ? possession : defending
                return rosterIndex[team]?[player] ?? PlayRecord.vacant
            }
        }

        func timeouts(of team: TeamID) -> UInt8 {
            team == setup.home.id ? homeTimeouts : awayTimeouts
        }

        /// Spend a timeout, which stops the clock until the snap.
        ///
        /// A timeout is not a play, so it produces no `PlayRecord`. It does not need to:
        /// the next play's situation carries the counts, so *they burned their last one
        /// with a minute forty left* is a query over the stream rather than a new event
        /// type ([ADR-0007](../../../../docs/adr/0007-event-stream-contract.md)).
        mutating func spendTimeout(offense: Bool) {
            spendTimeout(of: offense ? possession : defending)
        }

        /// A charged timeout one side asked for while the ball was dead (4-5-1), on the
        /// record of the snap it precedes with the side that took it — so a timeout
        /// taken with the ball about to change hands is charged to a team rather than
        /// inferred from two situations. Nothing is recorded when the side has none
        /// left, because nothing was charged — which is what `false` says, so that a
        /// caller acting on the stoppage acts on one that happened.
        @discardableResult
        mutating func takeTimeout(offense: Bool) -> Bool {
            guard spendTimeout(of: offense ? possession : defending) else { return false }
            beforeTheSnap.append(.timeout(byOffense: offense))
            return true
        }

        /// The same, charged to `team`, which an injury timeout is (4-5-4-a). A charged
        /// timeout is an administrative stoppage, so the play clock is the short one
        /// (4-6-2-b). `false` when the team had none left and nothing was charged.
        @discardableResult
        mutating func spendTimeout(of team: TeamID) -> Bool {
            if team == setup.home.id {
                guard homeTimeouts > 0 else { return false }
                homeTimeouts -= 1
            } else {
                guard awayTimeouts > 0 else { return false }
                awayTimeouts -= 1
            }
            previousBehavior = .stopsUntilSnap
            playClock = setup.rules.playClockAfterAnAdministrativeStoppage
            // The offence stands through this one with the ball, so it comes to the next
            // snap with its call in and its grouping set — which is what separates the
            // twenty-five a timeout leaves from the same twenty-five a change of
            // possession leaves, where the side about to snap has prepared nothing.
            offenseIsSetFromATimeout = true
            return true
        }

        /// Note a choice one side made about the clock on the play just recorded, so
        /// that the stream explains the clock rather than leaving it to be inferred.
        private mutating func elect(_ election: ClockElection) {
            guard !plays.isEmpty else { return }
            plays[plays.count - 1].decisions.append(.clockElection(election))
        }

        /// The answer to the first choice a half opened with (4-2-2-a): the toss loser
        /// receives, and the other side kicks off to it, or the loser kicks off itself.
        mutating func settleFirstChoice(receives: Bool) {
            guard firstChoicePending else { return }
            firstChoicePending = false
            if receives { possession = defending }
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
                // A foul during the touchdown is enforced here (14-2-3), and it moves
                // both options, because 11-3-3 spots the other one as any enforced
                // penalty has left it. Only on the first ask: a flag *on* the try is
                // enforced by `reposition` and must not be walked off twice.
                if let owed = owedEnforcement, owed.spot == .theTry {
                    ballOn = walkOff(owed.penalty, from: ballOn)
                    otherTrySpot = walkOff(owed.penalty, from: otherTrySpot)
                    owedEnforcement = nil
                }
            }
            tryGoesForTwo = goingForTwo
            tryNeedsRedecision = false
            down = .first
            distance = max(1, ballOn)
        }

        /// How the conversion will be attempted, decided once with the spot.
        mutating func chooseTryPlay(runs: Bool, personnel: PersonnelGroup) {
            tryRuns = runs
            offensePersonnel = personnel
        }

        /// Walk an owed penalty off a spot in the possessing team's frame.
        ///
        /// The team that has the ball at the spot is the one about to snap it or kick it,
        /// so a foul by that team moves the spot back and a foul by the other moves it
        /// forward. Half the distance to a goal line applies here as anywhere (14-2-1).
        private func walkOff(_ penalty: PenaltyRecord, from spot: UInt8) -> UInt8 {
            let against = penalty.offendingTeam == possession
            let yards = Int(penalty.yards)
            let raw = against ? Int(spot) + yards : Int(spot) - yards
            if against, raw >= 100 { return UInt8(min(99, Int(spot) + (100 - Int(spot)) / 2)) }
            if !against, raw <= 0 { return UInt8(max(1, Int(spot) - Int(spot) / 2)) }
            return UInt8(max(1, min(99, raw)))
        }

        /// The situation as it reads when a flag flies before the snap: the interval
        /// before the flag has elapsed if the clock was running into it, and nothing
        /// else has. The callers are asked with this one, before the rules layer charges
        /// the same interval and writes the same reading onto the record.
        func situationAtTheFlag(tempo: Tempo, foul: Foul?) -> Situation {
            var probe = clock
            _ = probe.run(
                intervalBeforeTheSnap(tempo: tempo, foul: foul), rules: setup.rules,
                isPostseason: setup.isPostseason)
            var atTheFlag = situation()
            atTheFlag.clockRemaining = probe.secondsRemaining
            return atTheFlag
        }

        /// The clock spent between one whistle and the next snap, when the clock ran
        /// into the interval (4-3-2): the offence's tempo against the play clock in
        /// force. For a delay of game it is the whole play clock instead, because the
        /// flag *is* the play clock expiring and there is no snap (4-6-1, 4-6-4).
        /// Nothing before a free kick or a try, where the clock is dead — and nothing
        /// when the two-minute warning has already ended this interval at 2:00, since
        /// what is left of it runs on a stopped clock (3-41, 4-3-2).
        private func intervalBeforeTheSnap(tempo: Tempo, foul: Foul?) -> GameClock.Elapsed {
            guard !pendingKickoff && !pendingTry, !intervalEndedAtTheWarning else {
                return GameClock.Elapsed(duringPlay: 0, beforeSnap: 0)
            }
            let snapAfter =
                foul == .delayOfGame ? playClock.expiresAfter : playClock.intendedSnap(at: tempo)
            return GameClock.Elapsed(
                duringPlay: 0,
                beforeSnap: GameClock.elapsed(
                    playDuration: 0, snapAfter: snapAfter, previousBehavior: previousBehavior
                ).beforeSnap)
        }

        /// Charge the interval between downs, before the down exists.
        ///
        /// The order is the football. A period is kept going past its expiry only while
        /// the ball is live (4-8-1); an interval between downs is not a down, so a period
        /// the interval alone exhausts ends where it stands with nothing snapped — which
        /// the caller reads off `clock.isExpired` here. And what is left when the
        /// interval has come off *is* the clock the ball was snapped on, so it is the
        /// clock the record carries.
        ///
        /// Returns whether the two-minute warning fell in the interval. It is a stoppage
        /// between downs (3-41), taken at 2:00 with the rest of the interval free, and it
        /// goes at the front of the record of the snap that follows it.
        private mutating func runTheIntervalBeforeTheSnap(tempo: Tempo, foul: Foul?) -> Bool {
            let taken = clock.run(
                intervalBeforeTheSnap(tempo: tempo, foul: foul), rules: setup.rules,
                isPostseason: setup.isPostseason)
            if taken { beforeTheSnap.append(.twoMinuteWarning) }
            // The warning may have ended this interval before the snap was prepared, in
            // which case it is already on the record and the clock is already at 2:00:
            // the interval is charged once, and what the caller asked is whether the
            // warning fell in it.
            let endedAtTheWarning = intervalEndedAtTheWarning
            intervalEndedAtTheWarning = false
            return taken || endedAtTheWarning
        }

        /// The two-minute warning, when the interval before this snap reaches it — taken
        /// here, before the snap is prepared, rather than with the rest of the interval.
        ///
        /// **It is what the offence about to snap is playing against.** The warning is one
        /// of the administrative stoppages 4-6-2 names in its own list, and what it leaves
        /// is twenty-five seconds from the Referee's whistle; the article covers the case
        /// where the forty of 4-6-1 was already counting down, and 4-6-3-a says the same
        /// from the other side. The clock the down is played against has to be settled
        /// before the down is prepared, or the reading written onto the record describes a
        /// different game from the one the resolver was asked about.
        ///
        /// Charging it here costs the game clock nothing extra. The warning stops the
        /// clock at 2:00 and it waits for the snap (3-41, 4-3-2), so the rest of the
        /// interval is free and the interval charged after the down comes to zero. And
        /// the interval is measured to the snap the offence *means* to take, not to the
        /// play clock's expiry: an offence that was going to be beaten by the forty is
        /// reached by the warning first and gets the fresh twenty-five to beat instead,
        /// which is the order the two happen in.
        ///
        /// A period cannot end here — an interval that reaches 2:00 stops there — so the
        /// case `apply` handles, where the interval alone exhausts a period (4-8-1), is
        /// untouched by this.
        ///
        /// `previousBehavior` is left alone on purpose: it is the verdict on the play
        /// *before*, and the clock did run into this interval — it ran from wherever the
        /// down left it down to 2:00, which is how the warning was reached at all.
        mutating func takeTwoMinuteWarningBeforeTheSnap(tempo: Tempo) {
            var reached = clock
            guard
                reached.run(
                    intervalBeforeTheSnap(tempo: tempo, foul: nil), rules: setup.rules,
                    isPostseason: setup.isPostseason)
            else { return }
            clock = reached
            beforeTheSnap.append(.twoMinuteWarning)
            intervalEndedAtTheWarning = true
            playClock = setup.rules.playClockAfterAnAdministrativeStoppage
        }

        // MARK: - Applying a play

        mutating func apply(
            _ outcome: Outcome, calls: Calls, decisions: [DecisionPoint],
            onField: [UInt8] = Array(repeating: PlayRecord.vacant, count: PlayerSlot.count),
            deadBall: DeadBallChoices? = nil
        ) {
            let rules = setup.rules

            // The interval between downs comes off first, so that the situation built
            // below reads at the snap rather than at the whistle before it. A flag before
            // the snap has its own interval — the whole play clock for a delay of game,
            // which is the play clock expiring — and ends at the flag rather than at a
            // snap that never came.
            let deadBallFoul = outcome.kind == .penaltyOnly ? outcome.penalties.first?.foul : nil
            // Whether the period was already over before the interval, which is not this
            // rule's case: an untimed down is owed at 0:00 and has to be played, and the
            // try is one (4-8-2-c, 11-3-1).
            let alreadyExpired = clock.isExpired
            let warningInTheInterval = runTheIntervalBeforeTheSnap(
                tempo: calls.offense.tempo, foul: deadBallFoul)
            // The period ran out *in* the interval: no down was snapped, so there is no
            // down to resolve, enforce or record (4-8-1).
            if clock.isExpired && !alreadyExpired {
                endThePeriodIfExpired()
                return
            }

            let before = situation()

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
                if let deferred = decision.deferredTo {
                    owedEnforcement = (decision.penalty, deferred)
                }
            } else {
                advancement = rules.advance(from: before, outcome: outcome)
            }

            // The points go on the play before it is written, so the board is the
            // stream summed. Whatever a resolver put there is overwritten: what a play
            // scored is the rules' verdict on it, not the resolver's.
            effective.pointsScored = UInt8(clamping: advancement.points)
            effective.scoring = advancement.points != 0 ? advancement.scoring : nil

            record(
                effective, calls: calls, decisions: decisions, onField: onField,
                situation: before)
            score(advancement)
            if effective.kind == .penaltyOnly {
                runClockForDeadBallFoul(
                    effective, choices: deadBall, warningInTheInterval: warningInTheInterval)
            } else {
                runClock(effective, advancement: advancement, choices: deadBall)
            }
            let wasKickoff = pendingKickoff
            let replayed = effective.kind == .penaltyOnly
            reposition(advancement, replayed: replayed)
            // A flag on the try moves both of its options — the one being attempted, which
            // `reposition` has just enforced, and the other (11-3-3). Both a flag before
            // the snap and a foul during a successful try do this: the second is the try
            // being *repeated* (Item 3-a) rather than replayed, and it is the same
            // question about where the other option now is.
            if pendingTry, replayed || advancement.requiresTry,
                let penalty = effective.penalties.first
            {
                moveTheOtherTryOption(for: penalty, before: before, outcome: outcome)
            }
            checkForEnd(advancement, wasKickoff: wasKickoff, replayed: replayed)
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
            _ outcome: Outcome, calls: Calls, decisions: [DecisionPoint], onField: [UInt8],
            situation: Situation
        ) {
            // The play clock this snap was taken against (4-6), and what it read: the
            // tempo's intended snap, or zero when it expired and the flag is the foul
            // (4-6-4). The rules layer writes it because which clock was in force is a
            // rule, and a reader should not have to infer it from the play before.
            let expired =
                outcome.kind == .penaltyOnly && outcome.penalties.first?.foul == .delayOfGame
            // What happened while the ball was dead goes first: it happened first, and
            // a reader walking the chain meets the timeout before the snap it set up.
            var explained = beforeTheSnap + decisions
            beforeTheSnap.removeAll()
            explained.append(
                .playClock(
                    seconds: playClock.seconds,
                    remaining: expired
                        ? 0
                        : PlayContext.remainingAtIntendedSnap(
                            playClock, at: calls.offense.tempo,
                            setFromATimeout: offenseIsSetFromATimeout)))
            // The timeout, if there was one, has now been spent: this is the snap it
            // bought, and the one after it starts from wherever this down leaves the
            // clock.
            offenseIsSetFromATimeout = false
            plays.append(
                PlayRecord(
                    game: setup.game,
                    index: UInt16(plays.count),
                    situation: situation,
                    calls: calls,
                    decisions: explained,
                    outcome: outcome,
                    onField: onField))
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

        /// The clock through the down that has just been recorded, and what it does after
        /// it. The interval that reached the snap has already come off — see
        /// `runTheIntervalBeforeTheSnap` — so what is charged here is the down itself.
        private mutating func runClock(
            _ outcome: Outcome, advancement: Advancement, choices: DeadBallChoices?
        ) {
            let rules = setup.rules

            let elapsed: GameClock.Elapsed
            if pendingTry {
                // The try is untimed (11-3-1), and the kickoff after it is put in play
                // on the whistle (4-6-2-g).
                elapsed = GameClock.Elapsed(duringPlay: 0, beforeSnap: 0)
                playClock = rules.playClockAfterAnAdministrativeStoppage
            } else if pendingKickoff {
                // The clock on a free kick starts on a legal touching of the ball inside
                // the field of play (4-3-1), so a return costs its seconds, and nothing
                // is charged before the kick, because the clock is dead after a score.
                // It does not start on a touchback (4-3-1-a), on a kick the kicking team
                // recovers before anyone else touches it (4-3-1-b) — which is what
                // `.fumbleRecovered` on a kickoff means — or on a fair catch (4-3-1-c).
                // The down over, the clock stops (4-4-a) and waits for the snap (4-3-2).
                let returned: Bool
                switch outcome.endedIn {
                case .tackled, .outOfBounds, .touchdown, .fumbleLost, .safety: returned = true
                default: returned = false
                }
                elapsed = GameClock.Elapsed(
                    duringPlay: returned ? outcome.clockRunoff : 0, beforeSnap: 0)
                if clock.run(elapsed, rules: rules, isPostseason: setup.isPostseason) {
                    beforeTheSnap.append(.twoMinuteWarning)
                }
                previousBehavior = .stopsUntilSnap
                // A kick that changed hands is an administrative stoppage (4-6-2-a);
                // one the kickers kept is a play that ended, and the forty runs from it.
                playClock =
                    advancement.possessionChanged
                    ? rules.playClockAfterAnAdministrativeStoppage : rules.playClockAfterAPlay
                return
            } else {
                elapsed = GameClock.Elapsed(
                    duringPlay: outcome.clockRunoff > 0 ? outcome.clockRunoff : 6, beforeSnap: 0)
            }

            // Whether the warning fell in *this down*. One that fell in the interval
            // before it is already on this snap's record and is not this question: the
            // clock this down leaves behind is what the down did to it.
            let warningTaken = clock.run(elapsed, rules: rules, isPostseason: setup.isPostseason)
            if warningTaken { beforeTheSnap.append(.twoMinuteWarning) }

            // What the clock does next is judged where the ball became dead, after the
            // play's own time has come off it. The late out-of-bounds windows — after the
            // first half's warning and inside the last five minutes of the second half
            // (4-3-2-a-2, a-3) — are read off that clock: a runner who steps out at 4:50
            // on a play snapped at 5:07 is inside them. Read `clock` before the play runs
            // and the window is judged where the play *before* ended, up to a huddle and
            // a play early, and the clock restarts on the ready where the book has it
            // wait for the snap.
            var behavior = rules.clockBehavior(
                after: outcome.endedIn, possessionChanged: advancement.possessionChanged,
                quarter: clock.quarter, isPostseason: setup.isPostseason,
                clockRemaining: clock.secondsRemaining)

            // A flag on the down stops the clock at the end of it (4-4-e), and settling
            // it is not free: the clock is dead through that and starts again as though
            // the foul had not occurred (4-3-2-e) — on the ready-for-play signal, since
            // it was running — or on the snap inside the windows e-1 and e-2 name.
            // One predicate decides that restart for a foul during a down and for one
            // before the snap, and it is told which this is, because e-3 reaches only a
            // foul that stopped the clock *before* a snap. Whichever restart is later
            // wins: a tackle in bounds with a flag on it is a stopped clock, and an
            // incompletion with a flag on it still waits for the snap.
            //
            // **Whether the penalty was taken does not enter into it.** 4-4-e's condition
            // is that somebody fouled during the down, and 4-3-2-e is written over a
            // penalty enforced *or declined*, naming declination inside the rule. Read as
            // though it were about enforcement alone — which is how this stood, gated on
            // `wasAccepted` — about one down a game left the clock running where the book
            // stops it. What the declined branch does not bring is the
            // short play clock below: 4-6-2-e names an enforcement, and turning a penalty
            // down is not one, so the forty of 4-6-1 runs from the end of the play.
            if let penalty = outcome.penalties.first {
                let restart: ClockBehavior =
                    rules.clockStartsOnTheSnapAfterFoul(
                        byOffense: penalty.offendingTeam == possession,
                        stoppedTheClockBeforeTheSnap: false, quarter: clock.quarter,
                        isPostseason: setup.isPostseason, clockRemaining: clock.secondsRemaining)
                    ? .stopsUntilSnap : .stopsUntilReadyForPlay
                behavior = ClockBehavior.later(behavior, restart)
            }

            previousBehavior = warningTaken ? .stopsUntilSnap : behavior

            // The play clock for the next snap: forty from the end of this play
            // (4-6-1), unless this play brought an administrative stoppage — a change
            // of possession, a score and the free kick it owes, the two-minute warning,
            // the end of a period, an enforced penalty — after which it is twenty-five
            // from the whistle (4-6-2). A touchdown's try is snapped against the forty:
            // a score is not among the stoppages the article lists.
            let stoppage =
                advancement.possessionChanged || advancement.requiresKickoff || warningTaken
                || clock.isExpired || outcome.penalties.first?.wasAccepted == true
            playClock =
                stoppage ? rules.playClockAfterAnAdministrativeStoppage : rules.playClockAfterAPlay

            // A foul with the ball live that the book lists among the acts that conserve
            // time — grounding is the one the engine draws (4-7-1-b) — is 4-7-1's business
            // exactly as a dead-ball foul is: by the offence after the two-minute warning it
            // costs ten seconds on top of the enforcement, the play clock is set to thirty
            // and the clock restarts on the ready, with the same two alternatives (Item 1).
            // Time is in for the whole of a down, so the question a dead-ball foul asks
            // about the clock at the flag has one answer here. The runoff comes off the
            // clock the down left, which is where the flag is enforced.
            if let penalty = outcome.penalties.first, penalty.wasAccepted,
                penalty.offendingTeam == possession, penalty.foul.isLiveBallActThatConservesTime,
                rules.carriesRunoff(
                    foul: penalty.foul, byOffense: true, quarter: clock.quarter,
                    isPostseason: setup.isPostseason, clockRemaining: clock.secondsRemaining,
                    clockWasRunning: true)
            {
                if choices?.offenseTakesTimeout == true, timeouts(of: possession) > 0 {
                    spendTimeout(offense: true)
                    previousBehavior = .stopsUntilSnap
                    elect(.timeoutInsteadOfRunoff)
                    return
                }
                // Declining the runoff keeps the yardage, and the clock then restarts as a
                // foul during a down has it restart (4-3-2-e), which is already `behavior`.
                if choices?.defenseDeclinesRunoff == true {
                    elect(.runoffDeclined)
                    return
                }
                _ = clock.run(
                    GameClock.Elapsed(duringPlay: 0, beforeSnap: rules.tenSecondRunoff),
                    rules: rules, isPostseason: setup.isPostseason)
                previousBehavior = .stopsUntilReadyForPlay
                playClock = rules.playClockAfterARunoff
                elect(.runoff)
            }
        }

        /// The clock after a flag before the snap. No play happened, so no play time is
        /// charged; the interval to the flag already has been, and the flag stops the
        /// clock the moment it flies, the ball being dead already (4-4-g). Then the
        /// runoff, where it applies (4-7-1), and how the clock restarts (4-3-2-e).
        ///
        /// `warningInTheInterval` is whether the two-minute warning fell before the flag,
        /// which the interval charged for the whole play knows and this cannot see.
        private mutating func runClockForDeadBallFoul(
            _ outcome: Outcome, choices: DeadBallChoices?, warningInTheInterval: Bool
        ) {
            let rules = setup.rules
            let clockWasRunning = previousBehavior != .stopsUntilSnap
            // The clock at the flag is running only if it was running into the interval
            // and the warning did not stop it on the way. The period running out is not
            // a case here: an interval that exhausts a period ends it before any of this,
            // with no down and no flag.
            let runningAtTheFlag = clockWasRunning && !warningInTheInterval
            // A penalty enforcement is an administrative stoppage, so unless a rule below
            // resets the play clock otherwise, the next snap is against the short one
            // (4-6-2-e).
            playClock = rules.playClockAfterAnAdministrativeStoppage

            guard let penalty = outcome.penalties.first else {
                previousBehavior = runningAtTheFlag ? .stopsUntilReadyForPlay : .stopsUntilSnap
                return
            }
            let byOffense = penalty.offendingTeam == possession
            // How the clock restarts once the flag is enforced, unless a specific rule
            // says otherwise: on the snap in the late-game cases, else as though the
            // foul had not occurred (4-3-2-e).
            let restart: ClockBehavior =
                rules.clockStartsOnTheSnapAfterFoul(
                    byOffense: byOffense, stoppedTheClockBeforeTheSnap: true,
                    quarter: clock.quarter, isPostseason: setup.isPostseason,
                    clockRemaining: clock.secondsRemaining)
                ? .stopsUntilSnap : .stopsUntilReadyForPlay

            if rules.carriesRunoff(
                foul: penalty.foul, byOffense: byOffense, quarter: clock.quarter,
                isPostseason: setup.isPostseason, clockRemaining: clock.secondsRemaining,
                clockWasRunning: runningAtTheFlag)
            {
                // The offence may spend a timeout instead, and the clock then starts on
                // the snap (4-7-1 Item 1).
                if choices?.offenseTakesTimeout == true, timeouts(of: possession) > 0 {
                    spendTimeout(offense: true)
                    elect(.timeoutInsteadOfRunoff)
                    return
                }
                // The defence may decline the runoff and keep the yardage; the clock
                // then restarts as any dead-ball foul's does, which inside two minutes
                // is on the snap (4-3-2-e-1, 4-3-2-e-2), against the short play clock.
                if choices?.defenseDeclinesRunoff == true {
                    previousBehavior = restart
                    elect(.runoffDeclined)
                    return
                }
                // The runoff, between downs; a half can end on it (4-5-4 Note 4). The
                // clock then starts on the ready-for-play signal (4-3-2-g), with the
                // play clock reset to thirty (4-7-1 Item 1).
                _ = clock.run(
                    GameClock.Elapsed(duringPlay: 0, beforeSnap: rules.tenSecondRunoff),
                    rules: rules, isPostseason: setup.isPostseason)
                previousBehavior = .stopsUntilReadyForPlay
                playClock = rules.playClockAfterARunoff
                elect(.runoff)
                return
            }

            // A defensive act that conserves time in the last forty seconds of a half
            // ends the half (4-7-3), unless the defence has a timeout left or the
            // offence would rather play on — in which case the clock's restart is the
            // offence's choice, as below.
            if !byOffense,
                rules.conservesTime(foul: penalty.foul, clockWasRunning: runningAtTheFlag),
                rules.isInTheLastFortySeconds(
                    quarter: clock.quarter, isPostseason: setup.isPostseason,
                    clockRemaining: clock.secondsRemaining),
                timeouts(of: defending) == 0
            {
                if choices?.offenseEndsTheHalf == true {
                    clock.secondsRemaining = 0
                    previousBehavior = .stopsUntilSnap
                    elect(.halfEnded)
                    return
                }
                elect(.playedOn)
            }

            // No runoff. A dead-ball foul stops the clock (4-4-g): one that was stopped
            // at the flag waits for the snap. One that was running restarts on the ready
            // signal after a defensive foul inside two minutes unless the offence
            // chooses the snap, with the play clock reset to forty (4-7-1 Item 2);
            // otherwise as 4-3-2-e says.
            guard runningAtTheFlag else {
                previousBehavior = .stopsUntilSnap
                return
            }
            let insideTwoMinutes = rules.isAfterTheTwoMinuteWarning(
                quarter: clock.quarter, isPostseason: setup.isPostseason,
                clockRemaining: clock.secondsRemaining)
            if !byOffense, insideTwoMinutes {
                let onTheSnap = choices?.offenseStartsClockOnTheSnap == true
                previousBehavior = onTheSnap ? .stopsUntilSnap : .stopsUntilReadyForPlay
                playClock = rules.playClockAfterADefensiveConservation
                elect(onTheSnap ? .clockStartsOnTheSnap : .clockStartsOnTheReady)
                return
            }
            previousBehavior = restart
        }

        // MARK: - An injury after the two-minute warning

        /// An injury timeout after the two-minute warning of a half (2025 rulebook,
        /// 4-5-4). Before the warning an injury timeout changes nothing here: the clock
        /// starts as if it had not occurred (4-5-3).
        ///
        /// The injured player's team is charged a team timeout if it has one (4-5-4-a);
        /// otherwise the Referee calls an excess timeout (4-5-4-b), which is where the
        /// clock rules are. Against the team in possession, if the timeout stopped a
        /// running clock or delayed its restart on the ready, the defence may have ten
        /// seconds run off, after which the clock starts on the ready with the play
        /// clock at thirty (Note 3) — a half can end on it (Note 4) — or decline it, in
        /// which case the clock starts on the ready unless the opponent, which is the
        /// defence, chooses the snap (Note 1); a defence that declined wants the clock
        /// stopped, so it chooses the snap. Against the defence, the play clock resets
        /// to forty and the clock starts on the ready unless the offence chooses the
        /// snap (Note 1); in the last forty seconds with the clock running the half ends
        /// unless the offence would rather play on (4-7-3). A foul on the play stopped
        /// the clock first, so no runoff follows it (Notes 6 and 7). There is never a
        /// runoff against the defence (Note 9).
        ///
        /// Not modelled: the five-yard penalty for a second excess timeout in a half
        /// (Note 2), and an injury to both sides at once (Note 5).
        mutating func applyInjuryTimeout(
            injuredTeam: TeamID, on play: PlayRecord, choices: InjuryChoices
        ) {
            let rules = setup.rules
            guard !isOver, !pendingTry, !clock.isExpired, clock.quarter == play.situation.quarter,
                clock.twoMinuteWarningTaken
            else { return }
            // No timeout is charged when the injury came of a foul by an opponent, or
            // during a down with a change of possession, a score or a try (4-5-4-a,
            // 4-5-4-b); the clock is dead after every one of those anyway.
            let opponentFouled = play.outcome.penalties.contains { $0.offendingTeam != injuredTeam }
            let scored: Bool
            switch play.outcome.endedIn {
            case .touchdown, .safety, .fieldGoalGood: scored = true
            default: scored = false
            }
            let changedHands = possession != play.situation.possession
            let wasATry =
                play.outcome.kind == .extraPoint || play.outcome.kind == .twoPointConversion
            guard !opponentFouled, !scored, !changedHands, !wasATry else { return }

            if timeouts(of: injuredTeam) > 0 {
                spendTimeout(of: injuredTeam)
                elect(.injuryTimeoutCharged)
                return
            }

            // An excess timeout. It touches the clock only when it stopped a running
            // clock or delayed a restart on the ready, and a foul on the play had not
            // already stopped it.
            let stoppedARunningClock =
                previousBehavior != .stopsUntilSnap && play.outcome.penalties.isEmpty
            guard stoppedARunningClock else {
                elect(.excessInjuryTimeout)
                return
            }

            if injuredTeam == possession {
                if choices.defenseTakesRunoff {
                    _ = clock.run(
                        GameClock.Elapsed(duringPlay: 0, beforeSnap: rules.tenSecondRunoff),
                        rules: rules, isPostseason: setup.isPostseason)
                    previousBehavior = .stopsUntilReadyForPlay
                    playClock = rules.playClockAfterARunoff
                    elect(.injuryRunoff)
                    endThePeriodIfExpired()
                    return
                }
                previousBehavior = .stopsUntilSnap
                elect(.injuryRunoffDeclined)
                return
            }

            elect(.excessInjuryTimeout)
            if rules.isInTheLastFortySeconds(
                quarter: clock.quarter, isPostseason: setup.isPostseason,
                clockRemaining: clock.secondsRemaining)
            {
                if choices.offenseEndsTheHalf {
                    clock.secondsRemaining = 0
                    previousBehavior = .stopsUntilSnap
                    playClock = rules.playClockAfterAnAdministrativeStoppage
                    elect(.halfEnded)
                    endThePeriodIfExpired()
                    return
                }
                elect(.playedOn)
            }
            previousBehavior =
                choices.offenseStartsClockOnTheSnap ? .stopsUntilSnap : .stopsUntilReadyForPlay
            playClock = rules.playClockAfterADefensiveConservation
            elect(
                choices.offenseStartsClockOnTheSnap ? .clockStartsOnTheSnap : .clockStartsOnTheReady
            )
        }

        /// A period that time between downs has exhausted — a runoff, the last-forty-
        /// seconds election, or simply the interval to a snap that never came — ends as
        /// it would have at the end of a play: the next period, or the game. Nothing
        /// extends it, because nothing was live (4-8-1); the advancement is the state as
        /// it stands, and `replayed` says no down happened, so an overtime possession is
        /// not ended by it either.
        private mutating func endThePeriodIfExpired() {
            guard clock.isExpired else { return }
            checkForEnd(
                Advancement(ballOn: ballOn, down: down, distance: distance), wasKickoff: false,
                replayed: true)
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
            // (16-1-5-b, 16-1-5-c). A kickoff the kicking team recovers is both at once:
            // the receivers have had their opportunity and the kickers possess
            // (16-1-5-c, A.R. 16.2).
            if clock.quarter > setup.rules.quarters {
                if pendingKickoff {
                    overtimePossessions = min(
                        2, overtimePossessions + (advancement.possessionChanged ? 1 : 2))
                } else if advancement.possessionChanged {
                    overtimePossessions = min(2, overtimePossessions + 1)
                }
            }

            ballOn = advancement.ballOn
            down = advancement.down
            distance = advancement.distance

            // Order matters: a try is owed before the kickoff that follows it — unless
            // the try itself has to be played again, which a foul by the scoring team
            // during a successful one owes (11-3-3 Item 3-a). `advancement.requiresTry`
            // is how the rules layer says so, and the ball is already at the enforced
            // spot.
            if pendingTry, advancement.requiresTry {
                // The choice already made stands, so `chooseTry` is not asked again: it
                // would reset the spot to the standard one and throw the enforcement
                // away. Whether the caller may change its mind is `tryNeedsRedecision`,
                // set by `moveTheOtherTryOption` exactly as it is for a flag before the
                // snap.
                return
            }
            if pendingTry {
                pendingTry = false
                tryGoesForTwo = nil
                tryRuns = nil
                tryNeedsRedecision = false
                pendingKickoff = true
                ballOn = freeKickSpot()
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
                ballOn = freeKickSpot(from: ballOn)
            }
        }

        /// Where the free kick is made from, with any penalty the rules owed it walked off
        /// (2025 rulebook, 14-2-3, 11-3-3 Item 4-a, 11-3-3 Item 7).
        ///
        /// `from` is the spot the advancement already put the ball on — the kicking team's
        /// 35 after a score, its 20 after a safety — and `nil` means the ordinary kickoff
        /// spot, which is what a try's own advancement does not supply.
        private mutating func freeKickSpot(from spot: UInt8? = nil) -> UInt8 {
            let base = spot ?? setup.rules.ballOnFromOwnYard(setup.rules.kickoffFromOwnYard)
            guard let owed = owedEnforcement, owed.spot == .theFreeKick else { return base }
            owedEnforcement = nil
            return walkOff(owed.penalty, from: base)
        }

        // MARK: - Ending periods and the game

        private mutating func checkForEnd(
            _ advancement: Advancement, wasKickoff: Bool, replayed: Bool
        ) {
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
                checkForOvertimeEnd(advancement, wasKickoff: wasKickoff, replayed: replayed)
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
        private mutating func checkForOvertimeEnd(
            _ advancement: Advancement, wasKickoff: Bool, replayed: Bool
        ) {
            let rules = setup.rules

            // A safety ends it whenever it comes: against the opening drive it is the one
            // named exception to each side getting a turn (16-1-3-a), and once both have
            // possessed any score that separates the sides wins (16-1-3-c).
            if advancement.scoring == .safety {
                isOver = true
                return
            }

            let suddenDeath = overtimePossessions >= 2
            // The play that starts a possession — the kickoff — ends one only when it
            // scores, or when the kicking team recovers it: the receivers' opportunity
            // is over either way (16-1-5-c, A.R. 16.2, A.R. 16.4). From scrimmage, a
            // score, a change of possession, or the try that closes a scoring sequence
            // ends one. A flag before the snap ends nothing; the down is replayed.
            let possessionEnded: Bool
            if replayed {
                possessionEnded = false
            } else if wasKickoff {
                possessionEnded = advancement.scoring != nil || !advancement.possessionChanged
            } else {
                possessionEnded =
                    advancement.possessionChanged || advancement.scoring != nil
                    || advancement.requiresKickoff
            }

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

            // Postseason: another period (16-1-4-d). Whether play carries on from the
            // spot or a half opens with a kick is the period's to say; either way the
            // end of a period is an administrative stoppage (4-6-2-d).
            startNextPeriod()
        }

        /// The next period: of regulation, or of overtime.
        ///
        /// A period that opens a half is put back in play with a free kick, and which
        /// periods those are is `Rules.periodResumesWithKickoff` — one predicate, because
        /// the printer in Tools/gamelog ends a drive on the same boundaries, and a second
        /// copy of the answer is how the two come to disagree. Every other period carries
        /// on from the spot: the teams change goals, and possession, the down, the ball
        /// and the line to gain are unchanged (4-2-3, 16-1-4-f).
        private mutating func startNextPeriod() {
            let rules = setup.rules
            guard let next = clock.advancingPeriod(rules: rules, isPostseason: setup.isPostseason)
            else {
                isOver = true
                return
            }
            clock = next

            if rules.periodResumesWithKickoff(quarter: next.quarter) {
                // A half's timeouts: three (4-5-1), in each postseason overtime half as
                // well (16-1-4-g), and two for the regular season's one overtime period
                // (16-1-3-e).
                let timeouts =
                    next.quarter > rules.quarters && !setup.isPostseason
                    ? rules.regularSeasonOvertimeTimeouts : rules.timeoutsPerHalf
                homeTimeouts = timeouts
                awayTimeouts = timeouts

                if rules.periodFollowsACoinToss(quarter: next.quarter) {
                    // The toss (16-1-2, 16-1-4-i) is not drawn: the side with the ball
                    // kicks off, and stands for the captain who lost it.
                    tossLoser = possession
                } else {
                    // The first choice of 4-2-2's privileges is the toss loser's — at
                    // the second half (4-2-2), and at a third overtime period
                    // (16-1-4-e) — and is put to that side's caller before the kick.
                    // Until it answers, the loser has the ball to kick off with.
                    possession = tossLoser
                    firstChoicePending = true
                }
                ballOn = rules.ballOnFromOwnYard(rules.kickoffFromOwnYard)
                down = .first
                distance = rules.yardsToGain
                pendingKickoff = true
                // Overtime's opportunities to possess are counted from its first period
                // (16-1-3-a, 16-1-4-a). A later toss continues the same overtime
                // (16-1-4-i): a side that has had its opportunity has had it.
                if next.quarter == rules.quarters + 1 { overtimePossessions = 0 }
            }
            previousBehavior = .stopsUntilSnap
            // The end of a period is an administrative stoppage (4-6-2-d), and so is the
            // free kick that opens a half (4-6-2-g). It is the period's clock that put
            // the twenty-five there, not a timeout, and a period the interval alone
            // exhausted may have had one charged in it that no snap ever spent.
            playClock = rules.playClockAfterAnAdministrativeStoppage
            offenseIsSetFromATimeout = false
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
                game: setup.game, plays: plays, injuries: injuries, rosters: rosters,
                weather: setup.weather, homeScore: homeScore, awayScore: awayScore,
                winner: winner)
        }
    }
}
