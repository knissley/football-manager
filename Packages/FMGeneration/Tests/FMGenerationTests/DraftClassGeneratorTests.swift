import FMCore
import FMRandom
import Testing

@testable import FMGeneration

@Suite("Draft classes")
struct DraftClassGeneratorTests {

    private func pipeline(
        seed: UInt64 = 11, teams: Int = 32,
        shape: DraftClassGenerator.ClassShape = .compact
    ) -> [DraftClassGenerator.GeneratedClass] {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 60, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var identifiers = IdentifierSequence<PlayerSubject>()
        return DraftClassGenerator.pipeline(
            firstDraftSeason: 2030, teams: teams, shape: shape, colleges: colleges,
            identifiers: &identifiers, using: &random)
    }

    @Test("The same seed produces the same classes", .tags(.contract))
    func deterministic() {
        #expect(pipeline().map(\.draftClass) == pipeline().map(\.draftClass))
    }

    /// Three years of visibility is what multi-year scouting needs: this year's seniors
    /// were watchable as sophomores.
    @Test("The pipeline shows three classes at descending college years", .tags(.unit))
    func pipelineShape() {
        let classes = pipeline()
        #expect(classes.count == 3)
        #expect(classes[0].draftClass.season == 2030)
        #expect(classes[2].draftClass.season == 2032)

        let years = classes.map { $0.draftClass.prospects[0].collegeYear }
        #expect(years == [.senior, .junior, .sophomore])
    }

    /// A prospect is in college. Nobody has drafted him and nobody has signed him, so he has
    /// not arrived — and a man who has not arrived is not a rookie, however close his class
    /// is to being picked from.
    ///
    /// He read as one because a player built without a draft board took the season he was
    /// built in as the season he first counted against a roster, which for a prospect is the
    /// season his class becomes eligible
    /// ([#67](https://github.com/knissley/football-manager/issues/67)).
    @Test("contract: a prospect has not arrived, so he is not a rookie", .tags(.contract))
    func prospectsHaveNotArrived() {
        for generated in pipeline() {
            let eligible = generated.draftClass.season
            for player in generated.players {
                #expect(
                    !player.isRookie(in: eligible),
                    "\(player.name.full) is a rookie while he is still in college")
                #expect(player.draft == nil, "\(player.name.full) has been drafted already")
                #expect(player.experience(in: eligible) == 0)
            }
        }
    }

    @Test("Every prospect maps to a player that exists", .tags(.contract))
    func prospectsMapToPlayers() {
        for generated in pipeline() {
            for prospect in generated.draftClass.prospects {
                #expect(generated.player(prospect.player) != nil)
            }
            #expect(generated.players.count == generated.draftClass.prospects.count)
        }
    }

    /// A class that exactly fills the board has no bottom to it, and no undrafted gem
    /// is findable.
    @Test("A class holds more prospects than there are picks", .tags(.unit))
    func classIsDeeperThanTheBoard() {
        let shape = DraftClassGenerator.ClassShape.compact
        let picks = shape.rounds * 32
        #expect(shape.prospectCount(teams: 32) > picks)
    }

    // MARK: - Class strength

    /// The conservation law's requirement: classes vary strongly, but the variation
    /// comes back to a fixed mean rather than drifting somewhere records stop being
    /// comparable.
    @Test("Class strength varies strongly but does not drift over fifty seasons", .tags(.contract))
    func strengthIsMeanReverting() {
        var random = SplittableRandom(seed: 5)
        let strengths = DraftClassGenerator.strengths(count: 50, using: &random)
        let overalls = strengths.map(\.overall)

        let mean = overalls.reduce(0, +) / Double(overalls.count)
        #expect(mean > -0.9 && mean < 0.9, "fifty classes drifted to a mean of \(mean)")

        // Real spread: if every class is ordinary, nothing is worth trading up for.
        #expect(overalls.contains { $0 > 2.5 }, "no loaded class in fifty years")
        #expect(overalls.contains { $0 < -2.5 }, "no thin class in fifty years")

        // And the halves agree, so there is no slow ramp hiding inside the mean.
        let firstHalf = overalls.prefix(25).reduce(0, +) / 25
        let secondHalf = overalls.suffix(25).reduce(0, +) / 25
        #expect(
            (firstHalf - secondHalf) < 1.6 && (secondHalf - firstHalf) < 1.6,
            "talent drifted between the first and second halves")
    }

    /// A loaded class should make the *next few* likelier to be thin — the reversion is
    /// spread over a window rather than landing entirely on the following year, because
    /// a tidy annual alternation is not something anybody would believe. Without the
    /// negative pull the series is a random walk and it wanders.
    @Test("The years after a strong class are thinner", .tags(.unit))
    func strengthReverts() {
        var random = SplittableRandom(seed: 21)
        let overalls = DraftClassGenerator.strengths(count: 600, using: &random).map(\.overall)

        var following: [Double] = []
        for index in 0..<(overalls.count - 3) where overalls[index] > 2.0 {
            following.append(contentsOf: overalls[(index + 1)...(index + 3)])
        }
        #expect(following.isEmpty == false)
        let mean = following.reduce(0, +) / Double(following.count)
        #expect(mean < -0.2, "the three years after a loaded class averaged \(mean)")
    }

    /// Shape redistributes talent within a class; only `overall` moves the total. That
    /// separation is what lets conservation be asserted on one number.
    @Test("Position shape is zero-sum", .tags(.unit))
    func shapeIsZeroSum() {
        var random = SplittableRandom(seed: 8)
        for strength in DraftClassGenerator.strengths(count: 30, using: &random) {
            let total = strength.byGroup.values.reduce(0, +)
            #expect(total > -0.001 && total < 0.001, "shape summed to \(total)")
        }
    }

    @Test("Some classes are rich at a position and say so", .tags(.unit))
    func headlineGroups() {
        var random = SplittableRandom(seed: 4)
        let strengths = DraftClassGenerator.strengths(count: 40, using: &random)
        #expect(strengths.contains { $0.headline != nil })
        #expect(Set(strengths.map(\.descriptor)).count >= 3)
    }

    // MARK: - Production

    /// Production is ability plus independent error. If it tracked ability exactly,
    /// there would be nothing for a scout to be wrong about.
    @Test("Production disagrees with ability often enough to matter", .tags(.unit))
    func productionCarriesIndependentError() {
        var random = SplittableRandom(seed: 3)
        var disagreements = 0
        let trials = 400

        for _ in 0..<trials {
            let ability = UInt8(random.nextInt(in: 55...85))
            let profile = DraftClassGenerator.production(
                season: 2029, collegeYear: .junior, currentAbility: ability,
                teamQuality: UInt8(random.nextInt(in: 25...90)),
                usage: UInt8(random.nextInt(in: 30...95)), using: &random)
            let gap = Int(profile.productionScore) - Int(ability)
            if gap > 8 || gap < -8 { disagreements += 1 }
        }

        #expect(disagreements > trials / 5, "production tracks ability too closely")
        #expect(disagreements < trials * 4 / 5, "production is noise rather than evidence")
    }

    /// The two cases that make production arguable: a good player nobody sees, and a
    /// limited one the system flatters. Compared against the *same* ability in neutral
    /// context, because production is on its own scale rather than the rating's.
    @Test("Context moves production in the direction it should", .tags(.unit))
    func contextMovesProduction() {
        var random = SplittableRandom(seed: 6)

        func meanScore(ability: UInt8, teamQuality: UInt8, usage: UInt8) -> Double {
            var total = 0
            let trials = 600
            for _ in 0..<trials {
                total += Int(
                    DraftClassGenerator.production(
                        season: 2029, collegeYear: .junior, currentAbility: ability,
                        teamQuality: teamQuality, usage: usage, using: &random
                    ).productionScore)
            }
            return Double(total) / Double(trials)
        }

        let neutralGood = meanScore(ability: 80, teamQuality: 55, usage: 55)
        let buriedGood = meanScore(ability: 80, teamQuality: 25, usage: 40)
        #expect(buriedGood < neutralGood - 6, "a good player nobody sees should look ordinary")

        let neutralLimited = meanScore(ability: 60, teamQuality: 55, usage: 55)
        let flatteredLimited = meanScore(ability: 60, teamQuality: 90, usage: 95)
        #expect(
            flatteredLimited > neutralLimited + 12,
            "a limited player in the right system should look better than he is")

        // Context does not overturn a twenty-point ability gap, and should not. What it
        // does overturn is a close call — which is where scouting actually happens.
        let buriedBetter = meanScore(ability: 74, teamQuality: 25, usage: 40)
        let flatteredWorse = meanScore(ability: 68, teamQuality: 90, usage: 95)
        #expect(
            flatteredWorse > buriedBetter,
            "between close prospects the numbers should be able to mislead")
    }

    /// Every cohort in the pipeline is playing right now, whatever year of college it
    /// is in. A junior's last season is the same autumn as a senior's; his draft is
    /// simply a year further out. Deriving seasons from the cohort's draft year alone
    /// got this right for seniors and a year wrong for everyone younger.
    @Test("Every cohort's last college season is the same autumn", .tags(.unit))
    func cohortsPlayInTheSameSeason() {
        let seasons = pipeline().flatMap { generated in
            generated.draftClass.prospects.compactMap { $0.production.last?.season }
        }
        #expect(Set(seasons).count == 1, "cohorts are playing in different years: \(Set(seasons))")
    }

    @Test("A prospect has one production season per college year played", .tags(.unit))
    func productionHistory() {
        for generated in pipeline() {
            for prospect in generated.draftClass.prospects {
                #expect(prospect.production.count == Int(prospect.collegeYear.rawValue) + 1)
                #expect(prospect.production.first?.collegeYear == .freshman)
                #expect(prospect.production.last?.collegeYear == prospect.collegeYear)
                // Seasons run forwards and end the year before he is eligible.
                // Anyone entering a draft played his last college season the autumn
                // before it. A junior who came out early is included — that is what
                // coming out early means.
                if prospect.isInThisClass {
                    #expect(prospect.production.last?.season == prospect.eligibleSeason - 1)
                }
            }
        }
    }

    // MARK: - Red flags

    @Test("Flags are uncommon, and serious ones are rarer still", .tags(.unit))
    func flagRates() {
        var random = SplittableRandom(seed: 12)
        var withFlags = 0
        var buried = 0
        let trials = 2_000

        for _ in 0..<trials {
            let flags = DraftClassGenerator.flags(using: &random)
            if !flags.isEmpty { withFlags += 1 }
            if flags.contains(where: \.isBuried) { buried += 1 }
        }

        #expect(withFlags > trials / 8 && withFlags < trials / 3)
        #expect(buried > 0, "no buried concern in two thousand prospects")
        #expect(buried < trials / 10, "a serious hidden flag should be rare")
    }

    /// Severity and visibility are independent on purpose. Correlating them would mean
    /// a bad problem is always an obvious one, and the slide nobody can explain at the
    /// time would stop happening.
    @Test("Severity does not predict visibility", .tags(.unit))
    func severityAndVisibilityAreIndependent() {
        var random = SplittableRandom(seed: 15)
        var severeAndHidden = 0
        var severeAndObvious = 0

        for _ in 0..<3_000 {
            for flag in DraftClassGenerator.flags(using: &random) where flag.severity >= 60 {
                if flag.visibility <= 35 { severeAndHidden += 1 }
                if flag.visibility >= 70 { severeAndObvious += 1 }
            }
        }
        #expect(severeAndHidden > 0 && severeAndObvious > 0)
        let ratio = Double(severeAndHidden) / Double(severeAndObvious)
        #expect(ratio > 0.4 && ratio < 2.5, "severity and visibility look correlated")
    }

    @Test("Both medical and football-professional concerns occur", .tags(.unit))
    func flagKinds() {
        var random = SplittableRandom(seed: 19)
        var kinds: Set<RedFlagKind> = []
        for _ in 0..<2_000 {
            for flag in DraftClassGenerator.flags(using: &random) { kinds.insert(flag.kind) }
        }
        #expect(kinds.contains { $0.isMedical })
        #expect(kinds.contains { !$0.isMedical })
        #expect(kinds.count >= 8)
    }

    // MARK: - Declaring

    /// A projected high pick comes out; a fringe junior goes back for another year and
    /// arrives next season as a different prospect.
    @Test("Good juniors declare and fringe ones return", .tags(.unit))
    func declarations() {
        var random = SplittableRandom(seed: 2)
        var colleges = NameGenerator.collegePool(count: 40, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var identifiers = IdentifierSequence<PlayerSubject>()

        let generated = DraftClassGenerator.generate(
            season: 2031, collegeYear: .junior, strength: .normal, count: 300,
            colleges: colleges, identifiers: &identifiers, using: &random)

        let declared = generated.draftClass.entering
        let returning = generated.draftClass.returning
        #expect(declared.isEmpty == false, "no junior declared")
        #expect(returning.isEmpty == false, "every junior declared")

        func meanOverall(_ prospects: [Prospect]) -> Double {
            let overalls = prospects.compactMap { generated.player($0.player)?.overall }
            return overalls.reduce(0) { $0 + Double($1) } / Double(max(1, overalls.count))
        }
        #expect(
            meanOverall(declared) > meanOverall(returning) + 3,
            "declaring should track how good a player believes he is")
    }

    /// A cohort is a year group; a draft class is who is available. Conflating them
    /// reported early entrants against the year they would have graduated, leaving the
    /// current draft missing its best young players.
    @Test("This year's draft holds its seniors plus the juniors who came out", .tags(.unit))
    func earlyEntrantsJoinThisYearsDraft() {
        let classes = pipeline()
        guard let thisYear = classes.first, classes.count >= 2 else {
            Issue.record("the pipeline should produce classes")
            return
        }

        #expect(thisYear.draftClass.returning.isEmpty, "nobody in this draft is sitting it out")
        #expect(thisYear.draftClass.earlyEntrants.isEmpty == false, "no junior came out early")

        // Everyone in it is either a senior with no choice or a junior who chose.
        for prospect in thisYear.draftClass.prospects {
            #expect(prospect.declaration == .automatic || prospect.declaration == .declared)
            #expect(prospect.eligibleSeason == thisYear.draftClass.season)
            #expect(thisYear.player(prospect.player) != nil, "a promoted prospect lost his player")
        }

        // And they left the cohort they came from, rather than being counted twice.
        let promoted = Set(thisYear.draftClass.earlyEntrants.map(\.player))
        #expect(classes[1].draftClass.prospects.allSatisfy { !promoted.contains($0.player) })
    }

    /// A sophomore is not weighing anything yet, so reporting him as "not entering"
    /// would describe a decision he has not made.
    @Test("Cohorts further out have not been asked yet", .tags(.unit))
    func distantCohortsAreUndecided() {
        let classes = pipeline()
        guard classes.count >= 3 else {
            Issue.record("the pipeline should produce three classes")
            return
        }
        #expect(classes[2].draftClass.prospects.allSatisfy { $0.declaration == .notYetEligible })
        #expect(classes[2].draftClass.prospects.allSatisfy { !$0.declaration.isDecided })
        #expect(classes[1].draftClass.prospects.allSatisfy { $0.declaration == .returning })
    }

    // MARK: - The class as a talent distribution

    /// A class is a distribution, not a rank: the top is thin and most of it is depth.
    /// If the curve flattens, every pick is worth the same and the draft stops being a
    /// decision.
    ///
    /// Measured against a class of *normal* strength. Asserting a fixed cap on any
    /// class would contradict the design — a historically loaded year is supposed to
    /// have more elite prospects in it, and testing against one caught this test
    /// arguing with the feature rather than the code.
    @Test("A class of normal strength is top-heavy in ceiling", .tags(.unit))
    func classIsTopHeavy() {
        let ceilings = classCeilings(strength: .normal, seed: 31)
        let elite = ceilings.filter { $0 >= 88 }.count
        let depth = ceilings.filter { $0 < 65 }.count

        #expect(elite > 0, "no elite ceiling in a whole class")
        #expect(elite < ceilings.count / 15, "too many elite prospects: \(elite)")
        #expect(depth > ceilings.count / 3, "a class should be mostly depth")
    }

    /// The design claim class strength actually makes: a loaded year has more players
    /// worth a high pick, and a thin one has fewer.
    @Test("A loaded class holds more elite prospects than a thin one", .tags(.unit))
    func strengthMovesTheTopOfTheClass() {
        func eliteCount(_ overall: Double) -> Int {
            classCeilings(strength: ClassStrength(overall: overall), seed: 31)
                .filter { $0 >= 88 }.count
        }
        #expect(eliteCount(4.5) > eliteCount(0))
        #expect(eliteCount(0) > eliteCount(-4.5))
    }

    private func classCeilings(strength: ClassStrength, seed: UInt64) -> [Int] {
        var random = SplittableRandom(seed: seed)
        var colleges = NameGenerator.collegePool(count: 40, using: &random)
        if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }
        var identifiers = IdentifierSequence<PlayerSubject>()
        let generated = DraftClassGenerator.generate(
            season: 2030, collegeYear: .senior, strength: strength, count: 336,
            colleges: colleges, identifiers: &identifiers, using: &random)
        return generated.players.map { Int($0.hidden.ceiling) }
    }

    @Test("A class spans the positions a draft actually produces", .tags(.unit))
    func positionSpread() {
        guard let generated = pipeline(shape: .standard).first else {
            Issue.record("the pipeline should produce a class")
            return
        }
        let groups = Set(generated.players.map(\.position.group))
        #expect(groups.count == PositionGroup.allCases.count)

        let quarterbacks = generated.players.filter { $0.position.group == .quarterback }.count
        let linemen = generated.players.filter { $0.position.group == .offensiveLine }.count
        #expect(quarterbacks > 0)
        #expect(linemen > quarterbacks, "a class produces more linemen than quarterbacks")
    }
}
