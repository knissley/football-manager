import FMCore
import FMRandom

/// The M1 resolver: named matchups, no geometry
/// ([ADR-0012](../../../../docs/adr/0012-play-resolver-seam.md)).
///
/// It resolves real contests between real players — this rusher against this tackle,
/// this corner on this receiver — and the outcome *falls out of them*. That ordering is
/// the whole point. A resolver that drew a result and then decorated it with plausible
/// reasons would let the analysis layer appear to work while reading fiction, which is
/// the named risk of building M2 against scaffolding.
///
/// So the decision points are not commentary on the outcome. They are the reasons the
/// outcome is what it is, and `CrudeResolverTests` asserts they agree.
///
/// Deleted at M5.
public struct CrudeResolver: PlayResolver {

    public init() {}

    public func resolve(
        situation: Situation, calls: Calls, context: PlayContext,
        random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let family = CrudePlaybook.family(of: calls.offense.design) ?? .insideRun
        let personnel = Personnel.onField(context, random: &random)

        // A flag before the snap means the play never happened, whatever was called.
        if family.isRun || family.isPass,
            let foul = Penalties.preSnap(
                situation: situation, calls: calls, context: context, personnel: personnel,
                random: &random)
        {
            return (
                Outcome(
                    kind: .penaltyOnly, yards: 0, endedIn: .penaltyEnforced,
                    participants: participation(for: foul.offender, personnel, role: .other),
                    penalties: [foul], clockRunoff: 0),
                []
            )
        }

        switch family {
        case .insideRun, .outsideRun:
            return run(family, situation, calls, context, personnel, &random)
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction:
            return pass(family, situation, calls, context, personnel, &random)
        case .punt:
            return punt(situation, context, personnel, &random)
        case .fieldGoal, .extraPoint:
            return kick(family, situation, context, personnel, &random)
        case .twoPointConversion:
            return pass(.quickPass, situation, calls, context, personnel, &random, isTry: true)
        case .kickoff:
            return (Outcome(kind: .kickoff, yards: 0, endedIn: .touchback), [])
        // A kneel and a spike are snaps somebody took. Crediting nobody would leave the
        // quarterback's snap count short and put plays in the stream that happened to
        // no one.
        case .kneel:
            return (
                Outcome(
                    kind: .kneel, yards: -1, endedIn: .tackled,
                    participants: quarterbackOnly(.rusher, personnel), clockRunoff: 2), []
            )
        case .spike:
            return (
                Outcome(
                    kind: .spike, yards: 0, endedIn: .incomplete,
                    participants: quarterbackOnly(.passer, personnel), clockRunoff: 1), []
            )
        }
    }

    /// One player, for a play where only he did anything worth recording.
    private func participation(
        for slot: PlayerSlot, _ personnel: Personnel, role: PlayRole
    ) -> [Participation] {
        guard let id = personnel[slot], let position = personnel.position(at: slot) else {
            return []
        }
        return [Participation(slot: slot, player: id, position: position, role: role)]
    }

    /// The quarterback, for plays only he takes part in.
    private func quarterbackOnly(_ role: PlayRole, _ personnel: Personnel) -> [Participation] {
        guard let id = personnel[SlotLayout.quarterback],
            let position = personnel.position(at: SlotLayout.quarterback)
        else { return [] }
        return [
            Participation(slot: SlotLayout.quarterback, player: id, position: position, role: role)
        ]
    }

    // MARK: - Ratings

    private func rating(
        _ key: RatingKey, _ slot: PlayerSlot, _ personnel: Personnel, _ context: PlayContext
    ) -> Double {
        context.effective(key, for: personnel[slot], onOffense: slot.isOffense)
    }

    /// A contest between two ratings, as a probability the attacker wins.
    ///
    /// A logistic curve would be tidier and pulls in `exp`, which the FM modules do not
    /// link. This is the same shape by other means, and three properties matter:
    ///
    /// - **Even at parity.** Equal players split their reps.
    /// - **Monotonic, with no ceiling short of the clamp.** A ninety-nine rusher must be
    ///   measurably better than an eighty-one against the same tackle. An earlier version
    ///   capped the pass-rush win rate at a flat number and those two came out identical,
    ///   which makes elite talent worthless exactly where it should show.
    /// - **Never certain.** Hard-clamped to 7%–93%, so the best player in the league
    ///   still loses reps and the worst still wins some. That is where upsets live, and
    ///   why a pass rusher is happy with two good snaps in a game rather than twelve.
    ///
    /// Internal rather than private so the curve itself can be tested. Its shape is a
    /// design property, not an implementation detail.
    func contest(_ attacker: Double, _ defender: Double, edge: Double = 0) -> Double {
        let margin = (attacker - defender) / 22.0 + edge
        let scaled = margin / (1.0 + abs(margin))
        return min(0.93, max(0.07, 0.5 + scaled * 0.45))
    }

    // MARK: - Pass

    private func pass(
        _ family: PlayFamily,
        _ situation: Situation,
        _ calls: Calls,
        _ context: PlayContext,
        _ personnel: Personnel,
        _ random: inout SplittableRandom,
        isTry: Bool = false
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var decisions: [DecisionPoint] = []
        var participants: [Participation] = []
        var penalty: PenaltyRecord?
        let defense = calls.defense

        /// Credit a player, or **upgrade** the role he is already credited in.
        ///
        /// Dropping the second credit silently is what made a sack attributable to
        /// nobody: the rusher was already down as a pass rusher from winning his rep,
        /// so the tackle credit that names him as the sacker was thrown away and the
        /// league had no sack leaders at all.
        func credit(_ slot: PlayerSlot, _ role: PlayRole) {
            guard let id = personnel[slot], let position = personnel.position(at: slot)
            else { return }
            if let existing = participants.firstIndex(where: { $0.slot == slot }) {
                // A tackle is the more specific fact about what he did on this play.
                if role == .tackler {
                    participants[existing] = Participation(
                        slot: slot, player: id, position: position, role: role)
                }
                return
            }
            participants.append(
                Participation(slot: slot, player: id, position: position, role: role))
        }

        credit(SlotLayout.quarterback, .passer)

        // 1. The pocket. Each rusher works a blocker, and the first one home sets the
        //    clock everything else runs against.
        let rushers = Array(SlotLayout.rushers.prefix(Int(defense.rush.rushers)))
        var pressureAt: Int? = nil
        var pressureBy = PlayerSlot.none

        for (index, rusher) in rushers.enumerated() {
            let blocker = SlotLayout.blockers[min(index, SlotLayout.blockers.count - 1)]
            // A matchup needs two players. If injuries have emptied a spot, there is no
            // rep to resolve — and recording one would name a slot nobody is standing in,
            // which is a decision point pointing at an uncredited player.
            guard personnel[rusher] != nil, personnel[blocker] != nil else { continue }
            let rush = rating(.powerMove, rusher, personnel, context)
            let block = rating(.passBlock, blocker, personnel, context)
            // A blitz means somebody is unblocked by construction.
            let edge = defense.rush.isBlitz && index >= SlotLayout.blockers.count ? 0.35 : 0
            // Scaled down rather than capped. Four rushers each winning a coin flip
            // means somebody is home on every snap, which is a 24% sack rate and not
            // football — but clipping the top at a fixed ceiling made a 99 rusher no
            // better than an 81 against a weak tackle, which is worse. Multiplying keeps
            // the whole talent curve intact and still bounds the best case.
            let winChance = contest(rush, block, edge: edge) * 0.64

            credit(rusher, .passRusher)
            credit(blocker, .blocker)

            if random.nextBool(probability: winChance) {
                let millis = 1_500 + Int(random.next(upperBound: 1_400))
                decisions.append(
                    .init(
                        tick: UInt16(millis / 100), kind: .pressureAllowed, primary: blocker,
                        secondary: rusher, detail: BlockResult.lost.rawValue,
                        value: Int16(millis)))
                // Drawn here, conditional on having lost, so the flag and the reason for
                // it are the same event: he held because he was beaten.
                if penalty == nil {
                    penalty = Penalties.whenBeatenBlocking(
                        blocker: blocker, personnel: personnel, context: context, random: &random)
                }
                if millis < (pressureAt ?? Int.max) {
                    pressureAt = millis
                    pressureBy = rusher
                }
            } else {
                let millis = 2_600 + Int(random.next(upperBound: 1_200))
                decisions.append(
                    .init(
                        tick: UInt16(millis / 100), kind: .pressureHeld, primary: blocker,
                        secondary: rusher, detail: BlockResult.won.rawValue,
                        value: Int16(millis)))
            }
        }

        // 2. Coverage, and the read. Separation is what the quarterback is looking at.
        let depth = routeDepth(family)
        var reads: [(receiver: PlayerSlot, defender: PlayerSlot, separation: Int)] = []

        for (index, receiver) in SlotLayout.receivers.prefix(3).enumerated() {
            let defender = SlotLayout.coverage[min(index, SlotLayout.coverage.count - 1)]
            guard personnel[receiver] != nil, personnel[defender] != nil else { continue }
            let route = rating(.routeRunning, receiver, personnel, context)
            let cover = rating(
                defense.coverage.isMan ? .manCoverage : .zoneCoverage, defender, personnel, context)
            let open = contest(route, cover)
            // Centimetres. Wide open is a couple of metres; blanketed is inside one.
            let separation = Int(30 + open * 190 + Double(random.next(upperBound: 60)) - 30)

            credit(receiver, .receiver)
            credit(defender, .coverage)
            decisions.append(
                .init(
                    tick: UInt16(12 + index * 3), kind: .coverageAssignment, primary: defender,
                    secondary: receiver,
                    detail: (defense.coverage.isMan ? CoverageTechnique.offMan : .zoneDeep).rawValue
                ))
            decisions.append(
                .init(
                    tick: UInt16(14 + index * 4), kind: .readProgression,
                    primary: SlotLayout.quarterback,
                    secondary: receiver, detail: UInt8(index + 1), value: Int16(separation)))
            reads.append((receiver, defender, separation))

            if penalty == nil {
                penalty = Penalties.whenBeatenInCoverage(
                    defender: defender, separationCentimetres: separation,
                    routeDepth: depth.yards, personnel: personnel, context: context,
                    random: &random)
            }
        }

        // 3. The decision. Pressure that arrives before the route develops is what turns
        //    a read into a sack or a throwaway.
        let timeNeeded = depth.timeMillis
        let pressured = pressureAt.map { $0 < timeNeeded } ?? false
        let best = reads.max { $0.separation < $1.separation }

        // A quarterback who feels it and takes off. Escaping was missing entirely — the
        // resolver went straight from pressure to a sack or a throw, so `PlayKind`
        // carried a `.scramble` case nothing could ever produce, and a quarterback could
        // not get hurt running.
        if pressured, random.nextBool(probability: 0.26) {
            let mobility =
                (rating(.speed, SlotLayout.quarterback, personnel, context)
                    + rating(.elusiveness, SlotLayout.quarterback, personnel, context)) / 2
            if random.nextBool(probability: min(0.8, max(0.16, (mobility - 42) * 0.013))) {
                decisions.append(
                    .init(
                        tick: UInt16((pressureAt ?? 2_000) / 100), kind: .throwDecision,
                        primary: SlotLayout.quarterback, secondary: pressureBy,
                        detail: ThrowDecision.scramble.rawValue,
                        value: Int16(pressureAt ?? 2_000)))

                let scramble = tackleSequence(
                    carrier: SlotLayout.quarterback, personnel: personnel, context: context,
                    decisions: &decisions, participants: &participants, startTick: 30,
                    random: &random)
                let gained = Int16(
                    max(-2, 2 + Int(random.next(upperBound: 6)) + scramble.extraYards))
                let scores = Int(situation.ballOn) - Int(gained) <= 0
                return (
                    Outcome(
                        kind: .scramble,
                        yards: scores ? Int16(situation.ballOn) : gained,
                        endedIn: scores ? .touchdown : scramble.ending,
                        participants: participants, penalties: penalty.map { [$0] } ?? [],
                        clockRunoff: UInt16(6 + Int(random.next(upperBound: 3)))),
                    decisions
                )
            }
        }

        // Most pressure is survived — thrown away, checked down, or simply beaten by the
        // ball coming out. Only a minority becomes a sack.
        if pressured, random.nextBool(probability: 0.155) {
            // Sacked, by the rusher who actually got there. Nothing else can be credited.
            decisions.append(
                .init(
                    tick: UInt16((pressureAt ?? 2_000) / 100), kind: .throwDecision,
                    primary: SlotLayout.quarterback, secondary: pressureBy,
                    detail: ThrowDecision.sack.rawValue, value: Int16(pressureAt ?? 2_000)))
            credit(pressureBy, .tackler)
            if penalty == nil {
                penalty = Penalties.onContact(
                    tackler: pressureBy, isQuarterback: true, personnel: personnel,
                    context: context, random: &random)
            }
            let room: Int = 99 - Int(situation.ballOn)
            let rawLoss: Int = 4 + Int(random.next(upperBound: 6))
            let inOwnEndZone: Bool = rawLoss > room
            let loss: Int16 = Int16(-min(rawLoss, room))
            let runoff = UInt16(5 + Int(random.next(upperBound: 3)))
            return (
                Outcome(
                    kind: .sack, yards: inOwnEndZone ? Int16(-room) : loss,
                    endedIn: inOwnEndZone ? .safety : .tackled,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    clockRunoff: runoff),
                decisions
            )
        }

        guard let target = best else {
            return (
                Outcome(kind: .pass, yards: 0, endedIn: .incomplete, participants: participants),
                decisions
            )
        }

        // 4. The throw, and the ball arriving.
        let accuracy = rating(depth.accuracyKey, SlotLayout.quarterback, personnel, context)
        let placement = placement(accuracy: accuracy, pressured: pressured, random: &random)
        let throwTick = UInt16(timeNeeded / 100)
        let arrivalTick = throwTick + UInt16(depth.flightTicks)
        decisions.append(
            .init(
                tick: throwTick, kind: .throwDecision,
                primary: SlotLayout.quarterback, secondary: target.receiver,
                detail: ThrowDecision.primary.rawValue, value: Int16(timeNeeded)))
        decisions.append(
            .init(
                tick: arrivalTick, kind: .ballArrival,
                primary: target.receiver, secondary: target.defender,
                detail: placement.rawValue, value: Int16(target.separation)))

        let catchResult = catchOutcome(
            placement: placement, separation: target.separation,
            hands: rating(.catching, target.receiver, personnel, context),
            ballHawk: rating(.ballHawk, target.defender, personnel, context),
            random: &random)
        decisions.append(
            .init(
                tick: arrivalTick + 1, kind: .catchAttempt,
                primary: target.receiver, secondary: target.defender,
                detail: catchResult.rawValue, value: Int16(target.separation)))

        let runoff = UInt16(4 + Int(random.next(upperBound: 4)))

        switch catchResult {
        case .intercepted:
            credit(target.defender, .coverage)
            let spot = UInt8(max(1, min(99, Int(situation.ballOn) - depth.yards)))
            return (
                Outcome(
                    kind: .pass, yards: 0, endedIn: .intercepted, participants: participants,
                    penalties: penalty.map { [$0] } ?? [], finalSpot: spot, clockRunoff: runoff),
                decisions
            )

        case .caught, .contestedCatch:
            let afterCatch = yardsAfterCatch(
                carrier: target.receiver, personnel: personnel, context: context,
                separation: target.separation, decisions: &decisions,
                participants: &participants, startTick: arrivalTick + 2, random: &random)
            let total: Int = depth.yards + afterCatch.yards
            let reachesEndZone: Bool = Int(situation.ballOn) - total <= 0
            let gained: Int16 = reachesEndZone ? Int16(situation.ballOn) : Int16(total)
            let ending: PlayEnding = reachesEndZone ? .touchdown : afterCatch.ending
            let kind: PlayKind = isTry ? .twoPointConversion : .pass
            return (
                Outcome(
                    kind: kind, yards: gained, endedIn: ending,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    clockRunoff: runoff),
                decisions
            )

        case .dropped, .brokenUp, .uncatchable:
            return (
                Outcome(
                    kind: isTry ? .twoPointConversion : .pass, yards: 0, endedIn: .incomplete,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    clockRunoff: runoff),
                decisions
            )
        }
    }

    // MARK: - Run

    private func run(
        _ family: PlayFamily,
        _ situation: Situation,
        _ calls: Calls,
        _ context: PlayContext,
        _ personnel: Personnel,
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var decisions: [DecisionPoint] = []
        var participants: [Participation] = []
        var penalty: PenaltyRecord?

        /// Credit a player, or **upgrade** the role he is already credited in.
        ///
        /// Dropping the second credit silently is what made a sack attributable to
        /// nobody: the rusher was already down as a pass rusher from winning his rep,
        /// so the tackle credit that names him as the sacker was thrown away and the
        /// league had no sack leaders at all.
        func credit(_ slot: PlayerSlot, _ role: PlayRole) {
            guard let id = personnel[slot], let position = personnel.position(at: slot)
            else { return }
            if let existing = participants.firstIndex(where: { $0.slot == slot }) {
                // A tackle is the more specific fact about what he did on this play.
                if role == .tackler {
                    participants[existing] = Participation(
                        slot: slot, player: id, position: position, role: role)
                }
                return
            }
            participants.append(
                Participation(slot: slot, player: id, position: position, role: role))
        }

        credit(SlotLayout.back, .rusher)

        // The hole is the sum of the blocks in front of it, against a front committed to
        // stopping the run or not.
        var blockScore = 0.0
        for (index, blocker) in SlotLayout.blockers.enumerated() {
            let defender = SlotLayout.rushers[min(index, SlotLayout.rushers.count - 1)]
            guard personnel[blocker] != nil, personnel[defender] != nil else { continue }
            let block = rating(.runBlock, blocker, personnel, context)
            let shed = rating(.blockShedding, defender, personnel, context)
            let commitment =
                calls.defense.runFit == .aggressive
                ? 0.18
                : (calls.defense.runFit == .sellOut ? 0.3 : 0)
            let won = random.nextBool(probability: contest(block, shed, edge: -commitment))

            credit(blocker, .blocker)
            credit(defender, .tackler)
            decisions.append(
                .init(
                    tick: UInt16(4 + index), kind: .blockResult, primary: blocker,
                    secondary: defender,
                    detail: (won ? BlockResult.won : .lost).rawValue))
            blockScore += won ? 1 : -1

            // Same rule as in protection: a hold is what a beaten blocker does.
            if !won, penalty == nil {
                penalty = Penalties.whenBeatenBlocking(
                    blocker: blocker, personnel: personnel, context: context, random: &random)
            }
        }

        let quality = Int16(blockScore * 12) + Int16(random.next(upperBound: 30)) - 15
        decisions.append(
            .init(
                tick: 10, kind: .holeQuality, primary: SlotLayout.back,
                detail: family == .insideRun ? 0 : 1, value: quality))

        // Vision turns a hole into yards; a back with none runs into his own linemen.
        let vision = rating(.vision, SlotLayout.back, personnel, context)
        // A flat line through the hole quality made every carry roughly the same, which
        // kept early downs so reliable that third downs were short and converted half
        // the time. Real carries are mostly modest with a fat tail: a hole that really
        // opens is a long run, and that tail is where the yards-per-carry average
        // actually comes from.
        var yards = Int(Double(quality) * 0.075 + (vision - 60) * 0.04 + 1.3)
        yards += Int(random.next(upperBound: 5)) - 2
        if quality > 30 {
            yards += Int(random.next(upperBound: UInt64(quality / 3)))
        }

        let tackle = tackleSequence(
            carrier: SlotLayout.back, personnel: personnel, context: context,
            decisions: &decisions, participants: &participants, startTick: 16, random: &random)
        yards += tackle.extraYards

        let gained = Int16(max(-8, min(80, yards)))
        let reachesEndZone = Int(situation.ballOn) - Int(gained) <= 0
        let intoOwnEndZone = Int(situation.ballOn) - Int(gained) >= 100

        // Contact fouls are drawn where the contact happened, on the man who made it.
        if penalty == nil, let tackler = participants.first(where: { $0.role == .tackler })?.slot {
            penalty = Penalties.onContact(
                tackler: tackler, isQuarterback: false, personnel: personnel, context: context,
                random: &random)
        }

        return (
            Outcome(
                kind: .rush,
                yards: reachesEndZone ? Int16(situation.ballOn) : gained,
                endedIn: reachesEndZone ? .touchdown : (intoOwnEndZone ? .safety : tackle.ending),
                participants: participants,
                penalties: penalty.map { [$0] } ?? [],
                clockRunoff: UInt16(5 + Int(random.next(upperBound: 3)))),
            decisions
        )
    }

    // MARK: - Kicks

    private func punt(
        _ situation: Situation, _ context: PlayContext, _ personnel: Personnel,
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let power =
            42.0 + (rating(.puntPower, SlotLayout.quarterback, personnel, context) - 60) * 0.25
        let distance = Int(power) + Int(random.next(upperBound: 14)) - 7
        let landing = Int(situation.ballOn) - distance

        if landing <= 0 {
            return (
                Outcome(kind: .punt, yards: 0, endedIn: .touchback, clockRunoff: 6), []
            )
        }
        return (
            Outcome(
                kind: .punt, yards: 0, endedIn: .fairCatch,
                finalSpot: UInt8(max(1, min(99, landing))), clockRunoff: 6),
            []
        )
    }

    private func kick(
        _ family: PlayFamily, _ situation: Situation, _ context: PlayContext,
        _ personnel: Personnel, _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let length = context.rules.fieldGoalDistance(ballOn: situation.ballOn)
        let accuracy = rating(.kickAccuracy, SlotLayout.quarterback, personnel, context)

        // Near certainty inside thirty, falling away steeply past fifty. Weather and a
        // strong leg move the curve; the shape is the same either way.
        var chance = 0.99 - Double(max(0, length - 25)) * 0.017
        chance += (accuracy - 60) * 0.004
        if situation.weather.windSpeed > 15 { chance -= 0.06 }
        if situation.weather.precipitation != .none { chance -= 0.04 }

        let good = random.nextBool(probability: min(0.99, max(0.02, chance)))
        return (
            Outcome(
                kind: family == .extraPoint ? .extraPoint : .fieldGoal, yards: 0,
                endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
                clockRunoff: family == .extraPoint ? 0 : 5),
            []
        )
    }

    // MARK: - Shared pieces

    private struct RouteDepth {
        let yards: Int
        let timeMillis: Int
        let flightTicks: Int
        let accuracyKey: RatingKey
    }

    private func routeDepth(_ family: PlayFamily) -> RouteDepth {
        switch family {
        case .screen:
            return RouteDepth(
                yards: -1, timeMillis: 1_400, flightTicks: 3, accuracyKey: .throwAccuracyShort)
        case .quickPass:
            return RouteDepth(
                yards: 4, timeMillis: 1_700, flightTicks: 4, accuracyKey: .throwAccuracyShort)
        case .mediumPass:
            return RouteDepth(
                yards: 10, timeMillis: 2_600, flightTicks: 7, accuracyKey: .throwAccuracyMedium)
        case .playAction:
            return RouteDepth(
                yards: 13, timeMillis: 3_000, flightTicks: 8, accuracyKey: .throwAccuracyMedium)
        case .deepPass:
            return RouteDepth(
                yards: 21, timeMillis: 3_400, flightTicks: 12, accuracyKey: .throwAccuracyDeep)
        default:
            return RouteDepth(
                yards: 8, timeMillis: 2_200, flightTicks: 5, accuracyKey: .throwAccuracyMedium)
        }
    }

    private func placement(
        accuracy: Double, pressured: Bool, random: inout SplittableRandom
    ) -> BallPlacement {
        var onTarget = 0.34 + (accuracy - 60) * 0.008
        if pressured { onTarget -= 0.16 }
        let roll = random.nextDouble()
        if roll < max(0.1, onTarget) { return .onTarget }
        if roll < max(0.1, onTarget) + 0.34 { return .slightlyOff }
        if roll < 0.95 { return .poor }
        return .uncatchable
    }

    private func catchOutcome(
        placement: BallPlacement, separation: Int, hands: Double, ballHawk: Double,
        random: inout SplittableRandom
    ) -> CatchResult {
        if placement == .uncatchable { return .uncatchable }

        var catchChance: Double
        switch placement {
        case .onTarget: catchChance = 0.87
        case .slightlyOff: catchChance = 0.60
        case .poor: catchChance = 0.22
        case .uncatchable: catchChance = 0
        }
        catchChance += (hands - 60) * 0.004
        catchChance += Double(separation - 130) * 0.0007

        if random.nextBool(probability: min(0.97, max(0.05, catchChance))) {
            return separation < 90 ? .contestedCatch : .caught
        }

        // A bad ball into tight coverage is where interceptions come from — not from a
        // flat per-attempt rate.
        var pickChance = placement == .poor ? 0.17 : 0.05
        pickChance += (ballHawk - 60) * 0.002
        pickChance -= Double(separation - 130) * 0.0006
        if random.nextBool(probability: min(0.5, max(0.005, pickChance))) { return .intercepted }

        return separation < 110 ? .brokenUp : .dropped
    }

    private func yardsAfterCatch(
        carrier: PlayerSlot, personnel: Personnel, context: PlayContext, separation: Int,
        decisions: inout [DecisionPoint], participants: inout [Participation],
        startTick: UInt16, random: inout SplittableRandom
    ) -> (yards: Int, ending: PlayEnding) {
        let tackle = tackleSequence(
            carrier: carrier, personnel: personnel, context: context, decisions: &decisions,
            participants: &participants, startTick: startTick, random: &random)
        // A receiver who caught it in stride is already past somebody. Separation earned
        // before the catch is worth yards after it.
        let inStride = max(0, separation - 140) / 45
        return (
            max(0, Int(random.next(upperBound: 3)) + inStride + tackle.extraYards), tackle.ending
        )
    }

    /// Who brought him down, and whether he broke one first.
    ///
    /// The tackler credited here is the one the outcome names. Nothing else can be, and
    /// that is asserted rather than assumed.
    private func tackleSequence(
        carrier: PlayerSlot, personnel: Personnel, context: PlayContext,
        decisions: inout [DecisionPoint], participants: inout [Participation],
        startTick: UInt16, random: inout SplittableRandom
    ) -> (extraYards: Int, ending: PlayEnding) {
        let breakTackle = context.effective(
            .breakTackle, for: personnel[carrier], onOffense: carrier.isOffense)

        var extra = 0
        var tick = startTick
        var broke = 0
        let attempts = 3

        for defender in SlotLayout.coverage.prefix(attempts) {
            guard let id = personnel[defender], let position = personnel.position(at: defender)
            else { continue }
            let tackling =
                context.player(id).map {
                    Double($0.ratings[.tackling] ?? $0.overall)
                } ?? 60

            // A flat base with a rating swing on top, rather than a contest: a contest
            // at parity breaks four tackles in ten, which turned every carry into seven
            // and a half yards.
            let breakChance = min(0.32, max(0.02, 0.09 + (breakTackle - tackling) * 0.0045))
            let broken = random.nextBool(probability: breakChance)
            decisions.append(
                .init(
                    tick: tick, kind: .tackleAttempt, primary: defender, secondary: carrier,
                    detail: (broken ? TackleResult.broken : .madeTackle).rawValue))
            tick += 4

            if !participants.contains(where: { $0.slot == defender }) {
                participants.append(
                    Participation(
                        slot: defender, player: id, position: position,
                        role: broken ? .other : .tackler))
            }

            if !broken {
                return (extra, random.nextBool(probability: 0.14) ? .outOfBounds : .tackled)
            }
            extra += 2 + Int(random.next(upperBound: 5))
            broke += 1
        }

        // He beat everybody who had an angle on him, so he is in open field rather than
        // three yards further on. This is the passing game's equivalent of the run's
        // burst through a hole, and its absence is why a first pass could produce a
        // maximum of three passing touchdowns in four hundred team-games: without a
        // breakaway there is no long touchdown, and without long touchdowns there is no
        // tail at all.
        if broke == attempts {
            let speed = context.effective(.speed, for: personnel[carrier], onOffense: true)
            let burst = 6 + Int((speed - 55) * 0.35) + Int(random.next(upperBound: 22))
            extra += max(4, burst)
        }

        return (extra, .outOfBounds)
    }
}
