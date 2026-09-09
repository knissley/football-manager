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

/// Two places, for rates small enough that one hides the whole signal — a fifth of a
/// touchdown per team-game reads as "0.1" and tells you nothing.
func twoDecimals(_ value: Double) -> String {
    let scaled = Int((value * 100).rounded())
    return "\(scaled / 100).\(scaled % 100 < 10 ? "0" : "")\(scaled % 100)"
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
var conditions: [(home: TeamID, setup: GameSetup)] = []
let teams = world.teams

for index in 0..<games {
    let home = teams[index % teams.count]
    let away = teams[(index + 1 + index / teams.count) % teams.count]
    guard home.id != away.id else { continue }

    // Played at a real ground, in real weather. Every calibration run before this one
    // was at "Neutral Field" with crowd noise 50 and clear skies — so home-field
    // advantage and weather were mechanisms the engine had, and that had never once been
    // measured.
    let week = index % 18 + 1
    var weatherRandom = SplittableRandom(seed: seed &+ UInt64(index) &* 104_729)
    let weather = WeatherGenerator.forGame(
        stadium: home.stadium, week: week, using: &weatherRandom)

    let setup = GameSetup(
        game: GameID(UInt64(index + 1)),
        home: GameTeam(
            id: home.id, depthChart: charts[home.id] ?? DepthChart(), scheme: home.scheme),
        away: GameTeam(
            id: away.id, depthChart: charts[away.id] ?? DepthChart(), scheme: away.scheme),
        players: players,
        stadium: home.stadium,
        weather: weather,
        seed: seed &+ UInt64(index) &* 7919)
    results.append(simulator.simulate(setup))
    conditions.append((home: home.id, setup: setup))
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

let flags = allPlays.flatMap(\.outcome.penalties)
let accepted = flags.filter(\.wasAccepted)
row("penalties (both teams)", Double(accepted.count) / Double(results.count), 10, 14)

let thirdDownDistance =
    thirdDowns.isEmpty
    ? 0
    : Double(thirdDowns.reduce(0) { $0 + Int($1.situation.distance) }) / Double(thirdDowns.count)
row("average third down distance", thirdDownDistance, 6.8, 8.2)

// Scrimmage plays only. A kickoff and an extra point are both first-down snaps that
// gain nothing by definition, and counting them dragged this row a yard and a half below
// its target — the row was measuring the wrong thing, not the engine failing to hit it.
let firstDowns = scrimmage.filter { $0.situation.down == .first }
let firstDownGain =
    firstDowns.isEmpty
    ? 0 : Double(firstDowns.reduce(0) { $0 + Int($1.outcome.yards) }) / Double(firstDowns.count)
row("yards gained on first down", firstDownGain, 4.6, 5.8)

// Yards per attempt is the passing game's real efficiency number — completion rate says
// nothing about whether the completions are worth anything.
let attemptYards = Double(attempts.reduce(0) { $0 + Int(max(0, $1.outcome.yards)) })
row("yards per pass attempt", attemptYards / Double(max(1, attempts.count)), 6.6, 7.6)
let scrimmageYards =
    attemptYards + rushYards
    + Double(sacks.reduce(0) { $0 + Int($1.outcome.yards) })
row("yards per play", scrimmageYards / Double(max(1, scrimmage.count)), 5.2, 5.9)
let receptionYards = attemptYards / Double(max(1, completions.count))
row("yards per completion", receptionYards, 10.5, 12.5)

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
print("  Flags")
var byFoul: [String: Int] = [:]
for flag in accepted { byFoul["\(flag.foul)", default: 0] += 1 }
for (foul, count) in byFoul.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }) {
    print(
        "    " + pad(foul, 28)
            + "\(oneDecimal(Double(count) / Double(results.count))) per game")
}
print(
    "    " + pad("declined", 28)
        + "\(oneDecimal(Double(flags.count - accepted.count) / Double(max(1, flags.count)) * 100))%"
)

// Player-games lost is the calibration row. A season is seventeen games, so the rate per
// game times seventeen is what has to land in range.
let allInjuries = results.flatMap(\.injuries)
let missedGames = allInjuries.reduce(0) { $0 + Int($1.gamesOut) }
let perTeamSeason = Double(missedGames) / teamGames * 17
print("")
print("  Injuries")
print(
    "    per game (both teams)       \(oneDecimal(Double(allInjuries.count) / Double(max(1, results.count))))"
)
print(
    "    forced out of the game      \(oneDecimal(Double(allInjuries.filter(\.leavesTheGame).count) / Double(max(1, results.count))))"
)
row("player-games lost per season", perTeamSeason, 40, 90)
let nonContact = allInjuries.filter { $0.cause == .nonContact }
print(
    "    non-contact share           "
        + "\(oneDecimal(Double(nonContact.count) / Double(max(1, allInjuries.count)) * 100))%")
let nonContactGames = nonContact.reduce(0) { $0 + Int($1.gamesOut) }
print(
    "    non-contact games lost      "
        + "\(oneDecimal(Double(nonContactGames) / Double(max(1, missedGames)) * 100))% of all")
let longest = allInjuries.map(\.gamesOut).max() ?? 0
print("    longest absence             \(longest) games")

let scrambles = allPlays.filter { $0.outcome.kind == .scramble }
print(
    "    scrambles per game          "
        + "\(oneDecimal(Double(scrambles.count) / Double(max(1, results.count))))")

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

// MARK: - Is this football?
//
// The calibration table measures the passing and running game and almost nothing else,
// which is how the engine came to be tuned to plausible per-play numbers while the shape
// of a football game around them went unexamined. These rows are the shape: where points
// come from, how drives end, and where teams start.

print("")
print("  Where the points come from")

var pointsBySource: [String: Int] = [:]
var driveEnds: [String: Int] = [:]
var startingSpots: [Int] = []
var kickoffEndings: [String: Int] = [:]
var puntSpots: [Int] = []
var fieldGoalsByDistance: [(distance: Int, good: Bool)] = []

var twoPointTries = 0
var twoPointGood = 0
var drivePlays: [Int] = []
var threeAndOuts = 0

for result in results {
    // A drive is a run of consecutive snaps by one team. Classified by how its last
    // snap ended, so a drive killed by the clock is counted rather than dropped.
    var current: (team: TeamID, start: Int, last: PlayRecord, plays: Int)?

    func closeDrive(_ drive: (team: TeamID, start: Int, last: PlayRecord, plays: Int)) {
        // Offensive plays only. Counting the punt that ends a three-and-out as a fourth
        // play is how that row read 33% against a real 22%.
        drivePlays.append(drive.plays)
        if drive.plays <= 3, drive.last.outcome.kind == .punt { threeAndOuts += 1 }
        startingSpots.append(drive.start)
        let play = drive.last
        let label: String
        // Classify by what the play *was* before how it ended. A punt that gets returned
        // ends in a tackle on fourth down, which read as a turnover on downs and put that
        // row at 19% against a real 5% — the drive chart was calling punts failed
        // fourth-down gambles.
        switch play.outcome.kind {
        case .punt:
            label = play.outcome.endedIn == .touchdown ? "punt returned for a score" : "punt"
        case .fieldGoal:
            label = play.outcome.endedIn == .fieldGoalGood ? "field goal" : "missed kick"
        default:
            switch play.outcome.endedIn {
            case .touchdown: label = "touchdown"
            case .intercepted, .fumbleLost: label = "turnover"
            case .safety: label = "safety"
            default:
                label =
                    play.situation.down == .fourth
                        && play.outcome.yards < Int16(play.situation.distance)
                    ? "downs" : "clock ran out"
            }
        }
        driveEnds[label, default: 0] += 1
    }

    for play in result.plays {
        let outcome = play.outcome

        switch outcome.kind {
        case .kickoff:
            kickoffEndings["\(outcome.endedIn)", default: 0] += 1
        case .punt:
            puntSpots.append(Int(play.situation.ballOn) - Int(outcome.finalSpot ?? 0))
        case .fieldGoal:
            fieldGoalsByDistance.append(
                (Int(play.situation.ballOn) + 17, outcome.endedIn == .fieldGoalGood))
        case .twoPointConversion:
            twoPointTries += 1
            if outcome.endedIn == .touchdown { twoPointGood += 1 }
        default:
            break
        }

        switch outcome.endedIn {
        case .touchdown where outcome.kind == .twoPointConversion:
            pointsBySource["two-point", default: 0] += 2
        case .touchdown:
            pointsBySource["touchdown", default: 0] += 6
        case .fieldGoalGood where outcome.kind == .extraPoint:
            pointsBySource["extra point", default: 0] += 1
        case .fieldGoalGood:
            pointsBySource["field goal", default: 0] += 3
        case .safety:
            pointsBySource["safety", default: 0] += 2
        default:
            break
        }

        guard outcome.kind.isScrimmagePlay || outcome.kind == .punt || outcome.kind == .fieldGoal
        else { continue }

        if let drive = current, drive.team != play.situation.possession {
            closeDrive(drive)
            current = nil
        }
        let counts = outcome.kind.isScrimmagePlay
        if current == nil {
            current = (play.situation.possession, Int(play.situation.ballOn), play, counts ? 1 : 0)
        } else {
            current?.last = play
            if counts { current?.plays += 1 }
        }
    }
    if let drive = current { closeDrive(drive) }
}

let totalPoints = pointsBySource.values.reduce(0, +)
for (source, value) in pointsBySource.sorted(by: { $0.value > $1.value }) {
    let share = Double(value) / Double(max(1, totalPoints)) * 100
    print(
        "    \(pad(source, 26))\(pad(oneDecimal(Double(value) / teamGames), 7))\(oneDecimal(share))%"
    )
}

print("")
print("  Who is on the field")
var groups: [UInt8: Int] = [:]
var packages: [DefensivePackage: Int] = [:]
for play in scrimmage {
    groups[play.situation.offensePersonnel.code, default: 0] += 1
    packages[play.situation.defensePackage, default: 0] += 1
}
let snaps = Double(max(1, scrimmage.count))
print("    offensive personnel")
for (code, count) in groups.sorted(by: { $0.value > $1.value }).prefix(6) {
    print(
        "      \(pad(code < 10 ? "0\(code)" : "\(code)", 28))\(oneDecimal(Double(count) / snaps * 100))%"
    )
}
print("    defensive package")
for (package, count) in packages.sorted(by: { $0.value > $1.value }) {
    print("      \(pad("\(package)", 28))\(oneDecimal(Double(count) / snaps * 100))%")
}

// The matchup, which is the point of having personnel at all. A run into a light box
// should go further than one into a stacked one, and if it does not then the substitution
// is decoration.
// The mechanism, rather than the box count on its own: a run works when the offence has
// more men at the point of attack than the defence, and a bare box count conflates that
// with the down-and-distance the package was called on.
// First and ten only. Across all downs this row is unreadable: heavy personnel is called
// in short yardage and at the goal line, where a carry is short by construction, so the
// grouping that wins the count also runs in the situations that cap the gain.
print("    yards per carry by count advantage, first and ten")
func countAdvantage(_ play: PlayRecord) -> Int {
    let group = play.situation.offensePersonnel
    let blockers = 5 + Int(group.tightEnds) + max(0, Int(group.runningBacks) - 1)
    return blockers - (11 - Int(play.situation.defensePackage.defensiveBacks))
}
for advantage in [-2, -1, 0, 1, 2] {
    let matching = carries.filter {
        countAdvantage($0) == advantage && $0.situation.down == .first
            && $0.situation.distance == 10
    }
    guard matching.count > 200 else { continue }
    let yards = Double(matching.reduce(0) { $0 + Int($1.outcome.yards) }) / Double(matching.count)
    let label = advantage > 0 ? "+\(advantage) blockers" : "\(advantage) blockers"
    print("      \(pad(label, 28))\(pad(oneDecimal(yards), 8))\(matching.count) carries")
}

print("")
print("  The shape of a carry")
// A mean is not a distribution. Real carries are mostly modest with a fat tail, and an
// engine can hit 4.3 a carry by giving everyone four and a half yards every time, which
// would be nothing like the sport.
let carryYards = carries.map { Int($0.outcome.yards) }
for (label, test, low, high) in [
    ("stuffed (0 or fewer)", { (y: Int) in y <= 0 }, 17.0, 22.0),
    ("2 yards or fewer", { (y: Int) in y <= 2 }, 40.0, 48.0),
    ("10 or more", { (y: Int) in y >= 10 }, 9.0, 13.0),
    ("20 or more", { (y: Int) in y >= 20 }, 2.0, 4.0),
] as [(String, (Int) -> Bool, Double, Double)] {
    let share = Double(carryYards.filter(test).count) / Double(max(1, carryYards.count)) * 100
    let flag = share < low || share > high ? "OFF" : "ok"
    print(
        "    \(pad(label, 26))\(pad(oneDecimal(share) + "%", 9))\(pad("\(oneDecimal(low))-\(oneDecimal(high))", 13))\(flag)"
    )
}

print("")
print("  The shape of a dropback")
// The same question as the carry rows. A passing game with the right mean and no tail
// produces drives that neither die quickly nor break open, which is what leaves a game
// with too few possessions in it.
let dropbackYards = dropbacks.map { Int($0.outcome.yards) }
for (label, test, low, high) in [
    ("lost yards or sacked", { (y: Int) in y < 0 }, 5.0, 9.0),
    ("no gain (incomplete)", { (y: Int) in y == 0 }, 30.0, 38.0),
    ("10 or more", { (y: Int) in y >= 10 }, 22.0, 29.0),
    ("20 or more", { (y: Int) in y >= 20 }, 8.0, 12.0),
    ("40 or more", { (y: Int) in y >= 40 }, 1.5, 3.0),
] as [(String, (Int) -> Bool, Double, Double)] {
    let share = Double(dropbackYards.filter(test).count) / Double(max(1, dropbackYards.count)) * 100
    let flag = share < low || share > high ? "OFF" : "ok"
    print(
        "    \(pad(label, 26))\(pad(oneDecimal(share) + "%", 9))\(pad("\(oneDecimal(low))-\(oneDecimal(high))", 13))\(flag)"
    )
}

print("")
print("  How drives end")
let totalDrives = driveEnds.values.reduce(0, +)
for (end, count) in driveEnds.sorted(by: { $0.value > $1.value }) {
    let share = Double(count) / Double(max(1, totalDrives)) * 100
    print(
        "    \(pad(end, 26))\(pad(oneDecimal(Double(count) / teamGames), 7))\(oneDecimal(share))%")
}
print(
    "    \(pad("drives per team-game", 26))\(pad(oneDecimal(Double(totalDrives) / teamGames), 9))10.5-12.0"
)
print(
    "    \(pad("plays per drive", 26))\(pad(oneDecimal(Double(drivePlays.reduce(0, +)) / Double(max(1, drivePlays.count))), 9))5.3-6.0"
)
// First downs are the currency of a drive: how many a team earns decides how long its
// drives last, and it is the row that separates "converts third downs at the right rate"
// from "never reaches third down".
let firstDownsEarned = allPlays.filter { play in
    guard play.outcome.kind.isScrimmagePlay else { return false }
    return play.outcome.yards >= Int16(play.situation.distance)
        || play.outcome.endedIn == .touchdown
}.count
print(
    "    \(pad("first downs per team-game", 26))\(pad(oneDecimal(Double(firstDownsEarned) / teamGames), 9))18.5-22.0"
)
print(
    "    \(pad("three and out", 26))\(pad(oneDecimal(Double(threeAndOuts) / Double(max(1, drivePlays.count)) * 100) + "%", 9))20.0-27.0"
)

print("")
print("  Field position")
let averageStart = Double(startingSpots.reduce(0, +)) / Double(max(1, startingSpots.count))
print("    \(pad("average start (own yard)", 30))\(oneDecimal(100 - averageStart))")
let ownHalf = startingSpots.filter { $0 > 50 }.count
print(
    "    \(pad("drives starting in own half", 30))"
        + "\(oneDecimal(Double(ownHalf) / Double(max(1, startingSpots.count)) * 100))%")
let averagePunt = Double(puntSpots.reduce(0, +)) / Double(max(1, puntSpots.count))
print("    \(pad("punts per team-game", 30))\(oneDecimal(Double(puntSpots.count) / teamGames))")
print("    \(pad("net punt (yards)", 30))\(oneDecimal(averagePunt))")
print(
    "    \(pad("two-point tries per team-game", 30))"
        + "\(pad(twoDecimals(Double(twoPointTries) / teamGames), 8))0.15-0.30")
print(
    "    \(pad("  converted", 30))"
        + "\(pad(oneDecimal(Double(twoPointGood) / Double(max(1, twoPointTries)) * 100) + "%", 8))44-54%"
)

print("")
print("  Kicking")
for (ending, count) in kickoffEndings.sorted(by: { $0.value > $1.value }) {
    print(
        "    \(pad("kickoff → \(ending)", 30))"
            + "\(oneDecimal(Double(count) / Double(max(1, kickoffEndings.values.reduce(0, +))) * 100))%"
    )
}
print(
    "    \(pad("field goals per team-game", 30))"
        + "\(oneDecimal(Double(fieldGoalsByDistance.count) / teamGames))")
for bucket in [(0, 29), (30, 39), (40, 49), (50, 70)] {
    let inBucket = fieldGoalsByDistance.filter {
        $0.distance >= bucket.0 && $0.distance <= bucket.1
    }
    guard !inBucket.isEmpty else { continue }
    let made = inBucket.filter(\.good).count
    print(
        "    \(pad("  \(bucket.0)-\(bucket.1) yards", 30))"
            + "\(pad(String(inBucket.count), 7))\(oneDecimal(Double(made) / Double(inBucket.count) * 100))%"
    )
}

print("")
print("  Fourth down")
// The most-discussed decision in the modern game, and the one a conservative caller
// makes invisible. Real teams go for it about 1.1 times a game and convert about half.
let fourthDowns = allPlays.filter {
    $0.situation.down == .fourth && $0.outcome.kind != .kickoff && $0.outcome.kind != .extraPoint
        && $0.outcome.kind != .twoPointConversion && $0.outcome.kind != .penaltyOnly
}
func fourthShare(_ name: String, _ test: (PlayRecord) -> Bool, _ low: Double, _ high: Double) {
    let matching = fourthDowns.filter(test)
    let share = Double(matching.count) / Double(max(1, fourthDowns.count)) * 100
    let flag = share < low || share > high ? "OFF" : "ok"
    print(
        "    \(pad(name, 26))\(pad(oneDecimal(share) + "%", 9))\(pad("\(oneDecimal(low))-\(oneDecimal(high))", 13))\(flag)"
    )
}
fourthShare("punted", { $0.outcome.kind == .punt }, 55.0, 68.0)
fourthShare("kicked", { $0.outcome.kind == .fieldGoal }, 20.0, 30.0)
fourthShare("went for it", { $0.outcome.kind.isScrimmagePlay }, 12.0, 20.0)
let goes = fourthDowns.filter { $0.outcome.kind.isScrimmagePlay }
let converted = goes.filter {
    $0.outcome.yards >= Int16($0.situation.distance) || $0.outcome.endedIn == .touchdown
}
print(
    "    \(pad("attempts per team-game", 26))\(pad(oneDecimal(Double(goes.count) / teamGames), 9))0.9-1.4"
)
print(
    "    \(pad("conversion rate", 26))\(pad(oneDecimal(Double(converted.count) / Double(max(1, goes.count)) * 100) + "%", 9))45.0-58.0"
)
let shortGoes = fourthDowns.filter { $0.situation.distance <= 1 }
let shortWent = shortGoes.filter { $0.outcome.kind.isScrimmagePlay }
print(
    "    \(pad("4th and 1: went for it", 26))\(pad(oneDecimal(Double(shortWent.count) / Double(max(1, shortGoes.count)) * 100) + "%", 9))55.0-75.0"
)

print("")
print("  Turnovers and the return game")
let fumblesLost = allPlays.filter { $0.outcome.endedIn == .fumbleLost }
let fumblesKept = allPlays.filter { $0.outcome.endedIn == .fumbleRecovered }
print(
    "    \(pad("fumbles lost per team-game", 30))\(pad(oneDecimal(Double(fumblesLost.count) / teamGames), 8))0.5-0.8"
)
print(
    "    \(pad("fumbles kept per team-game", 30))\(pad(oneDecimal(Double(fumblesKept.count) / teamGames), 8))0.4-0.8"
)
let takeaways = fumblesLost.count + interceptions.count
print(
    "    \(pad("turnovers per team-game", 30))\(pad(oneDecimal(Double(takeaways) / teamGames), 8))1.1-1.6"
)

// A touchdown the offence did not score. Real football takes about a fifth of a point
// per team-game from each source, and this engine produced none of them at all.
var returnScores: [String: Int] = [:]
for play in allPlays where play.outcome.endedIn == .touchdown {
    switch play.outcome.kind {
    case .kickoff: returnScores["kickoff return", default: 0] += 1
    case .punt: returnScores["punt return", default: 0] += 1
    default:
        if play.outcome.finalSpot == 100 {
            returnScores[
                play.outcome.kind == .pass ? "interception return" : "fumble return", default: 0] +=
                1
        }
    }
}
for play in allPlays where play.outcome.finalSpot == 100 && play.outcome.endedIn != .touchdown {
    returnScores[
        play.outcome.endedIn == .intercepted ? "interception return" : "fumble return", default: 0] +=
        1
}
let nonOffensive = returnScores.values.reduce(0, +)
print(
    "    \(pad("touchdowns not by the offence", 30))\(pad(twoDecimals(Double(nonOffensive) / teamGames), 8))0.15-0.28"
)
for (source, count) in returnScores.sorted(by: { $0.value > $1.value }) {
    print(
        "      \(pad(source, 28))\(pad(twoDecimals(Double(count) / teamGames), 8))\(count) in \(Int(teamGames)) team-games"
    )
}

var kickoffReturns = 0
var onside = 0
var onsideRecovered = 0
for play in allPlays where play.outcome.kind == .kickoff {
    if play.calls.offense.design == CrudePlaybook.design(for: .onsideKick) {
        onside += 1
        if play.outcome.endedIn == .fumbleRecovered { onsideRecovered += 1 }
    } else if play.outcome.endedIn != .touchback {
        kickoffReturns += 1
    }
}
print("    \(pad("onside kicks (recovered)", 30))\(onside) (\(onsideRecovered))")
print(
    "    \(pad("kickoffs returned", 30))\(kickoffReturns) of \(allPlays.filter { $0.outcome.kind == .kickoff }.count)"
)
let puntsReturned = allPlays.filter { $0.outcome.kind == .punt && $0.outcome.endedIn == .tackled }
    .count
print(
    "    \(pad("punts returned", 30))\(puntsReturned) of \(allPlays.filter { $0.outcome.kind == .punt }.count)"
)

print("")
print("  Backed up")
let deep = scrimmage.filter { $0.situation.ballOn >= 90 }
print(
    "    \(pad("snaps inside own 10", 26))\(pad(twoDecimals(Double(deep.count) / teamGames), 9))1.5-2.5"
)
let safeties = allPlays.filter { $0.outcome.endedIn == .safety }
print(
    "    \(pad("safeties per team-game", 26))\(pad(twoDecimals(Double(safeties.count) / teamGames), 9))0.03-0.08"
)
let deepSacks = deep.filter { $0.outcome.kind == .sack }
print(
    "    \(pad("sacks taken inside own 10", 26))\(deepSacks.count) in \(Int(teamGames)) team-games")

print("")
print("  Home field and weather")
// Both are mechanisms the engine already had. Neither had ever been measured, because
// every calibration game was played at a neutral field in still air.
var homeWins = 0, awayWins = 0, drawn = 0
var homePoints = 0, awayPoints = 0
for result in results {
    if result.homeScore > result.awayScore {
        homeWins += 1
    } else if result.awayScore > result.homeScore {
        awayWins += 1
    } else {
        drawn += 1
    }
    homePoints += Int(result.homeScore)
    awayPoints += Int(result.awayScore)
}
let decided = Double(max(1, homeWins + awayWins))
// No target on these two. Real home-field advantage is about two points and 56%, and
// most of it is travel, rest and short weeks — none of which can exist before there is a
// schedule to travel on (M3). What this engine models is the crowd, and the crowd alone
// is worth roughly half a point, which is about what the research attributes to it.
print(
    "    \(pad("home win rate", 30))\(pad(oneDecimal(Double(homeWins) / decided * 100) + "%", 9))crowd only, see M3"
)
print(
    "    \(pad("home scoring edge (points)", 30))\(pad(oneDecimal(Double(homePoints - awayPoints) / Double(max(1, results.count))), 9))crowd only, see M3"
)

// The mechanism itself, rather than the outcome: crowd noise raises the *visiting*
// offence's pre-snap penalties, and the advantage is supposed to fall out of that. The
// harness has always counted this and never printed it — computed and dropped, which is
// exactly why home field went unexamined for so long.
var homePreSnap = 0, awayPreSnap = 0
var homeSnaps = 0, awaySnaps = 0
for (index, entry) in conditions.enumerated() where index < results.count {
    // Including the flag-only snaps, which are *the plays that carry a pre-snap foul* —
    // filtering to `isScrimmagePlay` excluded every one of them and reported zero.
    for play in results[index].plays
    where play.outcome.kind.isScrimmagePlay || play.outcome.kind == .penaltyOnly {
        let offenceIsHome = play.situation.possession == entry.home
        if offenceIsHome { homeSnaps += 1 } else { awaySnaps += 1 }
        for flag in play.outcome.penalties
        where flag.foul.isPreSnap && flag.offendingTeam == play.situation.possession {
            if offenceIsHome { homePreSnap += 1 } else { awayPreSnap += 1 }
        }
    }
}
func per100(_ count: Int, _ snaps: Int) -> Double { Double(count) / Double(max(1, snaps)) * 100 }
// This one *is* the mechanism, and it has a real number attached: a road offence commits
// something like a fifth more pre-snap fouls than a home one.
let ratio = per100(awayPreSnap, awaySnaps) / max(0.01, per100(homePreSnap, homeSnaps))
print(
    "    \(pad("pre-snap fouls, road vs home", 30))"
        + "\(pad(oneDecimal(ratio) + "x", 9))1.15-1.35  "
        + (ratio < 1.15 || ratio > 1.35 ? "OFF" : "ok"))
print(
    "    \(pad("  per 100 snaps", 30))"
        + "home \(oneDecimal(per100(homePreSnap, homeSnaps)))  road \(oneDecimal(per100(awayPreSnap, awaySnaps)))"
)

// Weather: how often it turns up, and whether it changes anything.
var byPrecipitation: [Precipitation: (games: Int, points: Int)] = [:]
var indoorGames = 0
var windy = 0
for (index, entry) in conditions.enumerated() where index < results.count {
    let w = entry.setup.weather
    if w.isIndoors { indoorGames += 1 }
    if w.windSpeed >= 18 { windy += 1 }
    let total = Int(results[index].homeScore + results[index].awayScore)
    byPrecipitation[w.precipitation, default: (0, 0)].games += 1
    byPrecipitation[w.precipitation, default: (0, 0)].points += total
}
print(
    "    \(pad("games indoors", 30))\(oneDecimal(Double(indoorGames) / Double(max(1, results.count)) * 100))%"
)
print(
    "    \(pad("games with wind 18mph+", 30))\(oneDecimal(Double(windy) / Double(max(1, results.count)) * 100))%"
)
for kind in [Precipitation.none, .rain, .heavyRain, .snow] {
    guard let bucket = byPrecipitation[kind], bucket.games > 20 else { continue }
    print(
        "    \(pad("  \(kind): combined points", 30))"
            + "\(pad(oneDecimal(Double(bucket.points) / Double(bucket.games)), 9))\(bucket.games) games"
    )
}

print("")
print("  Scoreboard")
var finals: [String: Int] = [:]
for result in results {
    let high = max(result.homeScore, result.awayScore)
    let low = min(result.homeScore, result.awayScore)
    finals["\(high)-\(low)", default: 0] += 1
}
let common = finals.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.prefix(6)
print("    most common finals          " + common.map { "\($0.key)" }.joined(separator: "  "))
let margins = results.map { abs(Int($0.homeScore - $0.awayScore)) }
for margin in [3, 7] {
    let within = margins.filter { $0 <= margin }.count
    print(
        "    \(pad("games within \(margin)", 30))"
            + "\(oneDecimal(Double(within) / Double(max(1, results.count)) * 100))%")
}
