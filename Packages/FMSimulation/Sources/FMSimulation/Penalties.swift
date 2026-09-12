import FMCore
import FMRandom

/// Where flags come from.
///
/// The obvious implementation — roll a die each play — produces penalties that are
/// frequent, meaningless and inexplicable. So there are two classes here and **only one
/// of them is a roll** ([penalties.md](../../../../docs/penalties.md)).
///
/// **Discipline penalties** are procedural. Nobody was beaten; somebody broke a rule.
/// They come from a player's `discipline`, the noise he is working in, and the tempo he
/// is being asked to play at.
///
/// **Desperation penalties** are what a player does when he is *losing*. A hold is what
/// happens when a tackle is about to give up a sack; interference is what happens when a
/// corner is beaten. Those are drawn **at the moment the matchup resolves against him**,
/// which is what makes a flag explicable: *he held because he was beaten in 1.9 seconds*,
/// with the pressure decision sitting right there in the same play record. It also means
/// a bad offensive line commits more holds without anybody tuning a holding rate.
///
/// One thing this deliberately never reads is leverage. A flag is not likelier because it
/// is January — that would be authoring drama. It is exactly as likely as it always was
/// and simply matters more, and the analysis layer surfaces it because the swing in win
/// probability is enormous.
enum Penalties {

    /// The chance an offence that has already overrun its intended snap is still not
    /// snapped a second later. To the eighth power it is a half, so nine seconds of
    /// slack carry half the exposure of one: a team bleeding the clock takes twice the
    /// delays of one snapping at normal tempo, which is what the flat bonus used to say.
    static let playClockOverrunSurvival = 0.917

    /// The share of a beaten-in-coverage draw that stays a contact foul now that
    /// interference is drawn at the throw instead (`onTheThrow`).
    static let contactShareOfCoverage = 0.68

    /// What one draw on the target's matchup has to carry to replace a draw on each of
    /// the four reads the coverage loop used to make.
    static let throwsPerCoverageRead = 4.0

    /// How much of that draw is the receiver's foul rather than the defender's.
    ///
    /// Lower than the share the single coverage-loop draw carried, and for a reason the
    /// move itself creates: the man this is drawn on is the *most open* receiver on the
    /// play, because he is the one the quarterback threw to. Interference by a defender
    /// scales with how badly he is beaten; a push-off is what a receiver does when he is
    /// not winning, so drawing it against the winner at the old share tripled it.
    static let offensiveShareOfInterference = 0.075

    // MARK: - The play clock

    /// Whether the offence fails to get this snap away inside the play clock in force
    /// (2025 rulebook, 4-6-1, 4-6-2).
    ///
    /// Not a foul yet, and that is the point. An offence beaten by the clock has two
    /// ends available to it — five yards for the delay of game (4-6-4), or a charged
    /// timeout that stops the clock and costs it one of three (4-3-2, 4-5-1 Item 1) —
    /// and which of them the down comes to is a decision somebody makes afterwards. So
    /// this reports the interval and nothing about the consequence.
    ///
    /// The offence means to snap with some slack left — a second bleeding the clock,
    /// nine at normal tempo on the forty, six on the twenty-five that follows a change
    /// of possession — and the chance it overruns that slack halves with every eight
    /// seconds of it. The base is the crowd's, and noise moves this far less than it
    /// moves a false start: the play clock is the coach's problem, not the crowd's. At a
    /// tenth of a point per unit of noise it was doubling the road team's delay-of-game
    /// rate and quietly supplying most of the road/home penalty gap.
    ///
    /// The base is set so that a normal-tempo snap on the forty at a quiet ground
    /// overruns exactly as often as the flat rate it replaced fired (0.35%); everything
    /// else — the shorter clock, the tempo, the crowd, the huddle a timeout bought — is
    /// the derivation.
    static func overrunsThePlayClock(
        calls: Calls, context: PlayContext, random: inout SplittableRandom
    ) -> Bool {
        let noise = context.offenseIsHome ? 0.0 : Double(context.crowdNoise)
        let slack = Int(context.remainingAtIntendedSnap(at: calls.offense.tempo))
        var overrun = 0.007 + noise * 0.00006
        for _ in 1..<max(1, slack) { overrun *= playClockOverrunSurvival }
        return random.nextBool(probability: overrun)
    }

    // MARK: - Discipline

    /// A foul before the snap, which kills the play.
    ///
    /// Noise is the mechanism behind home field advantage: a visiting offence in a loud
    /// stadium false-starts more, drives stall, and the advantage emerges rather than
    /// being applied.
    static func preSnap(
        situation: Situation,
        calls: Calls,
        context: PlayContext,
        personnel: Lineup,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let noise = context.offenseIsHome ? 0.0 : Double(context.crowdNoise)

        // The play clock has already run out, so the ball never came into play and
        // nothing else about this down can have happened (2025 rulebook, 4-6-4). It is
        // not drawn here: whether the offence was beaten by the interval is
        // `overrunsThePlayClock`, asked before the benches were given their chance to
        // stop the clock, and what is left here is to report it. The quarterback is the
        // offender by convention — the ball is his to put in play.
        if context.playClockExpired {
            return record(
                .delayOfGame, by: [SlotLayout.quarterback], personnel, context, &random,
                offense: true)
        }

        // The offence's procedural fouls. A loud road stadium is worth roughly a extra
        // false start a game, which is what the advantage is made of.
        let lineSlots = personnel.blockers(includingEligibles: false)
        let offenseDiscipline = averageDiscipline(lineSlots, personnel, context, onOffense: true)
        var falseStart = 0.027 + (62 - offenseDiscipline) * 0.0011
        // Softer than it was. A road team commits measurably more of these, but the real
        // gap is about a fifth more, not double — which is what a coefficient tuned
        // against a neutral field with nobody in it had produced.
        falseStart += noise * 0.000036
        if calls.offense.tempo == .hurryUp { falseStart += 0.004 }

        if random.nextBool(probability: max(0.002, falseStart)) {
            return record(.falseStart, by: lineSlots, personnel, context, &random, offense: true)
        }

        // The rest of the procedural offensive fouls: lining up wrong, moving early, a
        // man still drifting at the snap, a substitution that did not beat the whistle.
        // All four exist in `Foul` with their yardage and their side already settled;
        // nothing had ever produced one.
        //
        // Motion is the reason `OffensiveCall.usedMotion` exists, and until now it was a
        // field the resolver never read: shifting people around before the snap is how
        // you find out what the defence is in, and it is also how you get flagged.
        var procedural = 0.006 + (62 - offenseDiscipline) * 0.0004
        if calls.offense.usedMotion { procedural += 0.004 }
        if calls.offense.tempo == .hurryUp { procedural += 0.003 }
        if random.nextBool(probability: max(0.001, procedural)) {
            let foul: Foul
            switch random.next(upperBound: 100) {
            case ..<46: foul = .illegalFormation
            case ..<72: foul = .illegalMotion
            case ..<91: foul = .illegalShift
            default: foul = .illegalSubstitution
            }
            return record(
                foul, by: personnel.routeRunners() + lineSlots, personnel, context, &random,
                offense: true)
        }

        // The defence jumping. A blitz asks defenders to time the snap, which is exactly
        // when they get it wrong.
        let rushSlots = personnel.front
        let defenseDiscipline = averageDiscipline(rushSlots, personnel, context, onOffense: false)
        var offside = 0.019 + (62 - defenseDiscipline) * 0.0009
        if calls.defense.rush.isBlitz { offside += 0.004 }
        if random.nextBool(probability: max(0.002, offside)) {
            // Three ways to be early, and they are enforced alike: over the ball,
            // into the neutral zone, or into somebody.
            let foul: Foul
            switch random.next(upperBound: 100) {
            case ..<52: foul = .offside
            case ..<86: foul = .neutralZoneInfraction
            default: foul = .encroachment
            }
            return record(foul, by: rushSlots, personnel, context, &random, offense: false)
        }

        // Twelve men is a *substitution* failure, not a player failure — defensive
        // personnel churn against offensive tempo. Which is what makes hurry-up a weapon
        // rather than a clock tactic: it does not only save time, it catches defences
        // with twelve on the grass.
        let churn: Double
        switch calls.offense.tempo {
        case .hurryUp: churn = 0.007
        case .fast: churn = 0.003
        default: churn = 0.0008
        }
        if random.nextBool(probability: churn) {
            return record(
                .tooManyMenOnField, by: personnel.coverageDefenders, personnel, context, &random,
                offense: false)
        }

        return nil
    }

    // MARK: - Desperation

    /// A blocker who has lost his rep and grabs.
    ///
    /// Conditional on losing, so it is never drawn for a lineman who won. A bad line
    /// holds more without anybody tuning a holding rate.
    static func whenBeatenBlocking(
        blocker: PlayerSlot, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let discipline = context.effective(.discipline, for: personnel[blocker], onOffense: true)
        let technique = context.effective(.handTechnique, for: personnel[blocker], onOffense: true)
        // Good hands keep a beaten blocker legal; poor ones do not.
        //
        // The base is small because *losing a rep is common*: five blockers, most of whom
        // lose to somebody on a given play. A first pass used a rate that read plausibly
        // per blocker and produced holding on a quarter of all snaps — five and a half
        // calls a game against a real one and a half, and because it is drawn first it
        // crowded every other flag out of the game entirely.
        let chance = 0.025 + (62 - discipline) * 0.0007 + (62 - technique) * 0.0006
        guard random.nextBool(probability: max(0.002, min(0.08, chance))) else { return nil }

        // A beaten blocker holds, or gets his hands outside, or gets his feet wrong. They
        // are the same moment with different flags on it, and only the first of them had
        // ever been thrown.
        let foul: Foul
        switch random.next(upperBound: 100) {
        case ..<72: foul = .offensiveHolding
        case ..<92: foul = .illegalUseOfHands
        case ..<96: foul = .tripping
        default: foul = .chopBlock
        }
        return record(foul, by: [blocker], personnel, context, &random, offense: true)
    }

    /// A defender who has been beaten in coverage, before anybody has thrown anything.
    ///
    /// Separation is the input, so the flag is drawn against exactly the defenders who
    /// lost. What it *can* be is limited by when it happens: these are the fouls whose
    /// restrictions begin at the snap and do not need a pass in the air — grabbing a
    /// receiver, or getting hands on him past the legal window. Interference is not one
    /// of them and is drawn at the throw instead (`onTheThrow`), because 8-5-1 makes a
    /// forward pass thrown from behind the line the thing interference needs to exist.
    static func whenBeatenInCoverage(
        defender: PlayerSlot, receiver: PlayerSlot, separationCentimetres: Int,
        personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        guard separationCentimetres > 120 else { return nil }
        let discipline = context.effective(.discipline, for: personnel[defender], onOffense: false)
        let beatenBy = Double(separationCentimetres - 120) * 0.0006
        // The same curve this draw always had, scaled by the share of it that stays here.
        // Roughly half of what it used to produce left as interference, which now has its
        // own draw at the throw; without the share, moving interference out doubles the
        // defensive-holding rate as a side effect of a change that is not about holding.
        // Measured over 400 games at seeds 7 and 11: 1.55 and 1.32 calls a game before
        // interference moved, 3.32 and 3.04 with it moved and this share not applied.
        // Where the rate *should* be is the retune's question, not this draw's.
        let chance = (0.014 + beatenBy + (62 - discipline) * 0.0009) * contactShareOfCoverage
        guard random.nextBool(probability: max(0.002, min(0.07, chance))) else { return nil }

        // Illegal contact is a rare call in the modern game; grabbing is the usual one.
        let foul: Foul = random.nextBool(probability: 0.86) ? .defensiveHolding : .illegalContact
        return record(foul, by: [defender], personnel, context, &random, offense: false)
    }

    /// What a flag drawn in coverage is still worth once the quarterback has taken the
    /// ball out of the pocket.
    ///
    /// 8-4-7 draws a line through the coverage-contact family at that moment, and it does
    /// not draw the same line through both fouls: illegal contact stops being available to
    /// the officials, and the cut block with it, while defensive holding goes on being
    /// available exactly as it was. 8-4-2 and 8-4-3 are why the line is there at all —
    /// both are written for a down the passer is still standing back there on, which is
    /// the condition 8-4-7 removes. The engine has no cut block, so illegal contact is the
    /// whole of what this takes away today.
    ///
    /// **Asked here rather than at the draw, because at the draw it is unanswerable.**
    /// The contact is settled at the coverage rep, which the resolver works out before the
    /// quarterback has decided anything at all; what the flag is worth turns on something
    /// that had not happened yet. Nothing is reclassified on the way through — a hold
    /// stays a hold, and illegal contact is simply gone — because turning one act into the
    /// other to keep a count up would be inventing a foul.
    ///
    /// **It takes away contact that came before he left, too, and cannot help it.** A
    /// `PenaltyRecord` carries no tick, so a flag from the coverage loop cannot be put
    /// either side of the moment the pocket was given up, and there is no second moment
    /// recorded to compare it against. Dropping it is the side of that the rules can live
    /// with: a foul nobody was charged with, rather than a first down nobody earned.
    /// [invariants.md](../../../../docs/invariants.md) carries the case.
    static func afterLeavingThePocket(_ penalty: PenaltyRecord?) -> PenaltyRecord? {
        penalty?.foul == .illegalContact ? nil : penalty
    }

    /// Interference, on the matchup the ball was thrown into.
    ///
    /// 8-5-1: interference needs a forward pass thrown from behind the line to exist, the
    /// defence's restrictions run from the throw until the ball is touched, and the foul
    /// itself is hindering an eligible receiver's chance at the ball. So a down with no
    /// throw in it has no interference at all. It used to be drawn per read in the
    /// coverage loop, before the quarterback had decided anything, which put it on sacks
    /// and on receivers nobody looked at.
    ///
    /// **Drawing it on the target's matchup and on no other is this engine's
    /// simplification, not 8-5-1's.** The article protects *any* eligible receiver and
    /// gives both sides the same right to the ball, so a real foul is available on a
    /// receiver the throw was never going to — a defender hooking the man on the far
    /// side, or an offensive pick well away from the catch. The engine picks one target
    /// and keeps no separation for anybody else after the throw, so the target's is the
    /// only matchup it has to draw on. What that loses is interference away from the
    /// ball, which a resolver that carried every matchup through the throw would have.
    ///
    /// `catchPoint` is where the ball is going, in the offence's frame with zero meaning
    /// the end zone: the defence's is a spot foul (8-6-1-b) and this is the spot.
    static func onTheThrow(
        defender: PlayerSlot, receiver: PlayerSlot, separationCentimetres: Int, routeDepth: Int,
        catchPoint: Int, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        guard separationCentimetres > 120 else { return nil }
        let discipline = context.effective(.discipline, for: personnel[defender], onOffense: false)
        let beatenBy = Double(separationCentimetres - 120) * 0.0006
        // One matchup a play rather than one per read, so the per-matchup rate has to
        // carry what four reads used to. The coverage loop read four route runners and
        // drew on each of them; this draws once. Four is the whole of the multiplier and
        // nothing in it is fitted to a band.
        //
        // It does not put the interference rate back where it was, and it is not meant
        // to: the old draw fired on every dropback including the ones nobody threw, and
        // the first flag in the loop stopped the three reads behind it, so one draw at
        // four times the rate is not four draws. Measured over 400 games at seeds 7 and
        // 11: 0.84 and 0.82 defensive interference calls a game, against 0.71 and 0.67
        // before the foul moved here. Both sit under the sourced band, and where the rate
        // belongs is the retune's question rather than this draw's.
        let chance = (0.014 + beatenBy + (62 - discipline) * 0.0009) * throwsPerCoverageRead
        guard random.nextBool(probability: max(0.004, min(0.45, chance))) else { return nil }

        // Sometimes the separation was made with a hand in the chest and the flag goes
        // the other way. 8-5-2 lists a shove or a push-off that buys a receiver room
        // among the acts either side can be flagged for while the ball is in the air.
        // Charging it to the target rather than to whichever receiver did it is the
        // simplification described above, not something the article says.
        if random.nextBool(probability: offensiveShareOfInterference) {
            return record(
                .offensivePassInterference, by: [receiver], personnel, context, &random,
                offense: true)
        }

        // Underneath, contact past the first yard downfield is still interference, but a
        // crude engine cannot tell a hook at eight yards from a hand-fight at one,
        // so a route short of the line to gain draws nothing here: contact on it is the
        // coverage loop's holding or illegal contact, which is what 8-5-1 says the acts
        // that are not interference could be. Calling it here as well counted the same
        // contact twice and put defensive holding at 2.64 a game against 1.55 before.
        guard routeDepth >= 10 else { return nil }
        return PenaltyRecord(
            foul: .defensivePassInterference, offender: defender,
            offendingTeam: context.defense, yards: Foul.defensivePassInterference.yards,
            wasAccepted: false, enforcementSpot: UInt8(max(0, min(99, catchPoint))))
    }

    /// A pass thrown away under pressure, and whether it was thrown away legally.
    ///
    /// The book's exception is a place (2025 rulebook, 8-2-1 Item 1): no grounding when
    /// the passer is, or has been, outside the pocket area and the ball comes down at or
    /// past the line of scrimmage extended. The crude resolver places nobody, so it can
    /// know neither where the passer was nor where the ball came down; what it draws is
    /// whether he got himself out of the pocket or the ball past the line, against his
    /// `awareness` and his `underPressure`, and the flag is the share that did neither.
    /// The spatial engine measures the same question (M5).
    ///
    /// Only asked of a throwaway made under pressure. A ball thrown away from a clean
    /// pocket with nothing open is an incomplete pass and not this foul, whose definition
    /// starts with the rush (8-2-1). The base is a modelling convention: nothing in
    /// `docs/reference/calibration-sources.md` bands grounding, so the harness prints the
    /// rate with no target beside it.
    static func whenThrowingItAway(
        passer: PlayerSlot, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let awareness = context.effective(.awareness, for: personnel[passer], onOffense: true)
        let composure = context.effective(.underPressure, for: personnel[passer], onOffense: true)
        let grounded = 0.10 - (awareness - 60) * 0.001 - (composure - 60) * 0.001
        guard random.nextBool(probability: max(0.01, min(0.4, grounded))) else { return nil }
        return record(
            .intentionalGrounding, by: [passer], personnel, context, &random, offense: true)
    }

    /// Contact fouls, drawn where the contact actually happened.
    static func onContact(
        tackler: PlayerSlot, isQuarterback: Bool, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let discipline = context.effective(.discipline, for: personnel[tackler], onOffense: false)
        let base = isQuarterback ? 0.05 : 0.024
        let chance = base + (62 - discipline) * 0.0006
        guard random.nextBool(probability: max(0.002, chance)) else { return nil }

        if isQuarterback {
            return record(
                .roughingThePasser, by: [tackler], personnel, context, &random, offense: false)
        }
        let foul: Foul
        switch random.next(upperBound: 100) {
        case ..<38: foul = .unnecessaryRoughness
        case ..<70: foul = .facemask
        case ..<88: foul = .illegalUseOfHelmet
        default: foul = .horseCollarTackle
        }
        return record(foul, by: [tackler], personnel, context, &random, offense: false)
    }

    /// Blocking in space, on a run that got past the line or a kick that got returned.
    ///
    /// This is where a return gets called back, and it is most of the reason a punt return
    /// average is lower than the yards actually gained. None of these fouls had ever been
    /// thrown, so a return had no way of being wiped out.
    static func onDownfieldBlock(
        blockers: [PlayerSlot], onOffense: Bool, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let available = blockers.filter { personnel[$0] != nil }
        guard !available.isEmpty else { return nil }
        let discipline = averageDiscipline(available, personnel, context, onOffense: onOffense)
        let chance = 0.014 + (62 - discipline) * 0.0005
        guard random.nextBool(probability: max(0.002, chance)) else { return nil }

        let foul: Foul
        switch random.next(upperBound: 100) {
        case ..<66: foul = .illegalBlockInTheBack
        case ..<86: foul = .illegalBlindsideBlock
        default: foul = .lowBlock
        }
        return record(foul, by: available, personnel, context, &random, offense: onOffense)
    }

    /// A lineman who went to block a run that turned out to be a pass.
    ///
    /// Screens and play-action are where this happens, which is why it is drawn against
    /// the concept rather than at a flat rate.
    static func onLineRelease(
        blockers: [PlayerSlot], isScreen: Bool, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        let chance = isScreen ? 0.010 : 0.002
        guard random.nextBool(probability: chance) else { return nil }
        let foul: Foul =
            random.nextBool(probability: 0.6)
            ? .ineligibleReceiverDownfield : .illegalManDownfield
        return record(foul, by: blockers, personnel, context, &random, offense: true)
    }

    /// The kicker is protected, and the rule distinguishes brushing him from ending him.
    static func onKick(
        rushers: [PlayerSlot], personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        guard random.nextBool(probability: 0.009) else { return nil }
        // Fifteen and a first down against five and a replay: the difference between
        // running into him and running through him.
        let foul: Foul =
            random.nextBool(probability: 0.4) ? .roughingTheKicker : .runningIntoTheKicker
        return record(foul, by: rushers, personnel, context, &random, offense: false)
    }

    /// What somebody says or does once the whistle has gone.
    ///
    /// Drawn after a play worth reacting to, because that is when it happens — and
    /// deliberately not scaled by leverage, which would be authoring drama.
    static func afterThePlay(
        _ outcome: Outcome, personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        // Deliberately not on a score or a turnover. A dead-ball foul on a play that ends
        // a possession is enforced on the kickoff, which is a rule the engine does not
        // model yet — so it is left uncalled rather than called and mis-enforced.
        let notable = outcome.yards >= 14 || outcome.kind == .sack
        guard notable, outcome.endedIn != .touchdown, !outcome.endedIn.isTurnover,
            random.nextBool(probability: 0.075)
        else { return nil }

        let byOffense = random.nextBool(probability: 0.45)
        let slots =
            byOffense
            ? personnel.routeRunners() + [SlotLayout.back]
            : personnel.coverageDefenders
        // Unsportsmanlike is the commoner call of the two; taunting is the one people
        // remember.
        let foul: Foul =
            random.nextBool(probability: 0.6)
            ? .unsportsmanlikeConduct : .taunting
        return record(foul, by: slots, personnel, context, &random, offense: byOffense)
    }

    // MARK: - Building the record

    private static func averageDiscipline(
        _ slots: [PlayerSlot], _ personnel: Lineup, _ context: PlayContext, onOffense: Bool
    ) -> Double {
        let values = slots.compactMap { slot -> Double? in
            guard personnel[slot] != nil else { return nil }
            return context.effective(.discipline, for: personnel[slot], onOffense: onOffense)
        }
        guard !values.isEmpty else { return 62 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Charge the foul to somebody, weighted so the least disciplined man is likeliest.
    private static func record(
        _ foul: Foul, by slots: [PlayerSlot], _ personnel: Lineup, _ context: PlayContext,
        _ random: inout SplittableRandom, offense: Bool
    ) -> PenaltyRecord? {
        let candidates = slots.filter { personnel[$0] != nil }
        guard !candidates.isEmpty else { return nil }

        let weights = candidates.map { slot -> Double in
            let discipline = context.effective(
                .discipline, for: personnel[slot], onOffense: offense)
            return max(0.2, 100 - discipline)
        }
        let index = random.weightedIndex(weights) ?? 0
        return PenaltyRecord(
            foul: foul, offender: candidates[index],
            offendingTeam: offense ? context.offense : context.defense,
            yards: foul.yards, wasAccepted: false)
    }
}
