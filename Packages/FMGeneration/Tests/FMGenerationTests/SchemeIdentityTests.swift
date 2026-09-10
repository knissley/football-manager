import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030

private func roster(
    builtFor scheme: TeamScheme?, strength: RosterGenerator.Strength = .leagueAverage,
    seed: UInt64 = 1
) -> [Player] {
    var random = SplittableRandom(seed: seed)
    var ids = IdentifierSequence<PlayerSubject>()
    return RosterGenerator.roster(
        strength: strength, builtFor: scheme, season: season,
        colleges: [], ids: &ids, using: &random)
}

private func meanCeiling(_ players: [Player], at position: Position) -> Double {
    let values = players.filter { $0.position == position }.map { Int($0.hidden.ceiling) }
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

private func meanFit(_ players: [Player], at position: Position, in scheme: TeamScheme) -> Double {
    let values = players.filter { $0.position == position }.map { $0.schemeFit(scheme) }
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

private let powerRun = TeamScheme(offense: .powerRun, defense: .fourThreeUnder)
private let airRaid = TeamScheme(offense: .airRaid, defense: .fourThreeUnder)

@Suite("Where a scheme puts its talent")
struct SchemeCeilingTests {

    /// The point that prompted this: a smashmouth club should not simply roll a
    /// generational passer it would have no idea what to do with.
    @Test("A run-heavy team invests less in a quarterback than a pass-heavy one", .tags(.unit))
    func quarterbackInvestment() {
        var run = 0.0
        var pass = 0.0
        for seed in UInt64(1)...25 {
            run += meanCeiling(roster(builtFor: powerRun, seed: seed), at: .quarterback)
            pass += meanCeiling(roster(builtFor: airRaid, seed: seed), at: .quarterback)
        }
        #expect(pass > run + 3, "run \(run / 25), pass \(pass / 25)")
    }

    @Test("And more in the run game", .tags(.unit))
    func runGameInvestment() {
        var runBacks = 0.0
        var passBacks = 0.0
        var runGuards = 0.0
        var passGuards = 0.0
        for seed in UInt64(1)...25 {
            let runTeam = roster(builtFor: powerRun, seed: seed)
            let passTeam = roster(builtFor: airRaid, seed: seed)
            runBacks += meanCeiling(runTeam, at: .runningBack)
            passBacks += meanCeiling(passTeam, at: .runningBack)
            runGuards += meanCeiling(runTeam, at: .leftGuard)
            passGuards += meanCeiling(passTeam, at: .leftGuard)
        }
        #expect(runBacks > passBacks + 2, "backs: run \(runBacks / 25), pass \(passBacks / 25)")
        #expect(
            runGuards > passGuards + 1, "guards: run \(runGuards / 25), pass \(passGuards / 25)")
    }

    @Test("Receivers follow the passing game", .tags(.unit))
    func receiverInvestment() {
        var run = 0.0
        var pass = 0.0
        for seed in UInt64(1)...25 {
            run += meanCeiling(roster(builtFor: powerRun, seed: seed), at: .wideReceiver)
            pass += meanCeiling(roster(builtFor: airRaid, seed: seed), at: .wideReceiver)
        }
        #expect(pass > run + 2)
    }

    /// Identity should be legible, not crippling. A run-heavy team still has to
    /// be able to employ a decent quarterback.
    @Test("Identity shifts investment without gutting a position", .tags(.unit))
    func shiftsAreBounded() {
        for position in Position.allCases {
            for offense in OffensiveScheme.families {
                for defense in DefensiveScheme.families {
                    let scheme = TeamScheme(offense: offense, defense: defense)
                    let delta = SchemeIdentity.ceilingDelta(for: position, in: scheme)
                    #expect(
                        abs(delta) <= 6.5, "\(position) under \(offense.passing) moved \(delta)")
                }
            }
        }
    }

    @Test("Specialists are unaffected by identity", .tags(.unit))
    func specialistsUnaffected() {
        for scheme in OffensiveScheme.families {
            let team = TeamScheme(offense: scheme, defense: .pressManBlitz)
            for position in [Position.kicker, .punter, .longSnapper] {
                #expect(SchemeIdentity.ceilingDelta(for: position, in: team) == 0)
            }
        }
    }

    @Test("Defensive identity moves the positions it depends on", .tags(.unit))
    func defensiveInvestment() {
        let threeFour = TeamScheme(offense: .westCoast, defense: .threeFourOkie)
        let pressMan = TeamScheme(offense: .westCoast, defense: .pressManBlitz)
        #expect(SchemeIdentity.ceilingDelta(for: .defensiveTackle, in: threeFour) > 0)
        #expect(SchemeIdentity.ceilingDelta(for: .cornerback, in: pressMan) > 0)
        #expect(SchemeIdentity.ceilingDelta(for: .cornerback, in: threeFour) == 0)
    }
}

@Suite("What kind of player a scheme produces")
struct SchemeShapeTests {

    /// The second effect, and the one that must not become the first: a scheme
    /// changes what kind of player a club acquired, not how good he is.
    @Test("Players are built to suit the scheme they were acquired for", .tags(.unit))
    func playersFitTheirScheme() {
        var own = 0.0
        var foreign = 0.0
        for seed in UInt64(1)...20 {
            let team = roster(builtFor: powerRun, seed: seed)
            own += meanFit(team, at: .leftGuard, in: powerRun)
            foreign += meanFit(team, at: .leftGuard, in: airRaid)
        }
        #expect(own > foreign + 3, "own \(own / 20), foreign \(foreign / 20)")
    }

    @Test("A zone team's linemen suit zone and a gap team's suit gap", .tags(.unit))
    func linemenDiverge() {
        let zoneTeam = TeamScheme(offense: .zoneRun, defense: .fourThreeUnder)
        var zoneInZone = 0.0
        var gapInZone = 0.0
        for seed in UInt64(1)...20 {
            zoneInZone += meanFit(roster(builtFor: zoneTeam, seed: seed), at: .center, in: zoneTeam)
            gapInZone += meanFit(roster(builtFor: powerRun, seed: seed), at: .center, in: zoneTeam)
        }
        #expect(zoneInZone > gapInZone + 3, "zone \(zoneInZone / 20), gap \(gapInZone / 20)")
    }

    /// Fit must be a bonus in the right scheme, never free rating points. A
    /// player's base overall is corrected to his target regardless.
    @Test("Scheme bias changes shape, not quality", .tags(.contract))
    func biasDoesNotInflateOverall() {
        for scheme in [powerRun, airRaid] {
            var random = SplittableRandom(seed: 41)
            var untrained = SplittableRandom(seed: 42)
            var errors: [Int] = []
            for _ in 0..<300 {
                let bias = SchemeIdentity.ratingBias(for: .leftGuard, in: scheme)
                let ratings = PlayerGenerator.ratings(
                    position: .leftGuard, targetOverall: 78, bias: bias, using: &random,
                    untrained: &untrained)
                errors.append(Int(PositionWeights.overall(ratings, at: .leftGuard)) - 78)
            }
            let mean = Double(errors.reduce(0, +)) / Double(errors.count)
            #expect(abs(mean) < 1.0, "bias inflated overall by \(mean)")
        }
    }

    @Test("An unschemed roster is still generated correctly", .tags(.unit))
    func noSchemeIsFine() {
        let players = roster(builtFor: nil)
        #expect(players.count == 53)
        for player in players {
            #expect(player.overall <= player.hidden.ceiling)
            #expect(player.ratings.isComplete)
        }
    }

    @Test("Scheme generation stays deterministic", .tags(.contract))
    func deterministic() {
        #expect(roster(builtFor: powerRun, seed: 77) == roster(builtFor: powerRun, seed: 77))
    }
}

@Suite("Identity mismatches")
struct SchemeMismatchTests {

    /// A run-heavy club with a gifted young passer is a team that ought to
    /// change. Deliberate, not a generation flaw.
    @Test("A minority of teams play a scheme their roster does not suit", .tags(.unit))
    func mismatchesHappen() {
        var random = SplittableRandom(seed: 5)
        var mismatched = 0
        let trials = 4000
        for _ in 0..<trials where SchemeIdentity.identity(using: &random).isMismatched {
            mismatched += 1
        }
        let rate = Double(mismatched) / Double(trials)
        #expect(rate > 0.08 && rate < 0.17, "mismatch rate \(rate)")
    }

    @Test("A mismatched identity really is two different schemes", .tags(.unit))
    func mismatchIsGenuine() {
        var random = SplittableRandom(seed: 9)
        for _ in 0..<2000 {
            let identity = SchemeIdentity.identity(using: &random)
            if identity.isMismatched {
                #expect(identity.played != identity.builtFor)
            } else {
                #expect(identity.played == identity.builtFor)
            }
        }
    }

    /// The situation from the player's side: your roster suits something other
    /// than what you run, and switching would visibly help.
    @Test("A mismatched roster fits the scheme it was built for better", .tags(.unit))
    func mismatchIsVisible() {
        var built = 0.0
        var played = 0.0
        for seed in UInt64(1)...20 {
            let team = roster(builtFor: powerRun, seed: seed)
            // The club plays air raid with a roster assembled for power run.
            built += meanFit(team, at: .leftGuard, in: powerRun)
            played += meanFit(team, at: .leftGuard, in: airRaid)
        }
        #expect(built > played, "built \(built / 20), played \(played / 20)")
    }
}
