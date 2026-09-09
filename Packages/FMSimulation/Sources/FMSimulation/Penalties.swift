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
        let lineSlots = SlotLayout.blockers
        let offenseDiscipline = averageDiscipline(lineSlots, personnel, context, onOffense: true)
        var falseStart = 0.027 + (62 - offenseDiscipline) * 0.0011
        falseStart += noise * 0.00022
        if calls.offense.tempo == .hurryUp { falseStart += 0.004 }

        if random.nextBool(probability: max(0.002, falseStart)) {
            return record(.falseStart, by: lineSlots, personnel, context, &random, offense: true)
        }

        // Delay of game is the other end of the same problem: too slow rather than too
        // eager, and worse when the offence cannot hear itself.
        var delay = 0.006 + noise * 0.0001
        if calls.offense.tempo == .bleedClock { delay += 0.004 }
        if random.nextBool(probability: delay) {
            return record(
                .delayOfGame, by: [SlotLayout.quarterback], personnel, context, &random,
                offense: true)
        }

        // The defence jumping. A blitz asks defenders to time the snap, which is exactly
        // when they get it wrong.
        let rushSlots = SlotLayout.rushers
        let defenseDiscipline = averageDiscipline(rushSlots, personnel, context, onOffense: false)
        var offside = 0.019 + (62 - defenseDiscipline) * 0.0009
        if calls.defense.rush.isBlitz { offside += 0.004 }
        if random.nextBool(probability: max(0.002, offside)) {
            let foul: Foul = random.nextBool(probability: 0.6) ? .offside : .neutralZoneInfraction
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
                .tooManyMenOnField, by: SlotLayout.coverage, personnel, context, &random,
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
        let chance = 0.018 + (62 - discipline) * 0.0005 + (62 - technique) * 0.0004
        guard random.nextBool(probability: max(0.002, min(0.06, chance))) else { return nil }
        return record(.offensiveHolding, by: [blocker], personnel, context, &random, offense: true)
    }

    /// A defender who has been beaten in coverage.
    ///
    /// Separation is the input, so interference is drawn against exactly the receivers
    /// who won — and the deep ones, where the spot foul hurts most.
    static func whenBeatenInCoverage(
        defender: PlayerSlot, separationCentimetres: Int, routeDepth: Int,
        personnel: Lineup, context: PlayContext, random: inout SplittableRandom
    ) -> PenaltyRecord? {
        guard separationCentimetres > 120 else { return nil }
        let discipline = context.effective(.discipline, for: personnel[defender], onOffense: false)
        let beatenBy = Double(separationCentimetres - 120) * 0.0006
        let chance = 0.014 + beatenBy + (62 - discipline) * 0.0009
        guard random.nextBool(probability: max(0.004, min(0.14, chance))) else { return nil }

        // Deep, it is interference and enforced from the spot. Underneath, it is holding
        // or illegal contact and costs five.
        // Anything past the sticks is deep enough for the spot foul to be the call.
        if routeDepth >= 10 {
            let spot = UInt8(max(1, min(99, routeDepth + Int(random.next(upperBound: 6)) - 3)))
            return PenaltyRecord(
                foul: .defensivePassInterference, offender: defender,
                offendingTeam: context.defense, yards: spot, wasAccepted: false)
        }
        let foul: Foul = random.nextBool(probability: 0.55) ? .defensiveHolding : .illegalContact
        return record(foul, by: [defender], personnel, context, &random, offense: false)
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
        let foul: Foul = random.nextBool(probability: 0.5) ? .facemask : .unnecessaryRoughness
        return record(foul, by: [tackler], personnel, context, &random, offense: false)
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
