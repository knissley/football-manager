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

        // Behind late, a punt is a surrender. Go, wherever you are.
        if classified.isDesperation && kickLength > Self.maximumFieldGoal { return nil }

        if kickLength <= Self.maximumFieldGoal {
            // Inside a yard of the marker near the goal line, points are not the only
            // option — but the baseline takes the points and lets a better caller
            // out-think it.
            if classified.downAndDistance == .goalToGo && situation.distance <= 1 { return nil }
            return .fieldGoal
        }

        // Short of the marker but a long way from a kick: go only where a stop would
        // not hand over the game.
        if classified.downAndDistance == .fourthShort && situation.ballOn < 45 { return nil }
        return .punt
    }

    private func family(
        for situation: SituationClass, random: inout SplittableRandom
    ) -> PlayFamily {
        // Short yardage is a run unless the clock says otherwise; long yardage is a
        // throw. Everything in between leans on the down.
        if situation.isMustPass {
            return passFamily(for: situation, random: &random)
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
        case .secondLong, .thirdMedium, .thirdLong, .fourthLong: runShare = 0.22
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

    /// Victory formation: the lead is safe if the clock can be exhausted.
    ///
    /// Three kneels from first down, each burning the play clock and a couple of seconds
    /// of live ball — less whatever the defence can claw back with its timeouts. A team
    /// that kneels a play too early hands the ball back, and one that runs a play it did
    /// not need to can fumble the game away.
    private func shouldKneel(
        _ situation: Situation, _ classified: SituationClass, _ context: PlayContext
    ) -> Bool {
        guard classified.score.isLeading, classified.time.isEndgame else { return false }
        guard situation.down != .fourth else { return false }

        let kneelsAvailable = Int(Down.fourth.rawValue) - Int(situation.down.rawValue)
        guard kneelsAvailable > 0 else { return false }

        let secondsPerKneel = Int(context.rules.playClock) + 2
        let clawedBack = Int(situation.defenseTimeouts) * secondsPerKneel
        let burnable = kneelsAvailable * secondsPerKneel - clawedBack
        return Int(situation.clockRemaining) <= burnable
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

        // The defence spends them to get the ball back. `scoreDifferential` is the
        // offence's, so a positive number means the team without the ball is behind.
        guard classified.time.isEndgame, situation.scoreDifferential > 0 else { return false }
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
