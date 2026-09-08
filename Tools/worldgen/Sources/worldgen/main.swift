// Inspect generated content without an app, an Xcode, or a Mac.
//
//   swift run --package-path Tools/worldgen -- --help
//   swift run --package-path Tools/worldgen -- --seed 42 --show roster --team 3
//   swift run --package-path Tools/worldgen -- --show league --teams 32
//
// Regenerating with the same seed always prints the same world, so anything
// surprising here can be reproduced exactly.

import FMCore
import FMGeneration
import FMRandom

// A developer tool, so libc is fair game — the no-frameworks rule applies to the
// FM* modules, which is what Tools/playsize guards.
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Arguments

var seed: UInt64 = 2030
var teamCount = 32
var teamIndex = 0
var mode = "roster"
var season = 2030

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--seed": seed = UInt64(arguments.next() ?? "") ?? seed
    case "--teams": teamCount = Int(arguments.next() ?? "") ?? teamCount
    case "--team": teamIndex = Int(arguments.next() ?? "") ?? teamIndex
    case "--show": mode = arguments.next() ?? mode
    case "--season": season = Int(arguments.next() ?? "") ?? season
    case "--help", "-h":
        print(
            """
            worldgen — inspect generated content

              --seed <n>      world seed (default 2030)
              --teams <n>     teams in the league (default 32)
              --team <n>      which team to show (default 0)
              --season <n>    season number (default 2030)
              --show <mode>   roster | starters | league | teams | standings
                              | class | pipeline | rivalries | colleges

            Same seed, same world, every time.
            """)
        exit(0)
    default:
        print("unknown argument: \(argument) — try --help")
        exit(1)
    }
}

// MARK: - Formatting

func pad(_ value: String, _ width: Int) -> String {
    var out = value
    while out.count < width { out += " " }
    return out
}

extension String {
    func trimmingWhitespace() -> String {
        var result = self
        while result.first == " " { result.removeFirst() }
        while result.last == " " { result.removeLast() }
        return result
    }
}

func padLeft(_ value: String, _ width: Int) -> String {
    var out = value
    while out.count < width { out = " " + out }
    return out
}

func abbreviate(_ position: Position) -> String {
    switch position {
    case .quarterback: return "QB"
    case .runningBack: return "RB"
    case .fullback: return "FB"
    case .wideReceiver: return "WR"
    case .tightEnd: return "TE"
    case .leftTackle: return "LT"
    case .leftGuard: return "LG"
    case .center: return "C"
    case .rightGuard: return "RG"
    case .rightTackle: return "RT"
    case .edge: return "EDGE"
    case .defensiveTackle: return "DT"
    case .linebacker: return "LB"
    case .cornerback: return "CB"
    case .safety: return "S"
    case .kicker: return "K"
    case .punter: return "P"
    case .longSnapper: return "LS"
    }
}

func fortyString(_ hundredths: UInt16) -> String {
    let whole = hundredths / 100
    let fraction = hundredths % 100
    return "\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
}

func trait(_ value: DevelopmentTrait) -> String {
    switch value {
    case .slow: return "slow"
    case .normal: return "normal"
    case .quick: return "quick"
    case .star: return "STAR"
    }
}

func mean(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    return Double(values.reduce(0, +)) / Double(values.count)
}

func oneDecimal(_ value: Double) -> String {
    let scaled = Rounding.toNearest(value * 10)
    return "\(scaled / 10).\(abs(scaled % 10))"
}

// MARK: - Build the world

var random = SplittableRandom(seed: seed)
var ids = IdentifierSequence<PlayerSubject>()
let colleges = NameGenerator.collegePool(count: 120, using: &random)

var rosters: [[Player]] = []
var identities: [SchemeIdentity.Identity] = []
for index in 0..<teamCount {
    let offset =
        teamCount == 1 ? 0 : -8.0 + 16.0 * Double(index) / Double(teamCount - 1)
    let identity = SchemeIdentity.identity(using: &random)
    identities.append(identity)
    rosters.append(
        RosterGenerator.roster(
            strength: .init(offset: offset), builtFor: identity.builtFor,
            season: season, colleges: colleges, ids: &ids, using: &random))
}

func describe(_ offense: OffensiveScheme) -> String {
    switch (offense.blocking, offense.passing) {
    case (.gap, .playAction): return "power run"
    case (.zone, .playAction): return "zone run"
    case (.mixed, .westCoast): return "west coast"
    case (.zone, .quickGame): return "spread"
    case (.zone, .airRaid): return "air raid"
    case (.gap, .vertical): return "vertical"
    default: return "custom"
    }
}

/// Names whichever side of the ball the roster does not suit. Reporting only
/// the offence made a defensive mismatch look like a contradiction: "plays air
/// raid, built for air raid".
func mismatchNote(_ identity: SchemeIdentity.Identity) -> String {
    guard identity.isMismatched else { return "" }
    var parts: [String] = []
    if identity.played.offense != identity.builtFor.offense {
        parts.append("off built for \(describe(identity.builtFor.offense))")
    }
    if identity.played.defense != identity.builtFor.defense {
        parts.append("def built for \(describe(identity.builtFor.defense))")
    }
    return "   " + parts.joined(separator: ", ")
}

func describe(_ defense: DefensiveScheme) -> String {
    switch (defense.front, defense.coverage, defense.pressure) {
    case (.fourMan, .singleHigh, .balanced): return "4-3 under"
    case (.threeMan, .singleHigh, .balanced): return "3-4 okie"
    case (.fourMan, .quartersMatch, .balanced): return "nickel match"
    case (.fourMan, .manPress, .blitzHeavy): return "press blitz"
    case (.multiple, .twoHighSoft, .conservative): return "bend/break"
    default: return "custom"
    }
}

// `season` is passed rather than captured: top-level variables in main.swift are
// main-actor isolated under Swift 6, and these helpers are not.
func printPlayers(_ players: [Player], title: String, season: Int) {
    print(title)
    print(
        pad("NAME", 24) + pad("POS", 6) + padLeft("AGE", 4) + "  "
            + pad("HT/WT", 10) + pad("40", 6) + padLeft("OVR", 4)
            + padLeft("CEIL", 6) + "  " + pad("DEV", 8) + "COLLEGE")
    for player in players {
        print(
            pad(player.name.full, 24)
                + pad(abbreviate(player.position), 6)
                + padLeft("\(player.age(in: season))", 4) + "  "
                + pad("\(player.physical.heightDescription)/\(player.physical.weightPounds)", 10)
                + pad(fortyString(player.physical.fortyYardDash), 6)
                + padLeft("\(player.overall)", 4)
                + padLeft("\(player.hidden.ceiling)", 6) + "  "
                + pad(trait(player.hidden.developmentTrait), 8)
                + player.college.name)
    }
}

// MARK: - Output

switch mode {
case "roster":
    guard teamIndex >= 0 && teamIndex < rosters.count else {
        print("no team \(teamIndex); the league has \(rosters.count)")
        exit(1)
    }
    let roster = rosters[teamIndex]
    printPlayers(
        roster, title: "Team \(teamIndex) — 53-man roster (seed \(seed))", season: season)
    print("")
    print("  mean overall \(oneDecimal(mean(roster.map { Int($0.overall) })))")

case "starters":
    guard teamIndex >= 0 && teamIndex < rosters.count else {
        print("no team \(teamIndex)")
        exit(1)
    }
    let starters = RosterGenerator.projectedStarters(from: rosters[teamIndex])
    printPlayers(
        starters, title: "Team \(teamIndex) — projected starters (seed \(seed))", season: season)

case "league":
    print("League of \(teamCount), seed \(seed)")
    print("")
    print(
        pad("TEAM", 5) + pad("OFFENSE", 12) + pad("DEFENSE", 14)
            + padLeft("MEAN", 6) + padLeft("QB", 5) + padLeft("RB", 5)
            + padLeft("OL", 6) + padLeft("WR", 5) + padLeft("FIT", 6))
    for (index, roster) in rosters.enumerated() {
        let identity = identities[index]
        func best(_ position: Position) -> String {
            "\(roster.filter { $0.position == position }.map { Int($0.overall) }.max() ?? 0)"
        }
        let line = roster.filter(\.position.isOffensiveLine).map { Int($0.overall) }
        let fit = mean(roster.map { $0.schemeFit(identity.played) })
        print(
            pad("\(index)", 5)
                + pad(describe(identity.played.offense), 12)
                + pad(describe(identity.played.defense), 14)
                + padLeft(oneDecimal(mean(roster.map { Int($0.overall) })), 6)
                + padLeft(best(.quarterback), 5)
                + padLeft(best(.runningBack), 5)
                + padLeft(oneDecimal(mean(line)), 6)
                + padLeft(best(.wideReceiver), 5)
                + padLeft(oneDecimal(fit), 6)
                + mismatchNote(identity))
    }
    let all = rosters.flatMap { $0 }
    print("")
    print("  \(all.count) players")
    print("  mean overall     \(oneDecimal(mean(all.map { Int($0.overall) })))")
    print("  rated 90+        \(all.filter { $0.overall >= 90 }.count)")
    print("  rated 85+        \(all.filter { $0.overall >= 85 }.count)")
    print("  under 60         \(all.filter { $0.overall < 60 }.count)")
    print("  mean age         \(oneDecimal(mean(all.map { $0.age(in: season) })))")
    print("  star developers  \(all.filter { $0.hidden.developmentTrait == .star }.count)")

case "teams", "standings":
    var structureRandom = SplittableRandom(seed: seed)
    let shape = LeagueShape(
        conferences: 2,
        divisionsPerConference: max(1, teamCount / 8),
        teamsPerDivision: 4,
        regularSeasonGames: 17,
        playoffTeamsPerConference: max(1, teamCount / 8) + 3)

    switch LeagueGenerator.league(shape: shape, using: &structureRandom) {
    case .failure(let error):
        print("That is not a league:")
        for explanation in error.explanations {
            print("  - \(explanation)")
        }
        exit(1)
    case .success(let world):
        print("\(world.league.name), seed \(seed)")
        print("")
        for conference in world.league.conferences {
            print("\(conference.name) Conference")
            for division in conference.divisions {
                print("  \(division.name)")
                for id in division.teams {
                    guard let team = world.team(id) else { continue }
                    let ground = team.stadium
                    let roof = ground.isIndoors ? "dome" : "\(ground.climate)"
                    let altitude = ground.isHighAltitude ? ", \(ground.altitudeFeet)ft" : ""
                    print(
                        "    " + pad(team.identity.abbreviation, 5)
                            + pad(team.identity.fullName, 32)
                            + pad("\(team.market)", 8)
                            + pad(ground.name, 26)
                            + "\(roof), \(ground.capacity / 1000)k, noise \(ground.noise)"
                            + altitude)
                }
            }
            print("")
        }

        let stadiums = world.teams.map(\.stadium)
        print("League texture")
        print("  domes            \(stadiums.filter(\.isIndoors).count) of \(stadiums.count)")
        print("  grass fields     \(stadiums.filter { $0.surface == .grass }.count)")
        print("  high altitude    \(stadiums.filter(\.isHighAltitude).count)")
        print("  major markets    \(world.teams.filter { $0.market == .major }.count)")
        print("  small markets    \(world.teams.filter { $0.market == .small }.count)")
        print(
            "  loudest          \(stadiums.max { $0.noise < $1.noise }.map { "\($0.name) (\($0.noise))" } ?? "-")"
        )
    }

case "class", "pipeline":
    var draftRandom = SplittableRandom(seed: seed)
    var identifiers = IdentifierSequence<PlayerSubject>()
    let classes = DraftClassGenerator.pipeline(
        firstDraftSeason: season, teams: teamCount, shape: .standard, colleges: colleges,
        identifiers: &identifiers, using: &draftRandom)

    for generated in classes {
        let draftClass = generated.draftClass
        let headline = draftClass.strength.headline.map { " · deep at \($0)" } ?? ""
        print(
            "\(draftClass.season) class — \(draftClass.strength.descriptor)"
                + " (\(oneDecimal(draftClass.strength.overall)))" + headline)
        print(
            "  \(draftClass.prospects.count) eligible · \(draftClass.entering.count) entering"
                + " · \(draftClass.earlyEntrants.count) early")

        if mode == "class" && draftClass.season == season {
            // Top of the class by ceiling. Nobody in the game sees this — it is the
            // truth a scout is trying to estimate, and the reason to look at it here is
            // to check the class is a distribution and not a ranking.
            let top = generated.players.sorted { $0.hidden.ceiling > $1.hidden.ceiling }.prefix(14)
            print("")
            print(
                "  " + pad("prospect", 24) + pad("pos", 16) + pad("ovr", 5) + pad("ceil", 6)
                    + pad("yr", 10) + pad("dev", 9) + pad("prod", 6) + "flags")
            for player in top {
                guard
                    let prospect = draftClass.prospects.first(where: { $0.player == player.id })
                else { continue }
                let flags =
                    prospect.flags.isEmpty
                    ? "-"
                    : prospect.flags.map {
                        "\($0.kind)(\($0.severity)/\($0.visibility))"
                            + ($0.isBuried ? "!" : "")
                    }.joined(separator: " ")
                print(
                    "  " + pad(player.name.full, 24)
                        + pad("\(player.position)", 16)
                        + pad("\(player.overall)", 5)
                        + pad("\(player.hidden.ceiling)", 6)
                        + pad("\(prospect.collegeYear)", 10)
                        + pad(trait(player.hidden.developmentTrait), 9)
                        + pad("\(prospect.latestProduction?.productionScore ?? 0)", 6)
                        + flags)
            }

            let ceilings = generated.players.map { Int($0.hidden.ceiling) }
            print("")
            print("  ceiling distribution")
            for bound in stride(from: 90, through: 50, by: -10) {
                let count = ceilings.filter { $0 >= bound && $0 < bound + 10 }.count
                print(
                    "    \(bound)-\(bound + 9)  " + String(repeating: "#", count: count / 3)
                        + " \(count)")
            }
            let buried = draftClass.prospects.filter { $0.flags.contains(where: \.isBuried) }
            print("  buried concerns  \(buried.count) of \(draftClass.prospects.count)")
        }
        print("")
    }

case "rivalries":
    var rivalryRandom = SplittableRandom(seed: seed)
    let rivalryShape = LeagueShape(
        conferences: 2, divisionsPerConference: max(1, teamCount / 8), teamsPerDivision: 4,
        regularSeasonGames: 17, playoffTeamsPerConference: max(1, teamCount / 8) + 3)

    switch LeagueGenerator.league(shape: rivalryShape, using: &rivalryRandom) {
    case .failure(let error):
        print("That is not a league:")
        for explanation in error.explanations { print("  - \(explanation)") }
        exit(1)
    case .success(let world):
        let rivalries = RivalryGenerator.rivalries(
            league: world.league, teams: world.teams, currentSeason: season,
            using: &rivalryRandom)

        func name(_ id: TeamID) -> String {
            world.team(id)?.identity.fullName ?? "?"
        }

        print("Rivalries, seed \(seed), season \(season)")
        print("")
        let hottest = rivalries.sorted { $0.intensity(in: season) > $1.intensity(in: season) }
        for rivalry in hottest.prefix(12) {
            let heat = rivalry.heat(in: season)
            print(
                "  " + pad("\(name(rivalry.pair.lower)) v \(name(rivalry.pair.higher))", 54)
                    + pad("\(rivalry.origin)", 12)
                    + pad("\(heat)", 11)
                    + oneDecimal(rivalry.intensity(in: season)))
            for event in rivalry.liveHistory(in: season, limit: 2) {
                let who = event.aggrievedTeam.map { " (\(name($0)) on the wrong end)" } ?? ""
                print("      \(event.season)  \(event.kind)\(who)")
            }
        }

        print("")
        print("League texture")
        print("  rivalries        \(rivalries.count)")
        for heat in RivalryHeat.allCases {
            let count = rivalries.filter { $0.heat(in: season) == heat }.count
            print(
                "    " + pad("\(heat)", 14) + String(repeating: "#", count: count / 2) + " \(count)"
            )
        }
        let events = rivalries.flatMap(\.history)
        print("  seeded events    \(events.count)")
        for origin in RivalryOrigin.allCases {
            let count = rivalries.filter { $0.origin == origin }.count
            print("    " + pad("\(origin)", 14) + "\(count)")
        }
    }

case "colleges":
    print("College pool, seed \(seed)")
    for college in colleges.prefix(40) {
        print("  " + pad(college.name, 36) + "\(college.profile)")
    }

default:
    print("unknown mode: \(mode) — try --help")
    exit(1)
}
