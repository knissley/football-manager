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
        situation: Situation, calls: Calls, onField personnel: Lineup, context: PlayContext,
        random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let concept = calls.offense.concept

        // A flag before the snap means the play never happened, whatever was called.
        // Every snap can draw one, kicks included. Tries and kickoffs used to be excluded
        // because a flag there cancelled the try or the kickoff outright — the rules loop
        // consumed the pending state on any play, including one that never happened. It
        // replays them properly now.
        if let foul = Penalties.preSnap(
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

        switch concept {
        case .insideRun, .outsideRun:
            return run(concept, situation, calls, context, personnel, &random)
        case .quickPass, .mediumPass, .deepPass, .screen, .playAction:
            return pass(concept, situation, calls, context, personnel, &random)
        case .punt:
            return punt(situation, context, personnel, &random)
        case .fieldGoal, .extraPoint:
            return kick(concept, situation, context, personnel, &random)
        case .twoPointPass:
            return pass(.quickPass, situation, calls, context, personnel, &random, isTry: true)
        case .twoPointRun:
            return run(.insideRun, situation, calls, context, personnel, &random, isTry: true)
        case .kickoff, .deepKickoff:
            return kickoff(situation, calls, context, personnel, &random)
        case .onsideKick:
            return onsideKick(situation, context, personnel, &random)
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
                    kind: .spike, yards: 0, endedIn: .incomplete, passResult: .incomplete,
                    participants: quarterbackOnly(.passer, personnel), clockRunoff: 1), []
            )
        }
    }

    /// One player, for a play where only he did anything worth recording.
    /// Credit a player, or **upgrade** the role he is already credited in.
    ///
    /// A player earns one line per play, so when two credits apply the more specific one
    /// has to win. Dropping the second silently is a bug this engine has now made three
    /// times: it made a sack attributable to nobody (the sacker was already down as a
    /// pass rusher), it hid every target behind a `.receiver` credit, and it threw away
    /// the tackle on a completed pass because the man who made it was already credited
    /// with the coverage. One rule, in one place, is the fix.
    private func credit(
        _ slot: PlayerSlot, _ role: PlayRole, _ personnel: Lineup,
        into participants: inout [Participation]
    ) {
        guard let id = personnel[slot], let position = personnel.position(at: slot) else { return }
        if let existing = participants.firstIndex(where: { $0.slot == slot }) {
            guard role.outranks(participants[existing].role) else { return }
            participants[existing] = Participation(
                slot: slot, player: id, position: position, role: role)
            return
        }
        participants.append(Participation(slot: slot, player: id, position: position, role: role))
    }

    /// A fumble, as the record carries it: how the play ended, where the ball came to
    /// rest, and — when the defence came up with it — where it came loose.
    private struct LooseBall {
        var ending: PlayEnding
        var finalSpot: UInt8
        /// The spot where possession was lost, in the offence's frame; `nil` when the
        /// offence fell on it.
        var lostAt: UInt8?
    }

    /// Turn a hit into a fumble, if it was one.
    ///
    /// Returns the ending and resting spot to use instead of the tackle's. The spot is in
    /// the offence's frame throughout: a defender who recovers runs *back* towards the
    /// offence's own goal, so his return **increases** `ballOn`, and reaching a hundred
    /// is a defensive touchdown.
    private func looseBall(
        carrier: PlayerSlot, tackler: PlayerSlot?, isSack: Bool, spot: Int,
        personnel: Lineup, context: PlayContext,
        participants: inout [Participation], random: inout SplittableRandom
    ) -> LooseBall? {
        guard let tackler,
            let loose = Fumbles.drawn(
                carrier: carrier, tackler: tackler, isSack: isSack, personnel: personnel,
                context: context, random: &random)
        else { return nil }

        credit(loose.forcedBy, .tackler, personnel, into: &participants)
        let lostAt = UInt8(max(1, min(99, spot)))
        guard loose.lost else {
            return LooseBall(ending: .fumbleRecovered, finalSpot: lostAt, lostAt: nil)
        }
        let resting = spot + loose.returnYards
        return LooseBall(
            ending: .fumbleLost, finalSpot: UInt8(max(1, min(100, resting))), lostAt: lostAt)
    }

    private func participation(
        for slot: PlayerSlot, _ personnel: Lineup, role: PlayRole
    ) -> [Participation] {
        guard let id = personnel[slot], let position = personnel.position(at: slot) else {
            return []
        }
        return [Participation(slot: slot, player: id, position: position, role: role)]
    }

    /// The quarterback, for plays only he takes part in.
    private func quarterbackOnly(_ role: PlayRole, _ personnel: Lineup) -> [Participation] {
        guard let id = personnel[SlotLayout.quarterback],
            let position = personnel.position(at: SlotLayout.quarterback)
        else { return [] }
        return [
            Participation(slot: SlotLayout.quarterback, player: id, position: position, role: role)
        ]
    }

    // MARK: - Ratings

    private func rating(
        _ key: RatingKey, _ slot: PlayerSlot, _ personnel: Lineup, _ context: PlayContext
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
        _ concept: PlayConcept,
        _ situation: Situation,
        _ calls: Calls,
        _ context: PlayContext,
        _ personnel: Lineup,
        _ random: inout SplittableRandom,
        isTry: Bool = false
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var decisions: [DecisionPoint] = []
        var participants: [Participation] = []
        var penalty: PenaltyRecord?
        let defense = calls.defense

        func credit(_ slot: PlayerSlot, _ role: PlayRole) {
            self.credit(slot, role, personnel, into: &participants)
        }

        /// What the play *was*, which on a try is the try and nothing else.
        ///
        /// A try is one scrimmage down after a touchdown, and the whistle closes it out
        /// whether or not anybody scored on it (2025 rulebook, 11-3-1, 11-3-2-e), so it is
        /// the try however it ended — caught, dropped, thrown away, sacked or picked off.
        /// `PlayEnding` and `Outcome.passResult` say which of those; `PlayKind` says only
        /// that this was the down after the touchdown. Every exit below goes through
        /// here, because a kind that varied with the ending is a kind carrying an ending:
        /// the rules layer reads it to know a kickoff and not a first down comes next
        /// (11-3-4), and a stream summed downstream cannot see a try the record filed as
        /// an ordinary pass.
        func recorded(_ ordinary: PlayKind) -> PlayKind { isTry ? .twoPointConversion : ordinary }

        credit(SlotLayout.quarterback, .passer)

        // 1. The pocket. Each rusher works a blocker, and the first one home sets the
        //    clock everything else runs against.
        // Who rushes comes from the package: four in nickel, three in a prevent shell,
        // five off the goal line. It used to be four defensive linemen whatever the
        // defence had actually sent out.
        let front = personnel.front
        let rushers = Array(front.prefix(max(1, min(front.count, Int(defense.rush.rushers)))))
        // Protection is the line, plus a back or tight end kept in when there is one to
        // spare. An empty set has nobody helping, which is the trade the grouping makes.
        let protection = personnel.blockers(includingEligibles: false)
        var pressureAt: Int? = nil
        var pressureBy = PlayerSlot.none

        for (index, rusher) in rushers.enumerated() {
            guard !protection.isEmpty else { break }
            let blocker = protection[min(index, protection.count - 1)]
            // A matchup needs two players. If injuries have emptied a spot, there is no
            // rep to resolve — and recording one would name a slot nobody is standing in,
            // which is a decision point pointing at an uncredited player.
            guard personnel[rusher] != nil, personnel[blocker] != nil else { continue }
            let rush = rating(.powerMove, rusher, personnel, context)
            var block = rating(.passBlock, blocker, personnel, context)
            // A silent count costs a fraction of a beat off the snap. This is the other
            // half of home field: the road offence loses a little protection in a loud
            // stadium, which is why hostile grounds show up in sack rates and not only in
            // false starts.
            if !context.offenseIsHome {
                block -= Double(context.crowdNoise) * 0.045
            }
            // A blitz means somebody is unblocked by construction.
            let edge = defense.rush.isBlitz && index >= protection.count ? 0.35 : 0
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
        //
        // A conversion from the two is not a quick pass that happens to start closer. It
        // is a throw into a phone booth with no grass behind the defence, and a man who
        // catches it a yard short has to get in on his own. Running it as an ordinary
        // four-yard route made every completion a conversion, so the try converted at the
        // completion rate — 66% against a real 48%.
        var depth =
            isTry
            ? RouteDepth(
                yards: 1, timeMillis: 1_500, flightTicks: 3, accuracyKey: .throwAccuracyShort)
            : routeDepth(concept)

        // Where the ball is actually caught. Every route of a kind used to be exactly the
        // same length — a `mediumPass` was ten yards, always — and that is most of why
        // the passing game had no tail: completions piled up in the ten-to-fourteen band
        // and nothing reached forty. A concept has a depth; a route run against a
        // particular coverage, by a particular receiver, does not.
        if !isTry {
            let spread = max(2, abs(depth.yards) / 2 + 2)
            depth.yards += Int(random.next(upperBound: UInt64(spread * 2 + 1))) - spread
        }
        var reads: [(receiver: PlayerSlot, defender: PlayerSlot, separation: Int)] = []

        // Four route runners: the three receivers and the tight end, which is what `11`
        // personnel *is* and what the slot layout says it fields. Taking three dropped
        // the tight end silently — he stood on the field on every snap of every game
        // without ever running a route, being thrown to, or being credited with
        // anything.
        let running = personnel.routeRunners()
        let covering = personnel.coverageDefenders
        for (index, receiver) in running.prefix(4).enumerated() {
            guard !covering.isEmpty else { break }
            let defender = covering[min(index, covering.count - 1)]
            guard personnel[receiver] != nil, personnel[defender] != nil else { continue }
            let route = rating(.routeRunning, receiver, personnel, context)
            let cover = rating(
                defense.coverage.isMan ? .manCoverage : .zoneCoverage, defender, personnel, context)
            let open = contest(route, cover)
            // Centimetres. Wide open is a couple of metres; blanketed is inside one.
            var separation = Int(30 + open * 190 + Double(random.next(upperBound: 60)) - 30)
            // From the two, there is no field to run to and no space behind the defence.
            // Running a conversion through the ordinary passing game converted it at 66%
            // against a real 48%: the throw was easy because the model had not noticed
            // the end zone was the only place to put it.
            if isTry { separation = separation * 3 / 5 }

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

            // Only the fouls whose restrictions start at the snap. Interference needs a
            // forward pass to exist at all (8-5-1), so it waits for the throw.
            if penalty == nil {
                penalty = Penalties.whenBeatenInCoverage(
                    defender: defender, receiver: receiver, separationCentimetres: separation,
                    personnel: personnel, context: context, random: &random)
            }
        }

        // 3. The decision. Pressure that arrives before the route develops is what turns
        //    a read into a sack or a throwaway.
        //
        // A try never gets past this line: its throw is out in 1,500 ms and the first
        // rusher home is never there sooner, so `pressured` is false on every two-point
        // snap whatever the reps did, and the scramble and sack exits below are
        // unreachable for one. They report the try anyway. A resolver whose labelling is
        // right only because of a timing constant is one edit away from being wrong, and
        // the constant is a tuning number rather than a rule.
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
                    carrier: SlotLayout.quarterback, pursuit: SlotLayout.scramblePursuit,
                    personnel: personnel, context: context,
                    // A quarterback who took off runs the same way an outside run does:
                    // towards the boundary, where the play ends with him upright.
                    sideline: sidelineChance(.outsideRun, situation, context),
                    decisions: &decisions, participants: &participants, startTick: 30,
                    random: &random)
                var gained = Int16(
                    max(-2, 2 + Int(random.next(upperBound: 6)) + scramble.extraYards))
                let scores = Int(situation.ballOn) - Int(gained) <= 0
                let dropped =
                    scores
                    ? nil
                    : looseBall(
                        carrier: SlotLayout.quarterback,
                        tackler: participants.first { $0.role == .tackler }?.slot, isSack: false,
                        spot: Int(situation.ballOn) - Int(gained), personnel: personnel,
                        context: context, participants: &participants, random: &random)
                if dropped?.ending == .fumbleLost { gained = 0 }
                return (
                    Outcome(
                        kind: recorded(.scramble),
                        yards: scores ? Int16(situation.ballOn) : gained,
                        endedIn: dropped?.ending ?? (scores ? .touchdown : scramble.ending),
                        participants: participants, penalties: penalty.map { [$0] } ?? [],
                        finalSpot: dropped?.finalSpot, possessionLostAt: dropped?.lostAt,
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

            // The strip sack: he never saw it coming, so it comes out far more often than
            // it does from a ball carrier who knows the hit is arriving.
            let strip =
                inOwnEndZone
                ? nil
                : looseBall(
                    carrier: SlotLayout.quarterback, tackler: pressureBy, isSack: true,
                    spot: Int(situation.ballOn) - Int(loss), personnel: personnel,
                    context: context, participants: &participants, random: &random)

            // A sack is a play worth reacting to by anybody's reckoning, and it could not
            // draw a word after the whistle either.
            if penalty == nil {
                penalty = Penalties.afterThePlay(
                    Outcome(kind: .sack, yards: loss, endedIn: .tackled),
                    personnel: personnel, context: context, random: &random)
            }

            return (
                Outcome(
                    kind: recorded(.sack),
                    yards: strip?.ending == .fumbleLost ? 0 : (inOwnEndZone ? Int16(-room) : loss),
                    endedIn: strip?.ending ?? (inOwnEndZone ? .safety : .tackled),
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    finalSpot: strip?.finalSpot, possessionLostAt: strip?.lostAt,
                    clockRunoff: runoff),
                decisions
            )
        }

        guard let target = best else {
            return (
                Outcome(
                    kind: recorded(.pass), yards: 0, endedIn: .incomplete,
                    passResult: .incomplete,
                    participants: participants),
                decisions
            )
        }

        // Linemen who released to block a run that turned out to be a throw.
        if penalty == nil {
            penalty = Penalties.onLineRelease(
                blockers: protection, isScreen: concept == .screen || concept == .playAction,
                personnel: personnel, context: context, random: &random)
        }

        // 4. The throw, and the ball arriving.
        //
        // Every route runner is already credited as a `.receiver`; the one the ball goes
        // to is upgraded to `.target`. Without this the distinction is unrecoverable
        // downstream — three men look identically involved on every dropback, which
        // makes target share, catch rate and drop rate unanswerable from the stream.
        credit(target.receiver, .target)
        let accuracy = rating(depth.accuracyKey, SlotLayout.quarterback, personnel, context)
        let placement = placement(
            accuracy: accuracy, pressured: pressured,
            conditions: Conditions.throwing(context.weather, depthYards: depth.yards),
            random: &random)
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

        // The ball is in the air, so interference exists now and did not before (8-5-1),
        // and it exists on exactly one matchup: the man the pass was thrown to and the
        // man covering him. The defence's is a spot foul (8-6-1-b) and the spot is where
        // the ball was going, in the offence's frame with zero meaning the end zone.
        //
        // Not on a throw nobody could have reached, though: 8-5-3-c makes contact that
        // would otherwise be interference legal when the pass is clearly uncatchable by
        // the players involved, and `.uncatchable` is the record's name for that throw.
        // The article's exception to its own clause is the offence's blocking downfield
        // (8-3-2, 8-5-4), which is not modelled as an act of its own, so the gate covers
        // both kinds here. Without it a spot foul is handed out at the catch point for
        // contact the rules do not make a foul at all.
        if penalty == nil, placement != .uncatchable {
            penalty = Penalties.onTheThrow(
                defender: target.defender, receiver: target.receiver,
                separationCentimetres: target.separation, routeDepth: depth.yards,
                catchPoint: Int(situation.ballOn) - depth.yards,
                personnel: personnel, context: context, random: &random)
        }

        // The foul is drawn first and the catch resolved with it in hand, which is the
        // order 8-5-1 puts them in: the defence's interference is contact that spoiled
        // the receiver's chance at the ball, so it is the reason the pass was not caught
        // rather than something that happened alongside a catch.
        let catchResult = catchOutcome(
            placement: placement, separation: target.separation,
            hands: rating(.catching, target.receiver, personnel, context),
            ballHawk: rating(.ballHawk, target.defender, personnel, context),
            interferedWith: penalty?.foul == .defensivePassInterference,
            contested: isTry, conditions: Conditions.handling(context.weather),
            random: &random)
        decisions.append(
            .init(
                tick: arrivalTick + 1, kind: .catchAttempt,
                primary: target.receiver, secondary: target.defender,
                detail: catchResult.rawValue, value: Int16(target.separation)))

        let runoff = UInt16(4 + Int(random.next(upperBound: 4)))

        switch catchResult {
        case .intercepted:
            credit(target.defender, .tackler)
            // He catches it and runs it back. Without a return an interception was worth
            // exactly where the throw was caught, and a pick six could not happen at all
            // — the spot was clamped one short of the only value that scores.
            let caught = Int(situation.ballOn) - depth.yards
            let ballHawk = rating(.ballHawk, target.defender, personnel, context)
            let broken = random.nextBool(probability: 0.18 + max(0, (ballHawk - 75) * 0.004))
            let back =
                broken ? Int(random.next(upperBound: 70)) + 20 : Int(random.next(upperBound: 14))
            let spot = UInt8(max(1, min(100, caught + back)))
            return (
                Outcome(
                    kind: recorded(.pass), yards: 0, endedIn: .intercepted,
                    passResult: .intercepted,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    finalSpot: spot, possessionLostAt: UInt8(max(1, min(99, caught))),
                    clockRunoff: runoff),
                decisions
            )

        case .caught, .contestedCatch:
            let afterCatch = yardsAfterCatch(
                carrier: target.receiver, coveredBy: target.defender, personnel: personnel,
                context: context, separation: target.separation,
                sideline: sidelineChance(
                    isTry ? .twoPointPass : concept, situation, context),
                decisions: &decisions,
                participants: &participants, startTick: arrivalTick + 2, random: &random)
            let total: Int = depth.yards + afterCatch.yards
            let reachesEndZone: Bool = Int(situation.ballOn) - total <= 0
            var gained: Int16 = reachesEndZone ? Int16(situation.ballOn) : Int16(total)
            let kind: PlayKind = recorded(.pass)

            // What somebody says once the whistle has gone. Drawn from the run path
            // alone until now, so no completion and no sack in the league ever drew a
            // word afterwards — two thirds of a team's snaps are dropbacks.
            if penalty == nil, !isTry {
                penalty = Penalties.afterThePlay(
                    Outcome(kind: kind, yards: gained, endedIn: afterCatch.ending),
                    personnel: personnel, context: context, random: &random)
            }

            // A receiver can put it on the ground too. A try is left alone: it cannot
            // fumble into anything but a failed try.
            let fumble =
                (reachesEndZone || isTry)
                ? nil
                : looseBall(
                    carrier: target.receiver,
                    tackler: participants.first { $0.role == .tackler }?.slot, isSack: false,
                    spot: Int(situation.ballOn) - total, personnel: personnel, context: context,
                    participants: &participants, random: &random)
            if fumble?.ending == .fumbleLost { gained = 0 }
            let ending: PlayEnding =
                fumble?.ending ?? (reachesEndZone ? .touchdown : afterCatch.ending)
            return (
                Outcome(
                    kind: kind, yards: gained, endedIn: ending, passResult: .complete,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    finalSpot: fumble?.finalSpot, possessionLostAt: fumble?.lostAt,
                    clockRunoff: runoff),
                decisions
            )

        case .dropped, .brokenUp, .uncatchable, .offTarget:
            return (
                Outcome(
                    kind: recorded(.pass), yards: 0, endedIn: .incomplete,
                    passResult: .incomplete,
                    participants: participants, penalties: penalty.map { [$0] } ?? [],
                    clockRunoff: runoff),
                decisions
            )
        }
    }

    // MARK: - Run

    private func run(
        _ concept: PlayConcept,
        _ situation: Situation,
        _ calls: Calls,
        _ context: PlayContext,
        _ personnel: Lineup,
        _ random: inout SplittableRandom,
        isTry: Bool = false
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var decisions: [DecisionPoint] = []
        var participants: [Participation] = []
        var penalty: PenaltyRecord?

        func credit(_ slot: PlayerSlot, _ role: PlayRole) {
            self.credit(slot, role, personnel, into: &participants)
        }

        credit(SlotLayout.back, .rusher)

        // The hole is the sum of the blocks in front of it, against a front committed to
        // stopping the run or not.
        var blockScore = 0.0
        // The line, plus every tight end and fullback on the field. This is what a heavy
        // personnel grouping *is* — more bodies at the point of attack — and with a fixed
        // five-man list an extra tight end did nothing at all.
        let blocking = personnel.blockers(includingEligibles: true)
        let box = personnel.boxDefenders
        for (index, blocker) in blocking.enumerated() {
            guard index < box.count else { break }
            let defender = box[index]
            guard personnel[blocker] != nil, personnel[defender] != nil else { continue }
            let block = rating(.runBlock, blocker, personnel, context)
            let shed = rating(.blockShedding, defender, personnel, context)
            let commitment =
                calls.defense.runFit == .aggressive
                ? 0.18
                : (calls.defense.runFit == .sellOut ? 0.3 : 0)
            let won = random.nextBool(probability: contest(block, shed, edge: -commitment))

            credit(blocker, .blocker)
            // Taking on a block is not making a tackle. Crediting `.tackler` here gave
            // every defensive lineman a tackle on every run before anyone had touched
            // the ball — tackle leaders were four deep in defensive tackles and no
            // linebacker ever made one — and it aimed contact fouls at the first man in
            // this loop rather than at whoever actually made the hit. The tackle
            // sequence names the tackler, and that credit outranks this one.
            credit(defender, .runDefender)
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

        // The count, which is what a run is about before anybody blocks anybody. A
        // defender nobody can block is a free hitter in the hole; a blocker with nobody
        // left to take is a double team. The engine could not see either, because every
        // defence had the same six men in the box and the offence always had the same six
        // blockers.
        let unblocked = max(0, box.count - blocking.count)
        let spare = max(0, blocking.count - box.count)
        let quality =
            Int16(blockScore * 12) + Int16(random.next(upperBound: 30)) - 15
            - Int16(unblocked * 12) + Int16(spare * 6)
        decisions.append(
            .init(
                tick: 10, kind: .holeQuality, primary: SlotLayout.back,
                detail: concept == .insideRun ? 0 : 1, value: quality))

        // Vision turns a hole into yards; a back with none runs into his own linemen.
        let vision = rating(.vision, SlotLayout.back, personnel, context)
        // A flat line through the hole quality made every carry roughly the same, which
        // kept early downs so reliable that third downs were short and converted half
        // the time. Real carries are mostly modest with a fat tail: a hole that really
        // opens is a long run, and that tail is where the yards-per-carry average
        // actually comes from.
        var yards = Int(Double(quality) * 0.075 + (vision - 60) * 0.04 + 1.3)
        yards += Int(random.next(upperBound: 5)) - 2
        // A carry from the two is a play into a phone booth: there is no second level to
        // reach and no grass behind the defence, so the crease pays nothing. That is the
        // run's half of the adjustment the conversion pass carries, and it is the whole
        // of it — the goal-line package the try is now answered with already puts eight
        // men in the box against six or seven blockers, and subtracting yards on top of
        // that counted the same crowd twice: it converted the try at 10% against the
        // pass's 72% on the same eighty games.
        if quality > 30, !isTry {
            // A hole that opens gets him to the second level. It does not by itself make
            // a long run — what does is beating the man waiting there, which the tackle
            // sequence below already decides. Paying the whole bonus here put 19% of
            // carries past ten yards against a real 11%, all of it in the ten-to-twenty
            // band: the blocking was doing work that belongs to the back.
            let crease = Int(quality) / 3
            yards +=
                random.nextBool(probability: 0.36)
                ? Int(random.next(upperBound: UInt64(max(1, crease * 8 / 5))))
                : Int(random.next(upperBound: UInt64(max(1, crease / 5))))
        }

        let tackle = tackleSequence(
            carrier: SlotLayout.back,
            pursuit: concept == .insideRun
                ? SlotLayout.insideRunPursuit : SlotLayout.outsideRunPursuit,
            personnel: personnel,
            context: context,
            sideline: sidelineChance(isTry ? .twoPointRun : concept, situation, context),
            decisions: &decisions, participants: &participants, startTick: 16, random: &random)
        yards += tackle.extraYards

        var gained = Int16(max(-8, min(80, yards)))
        var reachesEndZone = Int(situation.ballOn) - Int(gained) <= 0
        let intoOwnEndZone = Int(situation.ballOn) - Int(gained) >= 100

        // The ball on the ground, before the play is allowed to have been a gain.
        // A try is left alone, exactly as the conversion pass is. 11-3-2-b and 11-3-2-c
        // give the defence its own ways to score on a try, and none of them is enforced
        // yet, so a try that put the ball on the ground here could only be resolved as a
        // failed try — which is a wrong outcome dressed as a right one. It does not
        // fumble at all until the defence's half of the try exists.
        var fumble: LooseBall?
        if !reachesEndZone && !intoOwnEndZone && !isTry {
            fumble = looseBall(
                carrier: SlotLayout.back,
                tackler: participants.first { $0.role == .tackler }?.slot, isSack: false,
                spot: Int(situation.ballOn) - Int(gained), personnel: personnel, context: context,
                participants: &participants, random: &random)
            if fumble?.ending == .fumbleLost {
                gained = 0
                reachesEndZone = false
            }
        }

        if penalty == nil {
            penalty = Penalties.afterThePlay(
                Outcome(
                    kind: isTry ? .twoPointConversion : .rush, yards: gained,
                    endedIn: tackle.ending),
                personnel: personnel, context: context, random: &random)
        }

        // A run that got into space was blocked in space, and that is where a hold in the
        // back comes from. The block that sprang the run is placed halfway along it — a
        // modelling convention, with no draw behind it — and that spot is what the foul
        // is enforced from (14-3-6).
        if penalty == nil, gained >= 5 {
            penalty = Penalties.onDownfieldBlock(
                blockers: blocking, onOffense: true, personnel: personnel, context: context,
                random: &random)
            penalty?.enforcementSpot = UInt8(max(1, Int(situation.ballOn) - Int(gained) / 2))
        }

        // Contact fouls are drawn where the contact happened, on the man who made it.
        if penalty == nil, let tackler = participants.first(where: { $0.role == .tackler })?.slot {
            penalty = Penalties.onContact(
                tackler: tackler, isQuarterback: false, personnel: personnel, context: context,
                random: &random)
        }

        return (
            Outcome(
                kind: isTry ? .twoPointConversion : .rush,
                yards: reachesEndZone ? Int16(situation.ballOn) : gained,
                endedIn: fumble?.ending
                    ?? (reachesEndZone ? .touchdown : (intoOwnEndZone ? .safety : tackle.ending)),
                participants: participants,
                penalties: penalty.map { [$0] } ?? [],
                finalSpot: fumble?.finalSpot, possessionLostAt: fumble?.lostAt,
                clockRunoff: UInt16(5 + Int(random.next(upperBound: 3)))),
            decisions
        )
    }

    // MARK: - Kicks and the return game

    /// A kickoff, and what the man back there does with it.
    ///
    /// **The kick is aimed, and the spot decides what the aim is worth.** Under the
    /// dynamic kickoff there are two kicks and they trade different things: through the
    /// end zone concedes the receiving team's 35 for certainty (2025 rulebook, 6-1-5),
    /// and into the landing zone — the receiving team's 20 out to its goal line
    /// (6-1-2-e) — has to be returned (6-1-4), which is worth about seven yards of field
    /// position and costs a return touchdown once in a while. Which one is called is
    /// `PlayCaller.kicksForTouchback`; what the kicker then does with it is here.
    ///
    /// Everything reads `situation.ballOn`, which is the restraining line as a distance
    /// penalty has moved it (6-1-2-a, 6-1-6-b). That is the whole reason a flag on a
    /// kickoff means anything: from fifteen yards further back the end zone is fifteen
    /// yards further away, and a kick that would have sailed through it comes down short.
    /// This used to be a coin flip that read nothing at all, so a penalty on the kicking
    /// team changed the yard line printed and not one thing about the kick.
    private func kickoff(
        _ situation: Situation, _ calls: Calls, _ context: PlayContext, _ personnel: Lineup,
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var participants = participation(for: SlotLayout.specialist, personnel, role: .kicker)
        let rules = context.rules

        // Yards from the restraining line to the receiving team's goal line: 65 from the
        // ordinary 35, 80 after a safety or a fifteen-yard penalty, 50 with fifteen the
        // other way. Every chance below is written for the ordinary kick and moved from
        // there by the difference, so the spot is a mechanism rather than a caption.
        let carry = Int(situation.ballOn)
        let extraCarryNeeded = Double(
            carry - Int(rules.ballOnFromOwnYard(rules.kickoffFromOwnYard)))

        let leg = rating(.kickPower, SlotLayout.specialist, personnel, context)
        let placement = rating(.kickAccuracy, SlotLayout.specialist, personnel, context)
        // Wind and thin air move a kickoff the way they move any other kick.
        var conditions = 0.0
        if context.weather.windSpeed > 15 { conditions -= 0.10 }
        if context.weather.isIndoors { conditions += 0.04 }

        var decisions: [DecisionPoint] = []
        let aimsDeep = calls.offense.concept == .deepKickoff

        if aimsDeep {
            // Struck to carry through the end zone. A strong leg is what buys it, and
            // fifteen yards further back is most of the way to taking it off the table.
            let clears =
                0.86 + (leg - 68) * 0.010 + conditions - extraCarryNeeded * 0.030
            if random.nextBool(probability: min(0.97, max(0.02, clears))) {
                return (
                    Outcome(
                        kind: .kickoff, yards: 0, endedIn: .touchback,
                        participants: participants),
                    []
                )
            }
            // Short of the intention: it comes down in the landing zone after all, and
            // the coverage unit that expected to be jogging off has a return to make.
            return returned(
                landingAt: landingSpot(rules: rules, random: &random), situation, context,
                personnel, &participants, &decisions, &random)
        }

        // Aimed at the landing zone. Missing it long is the common miss — the ball only
        // has to carry twenty yards further than intended — and the kicker who can take
        // something off it is the one who does not. Missing it short or wide is the rare
        // one, and it is a foul (6-2-4).
        //
        // About one kick in six is missed long, which is where the touchback share of the
        // 2025 season comes from: almost every kick is aimed at the zone, so the share of
        // kickoffs that end in a touchback is very nearly this number
        // (`row:kickoffTouchbacks.2025`). A new mechanism has to be given its constants
        // from somewhere, and the sourced share is the only honest place for this one.
        let tooDeep =
            0.16 - (placement - 68) * 0.004 + (leg - 68) * 0.002 + conditions
            - extraCarryNeeded * 0.010
        if random.nextBool(probability: min(0.60, max(0.005, tooDeep))) {
            return (
                Outcome(kind: .kickoff, yards: 0, endedIn: .touchback, participants: participants),
                []
            )
        }

        let mishit = 0.030 - (placement - 68) * 0.0008 - conditions * 0.20
        if random.nextBool(probability: min(0.20, max(0.004, mishit))) {
            // Out of bounds between the goal lines, or first down on the turf short of
            // the zone. Either way the receiving team is given the ball rather than
            // playing from where it stopped, and the clock never starts because nobody
            // legally touched it in the field of play (4-3-1).
            let short = random.nextBool(probability: 0.45)
            let shortfall = 3 + Int(random.next(upperBound: 14))
            let deadAt = short ? Int(rules.kickoffLandingZoneOwnYard) + shortfall : shortfall
            // Nobody carried it anywhere, so where it died is where the record says it
            // was fielded — the same answer a downed punt gives, and what makes the
            // kick's gross recoverable from the stream.
            let dead = max(1, min(99, min(deadAt, carry)))
            return (
                Outcome(
                    kind: .kickoff, yards: 0, endedIn: short ? .downed : .outOfBounds,
                    participants: participants,
                    finalSpot: UInt8(dead), fieldedAt: Int8(dead), clockRunoff: 0),
                []
            )
        }

        return returned(
            landingAt: landingSpot(rules: rules, random: &random), situation, context, personnel,
            &participants, &decisions, &random)
    }

    /// Where in the landing zone the ball comes down, as the receiving team's own yard.
    ///
    /// Kickers put it deep in the zone, because a ball fielded at the 3 is a longer way
    /// home than one fielded at the 18 — but not so deep that it risks the end zone.
    private func landingSpot(rules: Rules, random: inout SplittableRandom) -> Int {
        let depth = Int(rules.kickoffLandingZoneOwnYard)
        return max(1, depth - 5 - Int(random.next(upperBound: 11)))
    }

    /// A kick that came down in the zone, fielded and run out. `landingAt` is the
    /// receiving team's own yard, which in the kicking team's frame is the same number.
    private func returned(
        landingAt: Int, _ situation: Situation, _ context: PlayContext, _ personnel: Lineup,
        _ participants: inout [Participation], _ decisions: inout [DecisionPoint],
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        // Twenty yards of return from about the 9 is a start near the 29, which is what
        // the sport's average start under this rule looks like. The breakaway chance is
        // the one it always was: the rule changed how many kicks are returned, not what a
        // returner does with one.
        let run = returnRun(
            from: landingAt, average: 20, breakawayChance: 0.0028, personnel: personnel,
            context: context, participants: &participants, decisions: &decisions,
            random: &random)

        // Where he fielded it is where it came down: a kick into the landing zone may not
        // be fair caught, so the returner takes it at the spot rather than choosing one.
        let fielded = Int8(max(-99, min(99, landingAt)))
        if run.scores {
            return (
                Outcome(
                    kind: .kickoff, yards: 0, endedIn: .touchdown, participants: participants,
                    finalSpot: 100, fieldedAt: fielded, clockRunoff: 12),
                decisions
            )
        }
        return (
            Outcome(
                kind: .kickoff, yards: 0, endedIn: .tackled, participants: participants,
                finalSpot: UInt8(max(1, min(99, run.spot))), fieldedAt: fielded,
                clockRunoff: UInt16(6 + run.spot / 12)),
            decisions
        )
    }

    /// A kick kept deliberately short, so the kicking team can fight for it.
    ///
    /// The one play that lets a trailing team get the ball back without a stop, and its
    /// absence meant the last two minutes of a two-score game had no football left in
    /// them.
    private func onsideKick(
        _ situation: Situation, _ context: PlayContext, _ personnel: Lineup,
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var participants = participation(for: SlotLayout.specialist, personnel, role: .kicker)

        // A kick everyone in the stadium knows is coming. Roughly one in nine.
        let recovered = random.nextBool(probability: 0.11)

        // The kicking team may not legally touch it until it has reached the receiving
        // team's restraining line, ten yards in advance of its own (2025 rulebook,
        // 6-1-6-e, 6-1-6-g), so the pile forms there and the ball dies at or just past
        // it. Measured from the restraining line the kick is actually taken from, which a
        // distance penalty moves (6-1-6-b).
        //
        // **One spot, for both sides.** Whoever comes up with it, the ball died in the
        // same place, and `finalSpot` is in the kicking team's frame either way. Flipping
        // it on one branch and not the other put a failed onside kick ten yards behind
        // where a recovered one lay and docked the receiving team the field position the
        // rule gives it.
        let deadAt = Int(situation.ballOn) - 10 - Int(random.next(upperBound: 7))
        let spot = UInt8(max(1, min(99, deadAt)))

        if recovered {
            for slot in SlotLayout.coverageUnit.prefix(2) {
                credit(slot.0, .other, personnel, into: &participants)
            }
            // Dead where it was fallen on, so that is where it was fielded too.
            return (
                Outcome(
                    kind: .kickoff, yards: 0, endedIn: .fumbleRecovered,
                    participants: participants, finalSpot: spot, fieldedAt: Int8(spot),
                    clockRunoff: 5),
                []
            )
        }
        credit(SlotLayout.returner, .returner, personnel, into: &participants)
        return (
            Outcome(
                kind: .kickoff, yards: 0, endedIn: .tackled, participants: participants,
                finalSpot: spot, fieldedAt: Int8(spot), clockRunoff: 5),
            []
        )
    }

    /// A man with the ball in space, and the coverage running at him.
    ///
    /// Shared by both kinds of return because they are the same problem: most are
    /// ordinary, the occasional one is gone. `from` is where he fields it, measured from
    /// his own goal line, and the result is the yard line he reaches in the same frame.
    private func returnRun(
        from start: Int, average: Int, breakawayChance: Double,
        personnel: Lineup, context: PlayContext,
        participants: inout [Participation], decisions: inout [DecisionPoint],
        random: inout SplittableRandom
    ) -> (spot: Int, scores: Bool) {
        let returner =
            personnel[SlotLayout.returner] != nil ? SlotLayout.returner : SlotLayout.secondReturner
        credit(returner, .returner, personnel, into: &participants)

        let burst =
            (context.effective(.speed, for: personnel[returner], onOffense: false)
                + context.effective(.elusiveness, for: personnel[returner], onOffense: false)) / 2

        var gained = average + Int((burst - 68) * 0.22) + Int(random.next(upperBound: 15)) - 7
        decisions.append(
            .init(
                tick: 20, kind: .holeQuality, primary: returner, detail: 2,
                value: Int16(clamping: gained)))

        // He beats the first wave, and then it is a footrace. This is where a return
        // touchdown comes from, and it has to be rare: a house call on one kick in
        // thirty is a different sport.
        if random.nextBool(probability: breakawayChance + max(0, (burst - 80) * 0.0016)) {
            return (100, true)
        }

        // Otherwise somebody on the coverage unit gets him.
        var remaining = SlotLayout.coverageUnit.filter { personnel[$0.0] != nil }
        if let index = random.weightedIndex(remaining.map(\.1)) {
            let tackler = remaining.remove(at: index).0
            credit(tackler, .tackler, personnel, into: &participants)
            let pursuit = context.effective(.pursuit, for: personnel[tackler], onOffense: true)
            gained -= Int((pursuit - 68) * 0.10)
        }

        return (max(1, min(99, start + max(0, gained))), false)
    }

    private func punt(
        _ situation: Situation, _ context: PlayContext, _ personnel: Lineup,
        _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        var participants = participation(for: SlotLayout.specialist, personnel, role: .kicker)
        var decisions: [DecisionPoint] = []

        // The rush at the punter, which the rules protect him from. Drawn here and
        // carried on whatever the punt turns out to be, rather than reported as a play
        // that never happened: the rush is over before the ball comes down, so the punt
        // is a fact the offended team weighs the flag against (14-2, 12-2-12). It
        // used to be `.penaltyOnly`, which gave the punting team the flag every time
        // because there was no punt to decline in favour of.
        let kickerFoul = Penalties.onKick(
            rushers: personnel.front, personnel: personnel, context: context, random: &random)

        // Accuracy is what turns distance into field position: the punter who can place
        // it inside the ten is worth more than the one who simply hits it a long way.
        let placement = rating(.puntAccuracy, SlotLayout.specialist, personnel, context)
        // How far he can hit it at all. This bounds the intent rather than being it: a
        // weak leg from his own end nets short whatever anybody asked for.
        let reach =
            42.0 + (rating(.puntPower, SlotLayout.specialist, personnel, context) - 60)
            * 0.25
        let plan = PuntPlan.chosen(from: situation.ballOn, touch: placement)
        let landing: Int
        if let band = plan.aimedAt {
            let target = band.lowerBound + Int(random.next(upperBound: UInt64(band.count)))
            // The scatter around the target is his touch, and it is not symmetric: the
            // long half of it grows with his leg. That is why a strong leg with poor
            // hands is the man who overkicks a pooch into the end zone and a modest leg
            // with good hands is the one who drops it on the 8.
            let short = max(2, Int(14 - (placement - 40) * 0.20))
            let long = max(1, short + Int((reach - 68) * 0.12))
            let miss = Int(random.next(upperBound: UInt64(short + long + 1))) - long
            // Aiming does not lengthen a leg: he still cannot place it beyond what he can
            // hit, which is what makes a pooch from midfield a different play from a
            // pooch from the opponent's 40.
            landing = max(target + miss, Int(situation.ballOn) - Int(reach) - 7)
        } else {
            let struck = Int(reach) + Int(random.next(upperBound: 14)) - 7
            landing = Int(situation.ballOn) - struck
        }

        // A touchback is now a *miss*: the scatter carried the ball into the end zone
        // (11-6-2-c) and the receivers snap at their 20 (9-5-1 Note a). It used to be
        // what happened whenever the punter was asked to kick from plus territory.
        if landing <= 0 {
            return (
                Outcome(
                    kind: .punt, yards: 0, endedIn: .touchback, participants: participants,
                    penalties: kickerFoul.map { [$0] } ?? [], clockRunoff: 6),
                []
            )
        }

        let pinned = landing <= 12

        // What the man back there does with it. Close to his own goal he lets it go and
        // hopes it bounces; in the middle of the field he catches it and runs.
        let letItGo = pinned ? 0.30 + (placement - 68) * 0.005 : 0.10
        if random.nextBool(probability: min(0.55, max(0.05, letItGo))) {
            // Downed by the coverage team, or run out of bounds — either way the ball is
            // dead where it stopped and nobody returned it.
            let roll = random.next(upperBound: 10)
            let drift = Int(random.next(upperBound: 5))
            var toucher = PlayerSlot.none
            if let index = random.weightedIndex(SlotLayout.coverageUnit.map(\.1)) {
                toucher = SlotLayout.coverageUnit[index].0
                credit(toucher, .other, personnel, into: &participants)
            }

            // A cover man who gets to it first and touches it before the returner does.
            // The receiving team takes the ball at the spot, which is why downing one at
            // the two is a skill and not a guarantee.
            var illegal: PenaltyRecord?
            if personnel[toucher] != nil, random.nextBool(probability: 0.018) {
                illegal = PenaltyRecord(
                    foul: .illegalTouching, offender: toucher, offendingTeam: context.offense,
                    yards: 0, wasAccepted: false)
            }
            // One flag a play, and the rush at the kicker is the one the rules layer can
            // enforce: only the first penalty on a record is enforced, so a second would
            // be dropped in silence.
            let dead = max(1, min(99, landing + drift))
            return (
                Outcome(
                    kind: .punt, yards: 0, endedIn: roll < 6 ? .downed : .outOfBounds,
                    participants: participants,
                    penalties: (kickerFoul ?? illegal).map { [$0] } ?? [],
                    finalSpot: UInt8(dead), fieldedAt: Int8(dead), clockRunoff: 6),
                []
            )
        }

        // Fair catch or return. Hang time buys the coverage team the chance to make him
        // wave it off; a returner with something about him takes it anyway.
        let returner =
            personnel[SlotLayout.returner] != nil ? SlotLayout.returner : SlotLayout.secondReturner
        let nerve = context.effective(.elusiveness, for: personnel[returner], onOffense: false)
        let fairCatch = 0.42 + (placement - 68) * 0.006 - (nerve - 68) * 0.004
        if random.nextBool(probability: min(0.85, max(0.15, fairCatch))) {
            credit(returner, .returner, personnel, into: &participants)
            return (
                Outcome(
                    kind: .punt, yards: 0, endedIn: .fairCatch, participants: participants,
                    penalties: kickerFoul.map { [$0] } ?? [],
                    finalSpot: UInt8(max(1, min(99, landing))),
                    fieldedAt: Int8(max(1, min(99, landing))), clockRunoff: 6),
                []
            )
        }

        let run = returnRun(
            from: landing, average: 9, breakawayChance: 0.009, personnel: personnel,
            context: context, participants: &participants, decisions: &decisions,
            random: &random)

        // Blocks in the back are what bring a return back, and the return team is on the
        // defensive slots because the kicking team has possession. The block is placed
        // halfway along the return, in the kicking team's frame like every other spot —
        // a modelling convention — and the rules flip it into the returners' frame to
        // enforce it (14-3-6).
        var blockBack = Penalties.onDownfieldBlock(
            blockers: SlotLayout.catchPursuit.map(\.0), onOffense: false, personnel: personnel,
            context: context, random: &random)
        let reached = run.scores ? 100 : run.spot
        blockBack?.enforcementSpot = UInt8(max(1, min(99, (landing + reached) / 2)))

        let fielded = Int8(max(1, min(99, landing)))
        if run.scores {
            return (
                Outcome(
                    kind: .punt, yards: 0, endedIn: .touchdown, participants: participants,
                    penalties: (kickerFoul ?? blockBack).map { [$0] } ?? [],
                    finalSpot: 100, fieldedAt: fielded, clockRunoff: 12),
                decisions
            )
        }
        return (
            Outcome(
                kind: .punt, yards: 0, endedIn: .tackled, participants: participants,
                penalties: (kickerFoul ?? blockBack).map { [$0] } ?? [],
                finalSpot: UInt8(max(1, min(99, run.spot))), fieldedAt: fielded,
                clockRunoff: 8),
            decisions
        )
    }

    /// A place kick, and the rush at the kicker the rules protect him from.
    ///
    /// **The kick is resolved first and the flag drawn after it.** The rush happens while
    /// the ball is in the air, so a foul on the kicker does not stop the kick — and
    /// reporting one as `.penaltyOnly` said that it did: a made field goal with roughing
    /// on it erased three points and handed the offence a first down instead. Resolved in
    /// this order the kick is a fact and the flag is a choice on top of it, which is what
    /// 14-2-3 and 12-2-12 need to be able to say anything.
    private func kick(
        _ concept: PlayConcept, _ situation: Situation, _ context: PlayContext,
        _ personnel: Lineup, _ random: inout SplittableRandom
    ) -> (outcome: Outcome, decisions: [DecisionPoint]) {
        let kickerFoul = Penalties.onKick(
            rushers: personnel.front, personnel: personnel, context: context, random: &random)

        let rawLength = context.rules.fieldGoalDistance(ballOn: situation.ballOn)
        let accuracy = rating(.kickAccuracy, SlotLayout.specialist, personnel, context)

        // The league-average kicker's curve, in two segments: near-automatic inside
        // thirty, a gentle slope through the range teams actually kick from, and a
        // steeper fall past the mid-forties. A single line from twenty-five was too
        // steep in the middle — it made forty-somethings 69% against a real 82%, and it
        // ran the extra point through the same slope, so kicks were missed at 15% when
        // the sport misses them at 5%.
        // Wind, cold, snow and thin air, before the curve is consulted. No `rounded()`:
        // these modules link without libm, and `Tools/playsize` is the guard that proves it.
        let carry = Conditions.kickingAdjustment(
            context.weather, altitudeFeet: context.altitudeFeet)
        let length = rawLength - Int(carry + (carry < 0 ? -0.5 : 0.5))
        var chance: Double
        if length <= 30 {
            chance = 0.95
        } else if length <= 45 {
            chance = 0.95 - Double(length - 30) * 0.010
        } else {
            chance = 0.80 - Double(length - 45) * 0.017
        }
        // A try is kicked from the middle of the field by a kicker nobody is trying very
        // hard to block, and the sport converts it at a better rate than a field goal of
        // the same length. Running it through the field-goal curve unmodified is what
        // made extra points a coin-flip-adjacent 85%.
        if concept == .extraPoint { chance += 0.025 }
        // Centred on an average leg, so the curve above *is* the league average rather
        // than a floor everybody beats.
        chance += (accuracy - 68) * 0.004
        if context.weather.precipitation != .none { chance -= 0.03 }

        let good = random.nextBool(probability: min(0.99, max(0.02, chance)))
        return (
            Outcome(
                kind: concept == .extraPoint ? .extraPoint : .fieldGoal, yards: 0,
                endedIn: good ? .fieldGoalGood : .fieldGoalMissed,
                participants: participation(for: SlotLayout.specialist, personnel, role: .kicker),
                penalties: kickerFoul.map { [$0] } ?? [],
                clockRunoff: concept == .extraPoint ? 0 : 5),
            []
        )
    }

    // MARK: - Shared pieces

    /// How hard the man with the ball works to reach the sideline, as a probability the
    /// play ends there rather than in the field.
    ///
    /// Two things decide it, and neither of them used to: the concept, and the clock.
    ///
    /// The concept, because a run outside the tackles is already headed for the boundary
    /// and one between them is twenty-odd yards from it, and because a go route runs the
    /// sideline while a crossing route runs away from it.
    ///
    /// The clock, because of 4-3-2-a: a runner who goes out of bounds normally leaves the
    /// clock to restart on the ready-for-play signal, but after the two-minute warning of
    /// the first half and inside the last five minutes of the second it does not start
    /// again until the snap. That is the whole reason the sideline is worth reaching, and
    /// the same rule read from the other bench is why an offence protecting a lead stays
    /// in. Without it a two-minute drill had no way to stop the clock and a clock-burning
    /// offence had no way to keep it running.
    ///
    /// The per-concept numbers are a modelling convention, not a sourced rate: nothing in
    /// `docs/reference/calibration-sources.md` bands where a play ends laterally.
    private func sidelineChance(
        _ concept: PlayConcept, _ situation: Situation, _ context: PlayContext
    ) -> Double {
        var chance: Double
        switch concept {
        case .outsideRun: chance = 0.26
        case .insideRun: chance = 0.05
        case .screen: chance = 0.20
        case .quickPass: chance = 0.15
        case .mediumPass: chance = 0.12
        // The one dropback whose route tree runs away from the boundary: play-action sells
        // the run and then throws the crosser and the deep over behind it.
        case .playAction: chance = 0.07
        case .deepPass: chance = 0.20
        // From the two there is no field to run to, and the try is untimed anyway
        // (4-3-2-h), so nobody is chasing the clock.
        case .twoPointPass, .twoPointRun, .extraPoint: chance = 0.02
        default: chance = 0.12
        }

        let classified = SituationClass(situation, rules: context.rules)
        if classified.isDesperation {
            // Trailing inside two minutes: he is coached to get out, and takes the
            // sideline over the extra yard.
            chance += 0.22
        } else if classified.isClockBurn {
            // Leading and late: he stays in, and takes the tackle over the sideline.
            chance *= 0.35
        }
        return min(0.75, max(0.01, chance))
    }

    private struct RouteDepth {
        var yards: Int
        let timeMillis: Int
        let flightTicks: Int
        let accuracyKey: RatingKey
    }

    private func routeDepth(_ concept: PlayConcept) -> RouteDepth {
        switch concept {
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
                yards: 12, timeMillis: 3_000, flightTicks: 8, accuracyKey: .throwAccuracyMedium)
        case .deepPass:
            return RouteDepth(
                yards: 20, timeMillis: 3_400, flightTicks: 12, accuracyKey: .throwAccuracyDeep)
        default:
            return RouteDepth(
                yards: 8, timeMillis: 2_200, flightTicks: 5, accuracyKey: .throwAccuracyMedium)
        }
    }

    private func placement(
        accuracy: Double, pressured: Bool, conditions: Double = 0,
        random: inout SplittableRandom
    ) -> BallPlacement {
        var onTarget = 0.34 + (accuracy - 60) * 0.008
        if pressured { onTarget -= 0.16 }
        onTarget -= conditions
        let roll = random.nextDouble()
        if roll < max(0.1, onTarget) { return .onTarget }
        if roll < max(0.1, onTarget) + 0.34 { return .slightlyOff }
        if roll < 0.95 { return .poor }
        return .uncatchable
    }

    /// What became of the throw at the catch point, and whose incompletion it was.
    ///
    /// Three men can be at fault and the record has a label for each: the placement says
    /// whether the ball was one the receiver could have caught, and the separation says
    /// whether the defender could reach it. Reading neither — calling every failed catch
    /// with the receiver open a drop — charged the passer's worst throws to the man they
    /// were thrown at, which is three quarters of all incompletions landing on the
    /// receiver.
    ///
    /// `interferedWith` is a defensive interference foul already drawn on this matchup.
    /// It is the reason the ball was not caught (2025 rulebook, 8-5-1: contact that
    /// spoils an eligible receiver's chance at the ball, from the throw until the ball is
    /// touched), so it settles the catch before anything is drawn: a foul that hindered
    /// him and a ball he caught anyway are two events that cannot both have happened.
    private func catchOutcome(
        placement: BallPlacement, separation: Int, hands: Double, ballHawk: Double,
        interferedWith: Bool = false, contested: Bool = false, conditions: Double = 0,
        random: inout SplittableRandom
    ) -> CatchResult {
        // Ahead of the placement check only for readability: 8-5-3-c means no flag is
        // drawn on an uncatchable ball, so the two cannot both be true.
        if interferedWith { return .brokenUp }
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
        // A throw into the end zone on a conversion has a back line behind it and every
        // defender in a phone booth. Caught less, and picked more.
        if contested { catchChance -= 0.10 }
        catchChance -= conditions * 0.055

        if random.nextBool(probability: min(0.97, max(0.05, catchChance))) {
            return separation < 90 ? .contestedCatch : .caught
        }

        // A bad ball into tight coverage is where interceptions come from — not from a
        // flat per-attempt rate.
        var pickChance = (placement == .poor ? 0.17 : 0.05) + (contested ? 0.02 : 0)
        pickChance += (ballHawk - 60) * 0.002
        pickChance -= Double(separation - 130) * 0.0006
        if random.nextBool(probability: min(0.5, max(0.005, pickChance))) { return .intercepted }

        // Placement decides whose incompletion it is, and only then does separation
        // decide which of the two men at the catch point it belongs to. A poor ball is
        // the throw's: it reached the receiver, so it is not `.uncatchable`, and it was
        // not one he could be expected to catch, so it is not his drop either.
        if placement == .poor { return .offTarget }
        return separation < 110 ? .brokenUp : .dropped
    }

    private func yardsAfterCatch(
        carrier: PlayerSlot, coveredBy: PlayerSlot, personnel: Lineup, context: PlayContext,
        separation: Int, sideline: Double,
        decisions: inout [DecisionPoint], participants: inout [Participation],
        startTick: UInt16, random: inout SplittableRandom
    ) -> (yards: Int, ending: PlayEnding) {
        // Wide open with grass in front of him. This is how a long completion actually
        // happens — a blown coverage, or a receiver simply faster than the man on him —
        // and it has to be drawn on its own. The engine's only route to a long gain was
        // breaking three tackles in a row at nine percent each, a one-in-fifteen-hundred
        // event, and the passing game produced no forty-yard plays at all.
        let speed = context.effective(.speed, for: personnel[carrier], onOffense: true)
        let gone =
            0.046 + max(0, Double(separation - 150)) * 0.00040 + max(0, (speed - 80)) * 0.0030
        if random.nextBool(probability: min(0.10, gone)) {
            credit(coveredBy, .other, personnel, into: &participants)
            decisions.append(
                .init(
                    tick: startTick, kind: .holeQuality, primary: carrier, detail: 3,
                    value: Int16(separation)))
            let burst = 14 + Int((speed - 55) * 0.45) + Int(random.next(upperBound: 38))
            return (max(0, burst), .tackled)
        }

        // The man who was covering him has the first shot, and the help arrives behind.
        let pursuit = [(coveredBy, 5.0)] + SlotLayout.catchPursuit.filter { $0.0 != coveredBy }
        let tackle = tackleSequence(
            carrier: carrier, pursuit: pursuit, personnel: personnel, context: context,
            sideline: sideline, decisions: &decisions,
            participants: &participants, startTick: startTick, random: &random)
        // A receiver who caught it in stride is already past somebody. Separation earned
        // before the catch is worth yards after it.
        let inStride = max(0, separation - 140) / 45
        // What he does with it once it is in his hands. This was a flat draw of nought to
        // two, so yards after the catch averaged about three against a real five, and
        // `elusiveness` did nothing for a receiver — the whole difference between a
        // possession target and one who turns a slant into forty was invisible.
        let openField = context.effective(.elusiveness, for: personnel[carrier], onOffense: true)
        let loose = Int(random.next(upperBound: 3)) + Int((openField - 68) * 0.04)
        return (max(0, loose + inStride + tackle.extraYards), tackle.ending)
    }

    /// Who brought him down, and whether he broke one first.
    ///
    /// The tackler credited here is the one the outcome names. Nothing else can be, and
    /// that is asserted rather than assumed.
    ///
    /// `sideline` is the chance the play ends out of bounds rather than in the field —
    /// see `sidelineChance`. It is drawn on every ending this function produces, the
    /// broken-everybody one included: a breakaway that always ended out of bounds was a
    /// fact about the code.
    private func tackleSequence(
        carrier: PlayerSlot, pursuit: [(PlayerSlot, Double)], personnel: Lineup,
        context: PlayContext, sideline: Double,
        decisions: inout [DecisionPoint], participants: inout [Participation],
        startTick: UInt16, random: inout SplittableRandom
    ) -> (extraYards: Int, ending: PlayEnding) {
        let breakTackle = context.effective(
            .breakTackle, for: personnel[carrier], onOffense: carrier.isOffense)

        var extra = 0
        var tick = startTick
        var broke = 0
        let attempts = 3

        // Drawn without replacement, so a broken tackle brings a different man, and a
        // slot nobody is standing in simply does not appear.
        var remaining = pursuit.filter { personnel[$0.0] != nil }

        for _ in 0..<attempts {
            guard let index = random.weightedIndex(remaining.map(\.1)) else { break }
            let defender = remaining.remove(at: index).0
            guard let id = personnel[defender] else { continue }
            let tackling = context.player(id).map { context.rating(.tackling, of: $0) } ?? 60

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

            credit(defender, broken ? .other : .tackler, personnel, into: &participants)

            if !broken {
                return (extra, random.nextBool(probability: sideline) ? .outOfBounds : .tackled)
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

        // He beat everybody and is eventually run down. Where that happens is drawn like
        // any other tackle: writing `.outOfBounds` here made every breakaway a sideline
        // play by construction, which is a fact about the code rather than about the run.
        return (extra, random.nextBool(probability: sideline) ? .outOfBounds : .tackled)
    }
}
