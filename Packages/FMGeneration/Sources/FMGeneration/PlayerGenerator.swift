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

    /// Label of the substream a player's untrained ratings are drawn from.
    ///
    /// Split on his identifier rather than drawn from the stream above, so that
    /// giving a man the ratings his position never trained leaves every rating it
    /// did — and his build, his name and everything else drawn after them —
    /// exactly where they were. In a world identifiers are unique. A test that
    /// builds many men on one identifier gives them all the same untrained draws,
    /// so a test that means to sample the untrained table varies the identifier.
    static let untrainedStream: UInt64 = 0x0b_1a_4c

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
    /// Ratings a position trains but does not weigh — a quarterback's stamina —
    /// are drawn independently, so a great player is not automatically great at
    /// everything. Ratings it does not train at all are drawn from `untrained`,
    /// a stream of the player's own, after every trained key and before the
    /// correction: every key is present when the overall is first read, and the
    /// trained draws are exactly what they would be if the untrained ones did not
    /// exist.
    static func ratings(
        position: Position,
        targetOverall: UInt8,
        bias: [RatingKey: Double] = [:],
        using random: inout SplittableRandom,
        untrained: inout SplittableRandom
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

        fillUntrained(&ratings, position: position, using: &untrained)

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

    // MARK: - The untrained keys

    /// Where a rating a position does not train sits.
    ///
    /// Every player carries every key. The ones his position trains are drawn
    /// around his quality above; the rest come from this table, and they are low
    /// on purpose — a lineman's throw is a lineman's throw. What varies is whether
    /// the job *sometimes* asks for the skill: a defender carries what he takes
    /// away, a safety catches what is thrown at him, a receiver is asked to block
    /// on every run, a kicker has punted. Those rows sit above the ones nobody's
    /// job asks for, and spread more widely — 8 against 6 — because a thing a man
    /// has done a little varies more than a thing he has never done.
    ///
    /// Rows match first to last, so a row for particular keys or positions comes
    /// before its family's row for everyone. A key the table does not name for a
    /// position takes its family's row for everyone, which is the family's lowest
    /// centre: nobody is assumed to have picked up what the table did not say he
    /// had. Three keys are not in the table at all — see `fillUntrained`.
    struct UntrainedRow {

        /// Who a row applies to.
        enum Positions {
            case everyone
            case side(Side)
            case groups([PositionGroup])
            case positions([Position])

            func include(_ position: Position) -> Bool {
                switch self {
                case .everyone: return true
                case .side(let side): return position.side == side
                case .groups(let groups): return groups.contains(position.group)
                case .positions(let positions): return positions.contains(position)
                }
            }
        }

        let keys: [RatingKey]
        let positions: Positions
        let centre: Double
        let spread: Double

        init(_ keys: [RatingKey], _ positions: Positions, centre: Double, spread: Double) {
            self.keys = keys
            self.positions = positions
            self.centre = centre
            self.spread = spread
        }

        init(_ family: RatingKey.Family, _ positions: Positions, centre: Double, spread: Double) {
            self.init(family.keys, positions, centre: centre, spread: spread)
        }
    }

    static let untrainedTable: [UntrainedRow] = [
        // Passing. Nobody but a quarterback throws.
        UntrainedRow(.passing, .everyone, centre: 25, spread: 6),

        // Ball carrying. A defender carries what he takes away; a lineman, and anyone
        // else whose position does not train it, has never carried at all.
        UntrainedRow(.ballCarrying, .side(.defense), centre: 35, spread: 8),
        UntrainedRow(.ballCarrying, .everyone, centre: 25, spread: 6),

        // Receiving. A defensive back or a linebacker catches what is thrown at him
        // and runs no routes; nobody else who does not train it does either.
        UntrainedRow(
            [.catching], .groups([.cornerback, .safety, .linebacker]), centre: 40, spread: 8),
        UntrainedRow(.receiving, .everyone, centre: 25, spread: 6),

        // Blocking. A receiver is asked to block on every run; a quarterback, a
        // defender and everyone else who does not train it, rarely.
        UntrainedRow(.blocking, .groups([.receiver]), centre: 35, spread: 8),
        UntrainedRow(.blocking, .everyone, centre: 30, spread: 8),

        // The front seven. Pursuit and hit power follow the athlete and are not here;
        // the pass-rush moves, shedding and tackling nobody outside the front trains.
        UntrainedRow(.frontSeven, .everyone, centre: 25, spread: 6),

        // Coverage. A defensive lineman drops into a zone now and then and into man
        // never; nobody on offence covers anybody.
        UntrainedRow([.zoneCoverage], .groups([.edge, .defensiveInterior]), centre: 30, spread: 8),
        UntrainedRow(.coverage, .everyone, centre: 20, spread: 6),

        // Kicking. A kicker has punted and a punter has kicked; nobody else has done
        // either.
        UntrainedRow([.puntPower, .puntAccuracy], .positions([.kicker]), centre: 45, spread: 8),
        UntrainedRow([.kickPower, .kickAccuracy], .positions([.punter]), centre: 45, spread: 8),
        UntrainedRow(.kicking, .everyone, centre: 15, spread: 6),
    ]

    /// The row that governs `key` at `position`: the first that names both.
    static func untrainedRow(for key: RatingKey, at position: Position) -> UntrainedRow? {
        untrainedTable.first { $0.keys.contains(key) && $0.positions.include(position) }
    }

    /// Noise on an untrained key that follows the athlete rather than the table.
    static let derivedSpread = 6.0

    /// Draw every key `position` does not train.
    ///
    /// Three keys follow the athlete rather than the table, for anyone whose
    /// position does not train them: elusiveness is half his agility with noise on
    /// top, pursuit half his speed and ten, hit power half his strength. A guard is
    /// not elusive because nobody at guard is, and a corner does not hit because
    /// he is not strong — and the general keys those read are drawn before this
    /// runs. The rest are the table's row for the key and the position, and the
    /// floor if no row names them, which a test says none lacks.
    static func fillUntrained(
        _ ratings: inout Ratings, position: Position, using random: inout SplittableRandom
    ) {
        let trained = Set(RatingKey.keys(for: position))
        let floor = Double(Ratings.untrainedFloor)
        for key in RatingKey.allCases where !trained.contains(key) {
            let value: Double
            switch key {
            case .elusiveness:
                value =
                    Double(ratings.value(.agility, or: Ratings.untrainedFloor)) / 2
                    + random.nextGaussian() * derivedSpread
            case .pursuit:
                value = Double(ratings.value(.speed, or: Ratings.untrainedFloor)) / 2 + 10
            case .hitPower:
                value = Double(ratings.value(.strength, or: Ratings.untrainedFloor)) / 2
            default:
                if let row = untrainedRow(for: key, at: position) {
                    value = row.centre + random.nextGaussian() * row.spread
                } else {
                    value = floor
                }
            }
            ratings[key] = UInt8(
                Rounding.toNearest(
                    value,
                    clampedTo: Int(Ratings.range.lowerBound)...Int(Ratings.range.upperBound)))
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
        var untrained = random.split(untrainedStream, id.rawValue)
        var ratingSet = ratings(
            position: position, targetOverall: overall, bias: bias, using: &random,
            untrained: &untrained)

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
        let arrival: (draft: DraftInfo?, firstSeason: Int?)
        if let draft {
            arrival = (draft, draft.season)
        } else if let board {
            arrival = DraftHistory.record(
                for: id, ceiling: ceiling, age: age, season: season, board: board,
                from: random)
        } else {
            // Nobody drafted him and no board says otherwise, so he has not arrived: a
            // prospect in a class that has not been picked from, or a fixture in a test.
            // He used to take the season he was built in, which made every prospect a
            // rookie in the season his class became eligible
            // ([#67](https://github.com/knissley/football-manager/issues/67)).
            arrival = (nil, nil)
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
