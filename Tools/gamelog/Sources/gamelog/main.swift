// Watch one simulated game, play by play.
//
//   cd Tools/gamelog && swift run gamelog --seed 7 --home 3 --away 11
//
// The only view anyone had of a simulated game was aggregate harness rows, and every
// rules bug the September audit found is obvious in thirty seconds of play-by-play and
// invisible in a table of means: the scoring team kicking off after a safety, a tie
// declared at the end of the fourth quarter, a touchdown at 0:00 with no try. Read one
// game end to end before and after any engine change — see docs/tools.md.
//
// **Everything printed here is a query over the `PlayRecord` stream**
// ([ADR-0007](../../../../docs/adr/0007-event-stream-contract.md)). The score, the drive
// boundaries and the period boundaries are folded out of the plays the engine emitted,
// using the same `Rules` arithmetic the game state machine used — nothing reaches into
// the engine's internals and nothing is accumulated alongside the simulation. That is
// also the point: if the printer cannot say what happened, the stream cannot either, and
// that is a finding about the contract rather than about the tool.

import FMCore
import FMGeneration
import FMRandom
import FMSimulation
import FMSimulationScenarios

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Arguments

var seed: UInt64 = 7
var homeIndex = 0
var awayIndex = 1
var week = 1
var season = 2030
var scenarioName: String?

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--seed": seed = UInt64(arguments.next() ?? "") ?? seed
    case "--home": homeIndex = Int(arguments.next() ?? "") ?? homeIndex
    case "--away": awayIndex = Int(arguments.next() ?? "") ?? awayIndex
    case "--week": week = Int(arguments.next() ?? "") ?? week
    case "--season": season = Int(arguments.next() ?? "") ?? season
    case "--scenario": scenarioName = arguments.next() ?? "list"
    case "--help", "-h":
        print(
            """
            gamelog — simulate one game and print it as a broadcast log

              --seed <n>     world seed (default 7)
              --home <i>     home team index into the generated league (default 0)
              --away <i>     away team index (default 1)
              --week <n>     week of the season, which is what the weather is drawn from
                             (default 1)
              --season <n>   season the rosters are generated for (default 2030)

              --scenario <name>   print one rules-conformance scenario instead of a
                                  seeded game — the same games the engine's conformance
                                  suite asserts on, through this same printer
              --scenario list     name them all, with the football each one shows

            One line per play: quarter and clock, the offence, down and distance, field
            position, the concept, what happened and who did it, any flag and how it was
            enforced, and the score after anything that scored. A drive summary at each
            change of possession and a scoreboard at the end of each period.
            """)
        exit(0)
    default:
        print("unknown argument: \(argument) — try --help")
        exit(1)
    }
}

// A scenario is a whole game of its own, so it answers here and the seeded game below is
// never built. Both end in the same `printPlayByPlay`.
if let scenarioName {
    printScenario(named: scenarioName)
    exit(0)
}

// MARK: - The world

/// Build the world this game is played in.
///
/// `WorldGenerator.generate(seed:shape:franchises:season:)`, with exactly the arguments
/// `Tools/simharness` passes — so `--seed 7` names the same thirty-two teams, of the same
/// drawn strength, that the calibration harness plays, and a game watched here is a game
/// from that world rather than from a parallel one.
///
/// No draft pipeline and no rivalries: neither reaches a snap.
func buildWorld(seed: UInt64, season: Int) -> WorldGenerator.GeneratedWorld? {
    try? WorldGenerator.generate(
        seed: seed, shape: .standard, season: season, parts: .teamsAndRosters, collegeCount: 80
    ).get()
}

guard let world = buildWorld(seed: seed, season: season) else {
    print("could not generate a league")
    exit(1)
}

guard homeIndex >= 0, homeIndex < world.teams.count,
    awayIndex >= 0, awayIndex < world.teams.count, homeIndex != awayIndex
else {
    print("--home and --away must be two different indices in 0..<\(world.teams.count)")
    exit(1)
}

let homeTeam = world.teams[homeIndex]
let awayTeam = world.teams[awayIndex]

// Played at a real ground in real weather, for the reason the harness is: a game at
// "Neutral Field" under clear skies exercises neither home field nor the forecast.
var weatherRandom = SplittableRandom(seed: seed &+ UInt64(week) &* 104_729)
let weather = WeatherGenerator.forGame(
    stadium: homeTeam.stadium, week: week, using: &weatherRandom)

let setup = GameSetup(
    game: GameID(1),
    home: GameTeam(
        id: homeTeam.id, depthChart: world.depthChart(of: homeTeam.id),
        scheme: homeTeam.scheme),
    away: GameTeam(
        id: awayTeam.id, depthChart: world.depthChart(of: awayTeam.id),
        scheme: awayTeam.scheme),
    players: world.players,
    stadium: homeTeam.stadium,
    weather: weather,
    // Two matchups from one world seed should not replay the same game, so the two team
    // indices are folded in. The whole game is still a pure function of this number.
    seed: seed &+ UInt64(homeIndex) &* 7_919 &+ UInt64(awayIndex) &* 65_537)

let result = GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller()).simulate(setup)

// MARK: - Formatting

func pad(_ value: String, _ width: Int) -> String {
    var padded = value
    while padded.count < width { padded += " " }
    return padded
}

func padLeft(_ value: String, _ width: Int) -> String {
    var padded = value
    while padded.count < width { padded = " " + padded }
    return padded
}

func minutesAndSeconds(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let remainder = clamped % 60
    return "\(clamped / 60):\(remainder < 10 ? "0" : "")\(remainder)"
}

/// The period as a broadcast names it. A postseason game plays as many overtime
/// periods as it takes (16-1-4-d), and which one it is in matters to the clock — a
/// second overtime period has the first half's two-minute warning and a first has none
/// (16-1-4-h) — so they are numbered the way a broadcast numbers them: OT, 2OT, 3OT.
func periodLabel(quarter: UInt8, rules: Rules) -> String {
    guard quarter > rules.quarters else { return "Q\(quarter)" }
    let period = quarter - rules.quarters
    return period == 1 ? "OT" : "\(period)OT"
}

/// The clock as a broadcast shows it: which period, and how long is left in it.
func clockLabel(quarter: UInt8, remaining: UInt16, rules: Rules) -> String {
    "\(periodLabel(quarter: quarter, rules: rules)) \(minutesAndSeconds(Int(remaining)))"
}

/// Yards from the opponent's goal line, in the terms the sport talks in.
///
/// `ballOn` is one representation everywhere inside the engine precisely so that turning
/// it into "own 34" is a presentation concern, and this is that concern.
func ownOrOpponent(_ ballOn: UInt8) -> String {
    if ballOn == 50 { return "midfield" }
    if ballOn > 50 { return "own \(100 - Int(ballOn))" }
    return "opp \(Int(ballOn))"
}

func downAndDistance(_ situation: Situation) -> String {
    let ordinal: String
    switch situation.down {
    case .first: ordinal = "1st"
    case .second: ordinal = "2nd"
    case .third: ordinal = "3rd"
    case .fourth: ordinal = "4th"
    }
    // Inside the ten the marker would be past the goal line, so the distance is measured
    // to the goal line instead and the sport says "and goal".
    return situation.isGoalToGo ? "\(ordinal) & goal" : "\(ordinal) & \(situation.distance)"
}

func concept(_ calls: Calls) -> String {
    guard let family = CrudePlaybook.family(of: calls.offense.design) else { return "unknown" }
    switch family {
    case .insideRun: return "inside run"
    case .outsideRun: return "outside run"
    case .quickPass: return "quick pass"
    case .mediumPass: return "medium pass"
    case .deepPass: return "deep pass"
    case .screen: return "screen"
    case .playAction: return "play action"
    case .punt: return "punt"
    case .fieldGoal: return "field goal"
    case .kneel: return "kneel"
    case .spike: return "spike"
    case .kickoff: return "kickoff"
    case .extraPoint: return "extra point"
    case .twoPointConversion: return "two-point try"
    case .onsideKick: return "onside kick"
    }
}

func coverageName(_ coverage: Coverage) -> String {
    switch coverage {
    case .coverZero: return "cover 0"
    case .manFree: return "man free"
    case .twoMan: return "2-man"
    case .coverThree: return "cover 3"
    case .coverTwo: return "cover 2"
    case .quarters: return "quarters"
    case .matchQuarters: return "match quarters"
    case .prevent: return "prevent"
    case .runBlitz: return "run blitz"
    }
}

func packageName(_ package: DefensivePackage) -> String {
    switch package {
    case .base: return "base"
    case .nickel: return "nickel"
    case .dime: return "dime"
    case .quarter: return "quarter"
    case .goalLine: return "goal line"
    case .prevent: return "prevent"
    }
}

func foulName(_ foul: Foul) -> String {
    switch foul {
    case .falseStart: return "false start"
    case .offside: return "offside"
    case .encroachment: return "encroachment"
    case .neutralZoneInfraction: return "neutral zone infraction"
    case .delayOfGame: return "delay of game"
    case .illegalFormation: return "illegal formation"
    case .illegalMotion: return "illegal motion"
    case .illegalShift: return "illegal shift"
    case .tooManyMenOnField: return "too many men on the field"
    case .illegalSubstitution: return "illegal substitution"
    case .offensiveHolding: return "offensive holding"
    case .illegalUseOfHands: return "illegal use of hands"
    case .illegalBlockInTheBack: return "illegal block in the back"
    case .illegalBlindsideBlock: return "illegal blindside block"
    case .chopBlock: return "chop block"
    case .tripping: return "tripping"
    case .ineligibleReceiverDownfield: return "ineligible receiver downfield"
    case .illegalManDownfield: return "illegal man downfield"
    case .defensiveHolding: return "defensive holding"
    case .defensivePassInterference: return "defensive pass interference"
    case .offensivePassInterference: return "offensive pass interference"
    case .illegalContact: return "illegal contact"
    case .roughingThePasser: return "roughing the passer"
    case .facemask: return "facemask"
    case .unnecessaryRoughness: return "unnecessary roughness"
    case .horseCollarTackle: return "horse-collar tackle"
    case .illegalUseOfHelmet: return "illegal use of the helmet"
    case .lowBlock: return "low block"
    case .roughingTheKicker: return "roughing the kicker"
    case .runningIntoTheKicker: return "running into the kicker"
    case .illegalTouching: return "illegal touching"
    case .unsportsmanlikeConduct: return "unsportsmanlike conduct"
    case .taunting: return "taunting"
    }
}

func weatherLine(_ weather: WeatherState) -> String {
    if weather.isIndoors { return "indoors, \(weather.temperature)°F" }
    var text = "\(weather.temperature)°F"
    text += weather.windSpeed == 0 ? ", no wind" : ", wind \(weather.windSpeed) mph"
    switch weather.precipitation {
    case .none: break
    case .rain: text += ", rain"
    case .heavyRain: text += ", heavy rain"
    case .snow: text += ", snow"
    }
    return text
}

// MARK: - The broadcast

/// Reads a finished game's stream and prints it the way a person watches one.
///
/// Holds only what the stream cannot supply — who was at home, what the teams are called,
/// who the players are and which rulebook was in force. Everything else is derived from
/// the plays as it walks them.
struct Broadcast {

    let home: Team
    let away: Team
    let players: [PlayerID: Player]
    let rules: Rules

    // Running state, all of it a fold over the stream rather than anything the engine
    // handed over.
    private var homeScore: Int16 = 0
    private var awayScore: Int16 = 0
    private var quarter: UInt8 = 1
    private var drive: Drive?
    private var ambiguousShortNames: Set<String> = []

    /// One team's possession, accumulated only so its summary line can be printed when
    /// it ends.
    private struct Drive {
        let team: TeamID
        let startBallOn: UInt8
        let startElapsed: Int
        var snaps = 0
        var last: PlayRecord
    }

    init(home: Team, away: Team, players: [PlayerID: Player], rules: Rules) {
        self.home = home
        self.away = away
        self.players = players
        self.rules = rules
    }

    // MARK: Names

    func abbreviation(_ team: TeamID) -> String {
        team == home.id ? home.identity.abbreviation : away.identity.abbreviation
    }

    func defending(_ team: TeamID) -> TeamID {
        team == home.id ? away.id : home.id
    }

    /// How a box score refers to him — "M. Whitfield" — unless both sides have one.
    ///
    /// Two generated players sharing a name is not a defect and the generator says so, but
    /// when both are in the same game the short form stops identifying anybody: a kickoff
    /// once printed as returned to the PH 16 by K. Vandergriff and tackled by
    /// K. Vandergriff, which reads as a bug that is not there. Anyone whose short name
    /// also belongs to someone on the other side is printed in full.
    func name(_ player: PlayerID?) -> String {
        guard let player, let found = players[player] else { return "someone" }
        let short = found.name.short
        return ambiguousShortNames.contains(short) ? found.name.full : short
    }

    /// Short names that belong to a player on each side of this game.
    ///
    /// A query over the stream like everything else: only men who were credited with
    /// something can be printed, so only they can collide, and which side a credit was on
    /// follows from the slot and who had the ball.
    private func collidingShortNames(in plays: [PlayRecord]) -> Set<String> {
        var teams: [String: Set<TeamID>] = [:]
        for play in plays {
            let offense = play.situation.possession
            let defense = defending(offense)
            for participant in play.outcome.participants {
                guard let player = players[participant.player] else { continue }
                let team = participant.team(possessionTeam: offense, defendingTeam: defense)
                teams[player.name.short, default: []].insert(team)
            }
        }
        var colliding: Set<String> = []
        for (short, sides) in teams where sides.count > 1 { colliding.insert(short) }
        return colliding
    }

    func name(at slot: PlayerSlot, in outcome: Outcome) -> String {
        name(outcome.participant(at: slot)?.player)
    }

    func credited(_ outcome: Outcome, _ role: PlayRole) -> String? {
        guard let found = outcome.participants.first(where: { $0.role == role }) else { return nil }
        return name(found.player)
    }

    /// A yard line named the way the sport names one: by whose half of the field it is
    /// in. `spot` is in the possessing team's frame, like every spot in the engine.
    func yardLine(_ spot: Int, offense: TeamID) -> String {
        let clamped = max(0, min(100, spot))
        if clamped == 50 { return "midfield" }
        if clamped <= 0 { return "the \(abbreviation(defending(offense))) goal line" }
        if clamped >= 100 { return "the \(abbreviation(offense)) goal line" }
        if clamped > 50 { return "\(abbreviation(offense)) \(100 - clamped)" }
        return "\(abbreviation(defending(offense))) \(clamped)"
    }

    // MARK: Clock arithmetic

    /// Seconds of football played by the time this situation came up.
    ///
    /// Needed only to subtract two of them into a time of possession, which is why an
    /// overtime period is measured from the end of regulation rather than given a
    /// quarter number of its own.
    func elapsed(quarter: UInt8, remaining: UInt16) -> Int {
        if quarter > rules.quarters {
            let regulation = Int(rules.quarters) * Int(rules.quarterLength)
            let overtime = Int(rules.overtimeLength(isPostseason: false)) - Int(remaining)
            return regulation + overtime
        }
        let finished = (Int(quarter) - 1) * Int(rules.quarterLength)
        return finished + Int(rules.quarterLength) - Int(remaining)
    }

    // MARK: The fold

    /// What the rules make of a play, which is where the points and the next spot come
    /// from.
    ///
    /// The same two calls the game state machine makes, on the same inputs, so the
    /// scoreboard printed here *is* the stream summed rather than a second opinion.
    func advancement(for play: PlayRecord) -> Advancement {
        guard let penalty = play.outcome.penalties.first else {
            return rules.advance(from: play.situation, outcome: play.outcome)
        }
        return rules.enforce(
            penalty, on: play.situation, outcome: play.outcome,
            offendingTeamHadBall: penalty.offendingTeam == play.situation.possession
        ).advancement
    }

    mutating func run(_ plays: [PlayRecord]) {
        ambiguousShortNames = collidingShortNames(in: plays)
        for play in plays { show(play) }
        closeDrive(after: nil)
        print("        " + String(repeating: "═", count: 40))
        print("        final · \(scoreline())")
    }

    func scoreline() -> String {
        "\(abbreviation(away.id)) \(awayScore), \(abbreviation(home.id)) \(homeScore)"
    }

    // MARK: One play

    private mutating func show(_ play: PlayRecord) {
        let situation = play.situation
        let outcome = play.outcome
        let offense = situation.possession
        // Asked of the *call* rather than the outcome, because a pre-snap flag on a
        // kickoff is a `penaltyOnly` play that is still part of the kicking sequence —
        // and printing it as first and ten from the offence's own thirty-five is exactly
        // the sort of thing this tool exists to stop.
        let family = CrudePlaybook.family(of: play.calls.offense.design)
        let isTry = family == .extraPoint || family == .twoPointConversion
        let isKickoff = family == .kickoff || family == .onsideKick

        // A kickoff and a try belong to the sequence between drives rather than to a
        // drive, so both close whatever was open — as does the ball changing hands.
        //
        // Decided *before* the period banner is printed rather than after it. A drive
        // that ended in the closing seconds of a quarter is over by the time the horn
        // goes, and printing its summary underneath the banner said the opposite.
        let closesDrive = isTry || isKickoff || (drive.map { $0.team != offense } ?? false)

        // A period ends between two plays and nowhere else, so the change is what marks
        // it. The scoreboard goes with it, because a quarter's score is the thing a
        // reader checks against the game they think they just watched.
        if situation.quarter != quarter {
            // A half ends a drive and a quarter does not: teams change ends and play on.
            let startsHalf = situation.quarter == rules.quarters / 2 + 1
            let startsOvertime = situation.quarter > rules.quarters
            if closesDrive || startsHalf || startsOvertime { closeDrive(after: play) }
            let ending = quarter
            let label =
                ending == rules.quarters / 2
                ? "halftime" : "end of \(periodLabel(quarter: ending, rules: rules))"
            print("        " + String(repeating: "═", count: 40))
            print("        \(label) · \(scoreline())")
            print("        " + String(repeating: "═", count: 40))
            quarter = situation.quarter
        }

        if closesDrive { closeDrive(after: play) }

        if !isTry && !isKickoff {
            if drive == nil {
                drive = Drive(
                    team: offense, startBallOn: situation.ballOn,
                    startElapsed: elapsed(
                        quarter: situation.quarter, remaining: situation.clockRemaining),
                    last: play)
            }
            drive?.last = play
            if outcome.kind.isScrimmagePlay { drive?.snaps += 1 }
        }

        let advancement = advancement(for: play)
        applyScore(advancement, offense: offense)

        var line = padLeft("\(play.index)", 4) + "  "
        line += pad(
            clockLabel(
                quarter: situation.quarter, remaining: situation.clockRemaining, rules: rules),
            9)
        line += pad(abbreviation(offense), 5)
        // Down and distance mean nothing on a kickoff or a try: both are snapped from a
        // fixed spot and neither can produce a second down.
        line += pad(isTry || isKickoff ? "" : downAndDistance(situation), 11)
        line += pad(ownOrOpponent(situation.ballOn), 10)
        // Fourteen, not thirteen: "two-point try" is thirteen characters exactly, and a
        // conversion printed as `two-point tryconversion good` is the one play in the
        // sport whose line nobody could read.
        line += pad(concept(play.calls), 14)
        line += describe(play)

        if advancement.scoring != nil, advancement.points != 0 { line += "   [\(scoreline())]" }
        print(line)

        for penalty in outcome.penalties { print(flagLine(penalty, on: play)) }
    }

    private mutating func applyScore(_ advancement: Advancement, offense: TeamID) {
        guard let scoring = advancement.scoring, advancement.points != 0 else { return }
        // A safety and a defensive touchdown pay the team that did *not* have the ball.
        let scorer: TeamID
        switch scoring {
        case .safety, .defensiveTouchdown: scorer = defending(offense)
        case .touchdown, .fieldGoal, .extraPoint, .twoPointConversion: scorer = offense
        }
        if scorer == home.id {
            homeScore += advancement.points
        } else {
            awayScore += advancement.points
        }
    }

    // MARK: Drives

    private mutating func closeDrive(after next: PlayRecord?) {
        guard let drive else { return }
        self.drive = nil

        let last = drive.last
        let endElapsed =
            next.map {
                elapsed(quarter: $0.situation.quarter, remaining: $0.situation.clockRemaining)
            }
            ?? elapsed(quarter: last.situation.quarter, remaining: 0)
        let seconds = max(0, endElapsed - drive.startElapsed)

        // Net yards, in the drive team's frame: the goal line if they scored, the line of
        // scrimmage of the kick if they kicked, and where the last snap put the ball
        // otherwise.
        let finish: Int
        if last.outcome.endedIn == .touchdown && last.outcome.kind.isScrimmagePlay {
            finish = 0
        } else if last.outcome.kind == .punt || last.outcome.kind == .fieldGoal {
            finish = Int(last.situation.ballOn)
        } else {
            finish = Int(last.situation.ballOn) - Int(last.outcome.yards)
        }
        let yards = Int(drive.startBallOn) - max(0, min(100, finish))

        print(
            "        ── \(abbreviation(drive.team)) drive: \(drive.snaps) "
                + "play\(drive.snaps == 1 ? "" : "s"), \(yardText(yards)), "
                + "\(minutesAndSeconds(seconds)) — \(driveResult(last, endOfGame: next == nil))")
    }

    /// How the drive ended, in the words a drive chart uses.
    ///
    /// - Parameters:
    ///   - play: the drive's last snap.
    ///   - endOfGame: whether the stream ran out rather than the ball changing hands.
    /// - Returns: the drive's result, as a drive chart would label it.
    private func driveResult(_ play: PlayRecord, endOfGame: Bool) -> String {
        // Classified by what the play *was* before how it ended: a punt that gets
        // returned ends in a tackle on fourth down, which reads as a turnover on downs to
        // anything that only looks at the ending.
        switch play.outcome.kind {
        case .punt:
            return play.outcome.endedIn == .touchdown ? "punt returned for a touchdown" : "punt"
        case .fieldGoal:
            return play.outcome.endedIn == .fieldGoalGood ? "field goal" : "missed field goal"
        default:
            switch play.outcome.endedIn {
            case .touchdown: return "touchdown"
            case .intercepted: return "interception"
            case .fumbleLost: return "fumble lost"
            case .safety: return "safety"
            default:
                // Only a play from scrimmage can be stopped short on fourth down. A snap
                // that never happened — a pre-snap flag, which is how a game running out
                // of clock often looks — is the period ending, not a failed gamble.
                if play.outcome.kind.isScrimmagePlay, play.situation.down == .fourth,
                    !play.gainedFirstDown
                {
                    return "turnover on downs"
                }
                return endOfGame ? "end of game" : "end of half"
            }
        }
    }

    // MARK: Flags

    private func flagLine(_ penalty: PenaltyRecord, on play: PlayRecord) -> String {
        let offender = name(at: penalty.offender, in: play.outcome)
        var text = "        flag: \(foulName(penalty.foul)) on \(offender) "
        text += "(\(abbreviation(penalty.offendingTeam))), "
        text +=
            penalty.foul.isSpotFoul ? "spot foul \(penalty.yards) yards" : "\(penalty.yards) yards"
        text += penalty.wasAccepted ? " — accepted" : " — declined"
        if penalty.awardedFirstDown { text += ", automatic first down" }
        return text
    }

    // MARK: What happened

    private func describe(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        var text: String

        switch outcome.kind {
        case .kickoff: text = describeKickoff(play)
        case .punt: text = describePunt(play)
        case .fieldGoal:
            let length = rules.fieldGoalDistance(ballOn: play.situation.ballOn)
            let kicker = credited(outcome, .kicker) ?? "the kicker"
            switch outcome.endedIn {
            case .fieldGoalGood: text = "\(kicker) \(length) yards — good"
            case .blocked: text = "\(kicker) \(length) yards — blocked"
            default: text = "\(kicker) \(length) yards — no good"
            }
        case .extraPoint:
            let kicker = credited(outcome, .kicker) ?? "the kicker"
            text = outcome.endedIn == .fieldGoalGood ? "\(kicker) — good" : "\(kicker) — no good"
        case .twoPointConversion:
            text = outcome.endedIn == .touchdown ? "conversion good" : "conversion failed"
            if let target = credited(outcome, .target) { text += ", to \(target)" }
        case .rush: text = describeRun(play)
        case .pass: text = describePass(play)
        case .sack: text = describeSack(play)
        case .scramble:
            let passer = credited(outcome, .passer) ?? "the quarterback"
            if outcome.endedIn == .fumbleLost {
                text = "\(passer) scrambles and fumbles — \(recovery(play))"
            } else {
                text = "\(passer) scrambles for \(gainText(outcome.yards))"
                text += tackleCredit(outcome)
                text += endingSuffix(play)
            }
        case .kneel:
            text = "kneels down"
        case .spike:
            text = "spikes it to stop the clock"
        case .penaltyOnly:
            text = "no play"
        }

        // Whether the chains moved is the second thing a reader looks for after the
        // yardage, and it is exactly the thing an aggregate never shows.
        if play.gainedFirstDown, outcome.endedIn != .touchdown, outcome.kind.isScrimmagePlay {
            text += " — first down"
        }

        if outcome.kind.isScrimmagePlay {
            text +=
                "  · \(personnelCode(play.situation.offensePersonnel)) vs "
                + "\(packageName(play.situation.defensePackage)), "
                + coverageName(play.calls.defense.coverage)
        }
        return text
    }

    /// The grouping in the digit convention the sport uses: backs then tight ends, always
    /// two digits. An empty set is `00` personnel, never `0`.
    private func personnelCode(_ group: PersonnelGroup) -> String {
        group.code < 10 ? "0\(group.code)" : "\(group.code)"
    }

    private func describeKickoff(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        let offense = play.situation.possession
        let kicker = credited(outcome, .kicker) ?? "the kicker"
        let returner = credited(outcome, .returner)
        let spot = Int(outcome.finalSpot ?? play.situation.ballOn)

        switch outcome.endedIn {
        case .touchback:
            return "\(kicker) into the end zone — touchback"
        case .fumbleRecovered:
            return "recovered by \(abbreviation(offense)) at \(yardLine(spot, offense: offense))"
        case .touchdown:
            return "\(returner ?? "the returner") returns it all the way — touchdown"
        default:
            var text = "\(returner ?? "the returner") returns it to "
            text += yardLine(spot, offense: offense)
            if let tackler = credited(outcome, .tackler) { text += " (\(tackler))" }
            return text
        }
    }

    private func describePunt(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        let offense = play.situation.possession
        let punter = credited(outcome, .kicker) ?? "the punter"
        let spot = Int(outcome.finalSpot ?? play.situation.ballOn)
        // Where the ball came to rest, so this is the gross punt when nobody ran it back
        // and the **net** when somebody did — the stream does not record where a returned
        // punt was fielded, so the gross of a returned punt cannot be recovered from it.
        // Saying "net" on those is the honest version of printing the same subtraction.
        let distance = yardText(Int(play.situation.ballOn) - spot)

        switch outcome.endedIn {
        case .touchback:
            return "\(punter) into the end zone — touchback"
        case .fairCatch:
            return "\(punter) \(distance), fair catch at \(yardLine(spot, offense: offense))"
        case .downed:
            return "\(punter) \(distance), downed at \(yardLine(spot, offense: offense))"
        case .outOfBounds:
            return "\(punter) \(distance), out of bounds at \(yardLine(spot, offense: offense))"
        case .touchdown:
            let returner = credited(outcome, .returner) ?? "the returner"
            return "\(punter) is returned all the way by \(returner) — touchdown"
        case .blocked:
            return "\(punter) — blocked"
        default:
            let returner = credited(outcome, .returner) ?? "the returner"
            var text = "\(punter) net \(distance), returned by \(returner) to "
            text += yardLine(spot, offense: offense)
            if let tackler = credited(outcome, .tackler) { text += " (\(tackler))" }
            return text
        }
    }

    private func describeRun(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        let carrier = credited(outcome, .rusher) ?? "the back"
        switch outcome.endedIn {
        case .fumbleLost:
            return "\(carrier) fumbles — \(recovery(play))"
        case .fumbleRecovered:
            return "\(carrier) fumbles and recovers it, \(gainText(outcome.yards))"
        default:
            return "\(carrier) \(gainText(outcome.yards))" + tackleCredit(outcome)
                + endingSuffix(play)
        }
    }

    private func describeSack(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        let passer = credited(outcome, .passer) ?? "the quarterback"
        let sacker = credited(outcome, .tackler) ?? "someone"
        if outcome.endedIn == .fumbleLost {
            return "\(passer) is stripped by \(sacker) — \(recovery(play))"
        }
        return "\(passer) sacked by \(sacker), \(gainText(outcome.yards))" + endingSuffix(play)
    }

    private func describePass(_ play: PlayRecord) -> String {
        let outcome = play.outcome
        let passer = credited(outcome, .passer) ?? "the quarterback"

        // The catch is the one moment whose *reason* only the decision stream carries: a
        // drop, a break-up and a ball nobody could have caught are one `.incomplete` in
        // the outcome and three different plays to a person watching.
        let attempt = play.decisions(ofKind: .catchAttempt).last
        let target = attempt.map { name(at: $0.primary, in: outcome) } ?? credited(outcome, .target)
        let defender = attempt.map { name(at: $0.secondary, in: outcome) }

        switch outcome.endedIn {
        case .incomplete:
            guard let attempt, let result = attempt.catchResult else {
                return "\(passer) throws it away"
            }
            switch result {
            case .dropped: return "\(passer) — dropped by \(target ?? "the receiver")"
            case .brokenUp:
                return "\(passer) — broken up by \(defender ?? "the defender") "
                    + "on \(target ?? "the receiver")"
            case .uncatchable: return "\(passer) — off target for \(target ?? "the receiver")"
            default: return "\(passer) incomplete to \(target ?? "the receiver")"
            }

        case .intercepted:
            let spot = Int(outcome.finalSpot ?? play.situation.ballOn)
            let thief = credited(outcome, .tackler) ?? defender ?? "the defender"
            if spot >= 100 {
                return "\(passer) INTERCEPTED by \(thief), returned all the way — touchdown"
            }
            return "\(passer) INTERCEPTED by \(thief), returned to "
                + yardLine(spot, offense: play.situation.possession)

        case .fumbleLost:
            return "\(passer) complete to \(target ?? "the receiver"), fumbled — \(recovery(play))"

        default:
            var text = "\(passer) complete to \(target ?? "the receiver") for "
            text += gainText(outcome.yards)
            text += tackleCredit(outcome)
            text += endingSuffix(play)
            return text
        }
    }

    /// Where a lost ball was recovered.
    ///
    /// The spot stays in the offence's frame throughout, and a defender who picks it up
    /// runs *back* towards the offence's own goal — so his return **increases** `ballOn`
    /// and a hundred is a defensive touchdown.
    private func recovery(_ play: PlayRecord) -> String {
        let offense = play.situation.possession
        let spot = Int(play.outcome.finalSpot ?? play.situation.ballOn)
        if spot >= 100 {
            return "\(abbreviation(defending(offense))) returns it all the way — TOUCHDOWN"
        }
        return "recovered by \(abbreviation(defending(offense))) at "
            + yardLine(spot, offense: offense)
    }

    private func tackleCredit(_ outcome: Outcome) -> String {
        guard outcome.endedIn == .tackled, let tackler = credited(outcome, .tackler) else {
            return ""
        }
        return " (\(tackler))"
    }

    private func endingSuffix(_ play: PlayRecord) -> String {
        switch play.outcome.endedIn {
        case .touchdown: return " — TOUCHDOWN"
        case .safety: return " in the end zone — SAFETY"
        case .outOfBounds: return ", out of bounds"
        case .fumbleRecovered: return ", fumbled and recovered"
        case .touchback: return " — touchback"
        default: return ""
        }
    }

    /// Yardage with its noun agreeing with it. A one-yard drive is not "1 yards".
    private func yardText(_ yards: Int) -> String {
        "\(yards) yard\(yards == 1 || yards == -1 ? "" : "s")"
    }

    private func gainText(_ yards: Int16) -> String {
        if yards == 0 { return "no gain" }
        if yards < 0 { return "a loss of \(-yards)" }
        return "\(yards) yard\(yards == 1 ? "" : "s")"
    }
}

// MARK: - Print it

/// The column header, the play-by-play and the check that the scoreboard is the stream
/// summed: everything a seeded game and a scripted scenario print the same way.
///
/// One printer, called from both, on purpose. A scenario shown through a printer of its
/// own would be showing a reader something other than the game the conformance suite
/// asserts on, and the whole point of `--scenario` is that those are the same game.
func printPlayByPlay(
    home: Team, away: Team, players: [PlayerID: Player], rules: Rules, result: GameResult
) {
    print(
        padLeft("#", 4) + "  " + pad("clock", 9) + pad("off", 5) + pad("down", 11)
            + pad("ball", 10) + pad("concept", 14) + "what happened")
    print("")

    var broadcast = Broadcast(home: home, away: away, players: players, rules: rules)
    broadcast.run(result.plays)

    // The scoreboard is the stream summed, and saying so out loud is cheap. If these two
    // ever disagree the printer is wrong or the engine is, and either is worth knowing
    // before anybody reads a conclusion off this log.
    let derived = broadcast.scoreline()
    let engine =
        "\(away.identity.abbreviation) \(result.awayScore), "
        + "\(home.identity.abbreviation) \(result.homeScore)"
    if derived != engine {
        print("")
        print("  !! the stream sums to \(derived) and the engine reported \(engine)")
    }
    print("")
    print("        \(result.plays.count) plays")
}

print("gamelog — seed \(seed), week \(week), season \(season)")
print(
    "\(awayTeam.identity.fullName) (\(awayTeam.identity.abbreviation)) at "
        + "\(homeTeam.identity.fullName) (\(homeTeam.identity.abbreviation))")
print("\(homeTeam.stadium.name) · \(weatherLine(weather))")
print("")

printPlayByPlay(
    home: homeTeam, away: awayTeam, players: world.players, rules: setup.rules, result: result)
