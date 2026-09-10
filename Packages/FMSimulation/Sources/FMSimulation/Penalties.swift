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

        // Delay of game is the play clock expiring with the ball not snapped (2025
        // rulebook, 4-6-1, 4-6-4), so it is derived from the clock in force and the
        // tempo rather than drawn at a flat rate. The offence means to snap with some
        // slack left — a second bleeding the clock, nine at normal tempo on the forty,
        // six on the twenty-five that follows a change of possession — and the chance
        // it overruns that slack halves with every eight seconds of it. The base is the
        // crowd's, and it moves this far less than it moves a false start: the play
        // clock is the coach's problem, not the crowd's. At a tenth of a point per unit
        // of noise it was doubling the road team's delay-of-game rate and quietly
        // supplying most of the road/home penalty gap.
        //
        // Set so that a normal-tempo snap on the forty at a quiet ground overruns
        // exactly as often as the flat rate used to fire (0.35%); everything else — the
        // shorter clock, the tempo, the crowd — is the derivation.
        let slack = Int(context.playClock.remainingAtIntendedSnap(at: calls.offense.tempo))
        var overrun = 0.007 + noise * 0.00006
        for _ in 1..<max(1, slack) { overrun *= playClockOverrunSurvival }
        if random.nextBool(probability: overrun) {
            return record(
                .delayOfGame, by: [SlotLayout.quarterback], personnel, context, &random,
                offense: true)
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
    /// of them and is drawn at the throw instead (`onTheThrow`), because 8-5-1 says
    /// interference can only occur when a forward pass is thrown from behind the line.
    static func whenBeatenInCoverage(
        defender: PlayerSlot, receiver: PlayerSlot, separationCentimetres: Int,
        personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> PenaltyRecord? {
        guard separationCentimetres > 120 else { return nil }
        let discipline = context.effective(.discipline, for: personnel[defender], onOffense: false)
        let beatenBy = Double(separationCentimetres - 120) * 0.0006
        let chance = 0.010 + beatenBy + (62 - discipline) * 0.0009
        guard random.nextBool(probability: max(0.003, min(0.11, chance))) else { return nil }

        // Illegal contact is a rare call in the modern game; grabbing is the usual one.
        let foul: Foul = random.nextBool(probability: 0.86) ? .defensiveHolding : .illegalContact
        return record(foul, by: [defender], personnel, context, &random, offense: false)
    }

    /// Interference, on the matchup the ball was thrown into.
    ///
    /// 8-5-1: interference "can only occur when a forward pass is thrown from behind the
    /// line of scrimmage", the defence's restrictions "apply from the time the ball is
    /// thrown until the ball is touched", and it is an act that hinders "an eligible
    /// player's opportunity to catch the ball". So there is exactly one matchup it can be
    /// drawn on — the target's — and a down with no throw in it has none at all. It used
    /// to be drawn per read in the coverage loop, before the quarterback had decided
    /// anything, which put it on sacks and on receivers nobody looked at.
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
        // Drawn on one matchup a play instead of on every read, so the per-matchup rate
        // carries what four reads used to.
        let chance = 0.030 + beatenBy * 2 + (62 - discipline) * 0.0018
        guard random.nextBool(probability: max(0.006, min(0.22, chance))) else { return nil }

        // Sometimes the separation was made with a hand in the chest and the flag goes
        // the other way — 8-5-1's "initiating contact with an opponent by shoving or
        // pushing off, thus creating separation", which is a foul on the man the ball was
        // thrown to and on nobody else.
        if random.nextBool(probability: 0.16) {
            return record(
                .offensivePassInterference, by: [receiver], personnel, context, &random,
                offense: true)
        }

        // Underneath, an act more than one yard beyond the line is still interference,
        // but the crude engine cannot tell a hook from a hand-fight inside the sticks, so
        // anything shorter than the line to gain is called as the contact foul it more
        // often is (8-5-1: acts that are not interference "could be offensive or
        // defensive holding").
        guard routeDepth >= 10 else {
            let foul: Foul =
                random.nextBool(probability: 0.86) ? .defensiveHolding : .illegalContact
            return record(foul, by: [defender], personnel, context, &random, offense: false)
        }
        return PenaltyRecord(
            foul: .defensivePassInterference, offender: defender,
            offendingTeam: context.defense, yards: Foul.defensivePassInterference.yards,
            wasAccepted: false, enforcementSpot: UInt8(max(0, min(99, catchPoint))))
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
