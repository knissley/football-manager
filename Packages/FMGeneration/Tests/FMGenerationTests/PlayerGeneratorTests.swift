import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030

private func generate(
    position: Position = .wideReceiver, ceiling: UInt8 = 78, age: Int = 26, seed: UInt64 = 1
) -> Player {
    var random = SplittableRandom(seed: seed)
    return PlayerGenerator.player(
        id: PlayerID(1), position: position, targetCeiling: ceiling,
        age: age, season: season, colleges: [], using: &random)
}

@Suite("Player generation")
struct PlayerGeneratorTests {

    @Test("The same seed produces the same player")
    func deterministic() {
        var a = SplittableRandom(seed: 555)
        var b = SplittableRandom(seed: 555)
        for _ in 0..<100 {
            let first = PlayerGenerator.player(
                id: PlayerID(1), position: .edge, targetCeiling: 80, age: 25,
                season: season, colleges: [], using: &a)
            let second = PlayerGenerator.player(
                id: PlayerID(1), position: .edge, targetCeiling: 80, age: 25,
                season: season, colleges: [], using: &b)
            #expect(first == second)
        }
    }

    /// The invariant the whole development design rests on. If a generated
    /// player can start above his ceiling, the league inflates from season one.
    @Test("No generated player is above his ceiling")
    func neverAboveCeiling() {
        var random = SplittableRandom(seed: 77)
        for position in Position.allCases {
            for ceiling in stride(from: 50, through: 95, by: 5) {
                for age in 21...36 {
                    let player = PlayerGenerator.player(
                        id: PlayerID(1), position: position, targetCeiling: UInt8(ceiling),
                        age: age, season: season, colleges: [], using: &random)
                    #expect(
                        player.overall <= player.hidden.ceiling,
                        "\(position) age \(age): \(player.overall) > ceiling \(player.hidden.ceiling)"
                    )
                }
            }
        }
    }

    @Test("Ratings match exactly the keys the position uses")
    func ratingKeys() {
        var random = SplittableRandom(seed: 88)
        for position in Position.allCases {
            let player = PlayerGenerator.player(
                id: PlayerID(1), position: position, targetCeiling: 75, age: 26,
                season: season, colleges: [], using: &random)
            #expect(
                player.ratings.matchesKeys(for: position),
                "\(position) carries the wrong rating set")
        }
    }

    /// Generation is asked for a talent level and has to deliver it. Noise on
    /// individual ratings biases the aggregate unless it is corrected, and a
    /// league generated to average 72 that arrives averaging 68 quietly
    /// invalidates every calibration target downstream.
    @Test("Generated overall lands on the requested level")
    func overallHitsTarget() {
        var random = SplittableRandom(seed: 99)
        for position in Position.allCases {
            var errors: [Int] = []
            for _ in 0..<200 {
                let target = PlayerGenerator.currentOverall(
                    ceiling: 82, age: 28, trait: .normal, group: position.group, rookieGap: 14)
                let ratings = PlayerGenerator.ratings(
                    position: position, targetOverall: target, using: &random)
                errors.append(
                    Int(PositionWeights.overall(ratings, at: position)) - Int(target))
            }
            let mean = Double(errors.reduce(0, +)) / Double(errors.count)
            #expect(abs(mean) < 1.0, "\(position) overall biased by \(mean)")
            #expect(errors.allSatisfy { abs($0) <= 2 }, "\(position) had a large miss")
        }
    }

    @Test("Young players sit below their ceiling and prime players reach it")
    func ageCurve() {
        let rookie = PlayerGenerator.currentOverall(
            ceiling: 85, age: 22, trait: .normal, group: .receiver, rookieGap: 14)
        let prime = PlayerGenerator.currentOverall(
            ceiling: 85, age: 27, trait: .normal, group: .receiver, rookieGap: 14)
        let old = PlayerGenerator.currentOverall(
            ceiling: 85, age: 34, trait: .normal, group: .receiver, rookieGap: 14)

        #expect(rookie < prime)
        #expect(prime == 85)
        #expect(old < prime)
    }

    /// A star developer arrives at his ceiling sooner. He does not arrive at a
    /// higher one.
    @Test("Development trait changes the rate, never the ceiling")
    func traitChangesRateNotCeiling() {
        let slow = PlayerGenerator.currentOverall(
            ceiling: 88, age: 24, trait: .slow, group: .edge, rookieGap: 14)
        let star = PlayerGenerator.currentOverall(
            ceiling: 88, age: 24, trait: .star, group: .edge, rookieGap: 14)
        #expect(star > slow)
        #expect(star <= 88)

        // By peak age both have arrived, and neither exceeds the ceiling.
        for trait in DevelopmentTrait.allCases {
            let peaked = PlayerGenerator.currentOverall(
                ceiling: 88, age: 27, trait: trait, group: .edge, rookieGap: 14)
            #expect(peaked == 88)
        }
    }

    @Test("Positions decline at different rates")
    func declineRates() {
        let back = PlayerGenerator.currentOverall(
            ceiling: 85, age: 32, trait: .normal, group: .backfield, rookieGap: 14)
        let lineman = PlayerGenerator.currentOverall(
            ceiling: 85, age: 32, trait: .normal, group: .offensiveLine, rookieGap: 14)
        #expect(back < lineman, "a back at 32 should be further gone than a lineman")
    }

    @Test("Development traits appear at their intended rarity")
    func traitRarity() {
        var random = SplittableRandom(seed: 123)
        var counts: [DevelopmentTrait: Int] = [:]
        let draws = 50_000
        for _ in 0..<draws {
            counts[PlayerGenerator.developmentTrait(using: &random), default: 0] += 1
        }
        let star = Double(counts[.star] ?? 0) / Double(draws)
        let normal = Double(counts[.normal] ?? 0) / Double(draws)
        #expect(star > 0.03 && star < 0.07, "star rate \(star)")
        #expect(normal > 0.50 && normal < 0.60, "normal rate \(normal)")
    }
}

@Suite("Generated physiques")
struct PhysicalGenerationTests {

    /// Measurables are outside the fog, so implausible ones are visible to the
    /// player immediately. A 5-10 left tackle reads as a broken generator.
    @Test("Builds are plausible for the position")
    func plausibleBuilds() {
        var random = SplittableRandom(seed: 31)
        var byPosition: [Position: [Int]] = [:]
        for position in Position.allCases {
            for _ in 0..<300 {
                let player = PlayerGenerator.player(
                    id: PlayerID(1), position: position, targetCeiling: 75, age: 26,
                    season: season, colleges: [], using: &random)
                byPosition[position, default: []].append(Int(player.physical.weightPounds))
                #expect(player.physical.heightInches >= 64)
                #expect(player.physical.heightInches <= 82)
            }
        }

        func meanWeight(_ position: Position) -> Double {
            let values = byPosition[position] ?? []
            return Double(values.reduce(0, +)) / Double(max(1, values.count))
        }

        #expect(meanWeight(.leftTackle) > meanWeight(.tightEnd))
        #expect(meanWeight(.tightEnd) > meanWeight(.wideReceiver))
        #expect(meanWeight(.defensiveTackle) > meanWeight(.linebacker))
        #expect(meanWeight(.linebacker) > meanWeight(.cornerback))
    }

    @Test("Faster players run faster forty times")
    func fortyTracksSpeed() {
        var random = SplittableRandom(seed: 41)
        var fastTimes: [Int] = []
        var slowTimes: [Int] = []
        for _ in 0..<400 {
            var fast = Ratings()
            fast[.speed] = 95
            fast[.acceleration] = 92
            fast[.agility] = 90
            fast[.strength] = 60
            fastTimes.append(
                Int(
                    PhysicalTemplates.combine(ratings: fast, weightPounds: 195, using: &random)
                        .forty))

            var slow = Ratings()
            slow[.speed] = 55
            slow[.acceleration] = 55
            slow[.agility] = 50
            slow[.strength] = 85
            slowTimes.append(
                Int(
                    PhysicalTemplates.combine(ratings: slow, weightPounds: 310, using: &random)
                        .forty))
        }
        let fastMean = Double(fastTimes.reduce(0, +)) / Double(fastTimes.count)
        let slowMean = Double(slowTimes.reduce(0, +)) / Double(slowTimes.count)
        #expect(fastMean < slowMean)
        #expect(fastMean > 420 && fastMean < 450, "elite forty averaged \(fastMean)")
    }

    /// The combine has to be informative and incomplete. Perfect prediction
    /// makes scouting trivial; none makes the workout pointless.
    @Test("Testing is correlated with ratings but not deterministic")
    func combineHasNoise() {
        var random = SplittableRandom(seed: 43)
        var ratings = Ratings()
        ratings[.speed] = 80
        ratings[.acceleration] = 80
        ratings[.agility] = 80
        ratings[.strength] = 70

        var times: Set<UInt16> = []
        for _ in 0..<200 {
            times.insert(
                PhysicalTemplates.combine(ratings: ratings, weightPounds: 210, using: &random).forty
            )
        }
        #expect(times.count > 10, "identical ratings produced only \(times.count) distinct times")
    }

    @Test("Heavier players bench more at the same strength")
    func benchTracksWeight() {
        var random = SplittableRandom(seed: 47)
        var ratings = Ratings()
        ratings[.strength] = 80
        ratings[.speed] = 60
        ratings[.acceleration] = 60
        ratings[.agility] = 60

        var light = 0
        var heavy = 0
        for _ in 0..<300 {
            light += Int(
                PhysicalTemplates.combine(ratings: ratings, weightPounds: 190, using: &random).bench
            )
            heavy += Int(
                PhysicalTemplates.combine(ratings: ratings, weightPounds: 320, using: &random).bench
            )
        }
        #expect(heavy > light)
    }

    @Test("Height reads the way the sport writes it")
    func heightFormatting() {
        let player = generate()
        let formatted = player.physical.heightDescription
        #expect(formatted.contains("-"))
        #expect(
            PhysicalProfile(
                heightInches: 76, weightPounds: 300, fortyYardDash: 510, verticalJump: 280,
                broadJump: 100, threeCone: 780, benchReps: 25
            ).heightDescription == "6-4")
    }
}

/// Measurables are the one thing every observer sees exactly, so an implausible
/// one is visible immediately. These guard the two bugs that produced 309-pound
/// tackles running 4.51 and pocket quarterbacks with receiver speed: athletic
/// attributes generated relative to overall rather than to the position, and a
/// forty time that ignored weight.
@Suite("Athletic plausibility")
struct AthleticPlausibilityTests {

    private func meanForty(_ position: Position, ceiling: UInt8, seed: UInt64) -> Double {
        var random = SplittableRandom(seed: seed)
        var total = 0
        let count = 400
        for _ in 0..<count {
            let player = PlayerGenerator.player(
                id: PlayerID(1), position: position, targetCeiling: ceiling, age: 26,
                season: season, colleges: [], using: &random)
            total += Int(player.physical.fortyYardDash)
        }
        return Double(total) / Double(count) / 100.0
    }

    @Test("Forty times are ordered the way the positions are")
    func fortyOrdering() {
        let corner = meanForty(.cornerback, ceiling: 80, seed: 1)
        let receiver = meanForty(.wideReceiver, ceiling: 80, seed: 2)
        let back = meanForty(.runningBack, ceiling: 80, seed: 3)
        let linebacker = meanForty(.linebacker, ceiling: 80, seed: 4)
        let tightEnd = meanForty(.tightEnd, ceiling: 80, seed: 5)
        let tackle = meanForty(.leftTackle, ceiling: 80, seed: 6)
        let interior = meanForty(.defensiveTackle, ceiling: 80, seed: 7)

        #expect(corner < back)
        #expect(receiver < linebacker)
        #expect(linebacker < tightEnd)
        #expect(tightEnd < interior)
        #expect(interior < tackle || abs(interior - tackle) < 0.15)
    }

    @Test("Every position's forty lands in a believable band")
    func fortyBands() {
        let bands: [(Position, ClosedRange<Double>)] = [
            (.cornerback, 4.30...4.65),
            (.wideReceiver, 4.30...4.70),
            (.runningBack, 4.35...4.75),
            (.linebacker, 4.50...4.95),
            (.tightEnd, 4.55...5.00),
            (.quarterback, 4.55...5.05),
            (.defensiveTackle, 4.95...5.30),
            (.leftTackle, 5.05...5.40),
            (.center, 5.10...5.45),
        ]
        for (position, band) in bands {
            let mean = meanForty(position, ceiling: 78, seed: UInt64(position.rawValue) + 100)
            #expect(band.contains(mean), "\(position) averaged \(mean), expected \(band)")
        }
    }

    /// The specific failure: a good pocket passer arriving with a corner's speed
    /// because quarterback weights speed at all.
    @Test("Quality does not turn a lineman or a passer into a sprinter")
    func qualityDoesNotOverridePosition() {
        let eliteTackle = meanForty(.leftTackle, ceiling: 95, seed: 21)
        let poorCorner = meanForty(.cornerback, ceiling: 58, seed: 22)
        #expect(eliteTackle > poorCorner, "an elite tackle outran a poor corner")

        let eliteQuarterback = meanForty(.quarterback, ceiling: 95, seed: 23)
        #expect(eliteQuarterback > 4.45, "elite quarterbacks averaged \(eliteQuarterback)")
    }

    @Test("No forty time is faster than anyone has ever run")
    func noImpossibleTimes() {
        var random = SplittableRandom(seed: 31)
        for position in Position.allCases {
            for _ in 0..<200 {
                let player = PlayerGenerator.player(
                    id: PlayerID(1), position: position, targetCeiling: 96, age: 24,
                    season: season, colleges: [], using: &random)
                #expect(player.physical.fortyYardDash >= 415, "\(position) ran an impossible time")
            }
        }
    }

    @Test("Heavier positions carry heavier builds and more bench")
    func strengthTracksPosition() {
        var random = SplittableRandom(seed: 37)
        var tackleStrength = 0
        var cornerStrength = 0
        for _ in 0..<300 {
            tackleStrength += Int(
                PlayerGenerator.player(
                    id: PlayerID(1), position: .leftTackle, targetCeiling: 78, age: 26,
                    season: season, colleges: [], using: &random
                ).ratings.value(.strength))
            cornerStrength += Int(
                PlayerGenerator.player(
                    id: PlayerID(1), position: .cornerback, targetCeiling: 78, age: 26,
                    season: season, colleges: [], using: &random
                ).ratings.value(.strength))
        }
        #expect(tackleStrength > cornerStrength)
    }
}
