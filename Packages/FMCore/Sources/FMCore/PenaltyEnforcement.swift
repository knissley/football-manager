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
    ///   - penalty: the foul, with its spot measured by the resolver if it is a spot foul.
    ///   - situation: the down as it was before the snap.
    ///   - outcome: what the play produced, which is what declining leaves standing.
    ///   - offendingTeamHadBall: whether the offence committed it.
    /// - Returns: the choice made, the penalty record stamped with it, and the resulting
    ///   down.
    ///
    /// **One enforcement routine, and one frame rule** (2025 rulebook, Rule 14 and
    /// Rule 8 Section 6): the accepted branch is computed in the frame of the team that
    /// will snap next. A foul by the team that ended the play without the ball is walked
    /// off against it from the spot its family names — the previous spot, the spot of
    /// the foul, or the dead-ball spot with the gain counting — and the possessor keeps
    /// the ball. A foul by the team that took the ball away during the play gives it
    /// back (14-4-3-a, 8-6-1-d), and a personal foul by the team that lost it leaves
    /// the new possessor in possession, walked off from the dead-ball spot in its own
    /// frame (14-4-3-b). Half the distance is measured from whichever spot the foul is
    /// enforced from (14-2-1).
    public func enforce(
        _ penalty: PenaltyRecord,
        on situation: Situation,
        outcome: Outcome,
        offendingTeamHadBall: Bool
    ) -> PenaltyDecision {
        let declined = advance(from: situation, outcome: outcome)

        // A foul during a score by the team scored upon, or a personal foul by the
        // scorer, is enforced on the try or the kickoff (14-2-3), which the engine does
        // not model yet: the score stands and the flag is recorded declined until it
        // does.
        guard
            let accepted = enforcedAdvancement(
                penalty, on: situation, outcome: outcome, declined: declined,
                offendingTeamHadBall: offendingTeamHadBall)
        else {
            return PenaltyDecision(
                penalty: declining(penalty), accepted: false, advancement: declined)
        }

        // A pre-snap foul is a dead ball: there is no play to decline in favour of. A
        // foul after the whistle is walked off on top of the play that stands, and there
        // is nothing to decline either.
        if penalty.foul.isPreSnap || penalty.foul.isDeadBall {
            return PenaltyDecision(
                penalty: accepted.record, accepted: true, advancement: accepted.advancement)
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
            yards: penalty.yards, wasAccepted: false, awardedFirstDown: false,
            enforcementSpot: penalty.enforcementSpot)
    }

    /// The down as it would stand with the flag accepted, or `nil` when the foul is
    /// deferred to the try or the kickoff and the play stands as it was.
    private func enforcedAdvancement(
        _ penalty: PenaltyRecord, on situation: Situation, outcome: Outcome,
        declined: Advancement, offendingTeamHadBall: Bool
    ) -> (record: PenaltyRecord, advancement: Advancement)? {
        let foul = penalty.foul
        let yards = Int(foul.yards)

        // A score by the team the offender is not on stands (14-2-3), and so does the
        // scorer's own when the foul came after the ball was dead: a dead-ball foul is
        // enforced on the try or the kickoff that follows, which the record does not
        // carry yet (C9). A live-ball foul by the scorer wipes its score (4-8-2-b): a
        // contact foul during its own run is enforced by the three-and-one method from
        // the spot of the foul (14-3-6), which the record does not carry either, so the
        // previous spot stands in for it and the down is replayed there.
        var nullifiesTheScore = false
        if let scoring = declined.scoring, declined.points > 0 {
            let scorerHadBall: Bool
            switch scoring {
            case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: scorerHadBall = true
            case .defensiveTouchdown, .safety: scorerHadBall = false
            }
            let offenderScored = scorerHadBall == offendingTeamHadBall
            if !offenderScored || foul.isDeadBall { return nil }
            nullifiesTheScore = true
        }

        let changed = declined.possessionChanged
        // A change of possession on downs happens after the down ends; one during the
        // play is a takeaway or a kick. The rules treat them differently.
        let changedOnDowns =
            changed && outcome.kind.isScrimmagePlay
            && [PlayEnding.tackled, .outOfBounds, .fumbleRecovered, .incomplete].contains(
                outcome.endedIn)
        let lostDuringThePlay = changed && !changedOnDowns
        // The dead-ball spot in the frame of the team that snapped, whoever has it now.
        let deadBallSnapFrame = changed ? 100 - Int(declined.ballOn) : Int(declined.ballOn)
        let previous = Int(situation.ballOn)

        var ballOn: UInt8
        var moved: Int
        var advancement: Advancement
        var awardsFirstDown = false

        let basis: EnforcementSpot =
            nullifiesTheScore && foul.enforcement == .succeedingSpot
            ? .previousSpot : foul.enforcement
        switch basis {
        case .previousSpot:
            // In the frame of the team that snapped, which keeps the ball: accepting a
            // defensive foul on a takeaway gives the ball back (14-4-3-a, 8-6-1).
            (ballOn, moved) = walk(
                from: previous, yards: yards, towardOpponentGoal: !offendingTeamHadBall)
            awardsFirstDown = !offendingTeamHadBall && foul.carriesAutomaticFirstDown
            advancement = replayed(at: ballOn, from: situation, firstDown: awardsFirstDown)

        case .spotOfFoul:
            let spot = penalty.enforcementSpot.map(Int.init) ?? previous
            if offendingTeamHadBall {
                // The offence's block, behind the basic spot of its own run: from the
                // spot of the foul, or from the previous spot when the foul was behind
                // the line (14-3-6 and its first exception). The offence keeps the
                // ball; a defence that took it away declines instead (14-4-3-b).
                let basis = spot > previous ? previous : spot
                (ballOn, moved) = walk(from: basis, yards: yards, towardOpponentGoal: false)
                advancement = replayed(at: ballOn, from: situation, firstDown: false)
            } else if lostDuringThePlay && foul != .defensivePassInterference {
                // The returning team's block during its own return: it keeps the ball,
                // and the spot is flipped into its frame before the walk-off.
                (ballOn, moved) = walk(from: 100 - spot, yards: yards, towardOpponentGoal: false)
                let downs = freshDowns(at: ballOn)
                advancement = Advancement(
                    ballOn: ballOn, down: downs.down, distance: downs.distance,
                    possessionChanged: true)
            } else {
                // Interference, or a defensive block on a play the offence kept: the
                // offence's ball at the spot. In the end zone it is the 1, or half the
                // distance from the previous spot when that was inside the 2
                // (8-5-4, 8-6-1-b).
                if foul == .defensivePassInterference {
                    if spot <= 0 {
                        ballOn =
                            previous >= 2
                            ? 1
                            : walk(from: previous, yards: previous, towardOpponentGoal: true).ballOn
                    } else {
                        ballOn = UInt8(max(1, min(99, spot)))
                    }
                    moved = previous - Int(ballOn)
                } else {
                    (ballOn, moved) = walk(from: spot, yards: yards, towardOpponentGoal: true)
                }
                awardsFirstDown = foul.carriesAutomaticFirstDown
                advancement = replayed(at: ballOn, from: situation, firstDown: awardsFirstDown)
            }

        case .succeedingSpot:
            if offendingTeamHadBall {
                if !changed {
                    // Its own foul on its own play: from the dead-ball spot, and the
                    // down stands (12-3-1).
                    (ballOn, moved) = walk(
                        from: deadBallSnapFrame, yards: yards, towardOpponentGoal: false)
                    advancement = Advancement(
                        ballOn: ballOn, down: declined.down,
                        distance: UInt8(max(1, min(99, Int(declined.distance) + moved))))
                } else {
                    // The defence has the ball, and keeps it: from the dead-ball spot in
                    // its own frame (14-4-3-b).
                    (ballOn, moved) = walk(
                        from: Int(declined.ballOn), yards: yards, towardOpponentGoal: true)
                    let downs = freshDowns(at: ballOn)
                    advancement = Advancement(
                        ballOn: ballOn, down: downs.down, distance: downs.distance,
                        possessionChanged: true)
                }
            } else {
                // The defence's personal or conduct foul carries a first down
                // (12-2-8, 12-2-10, 12-2-11, 12-2-15, 12-2-16, 12-3-1).
                awardsFirstDown = true
                if lostDuringThePlay {
                    // The ball reverts to the offence (14-4-3-a, 8-6-1-d). The spot
                    // where possession was lost is not in the record, so the previous
                    // spot stands in for it.
                    (ballOn, moved) = walk(from: previous, yards: yards, towardOpponentGoal: true)
                } else {
                    // The offence's play stands: from the dead-ball spot or the previous
                    // spot, whichever is better for the offence (8-6-1-d) — which is
                    // also the three-and-one method's answer when the basic spot is
                    // behind the line (14-3-6).
                    (ballOn, moved) = walk(
                        from: min(deadBallSnapFrame, previous), yards: yards,
                        towardOpponentGoal: true)
                }
                let downs = freshDowns(at: ballOn)
                advancement = Advancement(
                    ballOn: ballOn, down: downs.down, distance: downs.distance)
            }
        }

        let record = PenaltyRecord(
            foul: foul, offender: penalty.offender, offendingTeam: penalty.offendingTeam,
            yards: UInt8(max(0, min(99, moved))), wasAccepted: true,
            awardedFirstDown: awardsFirstDown, enforcementSpot: penalty.enforcementSpot)
        return (record, advancement)
    }

    /// Walk a penalty off from a spot, in the frame of whoever has the ball, and never
    /// into an end zone: more than half the distance to the goal line is half the
    /// distance, measured from the spot of enforcement (14-2-1).
    private func walk(
        from spot: Int, yards: Int, towardOpponentGoal: Bool
    ) -> (ballOn: UInt8, moved: Int) {
        if towardOpponentGoal {
            let raw = spot - yards
            if raw <= 0 {
                let moved = spot / 2
                return (UInt8(max(1, spot - moved)), moved)
            }
            return (UInt8(raw), yards)
        }
        let raw = spot + yards
        if raw >= 100 {
            let moved = (100 - spot) / 2
            return (UInt8(min(99, spot + moved)), moved)
        }
        return (UInt8(raw), yards)
    }

    /// The down replayed from a new spot with the marker where it was — moving back
    /// five yards makes it third and thirteen, not third and eight — or a fresh set
    /// when the foul carries a first down or the walk-off reached the marker.
    private func replayed(
        at ballOn: UInt8, from situation: Situation, firstDown: Bool
    ) -> Advancement {
        if firstDown {
            let downs = freshDowns(at: ballOn)
            return Advancement(ballOn: ballOn, down: downs.down, distance: downs.distance)
        }
        let gained = Int(situation.ballOn) - Int(ballOn)
        let distance = Int(situation.distance) - gained
        if distance <= 0 {
            let downs = freshDowns(at: ballOn)
            return Advancement(ballOn: ballOn, down: downs.down, distance: downs.distance)
        }
        return Advancement(
            ballOn: ballOn, down: situation.down,
            distance: UInt8(max(1, min(Int(UInt8.max), distance))))
    }

    /// Whether the non-offending team prefers the flag to the play.
    ///
    /// Two things here are certain and are handled first: nobody declines their own
    /// score to take yards, and nobody declines a flag that wipes out the other side's.
    /// Then possession: a team takes the branch in which it has the ball. Those are not
    /// judgement calls.
    ///
    /// The rest is. Third-and-twenty-two against fourth-and-ten is a genuine
    /// expected-points question, and the honest answer is that this does not have an
    /// expected-points model yet: **win probability is the shared infrastructure that
    /// decides questions like this**, and it is M2's keystone
    /// ([ADR-0008](../../../../docs/adr/0008-win-probability-keystone.md)). Until it
    /// exists, `outlook` below is a deliberately crude proxy — yards of slack across the
    /// downs that remain, nudged by field position. It is provisional, it is documented
    /// as provisional, and it is not pinned by tests that would pretend otherwise.
    ///
    /// The outlook is read in the frame of whoever has the ball in the advancement,
    /// which after a change of possession is not the team that snapped: the chooser
    /// wants the higher outlook when it is the possessor and the lower when it is not.
    private func prefers(
        _ accepted: Advancement, over declined: Advancement, forOffense: Bool
    ) -> Bool {
        // A score, and whether the chooser is the side that made it.
        func scoredByChooser(_ advancement: Advancement) -> Bool? {
            guard let scoring = advancement.scoring, advancement.points > 0 else { return nil }
            let byOffense: Bool
            switch scoring {
            case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: byOffense = true
            case .defensiveTouchdown, .safety: byOffense = false
            }
            return byOffense == forOffense
        }
        if let mine = scoredByChooser(declined) { return !mine }
        if let mine = scoredByChooser(accepted) { return mine }

        // Having the ball dominates everything short of a score.
        if accepted.possessionChanged != declined.possessionChanged {
            return forOffense != accepted.possessionChanged
        }

        let chooserHasBall = forOffense != declined.possessionChanged
        let acceptedOutlook = outlook(accepted)
        let declinedOutlook = outlook(declined)
        return chooserHasBall
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
