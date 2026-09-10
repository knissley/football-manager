/// How much each rating contributes to a player's overall at his position.
///
/// A left tackle's pass blocking matters far more than his agility; a corner
/// lives on coverage. Weights make "overall" a football judgement rather than an
/// average, and they are what let a single number sort a depth chart.
///
/// Every weight set sums to 1 and references only ratings the position actually
/// trains — both asserted in tests, because a weight on an untrained rating
/// would score every player at that position on a number generation draws low.
public enum PositionWeights {

    public static func weights(for position: Position) -> [(RatingKey, Double)] {
        switch position {
        case .quarterback:
            return [
                (.throwAccuracyShort, 0.18), (.awareness, 0.18), (.throwAccuracyMedium, 0.16),
                (.throwPower, 0.12), (.underPressure, 0.12), (.throwAccuracyDeep, 0.10),
                (.elusiveness, 0.05), (.speed, 0.05), (.playAction, 0.04),
            ]
        case .runningBack:
            return [
                (.vision, 0.18), (.breakTackle, 0.16), (.elusiveness, 0.16), (.speed, 0.16),
                (.carrying, 0.12), (.acceleration, 0.10), (.agility, 0.06), (.catching, 0.04),
                (.passBlock, 0.02),
            ]
        case .fullback:
            return [
                (.runBlock, 0.30), (.breakTackle, 0.18), (.strength, 0.18), (.carrying, 0.12),
                (.hitPower, 0.12), (.catching, 0.10),
            ]
        case .wideReceiver:
            return [
                (.routeRunning, 0.22), (.catching, 0.20), (.speed, 0.18),
                (.catchInTraffic, 0.12), (.releaseVsPress, 0.10), (.acceleration, 0.10),
                (.agility, 0.05), (.elusiveness, 0.03),
            ]
        case .tightEnd:
            return [
                (.catching, 0.18), (.runBlock, 0.16), (.routeRunning, 0.16),
                (.catchInTraffic, 0.14), (.passBlock, 0.10), (.strength, 0.10),
                (.speed, 0.10), (.releaseVsPress, 0.06),
            ]
        case .leftTackle, .rightTackle:
            return [
                (.passBlock, 0.28), (.blockAnchor, 0.20), (.handTechnique, 0.18),
                (.runBlock, 0.16), (.strength, 0.10), (.agility, 0.05), (.awareness, 0.03),
            ]
        case .leftGuard, .rightGuard, .center:
            return [
                (.runBlock, 0.26), (.passBlock, 0.22), (.strength, 0.18),
                (.blockAnchor, 0.16), (.handTechnique, 0.12), (.awareness, 0.06),
            ]
        case .edge:
            return [
                (.finesseMove, 0.20), (.powerMove, 0.18), (.blockShedding, 0.16),
                (.pursuit, 0.12), (.tackling, 0.12), (.speed, 0.10), (.strength, 0.07),
                (.hitPower, 0.05),
            ]
        case .defensiveTackle:
            return [
                (.powerMove, 0.22), (.blockShedding, 0.22), (.strength, 0.18),
                (.tackling, 0.14), (.finesseMove, 0.12), (.pursuit, 0.08), (.hitPower, 0.04),
            ]
        case .linebacker:
            return [
                (.tackling, 0.20), (.pursuit, 0.16), (.zoneCoverage, 0.14),
                (.blockShedding, 0.12), (.awareness, 0.12), (.manCoverage, 0.10),
                (.speed, 0.10), (.hitPower, 0.06),
            ]
        case .cornerback:
            return [
                (.manCoverage, 0.26), (.speed, 0.18), (.zoneCoverage, 0.16), (.ballHawk, 0.12),
                (.acceleration, 0.10), (.agility, 0.08), (.tackling, 0.06),
                (.releaseVsPress, 0.04),
            ]
        case .safety:
            return [
                (.zoneCoverage, 0.20), (.tackling, 0.16), (.awareness, 0.16),
                (.manCoverage, 0.12), (.ballHawk, 0.12), (.speed, 0.12), (.pursuit, 0.08),
                (.hitPower, 0.04),
            ]
        case .kicker:
            return [(.kickAccuracy, 0.60), (.kickPower, 0.40)]
        case .punter:
            return [(.puntAccuracy, 0.55), (.puntPower, 0.45)]
        case .longSnapper:
            return [(.awareness, 0.60), (.runBlock, 0.40)]
        }
    }

    /// A player's overall at a position, on the same 0...99 scale as a rating.
    ///
    /// Every weighted key counts, whatever position the player trained for. A
    /// receiver at quarterback is scored on the throwing ratings he carries low,
    /// which is what makes him a poor quarterback. This used to drop the weight of
    /// any key he lacked and renormalise over the rest, and that scored him on his
    /// awareness and speed alone — a better quarterback than a receiver.
    ///
    /// A generated set is complete, so an incomplete one is hand-built and the
    /// read is asserted in debug; a release build scores the missing key at
    /// `Ratings.untrainedFloor`, which is a bad player rather than a plausible one.
    public static func overall(_ ratings: Ratings, at position: Position) -> UInt8 {
        assert(ratings.isComplete, "overall at \(position) read an incomplete rating set")
        var weighted = 0.0
        var applied = 0.0
        for (key, weight) in weights(for: position) {
            weighted += Double(ratings.value(key, or: Ratings.untrainedFloor)) * weight
            applied += weight
        }
        guard applied > 0 else { return 0 }
        let scaled = weighted / applied
        return UInt8(max(0, min(99, Int(scaled + 0.5))))
    }
}
