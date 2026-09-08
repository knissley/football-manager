import FMCore
import FMRandom

/// Typical build by position, and how combine numbers follow from ratings.
///
/// Measurables sit outside the scouting fog, so they have to be *plausible* —
/// a 5-10 left tackle or a 340-pound corner would read as a generator failure
/// long before anyone checked a rating.
enum PhysicalTemplates {

    struct Build {
        let heightInches: Double
        let heightSpread: Double
        let weightPounds: Double
        let weightSpread: Double
    }

    /// Where a position's athletic attributes centre, on the 0...99 scale.
    ///
    /// General attributes are *absolute*, not relative to the position: a
    /// tackle's speed rating genuinely is around 45, and a corner's around 85.
    /// Generating them around a player's overall instead produced 309-pound
    /// tackles running 4.5 forties, because a good lineman was being made a good
    /// athlete in the abstract rather than a good lineman.
    struct Athleticism {
        let speed: Double
        let acceleration: Double
        let agility: Double
        let strength: Double
    }

    static func athleticism(for position: Position) -> Athleticism {
        switch position {
        case .wideReceiver, .cornerback:
            return Athleticism(speed: 85, acceleration: 85, agility: 85, strength: 52)
        case .runningBack, .safety:
            return Athleticism(speed: 80, acceleration: 82, agility: 82, strength: 60)
        case .tightEnd:
            return Athleticism(speed: 68, acceleration: 68, agility: 65, strength: 74)
        case .linebacker:
            return Athleticism(speed: 70, acceleration: 72, agility: 72, strength: 70)
        case .edge:
            return Athleticism(speed: 68, acceleration: 74, agility: 70, strength: 78)
        case .quarterback:
            return Athleticism(speed: 60, acceleration: 62, agility: 64, strength: 58)
        case .fullback:
            return Athleticism(speed: 58, acceleration: 62, agility: 56, strength: 78)
        case .defensiveTackle:
            return Athleticism(speed: 42, acceleration: 52, agility: 46, strength: 88)
        case .leftTackle, .rightTackle:
            return Athleticism(speed: 38, acceleration: 48, agility: 50, strength: 85)
        case .leftGuard, .rightGuard, .center:
            return Athleticism(speed: 34, acceleration: 46, agility: 43, strength: 88)
        case .kicker, .punter, .longSnapper:
            return Athleticism(speed: 38, acceleration: 42, agility: 44, strength: 45)
        }
    }

    static func build(for position: Position) -> Build {
        switch position {
        case .quarterback:
            return Build(heightInches: 75, heightSpread: 1.6, weightPounds: 222, weightSpread: 10)
        case .runningBack:
            return Build(heightInches: 70, heightSpread: 1.5, weightPounds: 214, weightSpread: 12)
        case .fullback:
            return Build(heightInches: 72, heightSpread: 1.3, weightPounds: 245, weightSpread: 10)
        case .wideReceiver:
            return Build(heightInches: 73, heightSpread: 2.0, weightPounds: 200, weightSpread: 13)
        case .tightEnd:
            return Build(heightInches: 77, heightSpread: 1.4, weightPounds: 250, weightSpread: 12)
        case .leftTackle, .rightTackle:
            return Build(heightInches: 78, heightSpread: 1.3, weightPounds: 313, weightSpread: 12)
        case .leftGuard, .rightGuard:
            return Build(heightInches: 77, heightSpread: 1.2, weightPounds: 318, weightSpread: 12)
        case .center:
            return Build(heightInches: 76, heightSpread: 1.2, weightPounds: 305, weightSpread: 11)
        case .edge:
            return Build(heightInches: 76, heightSpread: 1.5, weightPounds: 262, weightSpread: 14)
        case .defensiveTackle:
            return Build(heightInches: 75, heightSpread: 1.4, weightPounds: 308, weightSpread: 16)
        case .linebacker:
            return Build(heightInches: 74, heightSpread: 1.4, weightPounds: 238, weightSpread: 11)
        case .cornerback:
            return Build(heightInches: 71, heightSpread: 1.6, weightPounds: 193, weightSpread: 10)
        case .safety:
            return Build(heightInches: 73, heightSpread: 1.4, weightPounds: 207, weightSpread: 10)
        case .kicker, .punter:
            return Build(heightInches: 73, heightSpread: 1.8, weightPounds: 200, weightSpread: 14)
        case .longSnapper:
            return Build(heightInches: 74, heightSpread: 1.5, weightPounds: 245, weightSpread: 12)
        }
    }

    /// Combine numbers derived from the ratings they measure, plus noise.
    ///
    /// The noise is the point. A workout that perfectly predicted a rating would
    /// make scouting trivial; one that predicted nothing would make the combine
    /// pointless. Testing tells you something real and incomplete, which is why
    /// a riser can be both genuine and a mistake.
    static func combine(
        ratings: Ratings, weightPounds: UInt16, using random: inout SplittableRandom
    ) -> (forty: UInt16, vertical: UInt16, broad: UInt16, threeCone: UInt16, bench: UInt8) {
        let speed = Double(ratings.value(.speed, or: 50))
        let strength = Double(ratings.value(.strength, or: 50))
        let agility = Double(ratings.value(.agility, or: 50))
        let acceleration = Double(ratings.value(.acceleration, or: 50))

        // Speed sets the base; weight is a real and separate penalty. Two men
        // with the same speed rating do not run the same time if one of them is
        // 120 pounds heavier, and omitting that term produced 300-pound linemen
        // in the 4.5s.
        let weightPenalty = (Double(weightPounds) - 220.0) * 0.0022
        let fortySeconds =
            5.40 - speed * 0.011 + weightPenalty + random.nextGaussian() * 0.045
        let vertical = 20.0 + (speed * 0.10) + (acceleration * 0.09) + random.nextGaussian() * 1.6
        let broad = 90.0 + (speed * 0.16) + (acceleration * 0.14) + random.nextGaussian() * 3.0
        let threeCone = 8.10 - agility * 0.0105 + random.nextGaussian() * 0.08
        // Heavier players bench more for the same rating.
        let weightBonus = (Double(weightPounds) - 240.0) * 0.02
        let bench = 4.0 + strength * 0.36 + weightBonus + random.nextGaussian() * 2.2

        return (
            forty: UInt16(Rounding.toNearest(fortySeconds * 100, clampedTo: 415...600)),
            vertical: UInt16(Rounding.toNearest(vertical * 10, clampedTo: 200...480)),
            broad: UInt16(Rounding.toNearest(broad, clampedTo: 80...150)),
            threeCone: UInt16(Rounding.toNearest(threeCone * 100, clampedTo: 630...880)),
            bench: UInt8(Rounding.toNearest(bench, clampedTo: 0...55))
        )
    }
}
