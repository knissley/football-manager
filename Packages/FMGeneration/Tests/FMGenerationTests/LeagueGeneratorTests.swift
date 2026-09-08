import FMCore
import FMRandom
import Testing

@testable import FMGeneration

@Suite("League generation")
struct LeagueGeneratorTests {

    private func generate(
        shape: LeagueShape = .standard, seed: UInt64 = 7
    ) -> LeagueGenerator.GeneratedLeague? {
        var random = SplittableRandom(seed: seed)
        return try? LeagueGenerator.league(shape: shape, using: &random).get()
    }

    @Test("A generated league satisfies its own structure validator")
    func wellFormed() {
        for shape in [LeagueShape.standard, .compact, .minimal] {
            guard let world = generate(shape: shape) else {
                Issue.record("\(shape.totalTeams)-team league failed to generate")
                continue
            }
            #expect(world.league.isWellFormed)
            #expect(world.teams.count == shape.totalTeams)
            #expect(world.league.teams.count == shape.totalTeams)
        }
    }

    /// Rule 2: the same seed is the same world, or saved history is corrupt rather
    /// than merely different.
    @Test("The same seed produces the same league")
    func deterministic() {
        guard let first = generate(), let second = generate() else {
            Issue.record("generation failed")
            return
        }
        #expect(first.league == second.league)
        #expect(first.teams == second.teams)
    }

    @Test("Different seeds produce different leagues")
    func seedsDiverge() {
        guard let a = generate(seed: 1), let b = generate(seed: 2) else {
            Issue.record("generation failed")
            return
        }
        #expect(a.teams.map(\.identity.fullName) != b.teams.map(\.identity.fullName))
    }

    /// An impossible shape is refused rather than generated around, and the refusal
    /// carries the reasons a player needs.
    @Test("An impossible shape is refused with its reasons")
    func refusesImpossibleShapes() {
        var random = SplittableRandom(seed: 1)
        let oneConference = LeagueShape(
            conferences: 1, divisionsPerConference: 4, teamsPerDivision: 4,
            regularSeasonGames: 17, playoffTeamsPerConference: 7)

        switch LeagueGenerator.league(shape: oneConference, using: &random) {
        case .success:
            Issue.record("a one-conference league should not generate")
        case .failure(let error):
            guard case .invalidShape = error else {
                Issue.record("expected a shape failure, got \(error)")
                return
            }
            #expect(error.explanations.contains { $0.contains("championship") })
        }
    }

    // MARK: - The things a standings table would show

    /// Two teams with one nickname is the kind of thing nobody notices in a test and
    /// everybody notices in a standings table.
    @Test("No two teams share a nickname")
    func nicknamesAreUnique() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        let nicknames = world.teams.map(\.identity.nickname)
        #expect(Set(nicknames).count == nicknames.count)
    }

    @Test("No two teams share a city")
    func citiesAreUnique() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        let cities = world.teams.map(\.identity.city)
        #expect(Set(cities).count == cities.count)
    }

    /// Every team's colours have to read against each other, or the scoreboard is
    /// illegible no matter how good the simulation underneath it is.
    @Test("Every team's colours are legible")
    func colorsAreLegible() {
        for seed in UInt64(1)...12 {
            guard let world = generate(seed: seed) else { continue }
            for team in world.teams {
                #expect(
                    team.identity.colors.hasReadableContrast,
                    "\(team.identity.fullName) on seed \(seed) has unreadable colours")
            }
        }
    }

    @Test("Abbreviations are two or three letters and uppercase")
    func abbreviations() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        for team in world.teams {
            let abbreviation = team.identity.abbreviation
            #expect(abbreviation.count >= 2 && abbreviation.count <= 3, "\(abbreviation)")
            #expect(abbreviation == abbreviation.uppercased())
            #expect(abbreviation.allSatisfy { $0.isLetter || $0.isNumber })
        }
    }

    /// A division named "South" full of cities with hard winters reads as broken the
    /// moment anybody looks at a standings table. The name has to match the region.
    @Test("A division's name matches the weather of the cities in it")
    func divisionNamesMatchTheirRegion() {
        guard let world = generate(seed: 42) else {
            Issue.record("generation failed")
            return
        }

        // Cold is a northern climate in this world and hot is a southern one, so a
        // division named for one must not be full of the other.
        for division in world.league.divisions {
            let climates = division.teams.compactMap { world.team($0)?.stadium }
                .filter { !$0.isIndoors }.map(\.climate)

            if division.name == "North" {
                #expect(climates.contains(.hot) == false, "a hot city in the North division")
            }
            if division.name == "South" {
                #expect(climates.contains(.cold) == false, "a cold city in the South division")
            }
        }
    }

    /// Every conference fields one division per region, exactly as the real structure
    /// does. If that stops holding, a conference can end up entirely northern.
    @Test("Each conference spans the same regions")
    func conferencesSpanRegions() {
        guard let world = generate(shape: .standard) else {
            Issue.record("generation failed")
            return
        }
        let names = world.league.conferences.map { $0.divisions.map(\.name) }
        #expect(names.allSatisfy { $0 == ["North", "South", "East", "West"] })
    }

    /// Four teams named Saltflat-something read as one city with a stutter, which
    /// uniqueness of the full name does not catch.
    @Test("City names do not share a stem")
    func cityStemsAreDistinct() {
        for seed in UInt64(1)...8 {
            guard let world = generate(seed: seed) else { continue }
            let stems = world.teams.map { $0.identity.city.split(separator: " ")[0] }
            #expect(
                Set(stems).count == stems.count,
                "seed \(seed) repeats a city stem: \(stems.sorted())")
        }
    }

    /// Two teams abbreviated the same way is ambiguous everywhere a scoreboard is
    /// narrow enough to need the short form.
    @Test("No two teams share an abbreviation")
    func abbreviationsAreUnique() {
        for seed in UInt64(1)...8 {
            guard let world = generate(seed: seed) else { continue }
            let abbreviations = world.teams.map(\.identity.abbreviation)
            #expect(
                Set(abbreviations).count == abbreviations.count,
                "seed \(seed) repeats an abbreviation")
        }
    }

    /// A world where every stadium is a temperate dome has no weather, and weather is
    /// half of what makes a December road game feel different.
    @Test("Stadiums vary in roof, surface and climate")
    func stadiumsVary() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        let stadiums = world.teams.map(\.stadium)

        #expect(stadiums.contains { $0.isIndoors })
        #expect(stadiums.contains { !$0.isIndoors })
        #expect(Set(stadiums.map(\.surface)).count >= 2)
        #expect(Set(stadiums.filter { !$0.isIndoors }.map(\.climate)).count >= 3)
        #expect(Set(stadiums.map(\.name)).count == stadiums.count, "stadium names repeat")
    }

    /// A dome has no weather to speak of, so recording a climate for one would be a
    /// fact the engine could read and act on wrongly.
    @Test("Indoor stadiums are climate-neutral and louder")
    func domesAreNeutral() {
        for seed in UInt64(1)...10 {
            guard let world = generate(seed: seed) else { continue }
            for team in world.teams where team.stadium.isIndoors {
                #expect(team.stadium.climate == .temperate)
                #expect(team.stadium.weatherIsDecidedByClimate == false)
            }
        }
    }

    @Test("Capacities and noise stay in plausible ranges")
    func plausibleStadiums() {
        for seed in UInt64(1)...10 {
            guard let world = generate(seed: seed) else { continue }
            for team in world.teams {
                #expect(team.stadium.capacity >= 50_000 && team.stadium.capacity <= 85_000)
                #expect(team.stadium.noise >= 35 && team.stadium.noise <= 100)
                #expect(team.stadium.altitudeFeet >= 0 && team.stadium.altitudeFeet <= 6_000)
            }
        }
    }

    /// Altitude is a western thing in this world's geography, and it is real simulation
    /// input — a kick from five thousand feet carries.
    @Test("High altitude exists but is rare")
    func altitudeIsRare() {
        var highAltitudeTeams = 0
        var total = 0
        for seed in UInt64(1)...8 {
            guard let world = generate(seed: seed) else { continue }
            total += world.teams.count
            highAltitudeTeams += world.teams.filter { $0.stadium.isHighAltitude }.count
        }
        #expect(highAltitudeTeams > 0, "no high-altitude stadium in eight leagues")
        #expect(highAltitudeTeams * 4 < total, "high altitude should be unusual")
    }

    /// Markets drive revenue and free agent appeal. A league of nothing but major
    /// markets has no small-market problem to solve, which is half the GM's job.
    @Test("Markets span the range")
    func marketsVary() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        #expect(Set(world.teams.map(\.market)).count >= 3)
    }
}
