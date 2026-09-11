/// Where an accepted penalty is walked off, when it is not walked off on the down it was
/// committed on (2025 rulebook, 14-2-3, 11-3-3).
///
/// A score is not given back for a foul during it, and the yardage is not thrown away
/// either: it is carried to whatever the rules put in play next. Which of the two that is
/// depends on the score, not on the foul.
public enum DeferredEnforcement: UInt8, CaseIterable, Sendable, Hashable, Codable {
    /// The try that follows a touchdown (14-2-3).
    case theTry = 0
    /// The free kick that follows a field goal, a safety, or a try (14-2-3, 11-3-3
    /// Item 4-a, 11-3-3 Item 7).
    case theFreeKick = 1
}

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
    /// Where the accepted yardage is walked off, when it is not walked off here: the
    /// score in `advancement` stands and the spot the rules put in play next is moved
    /// instead. `nil` for every ordinary enforcement.
    ///
    /// The rules layer cannot apply it, because the spot it moves does not exist yet —
    /// the try has not been spotted and the free kick has not been set up. So this is the
    /// rules layer *telling* the game state what is owed, and `GameState` walks it off
    /// when it builds that spot.
    public let deferredTo: DeferredEnforcement?

    public init(
        penalty: PenaltyRecord, accepted: Bool, advancement: Advancement,
        deferredTo: DeferredEnforcement? = nil
    ) {
        self.penalty = penalty
        self.accepted = accepted
        self.advancement = advancement
        self.deferredTo = deferredTo
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
    /// back (14-4-3-a, 8-6-1-d), from the basic spot on a run and from the better of the
    /// previous and dead-ball spots on a pass, and a personal foul by the team that lost
    /// it leaves the new possessor in possession, walked off from the dead-ball spot in
    /// its own frame (14-4-3-b). Half the distance is measured from whichever spot the
    /// foul is enforced from (14-2-1).
    public func enforce(
        _ penalty: PenaltyRecord,
        on situation: Situation,
        outcome: Outcome,
        offendingTeamHadBall: Bool
    ) -> PenaltyDecision {
        let declined = advance(from: situation, outcome: outcome)

        // A foul on a play that scored is not enforced on that play. The score stands and
        // the yardage is carried to whatever the rules put in play next — the try after a
        // touchdown, the free kick after a field goal, a safety or a try (14-2-3, 11-3-3
        // Item 4-a). There is nothing to decline: the offended team is not being asked
        // whether to give the points back.
        if let deferred = deferredEnforcement(
            penalty, declined: declined, outcome: outcome,
            offendingTeamHadBall: offendingTeamHadBall)
        {
            let record = PenaltyRecord(
                foul: penalty.foul, offender: penalty.offender,
                offendingTeam: penalty.offendingTeam, yards: penalty.foul.yards,
                wasAccepted: true, awardedFirstDown: false,
                enforcementSpot: penalty.enforcementSpot)
            return PenaltyDecision(
                penalty: record, accepted: true, advancement: declined, deferredTo: deferred)
        }

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

    /// Where a foul on a play that scored is carried to, or `nil` when it is enforced on
    /// the down like any other foul (2025 rulebook, 14-2-3, 11-3-3).
    ///
    /// Three answers, and which one it is depends on the score rather than on the foul:
    ///
    /// - **A touchdown**: the try, whatever kind of foul it was and whichever side
    ///   committed it. The article says so in as many words.
    /// - **A field goal or a safety by the opponent**: the succeeding free kick, and only
    ///   for a personal or unsportsmanlike foul. Every other foul there leaves the
    ///   offended team a choice between the points and a replayed down, and no team gives
    ///   up points for five yards, so it is declined in the ordinary way below.
    /// - **A successful try**: the succeeding free kick for a foul by the defending team
    ///   (11-3-3 Item 4-a). A foul by the *scoring* team repeats the try instead
    ///   (Item 3-a), which is a live-ball enforcement and not a deferral, so it is `nil`
    ///   here and handled where the score is nullified.
    ///
    /// A foul by the scoring team on any other score wipes it: the down is replayed, and
    /// there is nothing to carry.
    private func deferredEnforcement(
        _ penalty: PenaltyRecord, declined: Advancement, outcome: Outcome,
        offendingTeamHadBall: Bool
    ) -> DeferredEnforcement? {
        guard let scoring = declined.scoring, declined.points > 0 else { return nil }
        let scorerHadBall: Bool
        switch scoring {
        case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: scorerHadBall = true
        case .defensiveTouchdown, .safety: scorerHadBall = false
        }
        let offenderScored = scorerHadBall == offendingTeamHadBall

        // A dead-ball foul by either side after a score goes on whatever follows,
        // whatever the foul was: 11-3-3 Item 1 for a touchdown, Item 7 after a try, and
        // for the rest 14-2-3, which reaches a foul whether the ball was live or dead
        // when it was committed.
        let afterTheWhistle = penalty.foul.isDeadBall

        switch scoring {
        case .touchdown, .defensiveTouchdown:
            if afterTheWhistle { return .theTry }
            // During the down, 14-2-3's subject is a personal or unsportsmanlike foul by
            // the side that did *not* score. The scorer's own live-ball foul is enforced
            // and the down replayed, which wipes the touchdown (14-3-6), and any other
            // foul by the defence is simply declined.
            guard !offenderScored else { return nil }
            return penalty.foul.isPersonalOrUnsportsmanlike ? .theTry : nil
        case .extraPoint, .twoPointConversion:
            // A foul by the defending team on a try has its distance penalty assessed on
            // the ensuing kickoff — every foul, not only the personal ones (11-3-3
            // Item 4-a). **Except defensive pass interference**, which the article's own
            // exception makes a spot foul instead and sends the reader to Rule 8 Section
            // 5 for. The scoring team's live-ball foul brings the try back (Item 3-a),
            // which is not a deferral.
            //
            // **The exception has no branch here, because the engine cannot draw that
            // foul on a try and an unreachable branch is untested code.** Two numbers put
            // it out of reach, and they live in two other files: a try's route is fixed
            // at 1 yard deep in the crude resolver's pass path — the mutation that would
            // deepen it is guarded on the play not being a try — and interference is only
            // called from a route depth of 10 or more. Raise the first or lower the
            // second and this line starts sending a spot foul to the free kick, which is
            // not what the article says; the coverage model is where that would happen.
            if offenderScored && !afterTheWhistle { return nil }
            return .theFreeKick
        case .fieldGoal, .safety:
            if afterTheWhistle { return .theFreeKick }
            guard !offenderScored else { return nil }
            return penalty.foul.isPersonalOrUnsportsmanlike ? .theFreeKick : nil
        }
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
        // carry yet (C9). A live-ball foul by the scorer wipes its score, because the
        // play it came on is enforced and replayed: a contact foul during its own run
        // is enforced by the three-and-one method from the spot of the foul (14-3-6),
        // which the record does not carry either, so the previous spot stands in for
        // it and the down is replayed there.
        var nullifiesTheScore = false
        // A try the scoring team fouled during is played *again* (11-3-3 Item 3-a): the
        // point comes off and the attempt comes back, from wherever the enforcement puts
        // the ball. Every other nullified score is a down replayed, which owes nothing.
        var repeatsTheTry = false
        if let scoring = declined.scoring, declined.points > 0 {
            let scorerHadBall: Bool
            switch scoring {
            case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: scorerHadBall = true
            case .defensiveTouchdown, .safety: scorerHadBall = false
            }
            let offenderScored = scorerHadBall == offendingTeamHadBall
            if !offenderScored || foul.isDeadBall { return nil }
            nullifiesTheScore = true
            repeatsTheTry = outcome.kind == .extraPoint || outcome.kind == .twoPointConversion
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
                // (8-5-Penalty, 8-6-1-b).
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
                    // The ball reverts to the offence (14-4-3-a, 8-6-1-d). Where it is
                    // walked off from depends on what kind of play the foul was during.
                    //
                    // A *run* is measured from the takeaway: a run followed by a change of
                    // possession has the spot where possession was lost as its basic spot
                    // (14-3-5-b). But only when that spot is in advance of the line — a
                    // basic spot behind the line of scrimmage puts a defensive foul back
                    // on the previous spot wherever the foul itself was (14-3-6, the
                    // exception for fouls by the defence; 14-4-6-b says the same of every
                    // foul during a fumble that came loose behind the line). The strip
                    // sack is the case that makes the difference, and it is the common
                    // one: measuring from where the ball came loose charges the offence
                    // for the sack twice, once in the yards and again in the walk-off.
                    //
                    // A forward pass is a different rule. Until a pass thrown from behind
                    // the line is over, a flag on either side comes off the previous spot,
                    // and the down turns into a running play only once somebody catches
                    // the ball (14-4-5) — so the catch is never the basic spot for a foul
                    // that came before it. The personal foul has its own answer inside
                    // that article: before such a pass is *completed*, the offence gets
                    // the better of two spots — where it snapped, or where the ball was
                    // dead (14-4-5-d, 8-6-1-d). An interception is a catch and is not a
                    // completion (8-1-3), which puts a foul that preceded it inside that
                    // exception rather than outside it, so the offence takes the better of
                    // the two spots — the dead-ball spot when the interceptor was dropped
                    // downfield of the snap, the previous spot when he was dropped behind
                    // it.
                    //
                    // A kick carries no takeaway spot, and neither does a fumble written
                    // by a resolver that recorded none; the previous spot stands in.
                    let spot: Int
                    switch outcome.endedIn {
                    case .fumbleLost:
                        let lost = outcome.possessionLostAt.map(Int.init) ?? previous
                        spot = min(lost, previous)
                    case .intercepted:
                        spot = min(deadBallSnapFrame, previous)
                    default:
                        spot = previous
                    }
                    (ballOn, moved) = walk(from: spot, yards: yards, towardOpponentGoal: true)
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

        if repeatsTheTry {
            // The try is owed again rather than a down being played from here, so the
            // spot the walk-off produced is where it will be snapped from and the down is
            // the try's own.
            advancement = Advancement(
                ballOn: advancement.ballOn, down: .first, distance: max(1, advancement.ballOn),
                requiresTry: true)
        }

        let record = PenaltyRecord(
            foul: foul, offender: penalty.offender, offendingTeam: penalty.offendingTeam,
            yards: UInt8(max(0, min(99, moved))), wasAccepted: true,
            awardedFirstDown: awardsFirstDown, enforcementSpot: penalty.enforcementSpot)
        return (record, advancement)
    }

    /// Walk a penalty off from a spot, in the frame of whoever has the ball.
    ///
    /// Half the distance is a ceiling on every distance penalty and not a guard on the
    /// end zone: when the walk-off would carry the ball past the midpoint between the
    /// spot of enforcement and the goal line the offending team defends, the ball goes
    /// to that midpoint instead, and 14-2-1 states itself as overriding every other
    /// enforcement of a distance penalty. **The gotcha is that it bites well short of a
    /// goal line** — five yards from the 7 is more than half of seven — so a walk-off
    /// that would have stopped inside the field is no evidence the ceiling is idle. The
    /// band it governs and the goal line meet only when the penalty is as long as the
    /// distance.
    ///
    /// Modelling: the field is whole yards here and the midpoint frequently is not, so
    /// the walk-off is rounded down and the ball is left on the nearer whole yard the
    /// ceiling still allows — the 4 from the 7, where the article's own midpoint is the
    /// three and a half. The article says nothing about rounding; we spot on whole
    /// yards and this is the side of the midpoint that never overshoots it.
    private func walk(
        from spot: Int, yards: Int, towardOpponentGoal: Bool
    ) -> (ballOn: UInt8, moved: Int) {
        let toGoal = towardOpponentGoal ? spot : 100 - spot
        let moved = yards * 2 > toGoal ? toGoal / 2 : yards
        let ballOn = towardOpponentGoal ? max(1, spot - moved) : min(99, spot + moved)
        return (UInt8(ballOn), moved)
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
