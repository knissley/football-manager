import FMCore
import FMRandom

/// Builds players.
///
/// The caller decides *how good* a player should be capable of becoming; this
/// decides everything else. Roster construction knows it needs an 88-ceiling
/// starter and a 68-ceiling backup, and asks for them.
public enum PlayerGenerator {

    /// Age at which a player is treated as arriving in the league.
    static let entryAge = 22

    /// How far below his ceiling a typical newcomer starts.
    static let typicalRookieGap = 14.0

    /// Development traits are drawn to these frequencies.
    ///
    /// Star developers are rare on purpose: they are the players who actually
    /// leap, and a league where leaps are common is a league that inflates.
    static func developmentTrait(using random: inout SplittableRandom) -> DevelopmentTrait {
        switch random.next(upperBound: 100) {
        case ..<20: return .slow
        case ..<75: return .normal
        case ..<95: return .quick
        default: return .star
        }
    }

    /// Where a player of this age sits relative to his ceiling.
    ///
    /// Young players are short of it, prime players reach it, and older players
    /// fall back from it. Nobody is ever above it
    /// ([decision 100](../../../../docs/design-decisions.md)).
    static func currentOverall(
        ceiling: UInt8, age: Int, trait: DevelopmentTrait, group: PositionGroup,
        rookieGap: Double
    ) -> UInt8 {
        let peak = Double(group.peakAge)
        let entry = Double(entryAge)
        let ageValue = Double(age)

        let progress: Double
        if ageValue <= entry {
            // A player at or below entry age has had no professional development at all,
            // so he sits a full rookie gap below his ceiling. Being a year young is not a
            // reason to be further behind than a rookie: the gap is what separates
            // arriving from arrived, and there is nothing below arriving.
            //
            // This branch used to compute a taper — `max(0, 1 - (entry - age) * 0.25)` —
            // and then multiply it by zero, so it read as though a nineteen-year-old were
            // handled differently from a twenty-two-year-old and was not.
            progress = 0
        } else if ageValue >= peak {
            progress = 1
        } else {
            let linear = (ageValue - entry) / max(1, peak - entry)
            progress = min(1, linear * trait.growthRate)
        }

        var overall = Double(ceiling) - rookieGap * (1 - progress)

        if ageValue > peak {
            overall -= group.declinePerSeason * (ageValue - peak)
        }

        return UInt8(Rounding.toNearest(overall, clampedTo: 20...Int(ceiling)))
    }

    /// Ratings that aggregate to `targetOverall` at `position`.
    ///
    /// Each rating is drawn around the target and then the weighted ones are
    /// corrected so the overall lands where it was asked to. Without the
    /// correction, noise on individual ratings biases the aggregate and a league
    /// generated to average 72 arrives averaging something else.
    ///
    /// Ratings a position carries but does not weigh — a quarterback's stamina —
    /// are drawn independently, so a great player is not automatically great at
    /// everything.
    static func ratings(
        position: Position,
        targetOverall: UInt8,
        bias: [RatingKey: Double] = [:],
        using random: inout SplittableRandom
    ) -> Ratings {
        let weighted = Dictionary(
            PositionWeights.weights(for: position), uniquingKeysWith: { first, _ in first })
        let target = Double(targetOverall)
        let athletic = PhysicalTemplates.athleticism(for: position)

        var ratings = Ratings()
        for key in RatingKey.keys(for: position) {
            let value: Double
            if let centre = athleticCentre(key, athletic) {
                // Athletic attributes blend a position-absolute centre with the
                // player's quality, in proportion to how much the position
                // actually lives on that attribute.
                //
                // A corner's speed tracks his overall almost exactly — a slow
                // corner is a bad corner. A quarterback's barely does: speed is
                // five percent of playing the position, so an excellent pocket
                // passer should not arrive with a receiver's forty time. And a
                // tackle's does not track it at all.
                let share = min(1.0, (weighted[key] ?? 0) / 0.15)
                value = centre * (1 - share) + target * share + random.nextGaussian() * 6.0
            } else if weighted[key] != nil {
                value = target + random.nextGaussian() * 8.0
            } else {
                // Everything else: loosely related to quality, widely spread.
                value = 52 + target * 0.28 + random.nextGaussian() * 10.0
            }
            // A scheme bias moves what kind of player this is, not how good he
            // is: the correction below still lands his overall on target, so
            // fitting the scheme shows up as a bonus in that scheme rather than
            // as free rating points.
            ratings[key] = UInt8(
                Rounding.toNearest(value + (bias[key] ?? 0), clampedTo: 20...99))
        }

        // Correct the weighted ratings so the aggregate lands on target.
        for _ in 0..<4 {
            let actual = Int(PositionWeights.overall(ratings, at: position))
            let delta = Int(targetOverall) - actual
            if delta == 0 { break }
            for (key, _) in PositionWeights.weights(for: position) {
                guard let current = ratings[key] else { continue }
                ratings[key] = UInt8(
                    Rounding.toNearest(Double(Int(current) + delta), clampedTo: 20...99))
            }
        }

        return ratings
    }

    /// Walk the weighted ratings down until the overall sits at or below the
    /// ceiling. Bounded, and in practice runs at most once or twice.
    static func enforceCeiling(_ ratings: inout Ratings, position: Position, ceiling: UInt8) {
        for _ in 0..<8 {
            guard PositionWeights.overall(ratings, at: position) > ceiling else { return }
            for (key, _) in PositionWeights.weights(for: position) {
                guard let current = ratings[key], current > 20 else { continue }
                ratings[key] = current - 1
            }
        }
    }

    private static func athleticCentre(
        _ key: RatingKey, _ athletic: PhysicalTemplates.Athleticism
    ) -> Double? {
        switch key {
        case .speed: return athletic.speed
        case .acceleration: return athletic.acceleration
        case .agility: return athletic.agility
        case .strength: return athletic.strength
        default: return nil
        }
    }

    /// A complete player.
    public static func player(
        id: PlayerID,
        position: Position,
        targetCeiling: UInt8,
        age: Int,
        season: Int,
        colleges: [College],
        draft: DraftInfo? = nil,
        board: DraftHistory.Board? = nil,
        scheme: TeamScheme? = nil,
        using random: inout SplittableRandom
    ) -> Player {
        let ceiling = UInt8(
            Rounding.toNearest(
                Double(targetCeiling) + random.nextGaussian() * 3.0, clampedTo: 40...99))
        let trait = developmentTrait(using: &random)
        let rookieGap = max(4, typicalRookieGap + random.nextGaussian() * 4.0)

        let overall = currentOverall(
            ceiling: ceiling, age: age, trait: trait, group: position.group, rookieGap: rookieGap)

        let bias =
            scheme.map { SchemeIdentity.ratingBias(for: position, in: $0) } ?? [:]
        var ratingSet = ratings(
            position: position, targetOverall: overall, bias: bias, using: &random)

        // The correction loop converges on the target, but `overall` is a
        // *rounded* weighted mean, so it can settle a point high. The ceiling is
        // not a target to approach — it is the invariant the whole development
        // design rests on (decision 100), so it is enforced rather than
        // approximated.
        enforceCeiling(&ratingSet, position: position, ceiling: ceiling)

        let build = PhysicalTemplates.build(for: position)
        let height = UInt8(
            Rounding.toNearest(
                build.heightInches + random.nextGaussian() * build.heightSpread,
                clampedTo: 64...82))
        let weight = UInt16(
            Rounding.toNearest(
                build.weightPounds + random.nextGaussian() * build.weightSpread,
                clampedTo: 150...380))
        let combine = PhysicalTemplates.combine(
            ratings: ratingSet, weightPounds: weight, using: &random)

        let college =
            colleges.isEmpty
            ? NameGenerator.college(using: &random)
            : colleges[Int(random.next(upperBound: UInt64(colleges.count)))]

        // How he arrived. Drawn from his own substream inside `DraftHistory` rather than
        // from the stream above, so giving a world a past leaves every rating in it
        // exactly where it was.
        let arrival: (draft: DraftInfo?, firstSeason: Int)
        if let draft {
            arrival = (draft, draft.season)
        } else if let board {
            arrival = DraftHistory.record(
                for: id, ceiling: ceiling, age: age, season: season, board: board,
                from: random)
        } else {
            // Nobody drafted him and no board says otherwise, so he is arriving now: a
            // prospect in a class that has not been picked from, or a fixture in a test.
            arrival = (nil, season)
        }

        return Player(
            id: id,
            name: NameGenerator.personName(using: &random),
            birthSeason: season - age,
            college: college,
            draft: arrival.draft,
            firstSeason: arrival.firstSeason,
            position: position,
            physical: PhysicalProfile(
                heightInches: height,
                weightPounds: weight,
                fortyYardDash: combine.forty,
                verticalJump: combine.vertical,
                broadJump: combine.broad,
                threeCone: combine.threeCone,
                benchReps: combine.bench
            ),
            ratings: ratingSet,
            hidden: HiddenAttributes(
                ceiling: ceiling,
                developmentTrait: trait,
                workEthic: UInt8(
                    Rounding.toNearest(60 + random.nextGaussian() * 15, clampedTo: 20...99)),
                durability: UInt8(
                    Rounding.toNearest(65 + random.nextGaussian() * 14, clampedTo: 20...99))
            )
        )
    }
}
