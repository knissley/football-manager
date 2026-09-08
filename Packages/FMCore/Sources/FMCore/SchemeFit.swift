/// How much a scheme changes what a position needs.
///
/// A scheme does not make players better or worse — it changes **what counts**.
/// A 320-pound mauler is an eighty-five in a gap scheme and a seventy-two in a
/// zone one: the same player, differently useful. That is the entire cost of
/// changing identity, and it is visible on a roster screen the day you do it.
///
/// Modifiers are defined per *component* rather than per family, so six
/// offensive families are combinations rather than six eighteen-position tables.
public enum SchemeFit {

    /// **Additive deltas** on a position's rating weights.
    ///
    /// Deliberately additive rather than multiplicative. A scheme does not only
    /// rescale what already counts — it can make something start counting. A
    /// guard's agility carries no weight at all in a gap scheme and is central
    /// in a zone one, and a multiplier on a zero weight is silently nothing.
    ///
    /// Weights are floored at zero and renormalised afterwards, so a scheme
    /// redistributes emphasis rather than handing out points.
    typealias Modifiers = [RatingKey: Double]

    // MARK: - Components

    static func modifiers(
        _ blocking: RunBlockingScheme, position: Position
    ) -> Modifiers {
        guard
            position.isOffensiveLine || position.group == .backfield
                || position == .tightEnd
        else { return [:] }

        switch blocking {
        case .zone:
            // Reach a shoulder and get to the second level. Mass matters less
            // than being able to move — and movement starts counting at all.
            if position.isOffensiveLine {
                return [
                    .agility: 0.16, .speed: 0.10, .handTechnique: 0.06, .runBlock: 0.04,
                    .strength: -0.12, .blockAnchor: -0.08,
                ]
            }
            // A tight end blocks without a lineman's technique ratings.
            if position == .tightEnd {
                return [.agility: 0.10, .speed: 0.06, .runBlock: 0.04, .strength: -0.08]
            }
            // A fullback is a lead blocker, and carries neither vision nor
            // elusiveness — modifiers naming those would silently do nothing.
            if position == .fullback {
                return [.agility: 0.08, .runBlock: 0.05, .strength: -0.06]
            }
            // The back presses a lane and cuts once, decisively.
            return [.vision: 0.10, .agility: 0.08, .acceleration: 0.06, .breakTackle: -0.06]
        case .gap:
            // Move a man off the ball.
            if position.isOffensiveLine {
                return [
                    .strength: 0.14, .runBlock: 0.10, .blockAnchor: 0.06,
                    .handTechnique: -0.04,
                ]
            }
            if position == .tightEnd {
                return [.strength: 0.10, .runBlock: 0.10, .agility: -0.05]
            }
            if position == .fullback {
                return [.strength: 0.10, .runBlock: 0.08, .hitPower: 0.05, .catching: -0.05]
            }
            return [.breakTackle: 0.10, .strength: 0.08, .carrying: 0.05, .elusiveness: -0.07]
        case .mixed:
            return [:]
        }
    }

    static func modifiers(
        _ passing: PassingIdentity, position: Position
    ) -> Modifiers {
        switch (passing, position) {
        case (.westCoast, .quarterback):
            return [
                .throwAccuracyShort: 0.10, .throwAccuracyMedium: 0.08, .awareness: 0.04,
                .throwPower: -0.07, .throwAccuracyDeep: -0.06,
            ]
        case (.westCoast, .wideReceiver):
            return [
                .routeRunning: 0.10, .catchInTraffic: 0.07, .elusiveness: 0.05,
                .speed: -0.08,
            ]
        case (.westCoast, .tightEnd):
            // A tight end carries no elusiveness rating.
            return [.routeRunning: 0.10, .catchInTraffic: 0.07, .speed: -0.06]

        case (.quickGame, .quarterback):
            return [
                .throwAccuracyShort: 0.14, .awareness: 0.05, .underPressure: -0.06,
                .throwPower: -0.06, .throwAccuracyDeep: -0.07,
            ]
        case (.quickGame, .wideReceiver):
            return [
                .releaseVsPress: 0.10, .routeRunning: 0.08, .elusiveness: 0.05,
                .speed: -0.07,
            ]
        case (.quickGame, .leftTackle), (.quickGame, .rightTackle),
            (.quickGame, .leftGuard), (.quickGame, .rightGuard), (.quickGame, .center):
            // The ball is gone before protection matters much.
            return [.passBlock: -0.08, .blockAnchor: -0.05, .runBlock: 0.08]

        case (.vertical, .quarterback):
            return [
                .throwPower: 0.12, .throwAccuracyDeep: 0.12, .underPressure: 0.04,
                .throwAccuracyShort: -0.10,
            ]
        case (.vertical, .wideReceiver):
            return [
                .speed: 0.12, .acceleration: 0.07, .catchInTraffic: 0.05,
                .routeRunning: -0.08,
            ]
        case (.vertical, .leftTackle), (.vertical, .rightTackle):
            // Shots take time, and somebody has to buy it.
            return [.passBlock: 0.12, .blockAnchor: 0.07, .runBlock: -0.09]

        case (.airRaid, .quarterback):
            return [
                .throwAccuracyMedium: 0.10, .throwAccuracyShort: 0.07, .awareness: 0.05,
                .playAction: -0.04, .elusiveness: -0.04,
            ]
        case (.airRaid, .wideReceiver):
            // Precision and volume, not track speed — the deliberate opposite
            // of a vertical offence.
            return [
                .routeRunning: 0.12, .catching: 0.06, .releaseVsPress: 0.05,
                .speed: -0.08,
            ]
        case (.airRaid, .runningBack):
            return [.catching: 0.14, .elusiveness: 0.05, .carrying: -0.06, .breakTackle: -0.08]
        case (.airRaid, .tightEnd):
            return [.routeRunning: 0.10, .catching: 0.07, .runBlock: -0.12]

        case (.playAction, .quarterback):
            return [
                .playAction: 0.12, .throwAccuracyDeep: 0.06, .throwPower: 0.04,
                .underPressure: -0.04,
            ]
        case (.playAction, .tightEnd):
            return [.runBlock: 0.10, .catchInTraffic: 0.04, .routeRunning: -0.07]

        default:
            return [:]
        }
    }

    static func modifiers(_ front: DefensiveFront, position: Position) -> Modifiers {
        switch (front, position) {
        case (.fourMan, .edge):
            // Beat a tackle one on one, hand in the ground.
            return [.finesseMove: 0.10, .speed: 0.06, .powerMove: 0.04, .blockShedding: -0.07]
        case (.fourMan, .defensiveTackle):
            return [.powerMove: 0.07, .pursuit: 0.04, .strength: -0.05]
        case (.threeMan, .edge):
            // Standing up, with more to do than rush.
            return [
                .blockShedding: 0.12, .strength: 0.08, .finesseMove: -0.10,
                .speed: -0.05,
            ]
        case (.threeMan, .defensiveTackle):
            // Somebody has to hold two blockers.
            return [
                .strength: 0.16, .blockShedding: 0.12, .powerMove: -0.12,
                .pursuit: -0.05,
            ]
        case (.threeMan, .linebacker):
            // Take on blockers and play zone behind it, rather than run and chase.
            return [
                .blockShedding: 0.10, .pursuit: 0.06, .tackling: 0.04,
                .manCoverage: -0.06,
            ]
        default:
            return [:]
        }
    }

    static func modifiers(_ coverage: CoverageShell, position: Position) -> Modifiers {
        switch (coverage, position) {
        case (.manPress, .cornerback):
            return [
                .manCoverage: 0.14, .releaseVsPress: 0.08, .speed: 0.05,
                .zoneCoverage: -0.12,
            ]
        case (.manPress, .safety):
            return [.manCoverage: 0.10, .speed: 0.05, .zoneCoverage: -0.10]
        case (.manPress, .linebacker):
            return [.manCoverage: 0.10, .speed: 0.05, .zoneCoverage: -0.08]

        case (.singleHigh, .safety):
            // One man responsible for everything behind everybody.
            return [.zoneCoverage: 0.10, .speed: 0.07, .awareness: 0.06, .hitPower: -0.03]
        case (.singleHigh, .cornerback):
            return [.manCoverage: 0.07, .zoneCoverage: -0.03]

        case (.quartersMatch, .safety):
            return [.zoneCoverage: 0.12, .awareness: 0.10, .ballHawk: 0.05, .hitPower: -0.04]
        case (.quartersMatch, .cornerback):
            return [.zoneCoverage: 0.14, .awareness: 0.06, .manCoverage: -0.12]
        case (.quartersMatch, .linebacker):
            return [.zoneCoverage: 0.10, .awareness: 0.05, .manCoverage: -0.07]

        case (.twoHighSoft, .cornerback):
            return [.zoneCoverage: 0.12, .tackling: 0.07, .manCoverage: -0.14, .speed: -0.05]
        case (.twoHighSoft, .safety):
            return [
                .zoneCoverage: 0.10, .tackling: 0.06, .awareness: 0.05,
                .manCoverage: -0.09,
            ]
        default:
            return [:]
        }
    }

    static func modifiers(_ pressure: PressureRate, position: Position) -> Modifiers {
        switch (pressure, position) {
        case (.blitzHeavy, .linebacker):
            return [.pursuit: 0.07, .tackling: 0.04, .zoneCoverage: -0.05]
        case (.blitzHeavy, .cornerback):
            // Left alone more often.
            return [.manCoverage: 0.08, .releaseVsPress: 0.04, .zoneCoverage: -0.04]
        case (.conservative, .edge), (.conservative, .defensiveTackle):
            // Four rushers, all game, with nobody helping. Winning matters far
            // more than punishing anybody once you get there.
            return [.finesseMove: 0.07, .powerMove: 0.06, .pursuit: 0.05, .hitPower: -0.08]
        default:
            return [:]
        }
    }

    // MARK: - Combination

    /// Deltas from several components sum. Two schemes that both want agility
    /// want it more than either alone.
    static func combined(_ sets: [Modifiers]) -> Modifiers {
        var result: Modifiers = [:]
        for set in sets {
            for (key, value) in set {
                result[key, default: 0] += value
            }
        }
        return result
    }

    public static func modifiers(
        for position: Position, in scheme: TeamScheme
    ) -> [RatingKey: Double] {
        switch position.side {
        case .offense:
            return combined([
                modifiers(scheme.offense.blocking, position: position),
                modifiers(scheme.offense.passing, position: position),
            ])
        case .defense:
            return combined([
                modifiers(scheme.defense.front, position: position),
                modifiers(scheme.defense.coverage, position: position),
                modifiers(scheme.defense.pressure, position: position),
            ])
        case .specialTeams:
            return [:]
        }
    }

    // MARK: - Fit

    /// A player's overall *as this scheme uses him*.
    ///
    /// Weights are renormalised after modification, so a scheme redistributes
    /// emphasis rather than inflating or deflating everybody.
    public static func effectiveOverall(
        _ ratings: Ratings, at position: Position, in scheme: TeamScheme
    ) -> UInt8 {
        let adjustments = modifiers(for: position, in: scheme)
        guard !adjustments.isEmpty else {
            return PositionWeights.overall(ratings, at: position)
        }

        // The union of what the position normally values and what the scheme
        // adds to it — a delta can introduce a rating that carried no weight.
        var weights: [RatingKey: Double] = [:]
        for (key, baseWeight) in PositionWeights.weights(for: position) {
            weights[key] = baseWeight
        }
        for (key, delta) in adjustments {
            weights[key, default: 0] += delta
        }

        var weighted = 0.0
        var applied = 0.0
        for (key, weight) in weights where weight > 0 {
            guard let value = ratings[key] else { continue }
            weighted += Double(value) * weight
            applied += weight
        }
        guard applied > 0 else { return 0 }
        return UInt8(Rounding.toNearest(weighted / applied, clampedTo: 0...99))
    }

    /// How much better or worse a scheme makes a player, in overall points.
    ///
    /// The number to put on a roster screen: `+3 in zone, -8 in gap`.
    public static func fit(
        _ ratings: Ratings, at position: Position, in scheme: TeamScheme
    ) -> Int {
        Int(effectiveOverall(ratings, at: position, in: scheme))
            - Int(PositionWeights.overall(ratings, at: position))
    }
}

extension Player {
    /// This player's overall as a given scheme would use him.
    public func overall(in scheme: TeamScheme) -> UInt8 {
        SchemeFit.effectiveOverall(ratings, at: position, in: scheme)
    }

    /// How well he suits a scheme, in overall points either way.
    public func schemeFit(_ scheme: TeamScheme) -> Int {
        SchemeFit.fit(ratings, at: position, in: scheme)
    }
}
