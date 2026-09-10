import FMCore
import FMGeneration
import FMRandom
import Testing

@testable import FMSimulation

/// Form is what correlates a player's plays within a game, and it is the difference
/// between a league where records can fall and one where they cannot. Independent
/// per-play randomness concentrates: a first pass produced a maximum of three passing
/// touchdowns in four hundred team-games and could never have produced four.
@Suite("Form")
struct FormTests {

    private let players = (1...40).map { PlayerID(UInt64($0)) }

    @Test("A player's day is the same every time the game is replayed")
    func deterministic() {
        let first = Form.table(for: players, game: GameID(7), seed: 99)
        let second = Form.table(for: players, game: GameID(7), seed: 99)
        #expect(first == second)
    }

    /// A day belongs to a game. The same player in a different week is a different day,
    /// or form would be a permanent rating rather than a day.
    @Test("A different game is a different day")
    func variesByGame() {
        let week1 = Form.table(for: players, game: GameID(1), seed: 99)
        let week2 = Form.table(for: players, game: GameID(2), seed: 99)
        #expect(week1 != week2)
        #expect(zip(players, players).allSatisfy { week1[$0.0] != nil && week2[$0.1] != nil })
    }

    /// Each player's day is drawn from a stream split on his own identifier, so signing
    /// somebody cannot shift a teammate's form.
    @Test("Adding a player does not disturb anybody else's day")
    func independentPerPlayer() {
        let small = Form.table(for: players.prefix(10), game: GameID(3), seed: 4)
        let large = Form.table(for: players, game: GameID(3), seed: 4)
        for player in players.prefix(10) {
            #expect(small[player] == large[player])
        }
    }

    /// Talent has to survive the noise. A spread wide enough to make a seventy play like
    /// a ninety would make ratings meaningless over a season.
    @Test("Ordinary days stay close to what a player is")
    func spreadIsModest() {
        let table = Form.table(
            for: (1...4_000).map { PlayerID(UInt64($0)) }, game: GameID(1), seed: 12)
        let values = table.values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)

        #expect(abs(mean) < 0.6, "form should not favour anybody on average: \(mean)")
        let typical = values.filter { abs($0) <= 8 }.count
        #expect(
            Double(typical) / Double(values.count) > 0.85,
            "most days should be within eight rating points")
    }

    /// And the tail has to exist, or a generational player in the right situation can
    /// never chase a number nobody should reach.
    @Test("Some days are well outside a player's normal range")
    func outliersHappen() {
        let table = Form.table(
            for: (1...4_000).map { PlayerID(UInt64($0)) }, game: GameID(1), seed: 12)
        let extremes = table.values.filter { abs($0) >= 12 }
        #expect(extremes.isEmpty == false, "nobody ever had an unusual day")
        #expect(
            Double(extremes.count) / Double(table.count) < 0.06,
            "an unusual day should be unusual")
        #expect(extremes.contains { $0 > 0 } && extremes.contains { $0 < 0 })
    }
}

@Suite("Scheme fit in the engine")
struct SchemeFitInEngineTests {

    private func context(
        scheme: TeamScheme, player: Player, form: [PlayerID: Double] = [:]
    ) -> PlayContext {
        PlayContext(
            offense: TeamID(1), defense: TeamID(2), offenseRotation: [], defenseRotation: [],
            players: [player.id: player], offenseScheme: scheme, defenseScheme: scheme,
            form: form, rules: .standard)
    }

    /// A receiver built for one thing and not the other. A *balanced* player fits
    /// everywhere by construction — the scheme's boosts and penalties cancel — so the
    /// design only shows on an uneven profile, which is the right behaviour and the
    /// reason a first version of this test read nothing at all.
    private func receiver(id: UInt64, ratings: Ratings) -> Player {
        Player(
            id: PlayerID(id),
            name: PersonName(given: "Test", family: "Receiver"),
            birthSeason: 2004,
            college: College(name: "Fallback State", profile: .midMajor),
            draft: nil,
            firstSeason: 2026,
            position: .wideReceiver,
            secondaryPositions: [],
            physical: PhysicalProfile(
                heightInches: 73, weightPounds: 200, fortyYardDash: 445, verticalJump: 350,
                broadJump: 1200, threeCone: 690, benchReps: 14),
            ratings: ratings,
            traits: [],
            hidden: HiddenAttributes(
                ceiling: 90, developmentTrait: .normal, workEthic: 60, durability: 60),
            status: .active)
    }

    private func fit(_ player: Player, _ offense: OffensiveScheme) -> Int {
        player.schemeFit(TeamScheme(offense: offense, defense: .nickelMatch))
    }

    /// The gap this closes: the resolver never mentioned a scheme, so a player in a
    /// system built around him performed exactly as he would in one that wasted him.
    /// `SchemeFit` was an elaborate no-op as far as the engine was concerned.
    @Test("A burner is a vertical receiver and a bad air-raid one")
    func schemeSuitsProfiles() {
        let burner = receiver(
            id: 1,
            ratings: [
                .speed: 96, .acceleration: 93, .catching: 70, .catchInTraffic: 66,
                .routeRunning: 58, .releaseVsPress: 62, .elusiveness: 78, .awareness: 62,
                .strength: 60, .agility: 84,
            ])
        let technician = receiver(
            id: 2,
            ratings: [
                .speed: 62, .acceleration: 68, .catching: 92, .catchInTraffic: 90,
                .routeRunning: 95, .releaseVsPress: 88, .elusiveness: 64, .awareness: 84,
                .strength: 68, .agility: 76,
            ])

        #expect(
            fit(burner, .verticalShots) > fit(burner, .airRaid),
            "a burner should be worth more to a vertical offence")
        #expect(
            fit(technician, .airRaid) > fit(technician, .verticalShots),
            "a route technician should be worth more to an air raid")
    }

    /// And the fit has to reach the engine, not merely exist on the player.
    @Test("The engine reads the scheme, not just the rating")
    func schemeReachesTheEngine() {
        let burner = receiver(
            id: 1,
            ratings: [
                .speed: 96, .acceleration: 93, .catching: 70, .catchInTraffic: 66,
                .routeRunning: 58, .releaseVsPress: 62, .elusiveness: 78, .awareness: 62,
            ])
        let vertical = context(
            scheme: TeamScheme(offense: .verticalShots, defense: .nickelMatch), player: burner
        ).effective(.speed, for: burner.id, onOffense: true)
        let airRaid = context(
            scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch), player: burner
        ).effective(.speed, for: burner.id, onOffense: true)

        #expect(vertical != airRaid, "the engine rated him the same in both systems")
        #expect(vertical > airRaid)
    }

    /// Fit is worth a few points, not a transformation. It should decide a close
    /// matchup without overturning talent.
    @Test("Fit moves a player without rewriting him")
    func fitIsBounded() {
        let burner = receiver(
            id: 1,
            ratings: [
                .speed: 96, .acceleration: 93, .catching: 70, .catchInTraffic: 66,
                .routeRunning: 58, .releaseVsPress: 62, .elusiveness: 78, .awareness: 62,
            ])
        for offense in OffensiveScheme.families {
            let moved = fit(burner, offense)
            #expect(abs(moved) <= 12, "\(offense) moved him by \(moved)")
        }
    }

    @Test("Form adds to the effective rating")
    func formIsApplied() {
        let player = receiver(id: 3, ratings: [.routeRunning: 80, .speed: 80, .catching: 80])
        let scheme = TeamScheme(offense: .airRaid, defense: .nickelMatch)
        let flat = context(scheme: scheme, player: player)
            .effective(.routeRunning, for: player.id, onOffense: true)
        let goodDay = context(scheme: scheme, player: player, form: [player.id: 7])
            .effective(.routeRunning, for: player.id, onOffense: true)
        #expect(abs((goodDay - flat) - 7) < 0.001)
    }

    @Test("An unknown player falls back rather than crashing")
    func missingPlayer() {
        let player = receiver(id: 3, ratings: [.routeRunning: 80])
        let value = context(
            scheme: TeamScheme(offense: .airRaid, defense: .nickelMatch), player: player
        )
        .effective(.routeRunning, for: PlayerID(9_999), onOffense: true)
        #expect(value == 60)
    }
}
