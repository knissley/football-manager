/// What a foul is worth to the team that did not commit it.
///
/// Enforcement is a **choice**, not an automatic yardage adjustment. Both branches are
/// computed and the non-offending team takes whichever is better, which is why a
/// holding call on a sixty-yard touchdown is declined and a five-yard offside on
/// third-and-eight is accepted.
///
/// The classic bug is a declined penalty that still moves the ball. Nothing here can do
/// that: declining returns the play's own advancement untouched.
public struct PenaltyDecision: Sendable, Hashable {

    public let penalty: PenaltyRecord
    public let accepted: Bool
    /// What the down looks like once the choice is made.
    public let advancement: Advancement

    public init(penalty: PenaltyRecord, accepted: Bool, advancement: Advancement) {
        self.penalty = penalty
        self.accepted = accepted
        self.advancement = advancement
    }
}

extension Rules {

    /// Enforce a foul, taking whichever branch favours the team that did not commit it.
    ///
    /// - Parameters:
    ///   - penalty: the foul, with its yardage already measured for spot fouls.
    ///   - situation: the down as it was before the snap.
    ///   - outcome: what the play produced, which is what declining leaves standing.
    ///   - offendingTeamHadBall: whether the offence committed it.
    /// - Returns: the choice made, the penalty record stamped with it, and the resulting
    ///   down.
    public func enforce(
        _ penalty: PenaltyRecord,
        on situation: Situation,
        outcome: Outcome,
        offendingTeamHadBall: Bool
    ) -> PenaltyDecision {
        let declined = advance(from: situation, outcome: outcome)
        let accepted = enforcedAdvancement(
            penalty, on: situation, offendingTeamHadBall: offendingTeamHadBall)

        // A pre-snap foul is a dead ball: there is no play to decline in favour of, so
        // the flag stands whatever the yardage would have been.
        if penalty.foul.isPreSnap {
            return PenaltyDecision(
                penalty: accepted.record, accepted: true, advancement: accepted.advancement)
        }

        // A dead-ball foul is walked off from where the play ended, and there is nothing
        // to decline: the play already counted. Without this the engine could not call
        // one at all, because every path it had either cancelled the snap or offered the
        // other team a choice between the flag and the play.
        if penalty.foul.isDeadBall {
            var after = declined
            // Who will have the ball, and is it them who did it?
            let offenderHasItNow = offendingTeamHadBall != declined.possessionChanged
            let yards = Int(penalty.foul.yards)
            if offenderHasItNow {
                after.ballOn = UInt8(max(1, min(99, Int(declined.ballOn) + yards)))
                after.distance = UInt8(
                    max(1, min(99, Int(declined.distance) + yards)))
            } else {
                after.ballOn = UInt8(max(1, min(99, Int(declined.ballOn) - yards)))
                let fresh = freshDowns(at: after.ballOn)
                after.down = fresh.down
                after.distance = fresh.distance
            }
            let record = PenaltyRecord(
                foul: penalty.foul, offender: penalty.offender,
                offendingTeam: penalty.offendingTeam, yards: penalty.foul.yards,
                wasAccepted: true, awardedFirstDown: !offenderHasItNow)
            return PenaltyDecision(penalty: record, accepted: true, advancement: after)
        }

        let takesIt = prefers(
            accepted.advancement, over: declined, forOffense: !offendingTeamHadBall)

        return PenaltyDecision(
            penalty: takesIt ? accepted.record : declining(penalty),
            accepted: takesIt,
            advancement: takesIt ? accepted.advancement : declined)
    }

    private func declining(_ penalty: PenaltyRecord) -> PenaltyRecord {
        PenaltyRecord(
            foul: penalty.foul, offender: penalty.offender, offendingTeam: penalty.offendingTeam,
            yards: penalty.yards, wasAccepted: false, awardedFirstDown: false)
    }

    /// The down as it would stand with the flag accepted.
    private func enforcedAdvancement(
        _ penalty: PenaltyRecord, on situation: Situation, offendingTeamHadBall: Bool
    ) -> (record: PenaltyRecord, advancement: Advancement) {
        let yards = Int(penalty.yards)
        // Against the offence the ball goes back; against the defence it comes forward.
        let signed = offendingTeamHadBall ? yards : -yards

        // Half the distance to the goal: a penalty can never place the ball in an end
        // zone, in either direction.
        let raw = Int(situation.ballOn) + signed
        let ballOn: UInt8
        if raw <= 0 {
            ballOn = UInt8(max(1, Int(situation.ballOn) - Int(situation.ballOn) / 2))
        } else if raw >= 100 {
            let toOwnGoal = 100 - Int(situation.ballOn)
            ballOn = UInt8(min(99, Int(situation.ballOn) + toOwnGoal / 2))
        } else {
            ballOn = UInt8(raw)
        }

        let awardsFirstDown = !offendingTeamHadBall && penalty.foul.carriesAutomaticFirstDown
        let record = PenaltyRecord(
            foul: penalty.foul, offender: penalty.offender, offendingTeam: penalty.offendingTeam,
            yards: penalty.yards, wasAccepted: true, awardedFirstDown: awardsFirstDown)

        if awardsFirstDown {
            let downs = freshDowns(at: ballOn)
            return (record, Advancement(ballOn: ballOn, down: downs.down, distance: downs.distance))
        }

        // Otherwise the down is replayed from the new spot, with the marker where it
        // was — moving back five yards makes it third and thirteen, not third and eight.
        let gained = Int(situation.ballOn) - Int(ballOn)
        let distance = Int(situation.distance) - gained
        if distance <= 0 {
            let downs = freshDowns(at: ballOn)
            return (record, Advancement(ballOn: ballOn, down: downs.down, distance: downs.distance))
        }
        return (
            record,
            Advancement(
                ballOn: ballOn, down: situation.down,
                distance: UInt8(max(1, min(Int(UInt8.max), distance))))
        )
    }

    /// Whether the non-offending team prefers the flag to the play.
    ///
    /// Two things here are certain and are handled first: nobody declines their own
    /// score to take yards, and nobody accepts a flag that leaves the other side's score
    /// standing. Those are not judgement calls.
    ///
    /// The rest is. Third-and-twenty-two against fourth-and-ten is a genuine
    /// expected-points question, and the honest answer is that this does not have an
    /// expected-points model yet: **win probability is the shared infrastructure that
    /// decides questions like this**, and it is M2's keystone
    /// ([ADR-0008](../../../../docs/adr/0008-win-probability-keystone.md)). Until it
    /// exists, `outlook` below is a deliberately crude proxy — yards of slack across the
    /// downs that remain, nudged by field position. It is provisional, it is documented
    /// as provisional, and it is not pinned by tests that would pretend otherwise.
    private func prefers(
        _ accepted: Advancement, over declined: Advancement, forOffense: Bool
    ) -> Bool {
        let acceptedScored = accepted.scoring != nil && accepted.points > 0
        let declinedScored = declined.scoring != nil && declined.points > 0

        if forOffense {
            if declinedScored { return false }
            if acceptedScored { return true }
        } else {
            if acceptedScored { return false }
            if declinedScored { return true }
        }

        // Losing the ball dominates everything short of a score.
        if accepted.possessionChanged != declined.possessionChanged {
            return forOffense ? declined.possessionChanged : accepted.possessionChanged
        }

        let acceptedOutlook = outlook(accepted)
        let declinedOutlook = outlook(declined)
        return forOffense
            ? acceptedOutlook > declinedOutlook : acceptedOutlook < declinedOutlook
    }

    /// How the offence's position looks, on an arbitrary scale where more is better.
    ///
    /// Provisional. See `prefers` — this is a placeholder for a win-probability read.
    private func outlook(_ advancement: Advancement) -> Double {
        let downsRemaining = Double(Int(downsToGain) - Int(advancement.down.rawValue) + 1)
        let slack = downsRemaining * 4.5 - Double(advancement.distance)
        let fieldPosition = Double(100 - Int(advancement.ballOn)) * 0.08
        return slack + fieldPosition
    }
}
