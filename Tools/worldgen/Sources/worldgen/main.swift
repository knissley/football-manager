// Inspect generated content without an app, an Xcode, or a Mac.
//
//   swift run --package-path Tools/worldgen -- --help
//   swift run --package-path Tools/worldgen -- --seed 42 --show roster --team 3
//   swift run --package-path Tools/worldgen -- --show league --teams 32
//
// Every mode reads one world, built by `WorldGenerator.generate(seed:shape:season:)` —
// the same call the harness and the tests make. Regenerating with the same seed always
// prints the same world, so anything surprising here can be reproduced exactly.

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
              --teams <n>     teams in the league (default 32), rounded down to the
                              nearest legal shape: two conferences of divisions of four
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

/// Where a player came from, the way a roster page writes it: round, pick and the season
/// he was drafted, or the season an undrafted player signed.
func draftString(_ player: Player) -> String {
    guard let draft = player.draft else { return "UDFA \(player.firstSeason)" }
    return "R\(draft.round)-\(draft.pick) \(draft.season)"
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

/// Signed, so a strength column reads as an offset from the league's middle rather than
/// as a rating.
///
/// The sign is written here and the magnitude formatted separately: `oneDecimal` divides
/// by ten in integer arithmetic, so it renders -0.4 as "0.4" and a small negative offset
/// would read as a small positive one.
func signedOneDecimal(_ value: Double) -> String {
    (value < 0 ? "-" : "+") + oneDecimal(value < 0 ? -value : value)
}

// MARK: - Build the world

/// The nearest legal league to a requested team count: two conferences of divisions of
/// four. A count that is not a multiple of eight rounds down, and the header prints what
/// was actually built rather than what was asked for.
func shape(forTeams requested: Int) -> LeagueShape {
    let divisions = max(1, requested / 8)
    let total = 2 * divisions * 4
    return LeagueShape(
        conferences: 2,
        divisionsPerConference: divisions,
        teamsPerDivision: 4,
        // A short league cannot play seventeen games: with eight teams there are only
        // fourteen opponents to meet, counting everyone twice.
        regularSeasonGames: min(17, 2 * (total - 1)),
        playoffTeamsPerConference: min(divisions * 4, divisions + 3))
}

let generated = WorldGenerator.generate(
    seed: seed, shape: shape(forTeams: teamCount), season: season)

let world: WorldGenerator.GeneratedWorld
switch generated {
case .failure(let error):
    print("That is not a league:")
    for explanation in error.explanations { print("  - \(explanation)") }
    exit(1)
case .success(let value):
    world = value
}

let teams = world.teams

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

/// Names whichever side of the ball the roster does not suit. Reporting only
/// the offence made a defensive mismatch look like a contradiction: "plays air
/// raid, built for air raid".
func mismatchNote(_ identity: SchemeIdentity.Identity?) -> String {
    guard let identity, identity.isMismatched else { return "" }
    var parts: [String] = []
    if identity.played.offense != identity.builtFor.offense {
        parts.append("off built for \(describe(identity.builtFor.offense))")
    }
    if identity.played.defense != identity.builtFor.defense {
        parts.append("def built for \(describe(identity.builtFor.defense))")
    }
    return "   " + parts.joined(separator: ", ")
}

// `season` is passed rather than captured: top-level variables in main.swift are
// main-actor isolated under Swift 6, and these helpers are not.
func printPlayers(_ players: [Player], title: String, season: Int) {
    print(title)
    print(
        pad("NAME", 24) + pad("POS", 6) + padLeft("AGE", 4) + "  "
            + pad("HT/WT", 10) + pad("40", 6) + padLeft("OVR", 4)
            + padLeft("CEIL", 6) + "  " + pad("DEV", 8) + pad("DRAFT", 12) + "COLLEGE")
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
                + pad(draftString(player), 12)
                + player.college.name)
    }
}

// MARK: - Output

switch mode {
case "roster":
    guard let team = world.team(at: teamIndex) else {
        print("no team \(teamIndex); the league has \(teams.count)")
        exit(1)
    }
    let roster = world.roster(of: team.id)
    printPlayers(
        roster,
        title: "\(team.identity.fullName) — 53-man roster (seed \(seed))",
        season: season)
    print("")
    print("  strength offset \(signedOneDecimal(world.strength(of: team.id).offset))")
    print("  mean overall \(oneDecimal(mean(roster.map { Int($0.overall) })))")
    // The target for the first is about three quarters of the league, league-wide rather
    // than team by team, so a good roster is meant to read above it and a poor one below.
    // The second has no target beyond being a minority: see DraftHistory.
    print("  drafted \(roster.filter { $0.draft != nil }.count) of \(roster.count)")
    print("  in their first season \(roster.filter { $0.isRookie(in: season) }.count)")

case "starters":
    guard let team = world.team(at: teamIndex) else {
        print("no team \(teamIndex); the league has \(teams.count)")
        exit(1)
    }
    let starters = RosterGenerator.projectedStarters(from: world.roster(of: team.id))
    printPlayers(
        starters,
        title: "\(team.identity.fullName) — projected starters (seed \(seed))",
        season: season)

case "league":
    print("League of \(teams.count), seed \(seed)")
    print("")
    print(
        pad("TEAM", 5) + pad("OFFENSE", 12) + pad("DEFENSE", 14)
            + padLeft("STR", 6) + padLeft("MEAN", 6) + padLeft("QB", 5) + padLeft("RB", 5)
            + padLeft("OL", 6) + padLeft("WR", 5) + padLeft("FIT", 6))
    for (index, team) in teams.enumerated() {
        let roster = world.roster(of: team.id)
        func best(_ position: Position) -> String {
            "\(roster.filter { $0.position == position }.map { Int($0.overall) }.max() ?? 0)"
        }
        let line = roster.filter(\.position.isOffensiveLine).map { Int($0.overall) }
        let fit = mean(roster.map { $0.schemeFit(team.scheme) })
        print(
            pad("\(index)", 5)
                + pad(describe(team.scheme.offense), 12)
                + pad(describe(team.scheme.defense), 14)
                + padLeft(signedOneDecimal(world.strength(of: team.id).offset), 6)
                + padLeft(oneDecimal(mean(roster.map { Int($0.overall) })), 6)
                + padLeft(best(.quarterback), 5)
                + padLeft(best(.runningBack), 5)
                + padLeft(oneDecimal(mean(line)), 6)
                + padLeft(best(.wideReceiver), 5)
                + padLeft(oneDecimal(fit), 6)
                + mismatchNote(world.identity(of: team.id)))
    }
    let all = teams.flatMap { world.roster(of: $0.id) }
    let offsets = teams.map { world.strength(of: $0.id).offset }
    print("")
    print("  \(all.count) players")
    print("  mean overall     \(oneDecimal(mean(all.map { Int($0.overall) })))")
    print("  rated 90+        \(all.filter { $0.overall >= 90 }.count)")
    print("  rated 85+        \(all.filter { $0.overall >= 85 }.count)")
    print("  under 60         \(all.filter { $0.overall < 60 }.count)")
    print("  mean age         \(oneDecimal(mean(all.map { $0.age(in: season) })))")
    print("  star developers  \(all.filter { $0.hidden.developmentTrait == .star }.count)")
    // The strength draw itself, so a league that is secretly flat — or secretly ordered —
    // is visible without reading every row.
    print(
        "  strength offset  \(signedOneDecimal(offsets.min() ?? 0)) to "
            + "\(signedOneDecimal(offsets.max() ?? 0)), mean "
            + "\(signedOneDecimal(offsets.reduce(0, +) / Double(max(1, offsets.count))))")

case "teams", "standings":
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

    let stadiums = teams.map(\.stadium)
    print("League texture")
    print("  domes            \(stadiums.filter(\.isIndoors).count) of \(stadiums.count)")
    print("  grass fields     \(stadiums.filter { $0.surface == .grass }.count)")
    print("  high altitude    \(stadiums.filter(\.isHighAltitude).count)")
    print("  major markets    \(teams.filter { $0.market == .major }.count)")
    print("  small markets    \(teams.filter { $0.market == .small }.count)")
    print(
        "  loudest          \(stadiums.max { $0.noise < $1.noise }.map { "\($0.name) (\($0.noise))" } ?? "-")"
    )

case "class", "pipeline":
    for generated in world.draftPipeline {
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
    func name(_ id: TeamID) -> String {
        world.team(id)?.identity.fullName ?? "?"
    }

    print("Rivalries, seed \(seed), season \(season)")
    print("")
    let hottest = world.rivalries.sorted { $0.intensity(in: season) > $1.intensity(in: season) }
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
    print("  rivalries        \(world.rivalries.count)")
    for heat in RivalryHeat.allCases {
        let count = world.rivalries.filter { $0.heat(in: season) == heat }.count
        print(
            "    " + pad("\(heat)", 14) + String(repeating: "#", count: count / 2) + " \(count)"
        )
    }
    let events = world.rivalries.flatMap(\.history)
    print("  seeded events    \(events.count)")
    for origin in RivalryOrigin.allCases {
        let count = world.rivalries.filter { $0.origin == origin }.count
        print("    " + pad("\(origin)", 14) + "\(count)")
    }

case "colleges":
    print("College pool, seed \(seed)")
    for college in world.colleges.prefix(40) {
        print("  " + pad(college.name, 36) + "\(college.profile)")
    }

default:
    print("unknown mode: \(mode) — try --help")
    exit(1)
}
