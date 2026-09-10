import FMCore
import FMRandom
import Testing

@testable import FMGeneration

/// The thirty-two franchises a career starts from, and the promise that they are the
/// same thirty-two every time.
///
/// The rule these are written from is [decision 215](../../../../docs/design-decisions.md):
/// the initial world starts from one curated set of franchises, rosters are still
/// generated, and the pool randomiser is a last resort behind an explicit option. So the
/// contracts are: the set is a league (thirty-two clubs nothing about which collides),
/// two seeds are two leagues in the same buildings, and the randomiser still produces
/// the ledger-clean league [#4](https://github.com/knissley/football-manager/issues/4)
/// made it produce.
///
/// One thing here is *not* mechanical and cannot be: that no line is a real club's city
/// and nickname. Checking that needs the list of real franchises, which cannot be in
/// this repository ([ADR-0005](../../../../docs/adr/0005-generated-fictional-content.md)),
/// so it is a review, and the review is recorded on
/// [#69](https://github.com/knissley/football-manager/issues/69).
@Suite("Curated franchises")
struct FranchiseSetTests {

    private func world(
        seed: UInt64, shape: LeagueShape = .standard, franchises: FranchiseSource = .curated
    ) -> WorldGenerator.GeneratedWorld? {
        try? WorldGenerator.generate(
            seed: seed, shape: shape, franchises: franchises, season: 2030,
            parts: .teamsAndRosters, collegeCount: 20
        ).get()
    }

    private func league(
        shape: LeagueShape = .standard, franchises: FranchiseSource = .curated, seed: UInt64 = 7
    ) -> LeagueGenerator.GeneratedLeague? {
        var random = SplittableRandom(seed: seed)
        return try? LeagueGenerator.league(
            shape: shape, franchises: franchises, using: &random
        ).get()
    }

    /// The word a ground is named for: everything before the kind it ends with. It is
    /// what collides — Riverfront Park and Riverfront Field are one ground written down
    /// twice — and the curated table has to obey the same rule the ledger enforces on a
    /// drawn one.
    private func stadiumFeature(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        return words.count > 1 ? words.dropLast().joined(separator: " ") : name
    }

    private func duplicates(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var repeated: [String] = []
        for value in values where !seen.insert(value).inserted { repeated.append(value) }
        return repeated.sorted()
    }

    // MARK: - The set itself

    @Test("contract: the curated set is thirty-two franchises, eight to a region", .tags(.contract))
    func theSetIsALeague() {
        #expect(FranchiseSet.initial.count == 32)
        for region in Region.allCases {
            #expect(
                FranchiseSet.franchises(in: region).count == 8,
                "\(region) has \(FranchiseSet.franchises(in: region).count) franchises, not 8")
        }
    }

    /// The ledger rules of [decision 154](../../../../docs/design-decisions.md), which a
    /// curated set has to hold by construction because there is no draw left to enforce
    /// them: two clubs with one nickname, one abbreviation or one ground is exactly what
    /// a standings table shows and a per-franchise test cannot see.
    @Test(
        "contract: nothing in the curated set collides with anything else in it", .tags(.contract))
    func nothingCollides() {
        let set = FranchiseSet.initial

        #expect(duplicates(set.map(\.city)).isEmpty, "repeated city")
        #expect(
            duplicates(set.map { TeamGenerator.stem(ofCity: $0.city) }).isEmpty,
            "repeated city stem")
        #expect(duplicates(set.map(\.nickname)).isEmpty, "repeated nickname")
        #expect(
            duplicates(set.map { TeamGenerator.stem(ofNickname: $0.nickname) }).isEmpty,
            "repeated nickname stem")
        #expect(duplicates(set.map(\.abbreviation)).isEmpty, "repeated abbreviation")
        #expect(duplicates(set.map(\.stadiumName)).isEmpty, "repeated stadium")
        #expect(
            duplicates(set.map { stadiumFeature($0.stadiumName) }).isEmpty,
            "two grounds named for one word")
    }

    /// Coyote Coyotes. The randomiser refuses it by drawing again; the table has to be
    /// written so it never comes up.
    @Test("contract: no curated nickname repeats the city it plays in", .tags(.contract))
    func nicknamesDoNotEchoTheirCity() {
        for franchise in FranchiseSet.initial {
            #expect(
                TeamGenerator.echoesCity(
                    franchise.nickname, stem: TeamGenerator.stem(ofCity: franchise.city)) == false,
                "\(franchise.fullName) says its city twice")
        }
    }

    /// A scoreboard nobody can read is not fixed by good simulation underneath it
    /// ([decision 152](../../../../docs/design-decisions.md)). Drawn colours are checked
    /// across twelve seeds; curated ones are checked here, because a hand edit is
    /// exactly how an illegible pairing would get in.
    @Test("contract: every curated club's colours read against each other", .tags(.contract))
    func colorsAreLegible() {
        for franchise in FranchiseSet.initial {
            #expect(
                franchise.colors.hasReadableContrast,
                "\(franchise.fullName)'s colours do not read")
        }
    }

    @Test("contract: an abbreviation is two or three uppercase letters", .tags(.contract))
    func abbreviationsAreShortAndUpper() {
        for franchise in FranchiseSet.initial {
            let abbreviation = franchise.abbreviation
            #expect(abbreviation.count >= 2 && abbreviation.count <= 3, "\(abbreviation)")
            #expect(abbreviation == abbreviation.uppercased())
            #expect(abbreviation.allSatisfy { $0.isLetter })
        }
    }

    /// The stadium is simulation input ([decision 151](../../../../docs/design-decisions.md)),
    /// so a hand edit reaches the engine. These are the bounds the drawn ones were built
    /// inside, kept as bounds on the table.
    @Test("contract: every curated ground is one a game could be played in", .tags(.contract))
    func groundsArePlausible() {
        for franchise in FranchiseSet.initial {
            let ground = franchise.stadium
            #expect(
                ground.capacity >= 50_000 && ground.capacity <= 85_000,
                "\(ground.name) seats \(ground.capacity)")
            #expect(ground.noise >= 35 && ground.noise <= 100, "\(ground.name) at \(ground.noise)")
            #expect(
                ground.altitudeFeet >= 0 && ground.altitudeFeet <= 6_000,
                "\(ground.name) at \(ground.altitudeFeet)ft")
        }
    }

    /// A dome has no weather to speak of, so recording a climate for one would be a fact
    /// the engine could read and act on wrongly. The table holds the *city's* climate,
    /// which is the fact a relocation or a new roof would keep.
    @Test("unit: a roof settles the weather; an open ground keeps the city's", .tags(.unit))
    func roofOverridesClimate() {
        for franchise in FranchiseSet.initial {
            if franchise.roof == .dome {
                #expect(franchise.stadium.isIndoors)
                #expect(franchise.stadium.climate == .temperate)
                #expect(franchise.stadium.weatherIsDecidedByClimate == false)
            } else {
                #expect(franchise.stadium.isIndoors == false)
                #expect(franchise.stadium.climate == franchise.climate)
            }
        }
    }

    /// A division is named for its region ([decision 153](../../../../docs/design-decisions.md)),
    /// so the region a franchise is written into decides what its weather is allowed to
    /// be. A "South" division full of hard winters reads as broken on sight.
    @Test("contract: a curated city's weather matches the division it will be in", .tags(.contract))
    func climatesMatchTheirRegion() {
        for franchise in FranchiseSet.franchises(in: .north) {
            #expect(franchise.climate != .hot, "\(franchise.fullName) is hot, in the North")
        }
        for franchise in FranchiseSet.franchises(in: .south) {
            #expect(franchise.climate != .cold, "\(franchise.fullName) is cold, in the South")
        }
    }

    /// A league where every ground is a temperate dome has no weather, and weather is
    /// half of what makes a December road game different. This was a property of the
    /// draw; now it is a property of the table, and the thing that could take it away is
    /// an edit.
    @Test(
        "contract: the curated league has weather, roofs and markets worth having", .tags(.contract)
    )
    func theLeagueHasTexture() {
        let set = FranchiseSet.initial
        let domes = set.filter { $0.roof == .dome }

        #expect(!domes.isEmpty, "no dome in the league")
        #expect(domes.count * 3 < set.count, "more than a third of the league is indoors")
        #expect(Set(set.map(\.surface)).count >= 2)
        #expect(Set(set.filter { $0.roof == .open }.map(\.climate)).count >= 3)
        #expect(Set(set.map(\.market)).count >= 3)

        // Altitude is real simulation input — a kick from five thousand feet carries —
        // and it is meant to be unusual rather than absent.
        let high = set.filter { $0.stadium.isHighAltitude }
        #expect(!high.isEmpty, "nowhere in the league is high")
        #expect(high.count * 4 < set.count, "high altitude should be unusual")
    }

    // MARK: - What a world does with it

    /// The point of the whole change. Two seeds are two leagues in the same buildings:
    /// the franchises are identical down to the noise in the stadium, and the rosters are
    /// not the same rosters ([decision 215](../../../../docs/design-decisions.md)).
    @Test(
        "contract: two seeds field the same thirty-two franchises with different rosters",
        .tags(.contract))
    func seedsShareFranchisesAndNotRosters() throws {
        let seven = try #require(world(seed: 7))
        let eleven = try #require(world(seed: 11))

        #expect(seven.teams.count == 32)
        #expect(seven.teams.map(\.identity) == eleven.teams.map(\.identity))
        #expect(seven.teams.map(\.stadium) == eleven.teams.map(\.stadium))
        #expect(seven.teams.map(\.market) == eleven.teams.map(\.market))
        #expect(seven.teams.map(\.region) == eleven.teams.map(\.region))

        let sameRoster = seven.teams.allSatisfy { team in
            seven.roster(of: team.id).map(\.name.full)
                == eleven.roster(of: team.id).map(\.name.full)
        }
        #expect(sameRoster == false, "two seeds produced the same rosters")
    }

    /// The curated table is the *league*, not a pool to draw from: the club in the first
    /// division of the first conference is the first line of the file for that region.
    @Test("contract: a world's franchises are the curated table, in file order", .tags(.contract))
    func theWorldIsTheTable() throws {
        let built = try #require(world(seed: 3))
        let expected = Region.allCases.sorted { $0.rawValue < $1.rawValue }
            .flatMap { FranchiseSet.franchises(in: $0) }

        #expect(Set(built.teams.map(\.identity.fullName)) == Set(expected.map(\.fullName)))
        for team in built.teams {
            let franchise = try #require(
                expected.first { $0.city == team.identity.city })
            #expect(team.identity.nickname == franchise.nickname)
            #expect(team.identity.abbreviation == franchise.abbreviation)
            #expect(team.identity.colors == franchise.colors)
            #expect(team.stadium == franchise.stadium)
            #expect(team.market == franchise.market)
            #expect(team.region == franchise.region)
        }
    }

    /// A smaller league takes the top of each region rather than its tail, so the file
    /// order says which franchises a test world — `.compact`, `.minimal` — is played in.
    @Test("contract: a smaller league takes the first franchises of each region", .tags(.contract))
    func smallerLeaguesTakeFromTheTop() throws {
        let built = try #require(league(shape: .minimal))
        let north = FranchiseSet.franchises(in: .north).prefix(4).map(\.city)
        let south = FranchiseSet.franchises(in: .south).prefix(4).map(\.city)

        #expect(built.teams.count == 8)
        #expect(Set(built.teams.map(\.identity.city)) == Set(north).union(south))
    }

    /// The league's own name is part of the same curated identity as the clubs in it
    /// ([decision 215](../../../../docs/design-decisions.md)): two careers open in the
    /// same league, not merely in the same buildings. It was a per-seed draw from
    /// `StructurePools.leagueNames` until
    /// [#82](https://github.com/knissley/football-manager/issues/82), so two careers in
    /// identically named clubs ran under differently named leagues.
    ///
    /// Twelve seeds rather than two, because the pool holds a handful of names and two
    /// seeds landing on one of them proves nothing — seeds 7 and 11 both drew "Premier
    /// Gridiron League" before this was fixed. The second assertion is what says the
    /// name is written rather than drawn: nothing the curated source produces may be a
    /// line of the pool.
    ///
    /// The randomiser keeps its draw, asserted in `LeagueGeneratorTests`.
    @Test("contract: every seed opens in the same curated league, by name", .tags(.contract))
    func theLeagueIsNamedByTheTable() throws {
        var names: Set<String> = []
        for seed in UInt64(1)...12 {
            names.insert(try #require(league(seed: seed)).league.name)
        }

        #expect(
            names.count == 1, "the curated league's name moved with the seed: \(names.sorted())")
        for name in names {
            #expect(
                StructurePools.leagueNames.contains(name) == false,
                "\(name) is a pool draw, not a name the curated table wrote down")
        }
    }

    // MARK: - The randomiser, still behind its option

    /// The last resort still has to work. Everything [#4](https://github.com/knissley/football-manager/issues/4)
    /// fixed is asserted here rather than only on the default path, because the default
    /// path no longer exercises any of it.
    @Test(
        "contract: the randomiser still produces a ledger-clean league",
        .tags(.contract),
        arguments: Array(UInt64(1)...8))
    func theRandomiserIsLedgerClean(seed: UInt64) throws {
        let built = try #require(league(franchises: .randomised, seed: seed))
        let teams = built.teams

        #expect(teams.count == 32)
        #expect(duplicates(teams.map(\.identity.city)).isEmpty, "seed \(seed): repeated city")
        #expect(
            duplicates(teams.map { TeamGenerator.stem(ofCity: $0.identity.city) }).isEmpty,
            "seed \(seed): repeated city stem")
        #expect(
            duplicates(teams.map(\.identity.nickname)).isEmpty, "seed \(seed): repeated nickname")
        #expect(
            duplicates(teams.map { TeamGenerator.stem(ofNickname: $0.identity.nickname) }).isEmpty,
            "seed \(seed): repeated nickname stem")
        #expect(
            duplicates(teams.map(\.identity.abbreviation)).isEmpty,
            "seed \(seed): repeated abbreviation")
        #expect(
            duplicates(teams.map(\.stadium.name)).isEmpty, "seed \(seed): repeated stadium")
        // Feature words specifically: the ledger keys on the word, so a *drawn* league
        // must not name two grounds for one of them.
        let features = teams.compactMap { team in
            StadiumPools.features.first { team.stadium.name.hasPrefix("\($0) ") }
        }
        #expect(duplicates(features).isEmpty, "seed \(seed): one word names two grounds")

        for team in teams {
            #expect(
                TeamGenerator.echoesCity(
                    team.identity.nickname,
                    stem: TeamGenerator.stem(ofCity: team.identity.city)) == false,
                "seed \(seed): \(team.identity.fullName) says its city twice")
            #expect(team.identity.colors.hasReadableContrast)
        }
    }

    /// Two seeds of the randomiser are two different leagues — the property the curated
    /// default deliberately gives up, kept asserted on the path that still has it.
    @Test("contract: the randomiser still gives two seeds two different leagues", .tags(.contract))
    func theRandomiserStillDiverges() throws {
        let first = try #require(league(franchises: .randomised, seed: 1))
        let second = try #require(league(franchises: .randomised, seed: 2))
        #expect(first.teams.map(\.identity.fullName) != second.teams.map(\.identity.fullName))
    }

    /// A set of the caller's own, and the smallest shape of the top-up: one region
    /// supplies a single franchise and the rest of the league is drawn around it. The
    /// curated club has to arrive intact, and nothing drawn may take its name — the
    /// ledger is told about every curated line in the league before a single draw.
    @Test(
        "contract: a short curated set is filled out without colliding with itself",
        .tags(.contract))
    func aShortSetIsFilledOut() throws {
        guard let first = FranchiseSet.franchises(in: .north).first else {
            Issue.record("the curated set has no northern franchise")
            return
        }
        let built = try #require(league(shape: .minimal, franchises: .set([first])))
        let teams = built.teams

        #expect(teams.count == 8)
        #expect(teams.contains { $0.identity.city == first.city })
        #expect(teams.contains { $0.stadium == first.stadium })
        #expect(duplicates(teams.map(\.identity.city)).isEmpty, "repeated city")
        #expect(duplicates(teams.map(\.identity.nickname)).isEmpty, "repeated nickname")
        #expect(
            duplicates(teams.map { TeamGenerator.stem(ofNickname: $0.identity.nickname) }).isEmpty,
            "repeated nickname stem")
        #expect(duplicates(teams.map(\.identity.abbreviation)).isEmpty, "repeated abbreviation")
        #expect(duplicates(teams.map(\.stadium.name)).isEmpty, "repeated stadium")
    }

    /// The curated set is finite and a shape is not. Sixty-four teams wants sixteen from
    /// each region, and the eight that are written down are joined by eight drawn ones —
    /// which must not collide with them, because the ledger was told about them first.
    @Test(
        "contract: a league bigger than the curated set is finished from the pools",
        .tags(.contract))
    func anOversizedLeagueIsToppedUp() throws {
        let sixtyFour = LeagueShape(
            conferences: 2, divisionsPerConference: 4, teamsPerDivision: 8,
            regularSeasonGames: 17, playoffTeamsPerConference: 7)
        let built = try #require(league(shape: sixtyFour))
        let teams = built.teams

        #expect(teams.count == 64)
        #expect(duplicates(teams.map(\.identity.city)).isEmpty, "repeated city")
        #expect(duplicates(teams.map(\.identity.nickname)).isEmpty, "repeated nickname")
        #expect(
            duplicates(teams.map { TeamGenerator.stem(ofNickname: $0.identity.nickname) }).isEmpty,
            "repeated nickname stem")
        #expect(duplicates(teams.map(\.identity.abbreviation)).isEmpty, "repeated abbreviation")

        // Every curated club is in it, and the rest came from somewhere else.
        let names = Set(teams.map(\.identity.fullName))
        for franchise in FranchiseSet.initial {
            #expect(names.contains(franchise.fullName), "\(franchise.fullName) is missing")
        }
    }
}
