// Simulate games headless and print what the league looks like.
//
//   swift run --package-path Tools/simharness -- --games 60
//
// Tuning is done against this output and never by playing the app. The rows below are
// the calibration table from docs/match-engine.md; rows the crude resolver is not
// expected to own are marked.

import FMCore
import FMGeneration
import FMRandom
import FMSimulation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

var games = 40
var seed: UInt64 = 2030

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--games": games = Int(arguments.next() ?? "") ?? games
    case "--seed": seed = UInt64(arguments.next() ?? "") ?? seed
    case "--help", "-h":
        print(
            """
            simharness — simulate games and report distributions

              --games <n>   games to simulate (default 40)
              --seed <n>    world seed (default 2030)
            """)
        exit(0)
    default:
        print("unknown argument: \(argument) — try --help")
        exit(1)
    }
}

func pad(_ value: String, _ width: Int) -> String {
    var padded = value
    while padded.count < width { padded += " " }
    return padded
}

func oneDecimal(_ value: Double) -> String {
    let scaled = Rounding.toNearest(value * 10)
    return "\(scaled / 10).\(abs(scaled % 10))"
}

func row(_ label: String, _ value: Double, _ low: Double, _ high: Double, owned: Bool = true) {
    let mark = !owned ? "·" : (value >= low && value <= high ? "ok" : "OFF")
    print(
        "  " + pad(label, 32) + pad(oneDecimal(value), 9)
            + pad("\(oneDecimal(low))-\(oneDecimal(high))", 13) + mark)
}

// MARK: - Build a world

var random = SplittableRandom(seed: seed)
var colleges = NameGenerator.collegePool(count: 80, using: &random)
if colleges.isEmpty { colleges = [College(name: "Fallback State", profile: .midMajor)] }

guard let world = try? LeagueGenerator.league(shape: .standard, using: &random).get() else {
    print("could not generate a league")
    exit(1)
}

var ids = IdentifierSequence<PlayerSubject>()
var players: [PlayerID: Player] = [:]
var charts: [TeamID: DepthChart] = [:]

for team in world.teams {
    let roster = RosterGenerator.roster(
        builtFor: team.scheme, season: 2030, colleges: colleges, ids: &ids, using: &random)
    for player in roster { players[player.id] = player }
    charts[team.id] = RosterGenerator.depthChart(from: roster)
}

// MARK: - Simulate

let simulator = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
var results: [GameResult] = []
let teams = world.teams

for index in 0..<games {
    let home = teams[index % teams.count]
    let away = teams[(index + 1 + index / teams.count) % teams.count]
    guard home.id != away.id else { continue }

    let setup = GameSetup(
        game: GameID(UInt64(index + 1)),
        home: GameTeam(
            id: home.id, depthChart: charts[home.id] ?? DepthChart(), scheme: home.scheme),
        away: GameTeam(
            id: away.id, depthChart: charts[away.id] ?? DepthChart(), scheme: away.scheme),
        players: players,
        seed: seed &+ UInt64(index) &* 7919)
    results.append(simulator.simulate(setup))
}

// MARK: - Query the stream

let allPlays = results.flatMap(\.plays)
let teamGames = Double(results.count * 2)

func rate(_ count: Int) -> Double { Double(count) / teamGames }

let scrimmage = allPlays.filter { $0.outcome.kind.isScrimmagePlay }
let dropbacks = allPlays.filter { $0.outcome.kind.isDropback }
let attempts = allPlays.filter { $0.outcome.kind.isPassAttempt }
let completions = attempts.filter { $0.outcome.yards > 0 || $0.outcome.endedIn == .touchdown }
let sacks = allPlays.filter { $0.outcome.kind == .sack }
let carries = allPlays.filter { $0.outcome.kind == .rush }
let interceptions = allPlays.filter { $0.outcome.endedIn == .intercepted }

let points = results.reduce(0.0) { $0 + Double($1.homeScore + $1.awayScore) }
let passYards = attempts.reduce(0.0) { $0 + Double(max(0, $1.outcome.yards)) }
let rushYards = carries.reduce(0.0) { $0 + Double($1.outcome.yards) }

let thirdDowns = allPlays.filter { $0.situation.down == .third }
let thirdDownConversions = thirdDowns.filter {
    $0.outcome.yards >= Int16($0.situation.distance) || $0.outcome.endedIn == .touchdown
}

print("simharness — \(results.count) games, seed \(seed)")
print("")
print("  " + pad("metric (per team per game)", 32) + pad("value", 9) + pad("target", 13) + "")
row("points", points / teamGames, 20, 26)
row("passing yards", passYards / teamGames, 200, 260)
row("rushing yards", rushYards / teamGames, 95, 140)
row(
    "yards per carry",
    carries.isEmpty ? 0 : rushYards / Double(carries.count), 4.0, 4.8)
row(
    "completion percentage",
    attempts.isEmpty ? 0 : Double(completions.count) / Double(attempts.count) * 100, 61, 68)
row(
    "sack rate per dropback",
    dropbacks.isEmpty ? 0 : Double(sacks.count) / Double(dropbacks.count) * 100, 5.5, 8.0)
row(
    "interception rate",
    attempts.isEmpty ? 0 : Double(interceptions.count) / Double(attempts.count) * 100, 1.8, 2.8)
row(
    "third down conversion",
    thirdDowns.isEmpty ? 0 : Double(thirdDownConversions.count) / Double(thirdDowns.count) * 100,
    36, 43)
row("plays from scrimmage", rate(scrimmage.count), 60, 70)

let thirdDownDistance =
    thirdDowns.isEmpty
    ? 0
    : Double(thirdDowns.reduce(0) { $0 + Int($1.situation.distance) }) / Double(thirdDowns.count)
row("average third down distance", thirdDownDistance, 6.8, 8.2)

let firstDowns = allPlays.filter { $0.situation.down == .first }
let firstDownGain =
    firstDowns.isEmpty
    ? 0 : Double(firstDowns.reduce(0) { $0 + Int($1.outcome.yards) }) / Double(firstDowns.count)
row("yards gained on first down", firstDownGain, 4.6, 5.8)

print("")
print("  Shape of the stream")
print("    plays per game              \(allPlays.count / max(1, results.count))")
print(
    "    decisions per play          \(allPlays.reduce(0) { $0 + $1.decisions.count } / max(1, allPlays.count))"
)
print(
    "    credits per play            \(allPlays.reduce(0) { $0 + $1.outcome.participants.count } / max(1, allPlays.count))"
)
let scores = results.map { "\($0.homeScore)-\($0.awayScore)" }
print("    first scorelines            \(scores.prefix(8).joined(separator: "  "))")
let ties = results.filter(\.isTie).count
print("    ties                        \(ties) of \(results.count)")

// MARK: - Do the best players lead?

// Every credit is a query over the stream, never accumulated alongside it.
var sacksBy: [PlayerID: Int] = [:]
var carriesBy: [PlayerID: Int] = [:]
var rushYardsBy: [PlayerID: Int] = [:]
var catchesBy: [PlayerID: Int] = [:]
var snapsBy: [PlayerID: Int] = [:]

for play in allPlays {
    for participant in play.outcome.participants {
        snapsBy[participant.player, default: 0] += 1
    }
    switch play.outcome.kind {
    case .sack:
        for participant in play.outcome.participants where participant.role == .tackler {
            sacksBy[participant.player, default: 0] += 1
        }
    case .rush:
        for participant in play.outcome.participants where participant.role == .rusher {
            carriesBy[participant.player, default: 0] += 1
            rushYardsBy[participant.player, default: 0] += Int(play.outcome.yards)
        }
    case .pass where play.outcome.yards > 0 || play.outcome.endedIn == .touchdown:
        for participant in play.outcome.participants where participant.role == .receiver {
            catchesBy[participant.player, default: 0] += 1
        }
    default:
        break
    }
}

@MainActor
func leaders(_ counts: [PlayerID: Int], _ label: String, minimum: Int = 1) {
    let ranked = counts.filter { $0.value >= minimum }
        .sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
    print("")
    print("  \(label)")
    for (id, count) in ranked.prefix(5) {
        guard let player = players[id] else { continue }
        print(
            "    " + pad(player.name.full, 24) + pad("\(player.position)", 15)
                + pad("ovr \(player.overall)", 9) + pad("\(count)", 7)
                + "\(snapsBy[id] ?? 0) snaps")
    }
}

leaders(sacksBy, "Sack leaders")
leaders(rushYardsBy, "Rushing yard leaders")

// The question this answers: does rating predict production? If the leaders are
// ordinary players, ratings are decoration.
let rushers = sacksBy.compactMap { id, count -> (Int, Int)? in
    guard let player = players[id] else { return nil }
    return (Int(player.overall), count)
}
if rushers.count > 6 {
    let sorted = rushers.sorted { $0.0 > $1.0 }
    let topHalf = sorted.prefix(sorted.count / 2)
    let bottomHalf = sorted.suffix(sorted.count / 2)
    let topRate = Double(topHalf.reduce(0) { $0 + $1.1 }) / Double(topHalf.count)
    let bottomRate = Double(bottomHalf.reduce(0) { $0 + $1.1 }) / Double(bottomHalf.count)
    print("")
    print("  Rating predicts production")
    print("    sacks by the better half of rushers   \(oneDecimal(topRate))")
    print("    sacks by the worse half               \(oneDecimal(bottomRate))")
}

// MARK: - Tails

// Means are easy and tails are where the sport lives. If nobody ever has a huge day,
// records are unreachable and a generational player is indistinguishable from a good one
// over a career.
var passTouchdownsByGameTeam: [String: Int] = [:]
var passYardsByGameTeam: [String: Int] = [:]
var rushYardsByCarrierGame: [String: Int] = [:]

for play in allPlays {
    let key = "\(play.game.rawValue)-\(play.situation.possession.rawValue)"
    if play.outcome.kind.isPassAttempt {
        passYardsByGameTeam[key, default: 0] += max(0, Int(play.outcome.yards))
        if play.outcome.endedIn == .touchdown {
            passTouchdownsByGameTeam[key, default: 0] += 1
        }
    }
    if play.outcome.kind == .rush {
        for participant in play.outcome.participants where participant.role == .rusher {
            rushYardsByCarrierGame[
                "\(play.game.rawValue)-\(participant.player.rawValue)", default: 0] += Int(
                    play.outcome.yards)
        }
    }
}

func spread(_ values: [Int], _ label: String, buckets: [Int]) {
    guard !values.isEmpty else { return }
    let sorted = values.sorted()
    let mean = Double(values.reduce(0, +)) / Double(values.count)
    print("")
    print("  \(label)  (mean \(oneDecimal(mean)), max \(sorted.last ?? 0))")
    for bucket in buckets {
        let count = values.filter { $0 >= bucket }.count
        let share = Double(count) / Double(values.count) * 100
        print("    " + pad(">= \(bucket)", 10) + pad("\(count)", 7) + "\(oneDecimal(share))%")
    }
}

spread(
    Array(passTouchdownsByGameTeam.values), "Passing touchdowns in a team-game",
    buckets: [3, 4, 5, 6, 7])
spread(
    Array(passYardsByGameTeam.values), "Passing yards in a team-game",
    buckets: [300, 400, 450, 500])
spread(
    Array(rushYardsByCarrierGame.values), "Rushing yards by one carrier in a game",
    buckets: [100, 150, 200, 250])

let kneels = allPlays.filter { $0.outcome.kind == .kneel }.count
let spikes = allPlays.filter { $0.outcome.kind == .spike }.count
var timeoutsSpent = 0
for result in results {
    for (previous, next) in zip(result.plays, result.plays.dropFirst())
    where previous.situation.possession == next.situation.possession {
        if next.situation.offenseTimeouts < previous.situation.offenseTimeouts {
            timeoutsSpent += 1
        }
        if next.situation.defenseTimeouts < previous.situation.defenseTimeouts {
            timeoutsSpent += 1
        }
    }
}
print("")
print("  The endgame")
print(
    "    kneels per game             \(oneDecimal(Double(kneels) / Double(max(1, results.count))))")
print(
    "    spikes per game             \(oneDecimal(Double(spikes) / Double(max(1, results.count))))")
print(
    "    timeouts spent per game     \(oneDecimal(Double(timeoutsSpent) / Double(max(1, results.count))))"
)

print("")
print("  Not measured here")
print("    Spread of team win totals — the single most important row in the")
print("    calibration table, and it needs a season with a schedule rather than")
print("    arbitrary matchups. It arrives with M3.")
print("    Penalties, injuries and red zone rate — not yet resolved.")
