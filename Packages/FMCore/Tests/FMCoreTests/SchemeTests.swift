import Testing

@testable import FMCore

/// A mauler: heavy, strong, technically sound, not remotely athletic.
private func maulerGuard() -> Ratings {
    var ratings = Ratings()
    for key in RatingKey.keys(for: .leftGuard) { ratings[key] = 60 }
    ratings[.strength] = 92
    ratings[.runBlock] = 88
    ratings[.blockAnchor] = 86
    ratings[.passBlock] = 74
    ratings[.handTechnique] = 78
    ratings[.agility] = 42
    ratings[.speed] = 38
    return ratings
}

/// An athlete: light, quick, gets to the second level, gets moved backwards.
private func zoneGuard() -> Ratings {
    var ratings = Ratings()
    for key in RatingKey.keys(for: .leftGuard) { ratings[key] = 60 }
    ratings[.strength] = 62
    ratings[.runBlock] = 74
    ratings[.blockAnchor] = 62
    ratings[.passBlock] = 78
    ratings[.handTechnique] = 84
    ratings[.agility] = 88
    ratings[.speed] = 82
    return ratings
}

@Suite("Scheme composition")
struct SchemeCompositionTests {

    @Test("Families are combinations of components", .tags(.unit))
    func families() {
        #expect(OffensiveScheme.powerRun.blocking == .gap)
        #expect(OffensiveScheme.airRaid.blocking == .zone)
        #expect(OffensiveScheme.airRaid.passing == .airRaid)
        #expect(OffensiveScheme.families.count == 6)
        #expect(DefensiveScheme.families.count == 5)
    }

    @Test("Pass lean is bounded and ordered as expected", .tags(.unit))
    func passLean() {
        #expect(OffensiveScheme.airRaid.passLean > OffensiveScheme.powerRun.passLean)
        for scheme in OffensiveScheme.families {
            #expect(scheme.passLean >= 0 && scheme.passLean <= 1)
        }
        #expect(OffensiveScheme(blocking: .zone, passing: .airRaid, passLean: 5).passLean == 1)
    }
}

/// The heart of it: a scheme changes what counts, not how good anybody is.
@Suite("Scheme fit")
struct SchemeFitTests {

    private func teamScheme(_ offense: OffensiveScheme) -> TeamScheme {
        TeamScheme(offense: offense, defense: .fourThreeUnder)
    }

    @Test("The same lineman is worth different amounts in different schemes", .tags(.unit))
    func maulerVersusAthlete() {
        let mauler = maulerGuard()
        let athlete = zoneGuard()

        let inGap = teamScheme(.powerRun)
        let inZone = teamScheme(.zoneRun)

        let maulerGap = SchemeFit.effectiveOverall(mauler, at: .leftGuard, in: inGap)
        let maulerZone = SchemeFit.effectiveOverall(mauler, at: .leftGuard, in: inZone)
        let athleteGap = SchemeFit.effectiveOverall(athlete, at: .leftGuard, in: inGap)
        let athleteZone = SchemeFit.effectiveOverall(athlete, at: .leftGuard, in: inZone)

        #expect(maulerGap > maulerZone, "mauler: gap \(maulerGap), zone \(maulerZone)")
        #expect(athleteZone > athleteGap, "athlete: zone \(athleteZone), gap \(athleteGap)")

        // The swing is meaningful, not cosmetic.
        #expect(Int(maulerGap) - Int(maulerZone) >= 5)
        #expect(Int(athleteZone) - Int(athleteGap) >= 5)
    }

    /// The number that belongs on a roster screen the day you switch.
    @Test("Fit reports the swing in overall points", .tags(.unit))
    func fitDelta() {
        let mauler = maulerGuard()
        #expect(SchemeFit.fit(mauler, at: .leftGuard, in: teamScheme(.powerRun)) > 0)
        #expect(SchemeFit.fit(mauler, at: .leftGuard, in: teamScheme(.airRaid)) < 0)
    }

    /// A scheme redistributes emphasis; it does not hand out free points.
    @Test("A uniformly rated player is unaffected by scheme", .tags(.contract))
    func uniformPlayerIsSchemeNeutral() {
        for position in Position.allCases {
            var flat = Ratings()
            for key in RatingKey.keys(for: position) { flat[key] = 75 }
            for offense in OffensiveScheme.families {
                for defense in DefensiveScheme.families {
                    let scheme = TeamScheme(offense: offense, defense: defense)
                    #expect(
                        SchemeFit.effectiveOverall(flat, at: position, in: scheme) == 75,
                        "\(position) drifted under \(offense.passing)/\(defense.coverage)")
                }
            }
        }
    }

    @Test("Specialists are unaffected by scheme", .tags(.unit))
    func specialistsUnaffected() {
        var kicker = Ratings()
        for key in RatingKey.keys(for: .kicker) { kicker[key] = 60 }
        kicker[.kickPower] = 92
        for offense in OffensiveScheme.families {
            let scheme = TeamScheme(offense: offense, defense: .pressManBlitz)
            #expect(SchemeFit.fit(kicker, at: .kicker, in: scheme) == 0)
        }
    }

    @Test("A man-cover corner and a zone corner want different defences", .tags(.unit))
    func cornerbacks() {
        var manCorner = Ratings()
        for key in RatingKey.keys(for: .cornerback) { manCorner[key] = 62 }
        manCorner[.manCoverage] = 92
        manCorner[.releaseVsPress] = 88
        manCorner[.speed] = 90
        manCorner[.zoneCoverage] = 55

        var zoneCorner = Ratings()
        for key in RatingKey.keys(for: .cornerback) { zoneCorner[key] = 62 }
        zoneCorner[.zoneCoverage] = 92
        zoneCorner[.awareness] = 88
        zoneCorner[.manCoverage] = 55
        zoneCorner[.tackling] = 82

        let press = TeamScheme(offense: .westCoast, defense: .pressManBlitz)
        let quarters = TeamScheme(offense: .westCoast, defense: .nickelMatch)

        #expect(
            SchemeFit.fit(manCorner, at: .cornerback, in: press)
                > SchemeFit.fit(manCorner, at: .cornerback, in: quarters))
        #expect(
            SchemeFit.fit(zoneCorner, at: .cornerback, in: quarters)
                > SchemeFit.fit(zoneCorner, at: .cornerback, in: press))
    }

    @Test("A three-man front wants a very different interior lineman", .tags(.unit))
    func noseTackle() {
        var anchor = Ratings()
        for key in RatingKey.keys(for: .defensiveTackle) { anchor[key] = 62 }
        anchor[.strength] = 94
        anchor[.blockShedding] = 88
        anchor[.powerMove] = 60
        anchor[.pursuit] = 50

        let threeMan = TeamScheme(offense: .westCoast, defense: .threeFourOkie)
        let fourMan = TeamScheme(offense: .westCoast, defense: .fourThreeUnder)
        #expect(
            SchemeFit.fit(anchor, at: .defensiveTackle, in: threeMan)
                > SchemeFit.fit(anchor, at: .defensiveTackle, in: fourMan))
    }

    /// The scenario that prompted the design: a strong-armed passer stuck in an
    /// offence that does not throw, and what happens when you switch.
    @Test("A deep passer is worth more once you stop running the ball", .tags(.unit))
    func theQuarterbackProblem() {
        var gunslinger = Ratings()
        for key in RatingKey.keys(for: .quarterback) { gunslinger[key] = 62 }
        gunslinger[.throwPower] = 95
        gunslinger[.throwAccuracyDeep] = 92
        gunslinger[.throwAccuracyMedium] = 84
        gunslinger[.playAction] = 58

        let smashmouth = TeamScheme(offense: .powerRun, defense: .fourThreeUnder)
        let vertical = TeamScheme(offense: .verticalShots, defense: .fourThreeUnder)

        let stuck = SchemeFit.fit(gunslinger, at: .quarterback, in: smashmouth)
        let freed = SchemeFit.fit(gunslinger, at: .quarterback, in: vertical)
        #expect(freed > stuck, "stuck \(stuck), freed \(freed)")
        #expect(freed - stuck >= 4, "switching gained only \(freed - stuck)")
    }
}

/// The cost of changing identity has to fade, or it is the gate this design
/// exists to avoid.
@Suite("Scheme experience")
struct SchemeExperienceTests {

    @Test("An unfamiliar coach is worse, not useless", .tags(.unit))
    func unfamiliarIsNotHopeless() {
        let fresh = SchemeExperience()
        let proficiency = fresh.proficiency(in: .airRaid)
        #expect(proficiency == SchemeExperience.unfamiliarProficiency)
        #expect(proficiency > 0.5, "an unfamiliar professional should still function")
    }

    @Test("Familiarity grows with seasons and saturates", .tags(.unit))
    func familiarityGrows() {
        var experience = SchemeExperience()
        var previous = experience.proficiency(in: .airRaid)
        for _ in 0..<SchemeExperience.seasonsToMastery {
            experience.recordSeason(offense: .airRaid)
            let current = experience.proficiency(in: .airRaid)
            #expect(current > previous)
            previous = current
        }
        #expect(previous == 1.0)

        // Further seasons cannot push past mastery.
        for _ in 0..<10 { experience.recordSeason(offense: .airRaid) }
        #expect(experience.proficiency(in: .airRaid) == 1.0)
    }

    /// The payoff of tracking components rather than families: related schemes
    /// share background, unrelated ones do not.
    @Test("Related schemes share familiarity", .tags(.unit))
    func componentsTransfer() {
        var experience = SchemeExperience()
        for _ in 0..<4 { experience.recordSeason(offense: .spread) }

        // Spread and air raid both block zone, so half the background carries.
        let toAirRaid = experience.proficiency(in: .airRaid)
        // Power run shares neither component.
        let toPowerRun = experience.proficiency(in: .powerRun)

        #expect(toAirRaid > toPowerRun, "air raid \(toAirRaid), power run \(toPowerRun)")
        #expect(toPowerRun == SchemeExperience.unfamiliarProficiency)
        #expect(toAirRaid < 1.0, "sharing one component should not confer mastery")
    }

    @Test("Installing costs extra in the first season, and mid-season costs more", .tags(.unit))
    func installAndMidSeason() {
        let fresh = SchemeExperience()
        let settled = fresh.proficiency(in: .airRaid)
        #expect(fresh.firstSeasonProficiency(in: .airRaid) < settled)
        #expect(
            fresh.midSeasonProficiency(in: .airRaid) < fresh.firstSeasonProficiency(in: .airRaid))
        #expect(fresh.midSeasonProficiency(in: .airRaid) > 0)
    }

    @Test("Defensive familiarity works the same way", .tags(.unit))
    func defensiveFamiliarity() {
        var experience = SchemeExperience()
        #expect(
            experience.proficiency(in: .pressManBlitz)
                == SchemeExperience.unfamiliarProficiency)
        for _ in 0..<4 { experience.recordSeason(defense: .pressManBlitz) }
        #expect(experience.proficiency(in: .pressManBlitz) == 1.0)
        // Shares a four-man front but not the coverage.
        let toNickel = experience.proficiency(in: .nickelMatch)
        #expect(toNickel > SchemeExperience.unfamiliarProficiency)
        #expect(toNickel < 1.0)
    }
}

/// The bug this guards against, which shipped once already: modifiers were
/// multipliers on existing weights, so `agility x 1.7` on a guard did nothing at
/// all — agility carries no base weight there, and a multiplier on zero is zero.
/// Deltas fixed that, but a delta on a rating the position does not *carry* is
/// still silently dropped.
@Suite("Scheme modifier validity")
struct SchemeModifierTests {

    @Test("Every modifier references a rating its position actually carries", .tags(.contract))
    func modifiersReferenceCarriedRatings() {
        for position in Position.allCases {
            let carried = Set(RatingKey.keys(for: position))
            for offense in OffensiveScheme.families {
                for defense in DefensiveScheme.families {
                    let scheme = TeamScheme(offense: offense, defense: defense)
                    for (key, _) in SchemeFit.modifiers(for: position, in: scheme) {
                        #expect(
                            carried.contains(key),
                            "\(position) modified on \(key), which it does not carry")
                    }
                }
            }
        }
    }

    @Test("Modifiers only apply to the side of the ball they belong to", .tags(.unit))
    func sidesAreRespected() {
        let scheme = TeamScheme(offense: .airRaid, defense: .pressManBlitz)
        for position in Position.allCases where position.side == .specialTeams {
            #expect(SchemeFit.modifiers(for: position, in: scheme).isEmpty)
        }
    }

    /// A modifier that changes nothing measurable is dead weight pretending to
    /// be design. For every position a scheme claims to modify, a player built
    /// to suit that modification must actually score better than the same player
    /// in a scheme that does not want him.
    ///
    /// Constructing the player *from the modifiers* is the point: an arbitrary
    /// lopsided player may simply miss the keys a scheme touches, which makes
    /// the test pass or fail for reasons unrelated to the design.
    @Test("Every modifier a scheme declares actually moves the player it names", .tags(.contract))
    func everyModifierMatters() {
        func idealPlayer(for position: Position, under scheme: TeamScheme) -> Ratings {
            let adjustments = SchemeFit.modifiers(for: position, in: scheme)
            var ratings = Ratings()
            for key in RatingKey.keys(for: position) {
                let delta = adjustments[key] ?? 0
                ratings[key] = delta > 0 ? 92 : (delta < 0 ? 48 : 68)
            }
            return ratings
        }

        var checked = 0
        for offense in OffensiveScheme.families {
            for defense in DefensiveScheme.families {
                let scheme = TeamScheme(offense: offense, defense: defense)
                for position in Position.allCases {
                    let adjustments = SchemeFit.modifiers(for: position, in: scheme)
                    guard !adjustments.isEmpty else { continue }
                    checked += 1

                    let ratings = idealPlayer(for: position, under: scheme)
                    let fit = SchemeFit.fit(ratings, at: position, in: scheme)
                    #expect(
                        fit >= 2,
                        "\(position) built for this scheme gained only \(fit)")
                }
            }
        }
        #expect(checked > 100, "only \(checked) position/scheme pairs carried modifiers")
    }

    /// Every family has to be distinguishable from every other, or it is a name
    /// rather than an identity.
    @Test("No two offensive families are interchangeable", .tags(.contract))
    func familiesAreDistinct() {
        func signature(_ offense: OffensiveScheme) -> [String] {
            let scheme = TeamScheme(offense: offense, defense: .fourThreeUnder)
            return Position.allCases.filter { $0.side == .offense }.map { position in
                let adjustments = SchemeFit.modifiers(for: position, in: scheme)
                return adjustments.keys.map(\.rawValue).sorted().map(String.init).joined(
                    separator: ",")
            }
        }
        let signatures = OffensiveScheme.families.map(signature)
        for first in signatures.indices {
            for second in signatures.indices where second > first {
                #expect(
                    signatures[first] != signatures[second],
                    "families \(first) and \(second) modify identical ratings")
            }
        }
    }

    @Test("Weights stay non-negative after a negative delta", .tags(.unit))
    func negativeDeltasClamp() {
        // Quick game drops a guard's pass blocking; it must not go below zero
        // and invert the maths.
        var ratings = Ratings()
        for key in RatingKey.keys(for: .leftGuard) { ratings[key] = 50 }
        ratings[.passBlock] = 99
        let scheme = TeamScheme(offense: .spread, defense: .fourThreeUnder)
        let overall = SchemeFit.effectiveOverall(ratings, at: .leftGuard, in: scheme)
        #expect(overall >= 50 && overall <= 99)
    }
}
