import FMCore
import FMRandom
import Testing

@testable import FMGeneration

@Suite("Rivalry seeding")
struct RivalryGeneratorTests {

    private struct World {
        let league: League
        let teams: [Team]
        let rivalries: [Rivalry]
    }

    private func world(
        seed: UInt64 = 13, shape: LeagueShape = .standard,
        settings: RivalryGenerator.Settings = .standard
    ) -> World? {
        var random = SplittableRandom(seed: seed)
        guard let generated = try? LeagueGenerator.league(shape: shape, using: &random).get() else {
            return nil
        }
        let rivalries = RivalryGenerator.rivalries(
            league: generated.league, teams: generated.teams, currentSeason: 2030,
            settings: settings, using: &random)
        return World(league: generated.league, teams: generated.teams, rivalries: rivalries)
    }

    @Test("The same seed seeds the same grudges")
    func deterministic() {
        #expect(world()?.rivalries == world()?.rivalries)
    }

    /// Everyone in your division is a rivalry by construction: you play them twice a
    /// year and share a bracket.
    @Test("Every divisional pair is a rivalry")
    func divisionalPairsAreCovered() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let seeded = Set(world.rivalries.map(\.pair))

        for division in world.league.divisions {
            for (index, team) in division.teams.enumerated() {
                for other in division.teams[(index + 1)...] {
                    #expect(seeded.contains(TeamPair(team, other)))
                }
            }
        }
        #expect(world.rivalries.contains { $0.origin == .divisional })
    }

    @Test("A rivalry is never stored twice, and never with itself")
    func pairsAreUnique() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        #expect(Set(world.rivalries.map(\.pair)).count == world.rivalries.count)
        #expect(world.rivalries.allSatisfy { $0.pair.lower != $0.pair.higher })
    }

    /// Cross-division rivalries have to be earned. The crosstown game is the one that
    /// earns itself by geography.
    @Test("Extra rivalries exist beyond the divisions, and some are neighbours")
    func extrasAreSeeded() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let extras = world.rivalries.filter { $0.origin != .divisional }
        #expect(extras.isEmpty == false, "no rivalry outside the divisions")

        let regions = Dictionary(uniqueKeysWithValues: world.teams.map { ($0.id, $0.region) })
        for rivalry in extras where rivalry.origin == .regional {
            #expect(regions[rivalry.pair.lower] == regions[rivalry.pair.higher])
            #expect(
                world.league.areDivisionRivals(rivalry.pair.lower, rivalry.pair.higher) == false,
                "a regional rivalry should be outside the division")
        }
    }

    /// A rivalry whose origin is January needs the January game in its log, or the
    /// origin is an assertion with nothing behind it.
    @Test("An earned origin has the event that earned it")
    func originsAreEvidenced() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        for rivalry in world.rivalries {
            switch rivalry.origin {
            case .postseason:
                #expect(rivalry.history.contains { $0.kind == .playoffElimination })
            case .personal:
                #expect(rivalry.history.contains { $0.kind == .coachDefection })
            case .divisional, .regional:
                break
            }
        }
    }

    // MARK: - What the invented past looks like

    /// A world is not a blank slate: these teams have been playing each other for
    /// decades before you arrived.
    @Test("A new world starts with history")
    func historyExists() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let withHistory = world.rivalries.filter { !$0.history.isEmpty }
        #expect(withHistory.count > world.rivalries.count / 2)
    }

    @Test("Invented history sits in the past, in order")
    func historyIsInThePast() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        for rivalry in world.rivalries {
            #expect(rivalry.history.allSatisfy { $0.season < 2030 })
            #expect(rivalry.history.allSatisfy { $0.season >= 2030 - 12 })
            #expect(rivalry.history.allSatisfy { $0.pair == rivalry.pair })
            let seasons = rivalry.history.map(\.season)
            #expect(seasons == seasons.sorted())
        }
    }

    /// A history where every year produced a controversial finish is a highlight reel,
    /// not a history, and every pairing would open as a blood feud.
    @Test("Most of the invented past is ordinary")
    func historyIsMostlyOrdinary() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let events = world.rivalries.flatMap(\.history)
        #expect(events.count > 50)

        let ordinary = events.filter { $0.kind == .closeGame || $0.kind == .blowout }.count
        let seismic = events.filter { $0.kind == .titleGame || $0.kind == .controversialFinish }
            .count
        #expect(ordinary > events.count / 4, "not enough ordinary years")
        #expect(seismic < events.count / 6, "too many league-defining moments")
    }

    /// The whole reason history is a log rather than a number: a write-up has to be able
    /// to name what happened.
    @Test("Every rivalry with history has something citable")
    func historyIsCitable() {
        guard let world = world(settings: .brief) else {
            Issue.record("generation failed")
            return
        }
        for rivalry in world.rivalries where !rivalry.history.isEmpty {
            #expect(rivalry.liveHistory(in: 2030).isEmpty == false)
        }
    }

    /// Divisional pairs play twice a year, so they have more to argue about.
    @Test("Divisional rivalries run hotter than the rest")
    func divisionalRivalriesAreHotter() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        func meanIntensity(_ rivalries: [Rivalry]) -> Double {
            guard !rivalries.isEmpty else { return 0 }
            return rivalries.reduce(0) { $0 + $1.intensity(in: 2030) } / Double(rivalries.count)
        }
        let divisional = world.rivalries.filter { $0.origin == .divisional }
        let rest = world.rivalries.filter { $0.origin != .divisional }
        #expect(meanIntensity(divisional) > meanIntensity(rest))
    }

    /// If everything opens bitter, nothing that happens afterwards can raise the stakes.
    @Test("A new world has a spread of heat, not a league of blood feuds")
    func heatIsSpread() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let heats = world.rivalries.map { $0.heat(in: 2030) }
        #expect(Set(heats).count >= 3, "every rivalry opens at the same temperature")

        let bitter = heats.filter { $0 == .bitter }.count
        #expect(bitter < heats.count / 4, "too much of the league opens bitter: \(bitter)")
        #expect(heats.contains(.heated) || heats.contains(.bitter), "nothing is warm at all")
    }

    /// Only one pair can have played in a given championship game. History is invented
    /// per pair, so three rivalries independently claimed the same one — which reads as
    /// fabricated the instant anybody looks at two of them together.
    @Test("At most one title game per season across the whole league")
    func titleGamesAreUnique() {
        for seed in UInt64(1)...8 {
            guard let world = world(seed: seed) else { continue }
            let titleSeasons = world.rivalries.flatMap(\.history)
                .filter { $0.kind == .titleGame }
                .map(\.season)
            #expect(
                Set(titleSeasons).count == titleSeasons.count,
                "seed \(seed) played two championship games in one season")
        }
    }

    /// Four origins exist, so all four should be reachable. Earlier passes allocated the
    /// extras by ranked order, and whichever origin had the most candidates silently
    /// took every slot.
    @Test("A league seeds every kind of rivalry")
    func everyOriginIsRepresented() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        let origins = Set(world.rivalries.map(\.origin))
        #expect(
            origins.count == RivalryOrigin.allCases.count,
            "only these origins were seeded: \(origins.sorted { $0.rawValue < $1.rawValue })")
    }

    /// A new world tops out at heated by design: the seeded past gives texture, and the
    /// first genuine blood feud should be one the player caused. But `bitter` must be
    /// reachable, or a whole band of the scale is dead.
    @Test("Bitter is out of reach at creation and reachable through lived history")
    func bitterIsEarnedNotSeeded() {
        guard let world = world() else {
            Issue.record("generation failed")
            return
        }
        #expect(
            world.rivalries.allSatisfy { $0.heat(in: 2030) != .bitter },
            "a brand-new world should not open with a blood feud")

        // A few genuinely bad years between two teams gets there.
        guard var lived = world.rivalries.first(where: { $0.origin == .divisional }) else {
            Issue.record("expected a divisional rivalry")
            return
        }
        for season in 2031...2034 {
            lived.history.append(
                RivalryEvent(pair: lived.pair, season: season, kind: .playoffElimination))
            lived.history.append(
                RivalryEvent(pair: lived.pair, season: season, kind: .controversialFinish))
        }
        #expect(lived.heat(in: 2034) == .bitter, "four bitter seasons should get there")
    }

    @Test("A smaller league still seeds a coherent set")
    func smallLeagues() {
        guard let world = world(shape: .compact, settings: .brief) else {
            Issue.record("generation failed")
            return
        }
        #expect(world.rivalries.isEmpty == false)
        #expect(world.rivalries.allSatisfy { world.league.teams.contains($0.pair.lower) })
        #expect(world.rivalries.allSatisfy { world.league.teams.contains($0.pair.higher) })
    }
}
