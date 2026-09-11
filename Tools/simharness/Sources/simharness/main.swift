// Simulate games headless and print what the league looks like.
//
//   swift run --package-path Tools/simharness -- --games 60
//
// Tuning is done against this output and never by playing the app. Every band printed
// here is a `CalibrationTarget` from Targets.swift, which names the real-league season and
// the source each one came from; the table in docs/match-engine.md is generated from the
// same array and a test fails if the two drift.

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
var rulebookOption: Int?
var timing = true
var worldChecksumOnly = false
var strengthSpread = WorldGenerator.strengthSpread

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--games": games = Int(arguments.next() ?? "") ?? games
    case "--seed": seed = UInt64(arguments.next() ?? "") ?? seed
    case "--rulebook":
        guard let season = Int(arguments.next() ?? ""), Rules.rulebook(season) != nil else {
            print(
                "--rulebook takes one of: "
                    + Rules.supportedRulebooks.map(String.init).joined(separator: ", "))
            exit(1)
        }
        rulebookOption = season
    case "--no-timing": timing = false
    case "--strength-spread":
        guard let value = Double(arguments.next() ?? ""), value >= 0 else {
            print("--strength-spread takes a number of overall points, zero or more")
            exit(1)
        }
        strengthSpread = value
    case "--world-checksum-only": worldChecksumOnly = true
    case "--targets-markdown":
        print(CalibrationTarget.markdownTable())
        exit(0)
    case "--help", "-h":
        print(
            """
            simharness — simulate games and report distributions

              --games <n>          games to simulate (default 40)
              --seed <n>           world seed (default 2030)
              --rulebook <season>  play under that season's rules and compare against the
                                   rows sourced under them (\(Rules.supportedRulebooks.map(String.init).joined(separator: " or ")));
                                   the default plays Rules.standard and compares against the
                                   \(engineRulebookSeason) targets
              --no-timing          leave out the Budget block at the end, so two runs of
                                   the same binary at the same seed are byte-identical
              --strength-spread <points>
                                   draw the league's talent this far either side of the
                                   middle instead of \(WorldGenerator.strengthSpread).
                                   A measuring instrument, not a setting: it is how the
                                   shipped width was settled against row:betweenTeamSigma,
                                   and a run that passes it is not a calibration run
              --world-checksum-only
                                   generate the world for the seed, print its checksum
                                   line and exit without simulating. What
                                   scripts/harness-reach.sh asks two branches, to decide
                                   whether a change can reach this run at all
              --targets-markdown   print the calibration table for docs/match-engine.md
            """)
        exit(0)
    default:
        print("unknown argument: \(argument) — try --help")
        exit(1)
    }
}

// The rulebook the bands are compared against. Without `--rulebook` the engine plays
// `Rules.standard` and is measured against the targets for the season it is supposed to
// implement; the rows sourced under an older rulebook then warn, which is the point.
let rulebookSeason = rulebookOption ?? engineRulebookSeason
let rulesInForce = rulebookOption.flatMap(Rules.rulebook) ?? .standard
let staleTargets = CalibrationTarget.stale(under: rulebookSeason)

func pad(_ value: String, _ width: Int) -> String {
    var padded = value
    while padded.count < width { padded += " " }
    return padded
}

func oneDecimal(_ value: Double) -> String {
    let scaled = Rounding.toNearest(value * 10)
    let magnitude = abs(scaled)
    return "\(scaled < 0 ? "-" : "")\(magnitude / 10).\(magnitude % 10)"
}

/// Two places, for rates small enough that one hides the whole signal — a fifth of a
/// touchdown per team-game reads as "0.1" and tells you nothing.
func twoDecimals(_ value: Double) -> String {
    let scaled = Int((value * 100).rounded())
    let magnitude = abs(scaled)
    return
        "\(scaled < 0 ? "-" : "")\(magnitude / 100).\(magnitude % 100 < 10 ? "0" : "")\(magnitude % 100)"
}

var verdicts: [String: [String]] = [:]
/// Wide enough for the longest label plus the two spaces every column keeps between
/// fields, which is what the CI summary's parser splits on.
let labelWidth = (CalibrationTarget.all.map(\.label.count).max() ?? 30) + 2

/// Print every target row for `id` — a rule-sensitive row has a variant per rulebook, and
/// both print so the reader sees the measured value against each — with the season, source
/// and rule sensitivity the band came from. `nil` is a row the harness cannot measure yet.
@MainActor
func report(_ id: String, _ value: Double?) {
    let targets = CalibrationTarget.all.filter { $0.id == id || $0.id.hasPrefix(id + ".") }
    if targets.isEmpty {
        print("  \(pad(id, labelWidth))has no target row — add one to Targets.swift")
        return
    }
    for target in targets {
        let verdict: String
        if staleTargets[target.id] != nil {
            verdict = "stale"
        } else if target.season == .unsourced {
            verdict = "unsourced"
        } else if let value, let low = target.low, let high = target.high {
            let inBand = value >= low && value <= high
            verdict = target.gate ? (inBand ? "ok" : "OFF") : (inBand ? "(ok)" : "(OFF)")
        } else {
            verdict = "n/a"
        }
        verdicts[verdict, default: []].append(target.id)
        print(
            "  " + pad(target.label, labelWidth) + pad(value.map(target.format) ?? "—", 9)
                + pad(target.band, 14) + pad(verdict, 11) + pad(target.season.printed, 9)
                + pad(CalibrationTarget.sourceKey(for: target.source), 5)
                + target.rulesSensitiveTo.map(\.rawValue).sorted().joined(separator: ","))
    }
}

func header() {
    print(
        "  " + pad("metric (per team per game)", labelWidth) + pad("value", 9)
            + pad("target", 14) + pad("verdict", 11) + pad("season", 9) + pad("src", 5)
            + "sensitive to")
}

// MARK: - Build a world

// The same world `worldgen` prints and the tests play in, from the same call. Until this
// existed the harness gave every team `Strength.leagueAverage`, so four hundred games were
// four hundred meetings between two identical clubs and no row that depends on one team
// being better than another meant anything.
//
// What it is built from — no draft pipeline, no rivalries, a smaller college pool — is
// HarnessWorld's, so the harness's tests can build the same world and the checksum below
// is provably taken over the one the games are played in.
let world: WorldGenerator.GeneratedWorld
switch HarnessWorld.generate(seed: seed, strengthSpread: strengthSpread) {
case .failure(let error):
    print("could not generate a league:")
    for explanation in error.explanations { print("  - \(explanation)") }
    exit(1)
case .success(let value):
    world = value
}

// Nothing below this line runs under --world-checksum-only: the question it answers is
// which league this seed builds, and that is settled the moment the world exists.
if worldChecksumOnly {
    print(HarnessWorld.checksumLine(for: world))
    exit(0)
}

let players = world.players

// MARK: - Simulate

let simulator = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
var results: [GameResult] = []
// Wall clock inside the simulate calls, and nothing else, for the Budget block at the
// end. Everything the loop does around the call — the weather draw, the setup — and
// every query over the stream afterwards are outside it.
var simulateSeconds = 0.0
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
            id: home.id, depthChart: world.depthChart(of: home.id), scheme: home.scheme),
        away: GameTeam(
            id: away.id, depthChart: world.depthChart(of: away.id), scheme: away.scheme),
        players: players,
        stadium: home.stadium,
        weather: weather,
        rules: rulesInForce,
        seed: seed &+ UInt64(index) &* 7919)
    let startedAt = monotonicSeconds()
    let result = simulator.simulate(setup)
    simulateSeconds += monotonicSeconds() - startedAt
    results.append(result)
    conditions.append((home: home.id, setup: setup))
}

// MARK: - Query the stream

let allPlays = results.flatMap(\.plays)
let teamGames = Double(results.count * 2)

func rate(_ count: Int) -> Double { Double(count) / teamGames }

let scrimmage = allPlays.filter { $0.outcome.kind.isScrimmagePlay }
let dropbacks = allPlays.filter { $0.outcome.kind.isDropback }
let attempts = allPlays.filter { $0.outcome.kind.isPassAttempt }
// A completion is what the record says, not what the yards imply: a ball caught for a
// loss is one. Inferring it from `yards > 0` scored every catch for nothing as an
// incompletion and read the completion row three points low while showing green.
let completions = attempts.filter(\.isCompletion)
// The older inference, kept for the rows whose bands were sourced against it — yards
// per completion and the catch leaders — until the harness read-out is re-baselined as
// a whole.
let completionsThatGained = attempts.filter {
    $0.outcome.yards > 0 || $0.outcome.endedIn == .touchdown
}
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
// No target: this is the world the games were played in, not a result. It is printed so a
// run that looks flat can be told apart from a league that was drawn flat.
let offsets = world.teams.map { world.strength(of: $0.id).offset }
print(
    "  \(world.teams.count) teams, strength offset "
        + "\(oneDecimal(offsets.min() ?? 0)) to \(oneDecimal(offsets.max() ?? 0))")
// The world this run was played in, as one number, from the same function GoldenWorldTests
// pins. It follows from the seed alone, so it is byte-identical between two runs (#52);
// two *branches* printing the same number generated the same league, which is what
// scripts/harness-reach.sh needs to know before it says a change cannot reach these rows.
print(
    "  " + HarnessWorld.checksumLine(for: world)
        + "  (no target: it names the league, it does not grade it)")
print("")
print("  Rulebook")
print(
    "    compared against            \(rulebookSeason)"
        + (rulebookOption == nil
            ? " (Rules.rulebookSeason, the book the engine plays)"
            : rulebookSeason == engineRulebookSeason ? "" : " (--rulebook)"))
print("    kickoff touchback spot      own \(rulesInForce.kickoffTouchbackOwnYard)")
print(
    "    onside kick from             "
        + (rulesInForce.onsideKickEarliestQuarter <= 1
            ? "any period, trailing" : "Q\(rulesInForce.onsideKickEarliestQuarter), trailing"))
if staleTargets.isEmpty {
    print("    every row was sourced under this rulebook")
} else {
    print("    rows sourced under another rulebook — stale, never ok, re-source before tuning:")
    for target in CalibrationTarget.all {
        guard let change = staleTargets[target.id] else { continue }
        print(
            "      \(pad(target.id, 34))sourced \(target.season.printed); "
                + "\(change.area.rawValue) changed in \(change.season) (\(change.citation))")
    }
}
print("")
print("  Sources")
for (key, title) in CalibrationTarget.sources {
    print("    \(pad(key, 5))\(title)")
}
print("    a stale row was sourced under a different rulebook than the run; an unsourced row")
print("    keeps a band nobody has cited and is never ok; (ok) and (OFF) are rows with no gate")

print("")
header()
report("points", points / teamGames)
report("passingYards", passYards / teamGames)
report("rushingYards", rushYards / teamGames)
report("yardsPerCarry", carries.isEmpty ? 0 : rushYards / Double(carries.count))
report(
    "completionPercentage",
    attempts.isEmpty ? 0 : Double(completions.count) / Double(attempts.count) * 100)
report("sackRate", dropbacks.isEmpty ? 0 : Double(sacks.count) / Double(dropbacks.count) * 100)
report(
    "interceptionRate",
    attempts.isEmpty ? 0 : Double(interceptions.count) / Double(attempts.count) * 100)
report(
    "thirdDownConversion",
    thirdDowns.isEmpty ? 0 : Double(thirdDownConversions.count) / Double(thirdDowns.count) * 100)
report("playsFromScrimmage", rate(scrimmage.count))

let flags = allPlays.flatMap(\.outcome.penalties)
let accepted = flags.filter(\.wasAccepted)
report("penaltiesPerGame", Double(accepted.count) / Double(results.count))

let thirdDownDistance =
    thirdDowns.isEmpty
    ? 0
    : Double(thirdDowns.reduce(0) { $0 + Int($1.situation.distance) }) / Double(thirdDowns.count)
report("thirdDownDistance", thirdDownDistance)

// Scrimmage plays only. A kickoff and an extra point are both first-down snaps that
// gain nothing by definition, and counting them dragged this row a yard and a half below
// its target — the row was measuring the wrong thing, not the engine failing to hit it.
let firstDowns = scrimmage.filter { $0.situation.down == .first }
let firstDownGain =
    firstDowns.isEmpty
    ? 0 : Double(firstDowns.reduce(0) { $0 + Int($1.outcome.yards) }) / Double(firstDowns.count)
report("firstDownGain", firstDownGain)

// Yards per attempt is the passing game's real efficiency number — completion rate says
// nothing about whether the completions are worth anything.
let attemptYards = Double(attempts.reduce(0) { $0 + Int(max(0, $1.outcome.yards)) })
report("yardsPerAttempt", attemptYards / Double(max(1, attempts.count)))
let scrimmageYards =
    attemptYards + rushYards
    + Double(sacks.reduce(0) { $0 + Int($1.outcome.yards) })
report("yardsPerPlay", scrimmageYards / Double(max(1, scrimmage.count)))
let receptionYards = attemptYards / Double(max(1, completionsThatGained.count))
report("yardsPerCompletion", receptionYards)

print("")
print("  Shape of the stream")
report("playsPerGame", Double(allPlays.count) / Double(max(1, results.count)))
print(
    "    decisions per play          \(allPlays.reduce(0) { $0 + $1.decisions.count } / max(1, allPlays.count))   (engine internals, no target)"
)
print(
    "    credits per play            \(allPlays.reduce(0) { $0 + $1.outcome.participants.count } / max(1, allPlays.count))   (engine internals, no target)"
)
let scores = results.map { "\($0.homeScore)-\($0.awayScore)" }
print("    first scorelines            \(scores.prefix(8).joined(separator: "  "))")
let ties = results.filter(\.isTie).count
print("    ties                        \(ties) of \(results.count)")
report("tiesPerGame", Double(ties) / Double(max(1, results.count)))
// Overtime is any snap in a fifth period. The seconds it used come from the last snap's
// clock, so a period that expires level reads as the full period.
let overtimeGames = results.filter { $0.plays.contains { $0.situation.quarter >= 5 } }
report("overtimeRate", Double(overtimeGames.count) / Double(max(1, results.count)) * 100)
let overtimeSeconds = overtimeGames.map { result -> Int in
    let remaining = result.plays.filter { $0.situation.quarter >= 5 }.map {
        Int($0.situation.clockRemaining)
    }
    return Int(rulesInForce.regularSeasonOvertimeLength) - (remaining.min() ?? 0)
}
report(
    "overtimeLength",
    overtimeGames.isEmpty
        ? nil : Double(overtimeSeconds.reduce(0, +)) / Double(overtimeGames.count))

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
//
// Sorted by overall and then by ID. Overall alone is not a total order: rushers tied on
// it kept whatever order the dictionary handed over, which is Swift's per-process hash
// seed, so the split at `count / 2` and both means below moved between runs of the same
// seed. Iteration order over an unordered collection never reaches output (ADR-0003).
let rushers = sacksBy.compactMap { id, count -> (overall: Int, sacks: Int, id: UInt64)? in
    guard let player = players[id] else { return nil }
    return (Int(player.overall), count, id.rawValue)
}
if rushers.count > 6 {
    let sorted = rushers.sorted {
        $0.overall != $1.overall ? $0.overall > $1.overall : $0.id < $1.id
    }
    let topHalf = sorted.prefix(sorted.count / 2)
    let bottomHalf = sorted.suffix(sorted.count / 2)
    let topRate = Double(topHalf.reduce(0) { $0 + $1.sacks }) / Double(topHalf.count)
    let bottomRate = Double(bottomHalf.reduce(0) { $0 + $1.sacks }) / Double(bottomHalf.count)
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

// Knees that were followed by an ordinary snap on the same possession. A knee is the
// offence saying the game is over; going back to running plays afterwards means the
// arithmetic behind it was wrong, and the lead was being handed back one snap at a time.
// Not a league rate and so not a `row:` — it is a promise the caller makes about itself,
// and the number to beat is zero.
var kneelsFollowedByALivePlay = 0
for result in results {
    var possession: TeamID?
    var quarter: UInt8 = 0
    var kneeled = false
    for play in result.plays {
        // A flag before the snap is not a snap: the down is replayed, and a false start on
        // a knee changes nothing about the decision.
        if play.outcome.kind == .penaltyOnly { continue }
        // A free kick and a new period each start a sequence of their own, and the side
        // that kneels a half out can be the side that kicks off to open the next one: the
        // kicking team has possession on a kickoff, so nothing else marks that boundary.
        if play.outcome.kind == .kickoff || play.situation.quarter != quarter
            || play.situation.possession != possession
        {
            quarter = play.situation.quarter
            possession = play.situation.possession
            kneeled = false
        }
        let isKneel = play.outcome.kind == .kneel
        if kneeled && !isKneel { kneelsFollowedByALivePlay += 1 }
        kneeled = kneeled || isKneel
    }
}

// Read off the record rather than inferred from two consecutive situations, which
// could not see a timeout taken with the ball about to change hands: a charged timeout
// before a snap is a `.timeout` on that snap, and one the rules charged after a play —
// the offence's alternative to a runoff, an injury timeout — is a clock election on it.
var timeoutsSpent = 0
var twoMinuteWarnings = 0
for play in allPlays {
    let taken = play.timeoutsBeforeTheSnap
    timeoutsSpent += taken.offense + taken.defense
    if play.hasTwoMinuteWarningBeforeTheSnap { twoMinuteWarnings += 1 }
    for election in play.decisions.compactMap(\.clockElectionValue)
    where election == .timeoutInsteadOfRunoff || election == .injuryTimeoutCharged {
        timeoutsSpent += 1
    }
}
print("")
print("  Flags")
// The ten most common fouls each have a target; the rest are printed as observations.
var byFoul: [String: Int] = [:]
for flag in accepted { byFoul["\(flag.foul)", default: 0] += 1 }
let targetedFouls = CalibrationTarget.all.filter { $0.id.hasPrefix("penalty.") }.map {
    String($0.id.dropFirst("penalty.".count))
}
for foul in targetedFouls {
    report("penalty.\(foul)", Double(byFoul[foul] ?? 0) / Double(max(1, results.count)))
}
for (foul, count) in byFoul.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) })
where !targetedFouls.contains(foul) {
    print(
        "    " + pad(foul, 28)
            + "\(oneDecimal(Double(count) / Double(results.count))) per game   (outside the ten most common, no target)"
    )
}
print(
    "    " + pad("declined", 28)
        + "\(oneDecimal(Double(flags.count - accepted.count) / Double(max(1, flags.count)) * 100))%   (no target: the source counts accepted fouls only)"
)
// The contact family is enforced from the dead-ball spot with the gain counting (A6,
// #18); measured from the previous spot it was declined against its own play's gain
// most of the time. No target, for the same reason as the row above: this is a rules
// check, and a family accepted far more often than declined is what the rule gives.
let contactFouls: Set<String> = [
    "facemask", "unnecessaryRoughness", "roughingThePasser", "horseCollarTackle",
    "illegalUseOfHelmet",
]
let contactFlags = flags.filter { contactFouls.contains("\($0.foul)") }
let contactDeclined = contactFlags.filter { !$0.wasAccepted }.count
print(
    "    " + pad("contact fouls declined", 28)
        + "\(oneDecimal(Double(contactDeclined) / Double(max(1, contactFlags.count)) * 100))% of \(contactFlags.count)   (no target: a rules check for #18, enforced from the dead-ball spot)"
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
report("playerGamesLost", perTeamSeason)
let nonContact = allInjuries.filter { $0.cause == .nonContact }
print(
    "    non-contact share           "
        + "\(oneDecimal(Double(nonContact.count) / Double(max(1, allInjuries.count)) * 100))%")
let nonContactGames = nonContact.reduce(0) { $0 + Int($1.gamesOut) }
print(
    "    non-contact games lost      "
        + "\(oneDecimal(Double(nonContactGames) / Double(max(1, missedGames)) * 100))% of all")
let longest = allInjuries.map(\.gamesOut).max() ?? 0
print("    longest absence             \(longest) games   (a tail; needs a season, not a sample)")

let scrambles = allPlays.filter { $0.outcome.kind == .scramble }

print("")
print("  The endgame")
report("scramblesPerGame", Double(scrambles.count) / Double(max(1, results.count)))
report("kneelsPerGame", Double(kneels) / Double(max(1, results.count)))
print(
    "  " + pad("knees followed by a live play", labelWidth)
        + pad("\(kneelsFollowedByALivePlay)", 9) + pad("0", 14)
        + pad(kneelsFollowedByALivePlay == 0 ? "ok" : "OFF", 11) + pad("-", 9) + pad("-", 5)
        + "a caller contract, not a league rate: test:aKneelIsNeverFollowedByALivePlay")
report("spikesPerGame", Double(spikes) / Double(max(1, results.count)))
report("timeoutsPerGame", Double(timeoutsSpent) / Double(max(1, results.count)))
print(
    "    \(pad("two-minute warnings per game", 30))"
        + "\(twoDecimals(Double(twoMinuteWarnings) / Double(max(1, results.count))))"
        + "   (no target: two a game by rule, 3-41, plus one for each regular-season overtime period that reaches 2:00; a rule, not a rate)"
)

// Where a play ends laterally, which after the two-minute warning of the first half and
// inside the last five minutes of the second is a clock decision rather than an accident
// (2025 rulebook, 4-3-2-a: out of bounds leaves the clock stopped until the snap in those
// windows and restarts it on the ready signal everywhere else). No target on any of the
// three: nothing in docs/reference/calibration-sources.md bands where a play ends
// laterally, and a sourced band would land with E2 (#42).
print("")
print("  Ending on the sideline   (no target: unsourced, a band belongs to #42)")
func sidelineShare(_ plays: [PlayRecord]) -> String {
    let down = plays.filter {
        $0.outcome.endedIn == .tackled || $0.outcome.endedIn == .outOfBounds
    }
    guard !down.isEmpty else { return "—" }
    let out = down.filter { $0.outcome.endedIn == .outOfBounds }.count
    return oneDecimal(Double(out) / Double(down.count) * 100) + "%"
}
let sidelineClassified = scrimmage.map {
    (play: $0, classified: SituationClass($0.situation, rules: rulesInForce))
}
let trailingLate = sidelineClassified.filter { $0.classified.isDesperation }.map(\.play)
let leadingLate = sidelineClassified.filter { $0.classified.isClockBurn }.map(\.play)
print("    \(pad("all scrimmage plays", 30))\(sidelineShare(scrimmage))")
print(
    "    \(pad("trailing inside two minutes", 30))\(sidelineShare(trailingLate))"
        + "   \(trailingLate.count) plays")
print(
    "    \(pad("protecting a lead late", 30))\(sidelineShare(leadingLate))"
        + "   \(leadingLate.count) plays")

print("")
print("  Not measured here")
report("winTotalSigma", nil)
print("    Spread of team win totals — the single most important row in the")
print("    calibration table, and it needs a season with a schedule rather than")
print("    arbitrary matchups. It arrives with M3.")

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
// Every punt's net, gross and return, read off the record: the line, where it was
// fielded and where it came to rest are all on it, so a returned punt's gross and its
// return are told apart rather than one inferred from the other, and a touchback is
// netted to the twenty as the source nets it. A blocked punt has no distance and is in
// none of these.
var puntNets: [Int] = []
var puntGrosses: [Int] = []
var puntReturnYards: [Int] = []
var kickoffReturnYards: [Int] = []
var fieldGoalsByDistance: [(distance: Int, good: Bool)] = []

var twoPointTries = 0
var twoPointGood = 0
var twoPointRuns = 0
var drivePlays: [Int] = []
var threeAndOuts = 0
var shortDriveEndings: [String: Int] = [:]
var redZoneDrives = 0
var redZoneTouchdowns = 0

for result in results {
    // A drive is a run of consecutive snaps by one team. Classified by how its last
    // snap ended, so a drive killed by the clock is counted rather than dropped.
    var current: (team: TeamID, start: Int, last: PlayRecord, plays: Int, redZone: Bool)?

    func closeDrive(
        _ drive: (team: TeamID, start: Int, last: PlayRecord, plays: Int, redZone: Bool)
    ) {
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
        if drive.plays <= 3 { shortDriveEndings[label, default: 0] += 1 }
        // A red zone trip is a drive with a snap inside the twenty; the rate is how many
        // of those trips end in the offence's touchdown rather than a kick or nothing.
        if drive.redZone {
            redZoneDrives += 1
            if label == "touchdown" { redZoneTouchdowns += 1 }
        }
    }

    for play in result.plays {
        let outcome = play.outcome

        switch outcome.kind {
        case .kickoff:
            kickoffEndings["\(outcome.endedIn)", default: 0] += 1
            // A return, as the source counts one: fielded and run, not fair caught,
            // not out of bounds, and not an onside kick.
            if play.calls.offense.concept != .onsideKick,
                outcome.endedIn == .tackled || outcome.endedIn == .touchdown,
                let back = play.returnYards
            {
                kickoffReturnYards.append(back)
            }
        case .punt:
            if let net = play.netPuntDistance(rules: rulesInForce) { puntNets.append(net) }
            if let gross = play.kickDistance { puntGrosses.append(gross) }
            if outcome.endedIn == .tackled || outcome.endedIn == .touchdown,
                let back = play.returnYards
            {
                puntReturnYards.append(back)
            }
        case .fieldGoal:
            fieldGoalsByDistance.append(
                (Int(play.situation.ballOn) + 17, outcome.endedIn == .fieldGoalGood))
        case .twoPointConversion:
            twoPointTries += 1
            if outcome.endedIn == .touchdown { twoPointGood += 1 }
            if play.calls.offense.concept == .twoPointRun {
                twoPointRuns += 1
            }
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
        let inRedZone = play.situation.ballOn <= 20
        if current == nil {
            current = (
                play.situation.possession, Int(play.situation.ballOn), play, counts ? 1 : 0,
                inRedZone
            )
        } else {
            current?.last = play
            if counts { current?.plays += 1 }
            if inRedZone { current?.redZone = true }
        }
    }
    if let drive = current { closeDrive(drive) }
}

let totalPoints = pointsBySource.values.reduce(0, +)
for (source, value) in pointsBySource.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }) {
    let share = Double(value) / Double(max(1, totalPoints)) * 100
    print(
        "    \(pad(source, 26))\(pad(oneDecimal(Double(value) / teamGames), 7))\(oneDecimal(share))%"
    )
}
report(
    "pointsFromTouchdowns",
    Double(pointsBySource["touchdown"] ?? 0) / Double(max(1, totalPoints)) * 100)
report(
    "pointsFromFieldGoals",
    Double(pointsBySource["field goal"] ?? 0) / Double(max(1, totalPoints)) * 100)

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
for (code, count) in groups.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }).prefix(6) {
    print(
        "      \(pad(code < 10 ? "0\(code)" : "\(code)", 28))\(oneDecimal(Double(count) / snaps * 100))%"
    )
}
print("    defensive package")
for (package, count) in packages.sorted(by: {
    ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue)
}) {
    print("      \(pad("\(package)", 28))\(oneDecimal(Double(count) / snaps * 100))%")
}
report("personnel11", Double(groups[11] ?? 0) / snaps * 100)
report("packageNickel", Double(packages[.nickel] ?? 0) / snaps * 100)
report("packageBase", Double(packages[.base] ?? 0) / snaps * 100)

// Who took the snap, from presence rather than credit. Every play carries the roster
// index of each of the twenty-two men on the field, so a snap count is a query over the
// stream, and these rows are player-snaps per team-game by the roster position group of
// each man — the same construction the source's participation feed allows, and a
// number the credits alone could never produce: a lineman was credited on three to five
// snaps in five, and a safety on a sixth of run plays.
print("    player-snaps by position group, per team-game, plays from scrimmage")
var snapsByGroup: [PositionGroup: Int] = [:]
for result in results {
    for play in result.plays where play.outcome.kind.isScrimmagePlay {
        for index in 0..<PlayerSlot.count {
            guard let player = play.player(at: PlayerSlot(index), rosters: result.rosters),
                let group = players[player]?.position.group
            else { continue }
            snapsByGroup[group, default: 0] += 1
        }
    }
}
@MainActor
func groupSnaps(_ groups: PositionGroup...) -> Double {
    Double(groups.reduce(0) { $0 + (snapsByGroup[$1] ?? 0) }) / teamGames
}
report("snaps.quarterback", groupSnaps(.quarterback))
report("snaps.backfield", groupSnaps(.backfield))
report("snaps.receiver", groupSnaps(.receiver))
report("snaps.tightEnd", groupSnaps(.tightEnd))
report("snaps.offensiveLine", groupSnaps(.offensiveLine))
report("snaps.frontSeven", groupSnaps(.edge, .defensiveInterior, .linebacker))
report("snaps.defensiveBack", groupSnaps(.cornerback, .safety))

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
var yardsByAdvantage: [Int: Double] = [:]
for advantage in [-2, -1, 0, 1, 2] {
    let matching = carries.filter {
        countAdvantage($0) == advantage && $0.situation.down == .first
            && $0.situation.distance == 10
    }
    guard matching.count > 200 else { continue }
    let yards = Double(matching.reduce(0) { $0 + Int($1.outcome.yards) }) / Double(matching.count)
    yardsByAdvantage[advantage] = yards
    let label = advantage > 0 ? "+\(advantage) blockers" : "\(advantage) blockers"
    print("      \(pad(label, 28))\(pad(oneDecimal(yards), 8))\(matching.count) carries")
}
report("ypcEvenCount", yardsByAdvantage[0])
report("ypcOutnumberedByOne", yardsByAdvantage[-1])

print("")
print("  The shape of a carry")
// A mean is not a distribution. Real carries are mostly modest with a fat tail, and an
// engine can hit 4.3 a carry by giving everyone four and a half yards every time, which
// would be nothing like the sport.
let carryYards = carries.map { Int($0.outcome.yards) }
func carryShare(_ test: (Int) -> Bool) -> Double {
    Double(carryYards.filter(test).count) / Double(max(1, carryYards.count)) * 100
}
report("carriesStuffed", carryShare { $0 <= 0 })
report("carries2orFewer", carryShare { $0 <= 2 })
report("carries10plus", carryShare { $0 >= 10 })
report("carries20plus", carryShare { $0 >= 20 })

print("")
print("  The shape of a dropback")
// The same question as the carry rows. A passing game with the right mean and no tail
// produces drives that neither die quickly nor break open, which is what leaves a game
// with too few possessions in it.
let dropbackYards = dropbacks.map { Int($0.outcome.yards) }
func dropbackShare(_ test: (Int) -> Bool) -> Double {
    Double(dropbackYards.filter(test).count) / Double(max(1, dropbackYards.count)) * 100
}
report("dropbackLoss", dropbackShare { $0 < 0 })
report("dropbackNoGain", dropbackShare { $0 == 0 })
report("dropback10plus", dropbackShare { $0 >= 10 })
report("dropback20plus", dropbackShare { $0 >= 20 })
report("dropback40plus", dropbackShare { $0 >= 40 })
// A pressured dropback is one whose pocket verdict says a rusher got there before the ball
// was out — the stream records that verdict as a decision point, so pressure is a query and
// not a counter the resolver keeps. A rep lost after the throw is a `.blockResult` and is
// deliberately not counted here.
let pressured = dropbacks.filter { $0.decisions.contains { $0.kind == .pressureAllowed } }
report("pressureRate", Double(pressured.count) / Double(max(1, dropbacks.count)) * 100)
// Every caught ball, including the ones that went backwards, read from the record's own
// pass result. This is the gap between the completion row and the older gains-only
// inference, stated as a share of completions.
let caughtForNothing = completions.filter {
    $0.outcome.yards <= 0 && $0.outcome.endedIn != .touchdown
}
report(
    "completionsZeroOrFewer",
    Double(caughtForNothing.count) / Double(max(1, completions.count)) * 100)

print("")
print("  How drives end")
let totalDrives = driveEnds.values.reduce(0, +)
for (end, count) in driveEnds.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }) {
    let share = Double(count) / Double(max(1, totalDrives)) * 100
    print(
        "    \(pad(end, 26))\(pad(oneDecimal(Double(count) / teamGames), 7))\(oneDecimal(share))%")
}
@MainActor
func driveEndShare(_ label: String) -> Double {
    Double(driveEnds[label] ?? 0) / Double(max(1, totalDrives)) * 100
}
report("driveEndPunt", driveEndShare("punt"))
report("driveEndTouchdown", driveEndShare("touchdown"))
report("driveEndDowns", driveEndShare("downs"))
report("drivesPerTeamGame", Double(totalDrives) / teamGames)
report("playsPerDrive", Double(drivePlays.reduce(0, +)) / Double(max(1, drivePlays.count)))
// First downs are the currency of a drive: how many a team earns decides how long its
// drives last, and it is the row that separates "converts third downs at the right rate"
// from "never reaches third down".
let firstDownsEarned = allPlays.filter { play in
    guard play.outcome.kind.isScrimmagePlay else { return false }
    return play.outcome.yards >= Int16(play.situation.distance)
        || play.outcome.endedIn == .touchdown
}.count
report("firstDownsPerTeamGame", Double(firstDownsEarned) / teamGames)
// A mean hides the shape here too. Real football has a fat spike of quick failures and a
// long tail of sustained drives; a league whose drives are all six plays long has neither.
@MainActor
func driveShare(_ test: (Int) -> Bool) -> Double {
    Double(drivePlays.filter(test).count) / Double(max(1, drivePlays.count)) * 100
}
report("drives3orFewer", driveShare { $0 <= 3 })
report("drives4to7", driveShare { $0 >= 4 && $0 <= 7 })
report("drives8plus", driveShare { $0 >= 8 })
print("    how the short ones ended")
let shortTotal = shortDriveEndings.values.reduce(0, +)
for (label, count) in shortDriveEndings.sorted(by: {
    ($0.value, $0.key) > ($1.value, $1.key)
}) {
    print(
        "      \(pad(label, 24))\(pad(oneDecimal(Double(count) / Double(max(1, shortTotal)) * 100) + "%", 9))\(count)"
    )
}
report("threeAndOut", Double(threeAndOuts) / Double(max(1, drivePlays.count)) * 100)
report(
    "redZoneTouchdownRate",
    redZoneDrives == 0 ? nil : Double(redZoneTouchdowns) / Double(redZoneDrives) * 100)

print("")
print("  Field position")
let averageStart = Double(startingSpots.reduce(0, +)) / Double(max(1, startingSpots.count))
report("averageStart", 100 - averageStart)
let ownHalf = startingSpots.filter { $0 > 50 }.count
report("ownHalfStarts", Double(ownHalf) / Double(max(1, startingSpots.count)) * 100)
@MainActor
func mean(_ values: [Int]) -> Double? {
    values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
}
report("puntsPerTeamGame", Double(puntNets.count) / teamGames)
report("netPunt", mean(puntNets))
report("grossPunt", mean(puntGrosses))
report("puntReturnYards", mean(puntReturnYards))
report("twoPointTries", Double(twoPointTries) / teamGames)
report(
    "twoPointConversion",
    twoPointTries == 0 ? nil : Double(twoPointGood) / Double(max(1, twoPointTries)) * 100)
// How the conversions were attempted. A try may be by pass *or run* (2025 rulebook,
// 11-3-1) and every one of them used to be a throw. No target: nothing in
// docs/reference/calibration-sources.md bands the split, and a sourced band belongs to
// E2 (#42).
print(
    "    \(pad("two-point tries run", 30))"
        + "\(twoPointTries == 0 ? "—" : oneDecimal(Double(twoPointRuns) / Double(twoPointTries) * 100) + "%")"
        + "   \(twoPointRuns) of \(twoPointTries)   (no target: unsourced, a band belongs to #42)"
)

// Where punters put the ball, which from plus territory is the whole of a punter's value:
// a scrimmage kick that reaches the end zone untouched is a touchback (2025 rulebook,
// 11-6-2-c) and comes out to the 20 (9-5-1 Note a), while one that stops short of it is
// the receivers' ball where it stopped (9-4-4). No target on any of these rows: nothing in
// docs/reference/calibration-sources.md bands them, and a sourced band belongs to E2 (#42).
// Their net is measured with a touchback spotted at the 20, which is *not* how the
// `netPunt` row above measures it — that one spots it at the goal line, a harness bug
// recorded in calibration-sources.md — so the two are not comparable by construction.
print("")
print("  Punting   (no target: unsourced, a band belongs to #42)")
let puntPlays = allPlays.filter { $0.outcome.kind == .punt }
let plusTerritoryPunts = puntPlays.filter { $0.situation.ballOn <= 45 }

/// Where the receiving team took over, as its own yard line, or `nil` when it never did.
func receiversStart(_ play: PlayRecord) -> Int? {
    switch play.outcome.endedIn {
    case .touchback: return 20
    case .downed, .outOfBounds, .fairCatch, .tackled: return Int(play.outcome.finalSpot ?? 20)
    default: return nil
    }
}

func shareOfTouchbacks(_ plays: [PlayRecord]) -> String {
    guard !plays.isEmpty else { return "—" }
    let touchbacks = plays.filter { $0.outcome.endedIn == .touchback }.count
    return oneDecimal(Double(touchbacks) / Double(plays.count) * 100) + "%"
}

func averageTakeover(_ plays: [PlayRecord]) -> String {
    let spots = plays.compactMap(receiversStart)
    guard !spots.isEmpty else { return "—" }
    return "own " + oneDecimal(Double(spots.reduce(0, +)) / Double(spots.count))
}

print(
    "    \(pad("touchbacks, from inside their 45", 34))\(shareOfTouchbacks(plusTerritoryPunts))"
        + "   \(plusTerritoryPunts.count) punts")
print(
    "    \(pad("drive start after those punts", 34))\(averageTakeover(plusTerritoryPunts))")
print("    \(pad("touchbacks, all punts", 34))\(shareOfTouchbacks(puntPlays))")

// Net punting by the punter's touch, which is the row that says whether the rating
// decides anything at all. Tiers are terciles of the punts actually kicked rather than
// fixed rating bands, so a league whose punters are all alike still splits into three.
let byTouch: [(play: PlayRecord, touch: Int)] = puntPlays.compactMap { play in
    guard let kicker = play.outcome.participants.first(where: { $0.role == .kicker }),
        let touch = players[kicker.player]?.ratings[.puntAccuracy]
    else { return nil }
    return (play, Int(touch))
}
let touchLadder = byTouch.map(\.touch).sorted()
if touchLadder.count >= 3 {
    let lower = touchLadder[touchLadder.count / 3]
    let upper = touchLadder[touchLadder.count * 2 / 3]
    func net(_ plays: [PlayRecord]) -> String {
        let nets = plays.compactMap { play -> Int? in
            guard let start = receiversStart(play) else { return nil }
            return Int(play.situation.ballOn) - start
        }
        guard !nets.isEmpty else { return "—" }
        return oneDecimal(Double(nets.reduce(0, +)) / Double(nets.count))
    }
    func tier(_ test: (Int) -> Bool, kickedFrom inRange: (UInt8) -> Bool) -> [PlayRecord] {
        byTouch.filter { test($0.touch) && inRange($0.play.situation.ballOn) }.map(\.play)
    }
    // Two ladders, because they answer different questions. Over all punts a punter's
    // touch is swamped by his leg and by where he is kicking from — most punts are from
    // a team's own end, where there is nothing to aim at and distance is the whole play.
    // From inside the opponent's 45 placement *is* the play, and that is where the rating
    // has to show.
    let ranges: [(String, (UInt8) -> Bool)] = [
        ("all punts", { _ in true }), ("from inside their 45", { $0 <= 45 }),
    ]
    for (title, inRange) in ranges {
        print("    net punt by the punter's touch, \(title)   (a touchback spotted at the 20)")
        let bottom = tier({ $0 < lower }, kickedFrom: inRange)
        let middle = tier({ $0 >= lower && $0 < upper }, kickedFrom: inRange)
        let top = tier({ $0 >= upper }, kickedFrom: inRange)
        print("      \(pad("touch under \(lower)", 32))\(net(bottom))   \(bottom.count) punts")
        print(
            "      \(pad("touch \(lower) to \(upper - 1)", 32))\(net(middle))"
                + "   \(middle.count) punts")
        print("      \(pad("touch \(upper) and up", 32))\(net(top))   \(top.count) punts")
    }
}

print("")
print("  Kicking")
let kickoffCount = kickoffEndings.values.reduce(0, +)
for (ending, count) in kickoffEndings.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }) {
    print(
        "    \(pad("kickoff → \(ending)", 30))"
            + "\(oneDecimal(Double(count) / Double(max(1, kickoffCount)) * 100))%"
    )
}
report(
    "kickoffTouchbacks",
    Double(kickoffEndings["touchback"] ?? 0) / Double(max(1, kickoffCount)) * 100)
report("fieldGoalsPerTeamGame", Double(fieldGoalsByDistance.count) / teamGames)
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
@MainActor
func fieldGoals(_ low: Int, _ high: Int) -> [(distance: Int, good: Bool)] {
    fieldGoalsByDistance.filter { $0.distance >= low && $0.distance <= high }
}
func madeShare(_ kicks: [(distance: Int, good: Bool)]) -> Double? {
    kicks.isEmpty ? nil : Double(kicks.filter(\.good).count) / Double(kicks.count) * 100
}
@MainActor
func attemptShare(_ kicks: [(distance: Int, good: Bool)]) -> Double {
    Double(kicks.count) / Double(max(1, fieldGoalsByDistance.count)) * 100
}
report("fieldGoalsUnder30", madeShare(fieldGoals(0, 29)))
report("fieldGoals30to39", madeShare(fieldGoals(30, 39)))
report("fieldGoals40to49", madeShare(fieldGoals(40, 49)))
report("fieldGoals50plus", madeShare(fieldGoals(50, 99)))
report("fieldGoalAttemptsUnder30", attemptShare(fieldGoals(0, 29)))
report("fieldGoalAttempts30to39", attemptShare(fieldGoals(30, 39)))
report("fieldGoalAttempts40to49", attemptShare(fieldGoals(40, 49)))
report("fieldGoalAttempts50plus", attemptShare(fieldGoals(50, 99)))
let extraPoints = allPlays.filter { $0.outcome.kind == .extraPoint }
let extraPointsGood = extraPoints.filter { $0.outcome.endedIn == .fieldGoalGood }.count
report(
    "extraPointsMade",
    extraPoints.isEmpty ? nil : Double(extraPointsGood) / Double(extraPoints.count) * 100)

print("")
print("  Fourth down")
// The most-discussed decision in the modern game, and the one a conservative caller
// makes invisible.
let fourthDowns = allPlays.filter {
    $0.situation.down == .fourth && $0.outcome.kind != .kickoff && $0.outcome.kind != .extraPoint
        && $0.outcome.kind != .twoPointConversion && $0.outcome.kind != .penaltyOnly
}
func fourthShare(_ test: (PlayRecord) -> Bool) -> Double {
    Double(fourthDowns.filter(test).count) / Double(max(1, fourthDowns.count)) * 100
}
report("fourthDownPunted", fourthShare { $0.outcome.kind == .punt })
report("fourthDownKicked", fourthShare { $0.outcome.kind == .fieldGoal })
report("fourthDownWentForIt", fourthShare { $0.outcome.kind.isScrimmagePlay })
let goes = fourthDowns.filter { $0.outcome.kind.isScrimmagePlay }
let converted = goes.filter {
    $0.outcome.yards >= Int16($0.situation.distance) || $0.outcome.endedIn == .touchdown
}
report("fourthDownAttempts", Double(goes.count) / teamGames)
report("fourthDownConversion", Double(converted.count) / Double(max(1, goes.count)) * 100)
// Where the offence actually stays on the field. "Going for it" is only a real decision
// in some parts of the field and some parts of the game; a team going for it on fourth
// and four from its own thirty in the first quarter is a broken caller, not a bold one.
print("    where it went for it")
for (label, test) in [
    ("own 1 to own 30", { (b: UInt8) in b > 70 }),
    ("own 30 to midfield", { (b: UInt8) in b > 50 && b <= 70 }),
    ("midfield to their 30", { (b: UInt8) in b > 30 && b <= 50 }),
    ("inside their 30", { (b: UInt8) in b <= 30 }),
] as [(String, (UInt8) -> Bool)] {
    let inZone = goes.filter { test($0.situation.ballOn) }
    let share = Double(inZone.count) / Double(max(1, goes.count)) * 100
    print("      \(pad(label, 24))\(pad(oneDecimal(share) + "%", 9))\(inZone.count) attempts")
}
let deepGoes = goes.filter { $0.situation.ballOn > 70 }
var deepByTime: [String: Int] = [:]
for play in deepGoes { deepByTime["\(SituationClass(play.situation).time)", default: 0] += 1 }
if !deepGoes.isEmpty {
    let byTime = deepByTime.sorted { ($0.value, $0.key) > ($1.value, $1.key) }
    print(
        "      \(pad("    deep ones, by time", 24))"
            + byTime.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
}
let neutral = goes.filter {
    let classified = SituationClass($0.situation)
    return !classified.score.isTrailing && !classified.time.isEndgame
}
print(
    "      \(pad("level or ahead, not late", 24))"
        + "\(pad(oneDecimal(Double(neutral.count) / Double(max(1, goes.count)) * 100) + "%", 9))"
        + "avg \(oneDecimal(Double(neutral.reduce(0) { $0 + Int($1.situation.distance) }) / Double(max(1, neutral.count)))) to go"
)

let shortGoes = fourthDowns.filter { $0.situation.distance <= 1 }
let shortWent = shortGoes.filter { $0.outcome.kind.isScrimmagePlay }
report(
    "fourthAndOneWentForIt", Double(shortWent.count) / Double(max(1, shortGoes.count)) * 100)

print("")
print("  Turnovers and the return game")
let fumblesLost = allPlays.filter { $0.outcome.endedIn == .fumbleLost }
let fumblesKept = allPlays.filter { $0.outcome.endedIn == .fumbleRecovered }
report("fumblesLost", Double(fumblesLost.count) / teamGames)
report("fumblesKept", Double(fumblesKept.count) / teamGames)
let takeaways = fumblesLost.count + interceptions.count
report("turnovers", Double(takeaways) / teamGames)

// A touchdown the offence did not score. Split by who scored it, because kick returns
// answer to the kickoff rules and interception returns do not.
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
report("nonOffensiveTouchdowns", Double(nonOffensive) / teamGames)
for (source, count) in returnScores.sorted(by: { ($0.value, $0.key) > ($1.value, $1.key) }) {
    print(
        "      \(pad(source, 28))\(pad(twoDecimals(Double(count) / teamGames), 8))\(count) in \(Int(teamGames)) team-games"
    )
}
let kickReturnScores = (returnScores["kickoff return"] ?? 0) + (returnScores["punt return"] ?? 0)
report("defensiveReturnTouchdowns", Double(nonOffensive - kickReturnScores) / teamGames)
report("kickReturnTouchdowns", Double(kickReturnScores) / teamGames)

var kickoffReturns = 0
var onside = 0
var onsideRecovered = 0
for play in allPlays where play.outcome.kind == .kickoff {
    if play.calls.offense.concept == .onsideKick {
        onside += 1
        if play.outcome.endedIn == .fumbleRecovered { onsideRecovered += 1 }
    } else if play.outcome.endedIn == .tackled || play.outcome.endedIn == .touchdown {
        // Returned, which is the row's definition. A touchback is not, and neither is a
        // kick that went out of bounds or came down short of the landing zone: those hand
        // the receiving team a spot (2025 rulebook, 6-2-4) rather than a return.
        kickoffReturns += 1
    }
}
print("    \(pad("onside kicks (recovered)", 30))\(onside) (\(onsideRecovered))")
report("onsideKicks", Double(onside) / Double(max(1, results.count)))
report("onsideRecovery", onside == 0 ? nil : Double(onsideRecovered) / Double(onside) * 100)
print(
    "    \(pad("kickoffs returned", 30))\(kickoffReturns) of \(allPlays.filter { $0.outcome.kind == .kickoff }.count)"
)
report("kickoffsReturned", Double(kickoffReturns) / Double(max(1, kickoffCount)) * 100)
report("kickoffReturnYards", mean(kickoffReturnYards))
let puntsReturned = allPlays.filter { $0.outcome.kind == .punt && $0.outcome.endedIn == .tackled }
    .count
let puntCount = allPlays.filter { $0.outcome.kind == .punt }.count
print("    \(pad("punts returned", 30))\(puntsReturned) of \(puntCount)")
report("puntsReturned", Double(puntsReturned) / Double(max(1, puntCount)) * 100)

print("")
print("  Backed up")
let deep = scrimmage.filter { $0.situation.ballOn >= 90 }
report("snapsInsideOwn10", Double(deep.count) / teamGames)
let safeties = allPlays.filter { $0.outcome.endedIn == .safety }
report("safeties", Double(safeties.count) / teamGames)
let deepSacks = deep.filter { $0.outcome.kind == .sack }
print(
    "    \(pad("sacks taken inside own 10", 26))\(deepSacks.count) in \(Int(teamGames)) team-games   (no target: not in the source)"
)

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
// No target on these two. Real home-field advantage is about two points and 54 to 56%
// (see the sourced note in Targets.swift), and most of it is travel, rest and short weeks
// — none of which can exist before there is a schedule to travel on (M3). What this
// engine models is the crowd alone, so the mechanism below gets the target and the
// aggregate gets a note.
print(
    "    \(pad("home win rate", 30))\(pad(oneDecimal(Double(homeWins) / decided * 100) + "%", 9))crowd only, see M3"
)
// The one row here that can go negative, now that home and away are not the same team:
// at 200 games, five seeds in twenty give the road side the edge. `oneDecimal` keeps the
// sign on a value in (-1, 0) since E1 (#2), so this needs nothing of its own.
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
let ratio = per100(awayPreSnap, awaySnaps) / max(0.01, per100(homePreSnap, homeSnaps))
report("preSnapRoadVsHome", ratio)
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
    "    \(pad("games indoors", 30))\(oneDecimal(Double(indoorGames) / Double(max(1, results.count)) * 100))%   (no target: follows the generated stadiums)"
)
print(
    "    \(pad("games with wind 18mph+", 30))\(oneDecimal(Double(windy) / Double(max(1, results.count)) * 100))%   (no target: follows the generated climates)"
)
@MainActor
func combinedPoints(_ kind: Precipitation) -> Double? {
    guard let bucket = byPrecipitation[kind], bucket.games > 20 else { return nil }
    return Double(bucket.points) / Double(bucket.games)
}
for kind in [Precipitation.none, .rain, .heavyRain, .snow] {
    guard let bucket = byPrecipitation[kind], bucket.games > 20 else { continue }
    print(
        "    \(pad("  \(kind): combined points", 30))"
            + "\(pad(oneDecimal(Double(bucket.points) / Double(bucket.games)), 9))\(bucket.games) games"
    )
}
if let dry = combinedPoints(.none), let wet = combinedPoints(.heavyRain) {
    report("heavyRainPoints", dry - wet)
} else {
    report("heavyRainPoints", nil)
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
report(
    "gamesWithin3", Double(margins.filter { $0 <= 3 }.count) / Double(max(1, results.count)) * 100)
report(
    "gamesWithin7", Double(margins.filter { $0 <= 7 }.count) / Double(max(1, results.count)) * 100)
report(
    "gamesBy14plus",
    Double(margins.filter { $0 >= 14 }.count) / Double(max(1, results.count)) * 100)

// The spread of the point differential, and how much of it is the clubs rather than the
// afternoon. The share rows above say how often a game is close; these two say how far
// apart the scores get and why, which is what tells a wide league from a wild engine.
let differentials = results.map { Double($0.homeScore) - Double($0.awayScore) }
let differentialMean = differentials.reduce(0, +) / Double(max(1, differentials.count))
let differentialVariance =
    differentials.reduce(0.0) { $0 + ($1 - differentialMean) * ($1 - differentialMean) }
    / Double(max(1, differentials.count))
report("marginSigma", differentialVariance.squareRoot())

// One club's differential per game, gathered by club, and split the way
// scripts/calibration-sources.py splits the real seasons: the spread of the club means
// less the pooled within-club spread over the games each club played. The subtraction is
// the point — a short season inflates the spread of the means by exactly that much — and
// without it a league of identical clubs would report a spread it does not have.
var differentialsByTeam: [TeamID: [Double]] = [:]
for (index, entry) in conditions.enumerated() where index < results.count {
    let result = results[index]
    let edge = Double(result.homeScore) - Double(result.awayScore)
    differentialsByTeam[entry.home, default: []].append(edge)
    differentialsByTeam[entry.setup.away.id, default: []].append(-edge)
}
// Sorted by identifier: a fold over a dictionary's own order would make the number depend
// on hashing rather than on the games (ADR-0003).
let byTeam = differentialsByTeam.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
if byTeam.count > 1, byTeam.allSatisfy({ $0.count > 1 }) {
    let teamMeans = byTeam.map { $0.reduce(0, +) / Double($0.count) }
    let meanOfMeans = teamMeans.reduce(0, +) / Double(teamMeans.count)
    let betweenTeams =
        teamMeans.reduce(0.0) { $0 + ($1 - meanOfMeans) * ($1 - meanOfMeans) }
        / Double(teamMeans.count - 1)
    var withinSum = 0.0
    var withinDegrees = 0
    for (team, values) in zip(teamMeans, byTeam) {
        withinSum += values.reduce(0.0) { $0 + ($1 - team) * ($1 - team) }
        withinDegrees += values.count - 1
    }
    let withinTeams = withinSum / Double(withinDegrees)
    let gamesEach = Double(byTeam.reduce(0) { $0 + $1.count }) / Double(byTeam.count)
    let variance = betweenTeams - withinTeams / gamesEach
    report("betweenTeamSigma", variance > 0 ? variance.squareRoot() : 0)
} else {
    report("betweenTeamSigma", nil)
}

print("")
print("  Verdicts")
for verdict in ["ok", "OFF", "stale", "unsourced", "(ok)", "(OFF)", "n/a"] {
    guard let rows = verdicts[verdict], !rows.isEmpty else { continue }
    let listed =
        verdict == "OFF" || verdict == "stale" || verdict == "unsourced" || verdict == "n/a"
    print(
        "    \(pad(verdict, 12))\(rows.count)"
            + (listed ? "   " + rows.sorted().joined(separator: ", ") : ""))
}

// MARK: - Budget

// Last, and after everything else, because these are the only numbers in the run that
// move between two processes. `--no-timing` drops the block, which is how the
// byte-identical property (#52) is still checked with a plain `md5sum`.
if timing {
    print("")
    for line in Budget(games: results.count, seconds: simulateSeconds).lines { print(line) }
}
