import FMCore
import FMRandom

/// Builds draft classes, and the college pipeline they arrive through.
///
/// Initial generation and the yearly intake only. Nothing here decides who gets picked
/// or what anybody thinks of a prospect: a board is somebody's opinion, and scouting
/// owns that ([draft-and-scouting.md](../../../../docs/draft-and-scouting.md)).
public enum DraftClassGenerator {

    // MARK: - Class strength

    /// Strengths for a run of consecutive classes, mean-reverting.
    ///
    /// A class is drawn against the trailing few years rather than independently, so a
    /// loaded year makes the next few likelier to be thin and the league's talent
    /// oscillates around a fixed mean instead of drifting. Reversion is spread over a
    /// window rather than a single year: subtracting last year alone would produce a
    /// tidy alternation nobody would believe.
    ///
    /// Deterministic in the seed and the season range, so the same world always has the
    /// same good and bad years.
    public static func strengths(
        count: Int, using random: inout SplittableRandom
    ) -> [ClassStrength] {
        precondition(count >= 0, "cannot generate a negative number of classes")

        let window = 3
        // Strong enough that the years after a loaded class are visibly thinner, and
        // well under 1 so the series stays stationary rather than oscillating.
        let reversion = 0.6
        let shock = 2.4

        var overalls: [Double] = []
        overalls.reserveCapacity(count)

        for index in 0..<count {
            let recent = overalls.suffix(window)
            let trailing = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
            overalls.append(random.nextGaussian() * shock - reversion * trailing)
            _ = index
        }

        return overalls.map { overall in
            ClassStrength(overall: overall, byGroup: shape(using: &random))
        }
    }

    /// A class's *shape*: which groups this year is rich and poor at.
    ///
    /// Zero-sum by construction, so shape redistributes talent within a class and only
    /// `overall` moves the total. Keeping the two separable is what lets the
    /// conservation law be asserted on one number.
    private static func shape(using random: inout SplittableRandom) -> [PositionGroup: Double] {
        let groups = PositionGroup.allCases.sorted { $0.rawValue < $1.rawValue }
        guard groups.count >= 2 else { return [:] }

        var offsets: [PositionGroup: Double] = [:]
        // One or two groups stand out in a given year; the rest absorb the difference.
        let standouts = 1 + Int(random.next(upperBound: 2))
        var total = 0.0

        for _ in 0..<standouts {
            let group = groups[Int(random.next(upperBound: UInt64(groups.count)))]
            guard offsets[group] == nil else { continue }
            let offset =
                random.nextDouble(in: 1.5..<4.0) * (random.nextBool(probability: 0.5) ? 1 : -1)
            offsets[group] = offset
            total += offset
        }

        let others = groups.filter { offsets[$0] == nil }
        guard !others.isEmpty else { return offsets }
        let correction = -total / Double(others.count)
        for group in others {
            offsets[group] = correction
        }
        return offsets
    }

    // MARK: - Production

    /// What a prospect's numbers looked like in one college season.
    ///
    /// Production is ability *plus independent error*, never a restatement of it. Three
    /// things pull it away from the truth: the team around him, how much he played, and
    /// whether the system flatters him. That is what a scout who "distrusts small-school
    /// production" is distrusting, and without it there is nothing to be wrong about.
    public static func production(
        season: Int,
        collegeYear: CollegeYear,
        currentAbility: UInt8,
        teamQuality: UInt8,
        usage: UInt8,
        using random: inout SplittableRandom
    ) -> ProductionProfile {
        // Centred on fifty and stretched, rather than sitting on top of the overall
        // rating. Sharing a scale with `overall` made every good prospect read in the
        // nineties, so the number stopped telling anyone apart at exactly the end of
        // the board where telling people apart is the whole job.
        let ability = 50 + (Double(currentAbility) - 68) * 1.4

        // A good player on a bad team puts up ordinary numbers; a limited one in the
        // right system puts up numbers he will never repeat again.
        let context = (Double(teamQuality) - 55) * 0.20
        let opportunity = (Double(usage) - 55) * 0.24
        let noise = random.nextGaussian() * 8.0

        let score = ability + context + opportunity + noise
        return ProductionProfile(
            season: season,
            collegeYear: collegeYear,
            productionScore: UInt8(Rounding.toNearest(score, clampedTo: 1...100)),
            usage: usage,
            teamQuality: teamQuality)
    }

    // MARK: - Red flags

    /// Concerns a prospect actually carries, whether or not anybody knows yet.
    ///
    /// Severity is truth and visibility is how hard it is to find. Most flags are minor
    /// and well known; the interesting tail is the serious one nobody has surfaced,
    /// which is what a slide for no visible reason is made of.
    public static func flags(using random: inout SplittableRandom) -> [RedFlag] {
        guard random.nextBool(probability: 0.22) else { return [] }

        let count = random.nextBool(probability: 0.18) ? 2 : 1
        var flags: [RedFlag] = []
        var kinds: Set<RedFlagKind> = []
        let all = RedFlagKind.allCases.sorted { $0.rawValue < $1.rawValue }

        for _ in 0..<count {
            let kind = all[Int(random.next(upperBound: UInt64(all.count)))]
            guard kinds.insert(kind).inserted else { continue }

            // Severity is skewed low: most concerns are noise, and a serious one has to
            // stay rare enough that finding one matters.
            let rawSeverity = random.nextGaussian() * 18 + 42
            let severity = UInt8(Rounding.toNearest(rawSeverity, clampedTo: 1...100))
            // Visibility is independent of severity. That independence is the design:
            // correlating them would mean a bad problem is always an obvious one.
            let visibility = UInt8(random.nextInt(in: 10...95))
            flags.append(RedFlag(kind: kind, severity: severity, visibility: visibility))
        }
        return flags
    }
}

// MARK: - The pipeline

extension DraftClassGenerator {

    /// A class and the players in it.
    ///
    /// Players are returned alongside the class for the same reason teams are returned
    /// alongside a league: a `Prospect` holds a `PlayerID`, so the college record and
    /// the person cannot disagree about who he is.
    public struct GeneratedClass: Sendable {
        public let draftClass: DraftClass
        public let players: [Player]

        public func player(_ id: PlayerID) -> Player? {
            players.first { $0.id == id }
        }
    }

    /// How many prospects a class holds, and how the pipeline is shaped.
    public struct ClassShape: Sendable, Hashable {

        /// Rounds in the draft. Picks are `rounds × teams`.
        public let rounds: Int
        /// Prospects per pick. Above one so undrafted players exist and a late gem is
        /// findable; a class that exactly fills the board has no bottom to it.
        public let prospectsPerPick: Double
        /// How many classes ahead are visible. Three means you have watched this year's
        /// seniors since they were sophomores, which is what multi-year scouting needs.
        public let seasonsVisible: Int

        public init(rounds: Int = 7, prospectsPerPick: Double = 1.5, seasonsVisible: Int = 3) {
            self.rounds = rounds
            self.prospectsPerPick = prospectsPerPick
            self.seasonsVisible = seasonsVisible
        }

        public static let standard = ClassShape()
        /// Small enough to inspect by eye and to keep tests quick.
        public static let compact = ClassShape(rounds: 4, prospectsPerPick: 1.4, seasonsVisible: 3)

        public func prospectCount(teams: Int) -> Int {
            max(
                1,
                Rounding.toNearest(Double(rounds * teams) * prospectsPerPick, clampedTo: 1...20_000)
            )
        }
    }

    /// Every class currently visible, oldest first.
    ///
    /// The class drafted in `firstDraftSeason` is made of players who are seniors now;
    /// the class after it is today's juniors, and so on. Generating them together is
    /// what lets a prospect be watched for three years before anybody can pick him.
    ///
    /// Ratings here are a prospect's ability *now*. That they move between college
    /// seasons is the job of the development stream
    /// ([development.md](../../../../docs/development.md)) rather than a second
    /// progression mechanism built here — reusing one mechanism is the point of
    /// [decision 125](../../../../docs/design-decisions.md).
    public static func pipeline(
        firstDraftSeason: Int,
        teams: Int,
        shape: ClassShape = .standard,
        colleges: [College],
        identifiers: inout IdentifierSequence<PlayerSubject>,
        using random: inout SplittableRandom
    ) -> [GeneratedClass] {
        precondition(teams > 0, "a draft needs teams to pick")
        precondition(!colleges.isEmpty, "prospects need somewhere to have played")

        let classStrengths = strengths(count: shape.seasonsVisible, using: &random)
        var cohorts: [GeneratedClass] = []

        for offset in 0..<shape.seasonsVisible {
            let season = firstDraftSeason + offset
            // This year's class are seniors; each cohort further out is a year younger.
            let year = CollegeYear(rawValue: UInt8(3 - min(3, offset))) ?? .freshman
            cohorts.append(
                generate(
                    season: season, collegeYear: year, strength: classStrengths[offset],
                    count: shape.prospectCount(teams: teams), colleges: colleges,
                    identifiers: &identifiers, using: &random))
        }

        return promotingEarlyEntrants(cohorts)
    }

    /// Moves declared juniors out of next year's cohort and into this year's draft.
    ///
    /// A cohort is a year group; a draft class is who is actually available. They are
    /// not the same set, and conflating them means a junior who came out early is
    /// reported against the year he would have graduated — a class that shows
    /// "43 entering" for a draft two seasons away, and a current draft missing the
    /// forty-three best young players in it.
    private static func promotingEarlyEntrants(_ cohorts: [GeneratedClass]) -> [GeneratedClass] {
        guard cohorts.count >= 2 else { return cohorts }

        var result = cohorts
        // Front to back: this year takes from next year, and so on down the pipeline.
        for index in 0..<(result.count - 1) {
            let source = result[index + 1]
            let leaving = source.draftClass.earlyEntrants
            guard !leaving.isEmpty else { continue }

            let leavingIDs = Set(leaving.map(\.player))
            let destination = result[index]
            let season = destination.draftClass.season

            // He enters this draft, so this is the season he is eligible for.
            let promoted = leaving.map {
                Prospect(
                    player: $0.player, collegeYear: $0.collegeYear, declaration: $0.declaration,
                    eligibleSeason: season, production: $0.production, flags: $0.flags)
            }

            result[index] = GeneratedClass(
                draftClass: DraftClass(
                    season: season,
                    strength: destination.draftClass.strength,
                    prospects: destination.draftClass.prospects + promoted),
                players: destination.players
                    + source.players.filter { leavingIDs.contains($0.id) })

            result[index + 1] = GeneratedClass(
                draftClass: DraftClass(
                    season: source.draftClass.season,
                    strength: source.draftClass.strength,
                    prospects: source.draftClass.prospects.filter {
                        !leavingIDs.contains($0.player)
                    }),
                players: source.players.filter { !leavingIDs.contains($0.id) })
        }
        return result
    }

    /// One class of prospects at a given stage of college.
    public static func generate(
        season: Int,
        collegeYear: CollegeYear,
        strength: ClassStrength,
        count: Int,
        colleges: [College],
        identifiers: inout IdentifierSequence<PlayerSubject>,
        using random: inout SplittableRandom
    ) -> GeneratedClass {
        var players: [Player] = []
        var prospects: [Prospect] = []
        players.reserveCapacity(count)
        prospects.reserveCapacity(count)

        // Shuffled, not cycled. Assigning positions in order down the ceiling curve
        // makes talent rank a function of position — every class's best prospects are
        // the same positions in the same order, which is not a draft. Shuffling keeps
        // the distribution exact and decouples it from rank.
        var positions = draftablePositions(count: count)
        random.shuffle(&positions)

        for index in 0..<count {
            let position = positions[index]
            let group = position.group

            // A class is a talent distribution, not a rank: most of it is depth, and
            // the top is thin. The square root is doing the work — a linear ramp from
            // best to worst spreads ceilings *uniformly*, which produces as many
            // ninety-ceiling prospects as sixty-ceiling ones and makes every pick worth
            // the same. Falling fast and then flattening is what a class actually is.
            let percentile = Double(index) / Double(max(1, count - 1))
            let baseCeiling = 94.0 - 38.0 * squareRoot(percentile)
            let ceiling = Rounding.toNearest(
                baseCeiling + strength.offset(for: group) + random.nextGaussian() * 3.0,
                clampedTo: 45...99)

            // College age: a senior is about 22, and each year back is a year younger.
            let age = 19 + Int(collegeYear.rawValue)

            let player = PlayerGenerator.player(
                id: identifiers.allocate(), position: position, targetCeiling: UInt8(ceiling),
                age: age, season: season, colleges: colleges, using: &random)
            players.append(player)

            prospects.append(
                prospect(
                    for: player, collegeYear: collegeYear, eligibleSeason: season,
                    using: &random))
        }

        return GeneratedClass(
            draftClass: DraftClass(season: season, strength: strength, prospects: prospects),
            players: players)
    }

    /// The college record for one player.
    private static func prospect(
        for player: Player,
        collegeYear: CollegeYear,
        eligibleSeason: Int,
        using random: inout SplittableRandom
    ) -> Prospect {
        let ability = player.overall

        // Team quality and role are a prospect's context, and they persist across his
        // college seasons — a good player does not change schools every year.
        let teamQuality = UInt8(random.nextInt(in: 25...90))
        var usage = UInt8(random.nextInt(in: 30...70))

        // Every cohort is playing *now*, whatever year of college it is in. A senior
        // enters the draft after this season; a junior has one more year first, so his
        // cohort's draft is a year further out while his last played season is the same
        // one. Deriving the first season from `eligibleSeason` alone got this right for
        // seniors and a year wrong for everyone younger.
        let yearsRemaining = Int(CollegeYear.senior.rawValue) - Int(collegeYear.rawValue)
        let lastSeason = eligibleSeason - 1 - yearsRemaining

        var seasons: [ProductionProfile] = []
        var year = CollegeYear.freshman
        var season = lastSeason - Int(collegeYear.rawValue)

        while year.rawValue <= collegeYear.rawValue {
            // Playing time grows as he does. A freshman who played is a different
            // prospect from a senior who finally broke through.
            usage = UInt8(min(100, Int(usage) + random.nextInt(in: 0...18)))
            seasons.append(
                production(
                    season: season, collegeYear: year, currentAbility: ability,
                    teamQuality: teamQuality, usage: usage, using: &random))
            guard let next = year.next else { break }
            year = next
            season += 1
        }

        return Prospect(
            player: player.id,
            collegeYear: collegeYear,
            declaration: declaration(
                collegeYear: collegeYear, ability: ability, using: &random),
            eligibleSeason: eligibleSeason,
            production: seasons,
            flags: flags(using: &random))
    }

    /// Whether an underclassman comes out.
    ///
    /// A projected high pick declares; a fringe one goes back for another year, and next
    /// season he is a different prospect with another year of tape and a stock that has
    /// moved either way. Seniors never had the choice.
    private static func declaration(
        collegeYear: CollegeYear, ability: UInt8, using random: inout SplittableRandom
    ) -> Declaration {
        guard collegeYear.mayReturnToSchool else { return .automatic }
        // Three years removed from high school is the bar, so only juniors face it.
        // Anyone younger is not weighing anything yet.
        guard collegeYear == .junior else { return .notYetEligible }

        // Rises steeply with how good he is. Everything about the decision is what he
        // believes he is worth, and the good ones are right often enough.
        let chance = min(0.95, max(0.02, (Double(ability) - 58.0) / 24.0))
        return random.nextBool(probability: chance) ? .declared : .returning
    }

    /// Newton's method, to three iterations.
    ///
    /// `Double.squareRoot()` resolves to libm, which the `FM*` modules do not link
    /// (`Tools/playsize` guards this). The input is a percentile in 0...1, where three
    /// iterations from a good start are accurate to far more than a rating needs.
    private static func squareRoot(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        var estimate = value > 1 ? value : (value + 1) / 2
        for _ in 0..<12 {
            estimate = (estimate + value / estimate) / 2
        }
        return estimate
    }

    /// Positions for a whole class, weighted the way a class is shaped: many more
    /// linemen and receivers than quarterbacks and kickers.
    private static func draftablePositions(count: Int) -> [Position] {
        let pattern = weightedPositions()
        guard !pattern.isEmpty, count > 0 else { return [] }

        // Scaled to the class size, never truncated. Taking a prefix of a list that is
        // grouped by position produces a class made entirely of quarterbacks and
        // running backs, which is what happened.
        var positions: [Position] = []
        positions.reserveCapacity(count)
        for index in 0..<count {
            positions.append(pattern[(index * pattern.count) / count])
        }
        return positions
    }

    /// A class's positional makeup, in parts per thousand of the class.
    ///
    /// Weighted per **group**, not per position. Weighting each position equally
    /// inflated whichever groups happen to have more cases in the enum: the offensive
    /// line has five positions and quarterback has one, so a per-position weight made
    /// linemen twelve times more common than passers and every class came out with a
    /// front five at the top of it.
    private static func groupShare(_ group: PositionGroup) -> Int {
        switch group {
        case .quarterback: return 45
        case .backfield: return 80
        case .receiver: return 150
        case .tightEnd: return 65
        case .offensiveLine: return 175
        case .edge: return 120
        case .defensiveInterior: return 105
        case .linebacker: return 100
        case .cornerback: return 110
        case .safety: return 75
        case .specialist: return 25
        }
    }

    private static func weightedPositions() -> [Position] {
        var positions: [Position] = []
        for group in PositionGroup.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let members = group.positions.sorted { $0.rawValue < $1.rawValue }
            guard !members.isEmpty else { continue }
            // The group's share is split between its positions, so a five-man offensive
            // line does not out-produce a one-man quarterback group by five to one.
            let each = max(1, groupShare(group) / members.count)
            for position in members {
                positions.append(contentsOf: repeatElement(position, count: each))
            }
        }
        return positions
    }
}
