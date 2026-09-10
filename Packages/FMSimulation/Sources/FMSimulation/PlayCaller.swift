import FMCore
import FMRandom

/// Chooses what each side runs.
///
/// Both sides, always. Building the offensive caller first and retrofitting defence
/// produces a defence whose job is to lose to it
/// ([play-calling.md](../../../../docs/play-calling.md)).
public protocol PlayCaller: Sendable {

    /// - Parameters:
    ///   - situation: the exact state, which a kicking decision needs — field goal range
    ///     is a matter of yards, not of buckets.
    ///   - classified: the same moment in the shared situational vocabulary, which is
    ///     what tendencies and gameplan rules key off.
    ///   - context: who is on the field, and the rules in force.
    ///   - random: the play's own stream.
    /// - Returns: the play the offence will run.
    func offensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> OffensiveCall

    func defensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> DefensiveCall

    /// Whether this side stops the clock before the snap.
    ///
    /// A timeout is not a play, so it is asked separately. Both sides get the question:
    /// the offence spends them to keep a drive alive, and the defence spends them to get
    /// the ball back, which is the half nothing in a football game ever does if you only
    /// model the team with the ball.
    func callsTimeout(
        for situation: Situation, classified: SituationClass, isOffense: Bool,
        context: PlayContext
    ) -> Bool

    /// Whether to go for two after this touchdown.
    ///
    /// The score here is *before* the try, so trailing by two means the conversion ties
    /// it and trailing by five means it cuts the lead to a field goal.
    func goesForTwo(situation: Situation, classified: SituationClass) -> Bool

    /// Whether to keep the kickoff short and fight for it.
    ///
    /// Note the frame: the *kicking* team has possession on a kickoff, so a negative
    /// differential here is the team that just scored and is still behind.
    func kicksOnside(situation: Situation, classified: SituationClass) -> Bool

    /// Whether the offence spends a charged timeout instead of taking the ten-second
    /// runoff its dead-ball foul has earned (2025 rulebook, 4-7-1 Item 1). The clock
    /// starts on the snap after the timeout rather than on the ready signal.
    ///
    /// `situation.clockRemaining` is the clock at the flag, not at the previous whistle.
    func takesTimeoutInsteadOfRunoff(situation: Situation, classified: SituationClass) -> Bool

    /// Whether the defence declines the ten-second runoff and keeps the yardage
    /// (4-7-1 Item 1). A defence that wants the clock stopped does.
    func declinesRunoff(situation: Situation, classified: SituationClass) -> Bool

    /// After a defensive dead-ball foul inside two minutes with the clock running, the
    /// clock starts on the ready signal unless the offence chooses the snap
    /// (4-7-1 Item 2). Whether it does.
    func startsClockOnTheSnap(
        afterDefensiveFoul situation: Situation, classified: SituationClass
    )
        -> Bool

    /// In the last forty seconds of a half, after a defensive act that conserves time
    /// with the clock running and the defence out of timeouts, whether the offence ends
    /// the half rather than play on (2025 rulebook, 4-7-3). Playing on, its choice of a
    /// snap or a ready-for-play start is `startsClockOnTheSnap(afterDefensiveFoul:)`.
    func endsTheHalf(
        afterDefensiveTimeConservation situation: Situation, classified: SituationClass
    )
        -> Bool

    /// Whether the defence has ten seconds run off for an excess injury timeout charged
    /// to the team in possession after the two-minute warning (4-5-4 Note 3). A defence
    /// that declines wants the clock stopped, and has it wait for the snap (4-5-4
    /// Note 1).
    func takesRunoff(forInjuryTimeout situation: Situation, classified: SituationClass) -> Bool

    /// Who the offence sends out, which it declares by substituting before the snap.
    ///
    /// This is the first half of the sport's oldest chess match: personnel is public
    /// information, and the defence answers it.
    func personnel(
        for family: PlayFamily, situation: Situation, classified: SituationClass,
        random: inout SplittableRandom
    ) -> PersonnelGroup

    /// What the defence answers with, having seen `situation.offensePersonnel`.
    func package(
        for situation: Situation, classified: SituationClass, random: inout SplittableRandom
    ) -> DefensivePackage
}

extension PlayCaller {

    /// The conventional chart, and the floor any real caller has to beat. A coach with a
    /// gameplan overrides these; one without still has to answer the question, because a
    /// team that never goes for two and never kicks onside cannot come back from ten.
    public func goesForTwo(situation: Situation, classified: SituationClass) -> Bool {
        // The score here is read *before* the try, so trailing by two means the
        // conversion ties it and trailing by five means it turns a two-score deficit into
        // a field goal. Those two are on the chart from the second half onwards, not only
        // in the last minutes — a coach who waits for the endgame to consult it has
        // already kicked the point that made the arithmetic wrong.
        // The chart, on the trailing side: the deficits where the second point changes
        // what you need next. Down two the conversion ties it; down five it turns two
        // scores into a field goal; down ten it turns a two-score game into a touchdown
        // and a conversion.
        if situation.quarter >= 3,
            [-2, -5, -10].contains(situation.scoreDifferential)
        {
            return true
        }
        // And on the leading side, where the second point turns a one-score lead into
        // one they cannot answer with a single possession.
        if situation.quarter >= 4, [1, 4, 5].contains(situation.scoreDifferential) {
            return true
        }
        return classified.time.isEndgame && situation.scoreDifferential < 0
            && situation.scoreDifferential >= -10
    }

    /// The conventional groupings, by what the play is asking for.
    public func personnel(
        for family: PlayFamily, situation: Situation, classified: SituationClass,
        random: inout SplittableRandom
    ) -> PersonnelGroup {
        // Short yardage and the goal line are where the extra bodies go — though the
        // modern game runs plenty of it from an ordinary grouping too.
        if classified.downAndDistance.isShortYardage || situation.ballOn <= 3 {
            switch random.next(upperBound: 100) {
            case ..<32: return .twentyTwo
            case ..<70: return .twelve
            default: return .eleven
            }
        }
        // Two minutes down by a score, everybody who can run a route is on the field.
        if classified.isMustPass && classified.time.isTwoMinute {
            switch random.next(upperBound: 100) {
            case ..<18: return .empty
            case ..<45: return .ten
            default: return .eleven
            }
        }
        if classified.isMustPass {
            return random.nextBool(probability: 0.11) ? .ten : .eleven
        }
        if classified.isClockBurn {
            switch random.next(upperBound: 100) {
            case ..<30: return .twentyOne
            case ..<62: return .twelve
            default: return .eleven
            }
        }
        // Otherwise the modern default, with a heavier look mixed in — about two thirds
        // of the sport's snaps are eleven personnel.
        switch random.next(upperBound: 100) {
        case ..<74: return .eleven
        case ..<89: return .twelve
        case ..<96: return .twentyOne
        default: return .ten
        }
    }

    /// The answer, which is mostly a matter of counting receivers.
    ///
    /// A defence substitutes to match: three receivers get a nickel back, four get a
    /// dime. Guessing wrong is the cost of guessing, and the offence declaring first is
    /// what makes it a decision at all.
    public func package(
        for situation: Situation, classified: SituationClass, random: inout SplittableRandom
    ) -> DefensivePackage {
        if situation.ballOn <= 3 && !classified.isMustPass { return .goalLine }
        if classified.time == .twoMinuteGame && classified.score.isLeading
            && situation.ballOn > 60
        {
            return .prevent
        }

        switch situation.offensePersonnel.wideReceivers {
        case 5: return .quarter
        case 4: return .dime
        case 3:
            // Against three receivers, nickel is the default answer — but a defence that
            // matches personnel every single time is a defence nobody can ever catch out,
            // and the count mismatch is where the chess match pays. Real defences stay in
            // their base front against eleven personnel about a quarter of the time,
            // betting on the run, and wear the extra receiver when they are wrong.
            if classified.downAndDistance.isShortYardage {
                return random.nextBool(probability: 0.55) ? .base : .nickel
            }
            if classified.isMustPass {
                return random.nextBool(probability: 0.15) ? .dime : .nickel
            }
            return random.nextBool(probability: 0.24) ? .base : .nickel
        default:
            // Two or fewer: heavy personnel, and a base defence unless the down says
            // otherwise.
            return classified.isMustPass ? .nickel : .base
        }
    }

    public func kicksOnside(situation: Situation, classified: SituationClass) -> Bool {
        guard situation.quarter >= 4, situation.scoreDifferential < 0 else { return false }
        // Two scores down: any time inside the last three minutes.
        if situation.scoreDifferential <= -9 && situation.clockRemaining <= 180 { return true }
        // One score down with no realistic way to get the ball back and score again.
        return situation.clockRemaining <= 50 && situation.defenseTimeouts == 0
    }

    // The baseline answers to the runoff's decisions. Coaching choices, not rules;
    // a caller with a gameplan overrides them.

    /// Take the runoff unless a timeout remains and the clock is at fifteen seconds or
    /// less, where ten seconds is most of what is left.
    public func takesTimeoutInsteadOfRunoff(
        situation: Situation, classified: SituationClass
    )
        -> Bool
    {
        situation.offenseTimeouts > 0 && situation.clockRemaining <= 15
    }

    /// Accept the runoff when level or leading; decline it when trailing, because a
    /// trailing defence wants the clock stopped, not run. `scoreDifferential` is the
    /// offence's, so a positive number means the defence is behind.
    public func declinesRunoff(situation: Situation, classified: SituationClass) -> Bool {
        situation.scoreDifferential > 0
    }

    /// Have the clock wait for the snap unless leading: a trailing or level offence
    /// inside two minutes wants every second.
    public func startsClockOnTheSnap(
        afterDefensiveFoul situation: Situation, classified: SituationClass
    ) -> Bool {
        situation.scoreDifferential <= 0
    }

    /// End the half when leading, where nothing that can happen in thirty seconds is
    /// good news; level or trailing, the offence has the ball and wants the time.
    public func endsTheHalf(
        afterDefensiveTimeConservation situation: Situation, classified: SituationClass
    ) -> Bool {
        situation.scoreDifferential > 0
    }

    /// The same judgement as declining the runoff for the offence's foul, and for the
    /// same reason: a trailing defence wants the clock stopped, not run.
    public func takesRunoff(
        forInjuryTimeout situation: Situation, classified: SituationClass
    ) -> Bool {
        !declinesRunoff(situation: situation, classified: classified)
    }
}

/// A caller with no memory, no gameplan and no opinion about the opponent.
///
/// The floor from [play-calling.md](../../../../docs/play-calling.md)'s benchmark: any
/// coordinator who cannot beat this comfortably is broken rather than merely bad. It
/// exists so a season can be simulated before the real caller is written, and because a
/// baseline you can measure against is worth more than a first attempt at a good one.
///
/// It reads `SituationClass` and nothing else, which is the point — the situational
/// vocabulary is shared, so this caller and a real one are answering the same question.
public struct BaselineCaller: PlayCaller {

    public init() {}

    // MARK: - Offence

    /// The longest kick the baseline will attempt.
    ///
    /// A flat number, because the baseline has no kicker to consult. A real caller reads
    /// his kicker's leg and the weather, and that is one of the things it should beat
    /// this by.
    public static let maximumFieldGoal = 55

    /// The longest kick worth attempting when a punt is still a sensible alternative.
    ///
    /// A fifty-five yarder is a real option at the end of a half, when the choice is
    /// between a long kick and nothing. On a first-quarter fourth down it is a bad trade
    /// against forty yards of field position, and treating every kick inside the maximum
    /// as automatic is what made this caller attempt a fifty-five yarder on fourth and
    /// one from the opponent's thirty-eight.
    public static let routineFieldGoal = 51

    public func offensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> OffensiveCall {
        if shouldKneel(situation, classified, context) {
            return CrudePlaybook.call(.kneel, tempo: .bleedClock)
        }
        if shouldSpike(situation, classified, context) {
            return CrudePlaybook.call(.spike, tempo: .hurryUp)
        }
        if situation.down == .fourth, let kick = fourthDown(situation, classified, context) {
            return CrudePlaybook.call(kick)
        }
        return CrudePlaybook.call(
            family(for: classified, random: &random), tempo: tempo(for: classified))
    }

    /// Kick, punt, or go. Returns `nil` when the answer is to run a play.
    ///
    /// Deliberately simple and deliberately conservative — it is the floor a real caller
    /// is measured against, and fourth-down aggression is one of the dials that makes
    /// hiring a coordinator matter.
    private func fourthDown(
        _ situation: Situation, _ classified: SituationClass, _ context: PlayContext
    ) -> PlayFamily? {
        let kickLength = context.rules.fieldGoalDistance(ballOn: situation.ballOn)

        // A long kick is worth attempting when the alternative is nothing — the end of a
        // half, or a game that is decided here. Otherwise it is a bad trade against the
        // field position a punt buys.
        let stretching = classified.time.isEndgame || classified.time == .twoMinuteFirstHalf
        let inRange = kickLength <= (stretching ? Self.maximumFieldGoal : Self.routineFieldGoal)

        // Behind, late: a punt is a surrender, and a kick is only worth taking if it ties
        // the game or wins it.
        //
        // The *second* half only. `isDesperation` is true inside two minutes of either
        // half — correctly, as a description of the moment — but two minutes before
        // halftime you are trying to score before the break, not trying to save the game.
        // There is a whole half left, and punting from your own twenty is still the right
        // call. Treating both halves alike had teams going for it on fourth and long from
        // their own end before halftime, which was half of every deep fourth-down attempt
        // in the league.
        if classified.isDesperation && classified.time != .twoMinuteFirstHalf {
            return inRange && situation.scoreDifferential >= -3 ? .fieldGoal : nil
        }

        if goesForIt(situation, classified, inRange: inRange) { return nil }
        return inRange ? .fieldGoal : .punt
    }

    /// Whether to keep the offence on the field.
    ///
    /// The old answer was almost never: any kick inside the maximum was taken before the
    /// question was asked, and going for it needed fourth and three or less between the
    /// opponent's thirty-nine and forty-five. That produced a team going for it on 13% of
    /// its fourth-and-ones, in a sport where the figure is nearer two-thirds.
    ///
    /// Deliberately a chart rather than a win-probability model. It is the floor a real
    /// caller is measured against, and fourth-down aggression is one of the dials that
    /// makes hiring a coordinator matter.
    private func goesForIt(
        _ situation: Situation, _ classified: SituationClass, inRange: Bool
    ) -> Bool {
        let ballOn = Int(situation.ballOn)

        // Fourth and goal from inside the three is a yard or so for a touchdown against
        // the safest three points in the sport, and taking the kick every single time is
        // what made a third of this caller's field goal attempts chip shots — against a
        // sourced 19.1-25.3% of attempts inside thirty yards (2023-24, nflverse
        // play-by-play; `row:fieldGoalAttemptsUnder30`).
        if classified.downAndDistance == .goalToGo && ballOn <= 3 {
            // Unless the lead and the clock make three points worth more than four.
            return !(inRange && classified.isClockBurn)
        }

        // Backed up inside your own thirty, a stop is worth more to them than the down is
        // to you, whatever the distance.
        if ballOn > 70 { return false }

        switch situation.distance {
        case ...1:
            // Protecting a lead late with a kick available, take the points.
            if inRange && classified.isClockBurn { return false }
            // Past midfield as a matter of course, and from further back when you are
            // chasing the game.
            return ballOn <= 52 || (classified.score.isTrailing && ballOn <= 64)
        case 2...3:
            // No-man's land: too far to kick, too close for a punt to buy much.
            return !inRange && (ballOn <= 50 || (classified.score.isTrailing && ballOn <= 60))
        case 4...6:
            return !inRange && classified.score.isTrailing && ballOn <= 48
        default:
            return false
        }
    }

    private func family(
        for situation: SituationClass, random: inout SplittableRandom
    ) -> PlayFamily {
        // Short yardage is a run unless the clock says otherwise; long yardage is a
        // throw. Everything in between leans on the down.
        //
        // The clock shrinks the menu further than any distance does, and it outranks the
        // down: forty seconds behind by four, third and two is a throw. Never all the
        // way to nothing, though. The classification is a description of the moment, and
        // a caller that reads it as an instruction — no run at all, ever, from here — is
        // one a defence can play the pass against for free.
        if situation.isMustPass && situation.time.isTwoMinute {
            return random.nextBool(probability: 0.05)
                ? (random.nextBool(probability: 0.62) ? .insideRun : .outsideRun)
                : passFamily(for: situation, random: &random)
        }
        if situation.downAndDistance.isShortYardage {
            // Short yardage on the goal line is not the same as short yardage at
            // midfield: the end zone is a defender-free area a throw can reach.
            if situation.field == .goalLine && random.nextBool(probability: 0.34) {
                return .quickPass
            }
            return random.nextBool(probability: 0.72) ? .insideRun : .outsideRun
        }
        if situation.isClockBurn {
            return random.nextBool(probability: 0.82)
                ? (random.nextBool(probability: 0.65) ? .insideRun : .outsideRun) : .quickPass
        }

        // A lean per bucket, and **every bucket is nonzero**: the sport runs on third and
        // eight often enough that a defence has to keep a body in the box for it, and a
        // caller whose third-and-long share is exactly zero is a caller a tendency table
        // can read off a single snap. These are modelling conventions rather than sourced
        // rates; the run and pass rows in `Tools/simharness` are what grade the balance.
        let runShare: Double
        switch situation.downAndDistance {
        case .firstDown: runShare = 0.61
        // Near the goal line the field is short and the throw is the higher-value call
        // more often than a run-first lean suggests. A run-heavy goal line put too many
        // touchdowns on the ground and left the passing distribution without a mean high
        // enough to have a tail.
        case .goalToGo: runShare = 0.38
        case .secondShort, .thirdShort, .fourthShort: runShare = 0.70
        case .secondMedium: runShare = 0.53
        case .secondLong: runShare = 0.22
        // Third and five is a down the sport runs on constantly; third and eight is one
        // it hardly ever does, and the gap between them is the whole point of splitting
        // the bucket at six.
        case .thirdMedium, .fourthMedium: runShare = 0.20
        case .thirdLong, .fourthLong: runShare = 0.08
        }

        if random.nextBool(probability: runShare) {
            return random.nextBool(probability: 0.62) ? .insideRun : .outsideRun
        }
        return passFamily(for: situation, random: &random)
    }

    private func passFamily(
        for situation: SituationClass, random: inout SplittableRandom
    ) -> PlayFamily {
        // Desperation throws deep because there is no time for anything else; ordinary
        // downs spread across the tree.
        if situation.isDesperation && situation.field != .redZone {
            return random.nextBool(probability: 0.55) ? .deepPass : .mediumPass
        }
        switch random.next(upperBound: 100) {
        case ..<44: return .quickPass
        case ..<72: return .mediumPass
        case ..<82: return .deepPass
        case ..<92: return .playAction
        default: return .screen
        }
    }

    private func tempo(for situation: SituationClass) -> Tempo {
        if situation.isDesperation { return .hurryUp }
        if situation.isClockBurn { return .bleedClock }
        if situation.time.isTwoMinute { return .fast }
        return .normal
    }

    // MARK: - The endgame

    /// The seconds between the snap of a knee and the whistle.
    ///
    /// A modelling convention about how long a quarterback takes to go down, not a rule,
    /// and the same two seconds the resolver charges the play.
    private static let secondsToTakeAKnee = 2

    /// Victory formation: the lead is safe if the clock can be exhausted.
    ///
    /// Every term of the arithmetic is a rule. A knee ends the down in bounds, so the
    /// clock keeps running and the next snap has to come inside the forty seconds of the
    /// play clock (2025 rulebook, 4-6-1) — all of which an offence in victory formation
    /// spends. A charged timeout stops it until the next snap instead (4-3-2), so every
    /// timeout the defence still holds erases one of those intervals; it has three a half
    /// (4-5-1 Item 1). And nothing extends a period that expires between downs: 4-8-1
    /// extends one only while the ball is in play, 4-8-2 only for a foul in the down that
    /// expired it.
    ///
    /// So from this down: one knee per remaining down and one on fourth, an interval
    /// before each of those snaps after the first, and one more before the snap this
    /// offence is already standing over if the clock is running into it. The fourth
    /// down's interval counts because the fourth down is a knee too — see below — and a
    /// sequence that stopped a down short would hand the ball to a punter with half a
    /// play clock left on the game clock.
    ///
    /// What the count does not do is round anything up. Getting it wrong upwards hands
    /// the other side the ball; getting it wrong downwards costs one ordinary snap.
    ///
    /// Counted this way the decision is monotone, which is what makes a knee stick. The
    /// clock the next snap faces is exactly what this knee leaves — one interval and one
    /// knee, or one knee alone if the defence stops the clock — and the count falls by
    /// exactly as much, so a lead that could be knelt out on first down can still be knelt
    /// out on second. A count that shrinks faster than the clock kneels twice and then
    /// runs an ordinary play, which is what a won game gets fumbled away on.
    private func shouldKneel(
        _ situation: Situation, _ classified: SituationClass, _ context: PlayContext
    ) -> Bool {
        guard endingIsWorthMoreThanASnap(classified) else { return false }

        // The interval before the snap the offence is standing over runs against the play
        // clock actually in force — twenty-five from the whistle after a stoppage, forty
        // from the end of a play, forty again from the whistle after a defensive act that
        // conserved time (4-6-1, 4-6-2, 4-6-3-b) — and those are not the same length.
        // Every interval after it runs against the forty from the end of the play,
        // because a knee is an ordinary play that ends and nothing about it is one of the
        // stoppages 4-6-2 lists. Counting the first at the second's length is how a caller
        // kneels on a twenty-five, gets nine seconds less than it counted on, and has to
        // play the next down after all.
        //
        // A clock that starts on the ready rather than at the whistle costs the game clock
        // the officials' spot less than the play clock says, because the play clock has
        // not started yet while they set the ball. Count what the *game* clock loses, and
        // never more: counting high hands the ball over, counting low costs one snap.
        let inForce = context.playClock
        let spotting = inForce.startsOnTheReady ? Int(GameClock.readyForPlayDelay) : 0
        let standing = max(0, Int(inForce.intendedSnap(at: .bleedClock)) - spotting)
        let ordinary = Int(context.rules.playClockAfterAPlay.intendedSnap(at: .bleedClock))

        // A knee on fourth down is a turnover on downs — unless the period cannot survive
        // the play clock in front of it, in which case there is no fourth-down snap to
        // give away and the knee is the offence standing on the ball while the clock runs
        // out.
        guard situation.down != .fourth else {
            return context.clockIsRunning && Int(situation.clockRemaining) <= standing
        }

        let knees = Int(Down.fourth.rawValue) - Int(situation.down.rawValue)
        guard knees > 0 else { return false }

        // A charged timeout erases an interval, since the clock then starts on the next
        // snap (4-3-2). The longest go first, which is the ordinary ones.
        let timeouts = Int(situation.defenseTimeouts)
        let ordinaries = max(0, knees - timeouts)
        let inHand = context.clockIsRunning && timeouts <= knees ? standing : 0
        let exhaustible = knees * Self.secondsToTakeAKnee + ordinaries * ordinary + inHand
        return Int(situation.clockRemaining) <= exhaustible
    }

    /// Whether a snap can only cost this offence, so that ending the period is the
    /// better outcome.
    ///
    /// Inside two minutes of a half, and no earlier.
    ///
    /// The two-minute warning is a stoppage the defence is handed for nothing (2025
    /// rulebook, 4-4: the clock stops when the Referee signals it), so above it a lead is
    /// never safe — the warning is a fourth timeout, and one the count below cannot see.
    /// Kneeling into it also truncates the interval it was counting on, which is how a
    /// team kneels at 2:01 and then finds it has to play the down after all.
    ///
    /// Behind, never: a snap is the only thing that can still change the scoreboard, and
    /// that goes for the half as much as the game.
    ///
    /// Ending the *game* then needs a lead — level, the snap can still win it. Ending the
    /// *half* is a different question, because the half is not the game and the points
    /// still count: a team in field goal range plays for them however comfortable the
    /// lead is, and a knee there throws away three or seven for nothing. What is left is
    /// a lead with the ball too far out to do anything with before the break, or your own
    /// goal line right behind you, where the only points a snap can produce are the other
    /// side's.
    private func endingIsWorthMoreThanASnap(_ classified: SituationClass) -> Bool {
        guard classified.time.isTwoMinute, !classified.score.isTrailing else { return false }
        guard classified.time == .twoMinuteFirstHalf else { return classified.score.isLeading }
        guard !classified.isFieldGoalRange else { return false }
        return classified.score.isLeading || classified.field == .ownDeep
    }

    /// Throw it at the ground to stop the clock.
    ///
    /// Costs a down and a second, and it is only ever worth it when the clock is
    /// actually running and there is no timeout left to spend instead. Spiking with
    /// timeouts in hand wastes a down; spiking on a stopped clock wastes one for nothing.
    private func shouldSpike(
        _ situation: Situation, _ classified: SituationClass, _ context: PlayContext
    ) -> Bool {
        guard context.clockIsRunning, classified.time.isTwoMinute else { return false }
        guard classified.isDesperation || classified.score.isOneScoreGame else { return false }
        guard situation.offenseTimeouts == 0 else { return false }
        // A spike on fourth down is a turnover with extra steps.
        guard situation.down != .fourth else { return false }
        return situation.clockRemaining <= 28
    }

    public func callsTimeout(
        for situation: Situation, classified: SituationClass, isOffense: Bool,
        context: PlayContext
    ) -> Bool {
        guard context.clockIsRunning else { return false }
        let remaining = isOffense ? situation.offenseTimeouts : situation.defenseTimeouts
        guard remaining > 0 else { return false }

        if isOffense {
            // Keep the drive alive: the clock is running and there is not enough of it.
            guard classified.isDesperation else { return false }
            return situation.clockRemaining <= 100
        }

        // The defence spends them to get the ball back — in a game it can still win.
        // `scoreDifferential` is the offence's, so `score.isLeading` means the team
        // without the ball is the one behind, and three scores down is further than a
        // timeout can reach: it buys a possession nobody can use, and burning all three
        // to shorten a loss is not football.
        guard classified.time.isEndgame, classified.score.isLeading else { return false }
        guard classified.score != .leadingThreeScores else { return false }
        return situation.clockRemaining <= 200
    }

    // MARK: - Defence

    public func defensiveCall(
        for situation: Situation, classified: SituationClass, context: PlayContext,
        random: inout SplittableRandom
    ) -> DefensiveCall {
        defensiveCall(for: classified, random: &random)
    }

    private func defensiveCall(
        for situation: SituationClass, random: inout SplittableRandom
    ) -> DefensiveCall {
        // Sound against the thing the situation makes likely, and wrong often enough to
        // be a bet rather than a lookup. Every call gives something up.
        if situation.isMustPass {
            if situation.time.isTwoMinute && situation.score.isTrailing {
                // They have to throw and they have to hurry: take away the sideline and
                // make them earn it underneath.
                return random.nextBool(probability: 0.7) ? .preventShell : .dimeRush
            }
            switch random.next(upperBound: 100) {
            case ..<30: return .nickelTwoMan
            case ..<52: return .quartersMatch
            case ..<70: return .fireZone
            case ..<86: return .manFreeBlitz
            default: return .coverTwoZone
            }
        }

        if situation.downAndDistance.isShortYardage {
            return random.nextBool(probability: 0.62) ? .goalLineStop : .runStuff
        }

        if situation.isClockBurn {
            // They want the clock to run, so the defence has to get off the field.
            return random.nextBool(probability: 0.5) ? .runStuff : .manFreeBlitz
        }

        switch random.next(upperBound: 100) {
        case ..<32: return .baseCoverThree
        case ..<54: return .quartersMatch
        case ..<70: return .coverTwoZone
        case ..<82: return .nickelTwoMan
        case ..<92: return .fireZone
        default: return .runStuff
        }
    }
}
