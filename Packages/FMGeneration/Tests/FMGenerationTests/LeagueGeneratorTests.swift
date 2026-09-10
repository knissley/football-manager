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

    @Test("A generated league satisfies its own structure validator", .tags(.contract))
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
    @Test("The same seed produces the same league", .tags(.contract))
    func deterministic() {
        guard let first = generate(), let second = generate() else {
            Issue.record("generation failed")
            return
        }
        #expect(first.league == second.league)
        #expect(first.teams == second.teams)
    }

    @Test("Different seeds produce different leagues", .tags(.contract))
    func seedsDiverge() {
        guard let a = generate(seed: 1), let b = generate(seed: 2) else {
            Issue.record("generation failed")
            return
        }
        #expect(a.teams.map(\.identity.fullName) != b.teams.map(\.identity.fullName))
    }

    /// An impossible shape is refused rather than generated around, and the refusal
    /// carries the reasons a player needs.
    @Test("An impossible shape is refused with its reasons", .tags(.unit))
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
    @Test("No two teams share a nickname", .tags(.contract))
    func nicknamesAreUnique() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        let nicknames = world.teams.map(\.identity.nickname)
        #expect(Set(nicknames).count == nicknames.count)
    }

    @Test("No two teams share a city", .tags(.contract))
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
    @Test("Every team's colours are legible", .tags(.unit))
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

    @Test("Abbreviations are two or three letters and uppercase", .tags(.unit))
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
    @Test("A division's name matches the weather of the cities in it", .tags(.unit))
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
    @Test("Each conference spans the same regions", .tags(.unit))
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
    @Test("City names do not share a stem", .tags(.contract))
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
    @Test("No two teams share an abbreviation", .tags(.contract))
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
    @Test("Stadiums vary in roof, surface and climate", .tags(.unit))
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
    @Test("Indoor stadiums are climate-neutral and louder", .tags(.unit))
    func domesAreNeutral() {
        for seed in UInt64(1)...10 {
            guard let world = generate(seed: seed) else { continue }
            for team in world.teams where team.stadium.isIndoors {
                #expect(team.stadium.climate == .temperate)
                #expect(team.stadium.weatherIsDecidedByClimate == false)
            }
        }
    }

    @Test("Capacities and noise stay in plausible ranges", .tags(.unit))
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
    @Test("High altitude exists but is rare", .tags(.unit))
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
    @Test("Markets span the range", .tags(.unit))
    func marketsVary() {
        guard let world = generate() else {
            Issue.record("generation failed")
            return
        }
        #expect(Set(world.teams.map(\.market)).count >= 3)
    }

    // MARK: - Stems and feature words

    /// The city's stem: its name with a pool suffix taken off. A bare city is all stem,
    /// and a stem of two words — the pools hold one — keeps both.
    private func stem(ofCity city: String) -> String {
        let words = city.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last, CityPools.suffixes.contains(last) else {
            return city
        }
        return words.dropLast().joined(separator: " ")
    }

    /// A nickname's comparable root: lowercased, with a plural ending taken off, so
    /// "Coyotes" and the city stem "Coyote" are the same word.
    private func stem(ofNickname nickname: String) -> String {
        let lowered = nickname.lowercased()
        return lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
    }

    /// The word a stadium is named for, when it is named for a feature rather than for
    /// its city. Read back off the pool rather than off the generator's ledger, so this
    /// fails if the ledger stops being honoured.
    private func featureWord(in stadiumName: String) -> String? {
        StadiumPools.features.first { stadiumName.hasPrefix("\($0) ") }
    }

    /// The ledger checked whole stadium names, so a feature word could name three
    /// grounds in one league — Riverfront Park, Riverfront Field and Riverfront Arena
    /// read as one ground written down three times. Decision 154 fixed exactly this for
    /// city stems and fixed it there only (issue #4).
    ///
    /// Twelve seeds, standard shape: a feature word that appears twice in any of them is
    /// a league that names its grounds after itself.
    @Test(
        "contract: a stadium feature word names one ground in a world", .tags(.contract),
        arguments: Array(UInt64(1)...12))
    func stadiumFeatureWordsAreUsedOnce(seed: UInt64) {
        guard let world = generate(seed: seed) else {
            Issue.record("seed \(seed) did not generate")
            return
        }

        // Keyed lookup, walked in the league's own team order — nothing here iterates the
        // dictionary, so the failure it reports is the same one every run (rule 2).
        var named: [String: String] = [:]
        for team in world.teams {
            guard let feature = featureWord(in: team.stadium.name) else { continue }
            if let already = named[feature] {
                Issue.record(
                    "seed \(seed): \(feature) names both \(already) and \(team.stadium.name)")
            }
            named[feature] = team.stadium.name
        }
    }

    /// A nickname that repeats its own city — Coyote Coyotes — is the stutter the city
    /// stem ledger already refuses between two cities, and the nickname draw never
    /// checked for (issue #4).
    ///
    /// The twelve-seed sweep is seeds 1 through 12; 14 and 42 are on the end because they
    /// are where the fault actually shows in the first four dozen worlds, and a sweep
    /// that only ever passes is not evidence of anything.
    @Test(
        "contract: a nickname never repeats the city it plays in", .tags(.contract),
        arguments: Array(UInt64(1)...12) + [UInt64(14), UInt64(42)])
    func nicknamesDoNotEchoTheirCity(seed: UInt64) {
        guard let world = generate(seed: seed) else {
            Issue.record("seed \(seed) did not generate")
            return
        }

        for team in world.teams {
            let city = stem(ofCity: team.identity.city).lowercased()
            let nickname = team.identity.nickname.lowercased()
            #expect(
                nickname.contains(city) == false,
                "seed \(seed): \(team.identity.fullName) says its city twice")
            #expect(
                city.contains(stem(ofNickname: nickname)) == false,
                "seed \(seed): \(team.identity.fullName) says its city twice")
        }
    }

    /// Two nicknames that reduce to one word are two teams with one name, whatever the
    /// spelling. Nothing in today's pools reduces to another entry, and the ledger keys
    /// on the stem so that a pool which grows a singular beside its plural cannot hand
    /// out both.
    @Test(
        "contract: no two teams share a nickname stem", .tags(.contract),
        arguments: Array(UInt64(1)...12))
    func nicknameStemsAreDistinct(seed: UInt64) {
        guard let world = generate(seed: seed) else {
            Issue.record("seed \(seed) did not generate")
            return
        }
        let stems = world.teams.map { TeamGenerator.stem(ofNickname: $0.identity.nickname) }
        #expect(Set(stems).count == stems.count, "seed \(seed) repeats a nickname stem")
    }

    /// The rule the nickname draw applies, on its own. An echo is a shared word in
    /// either direction; a shared *idea* is not one, and the last row says so rather
    /// than leaving the gap for someone to find in a standings table.
    @Test(
        "unit: a nickname echoes its city when either name carries the other's word", .tags(.unit),
        arguments: [
            ("Coyotes", "Coyote", true),
            ("Frostbite", "Frost", true),
            ("Timberwolves", "Timber", true),
            ("Elk", "Elkhart", true),
            ("Pumas", "Kettle", false),
            ("Surge", "Big Sur", false),
            ("Blizzard", "Winter", false),
        ])
    func nicknameEchoes(nickname: String, city: String, isEcho: Bool) {
        #expect(TeamGenerator.echoesCity(nickname, stem: city) == isEcho)
    }

    /// Crude on purpose: the stem is a key for comparing two names, not grammar. "Foxes"
    /// reducing to "foxe" is the honest shape of that, and it is written down here so a
    /// later reader does not mistake it for a bug.
    @Test(
        "unit: a nickname's stem is its name without a plural ending", .tags(.unit),
        arguments: [
            ("Coyotes", "coyote"),
            ("Elk", "elk"),
            ("Foxes", "foxe"),
            ("Dust Devils", "dust devil"),
            ("Nor'easters", "nor'easter"),
        ])
    func nicknameStems(nickname: String, stem: String) {
        #expect(TeamGenerator.stem(ofNickname: nickname) == stem)
    }
}
