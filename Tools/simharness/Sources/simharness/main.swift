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

print("")
print("  Not measured here")
print("    Spread of team win totals — the single most important row in the")
print("    calibration table, and it needs a season with a schedule rather than")
print("    arbitrary matchups. It arrives with M3.")
print("    Penalties, injuries and red zone rate — not yet resolved.")
