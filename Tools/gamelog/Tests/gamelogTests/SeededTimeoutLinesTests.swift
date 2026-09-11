import FMCore
import FMGeneration
import FMRandom
import FMSimulation
import Testing

@testable import gamelog

/// Every charged timeout in a real game is on the page.
///
/// The scenario suite next door checks the timeouts a bench calls. This checks the ones
/// the *rules* charge — an injury timeout after the two-minute warning (2025 rulebook,
/// 4-5-4-a), the offence's timeout instead of a ten-second runoff (4-7-1 Item 1) — which
/// a scripted game rarely draws and a seeded one does. A timeout is a clock-stopping
/// event, and a trace that leaves one out invites a reader to explain the seconds it
/// saved by some other mechanism.
@Suite("Timeouts in a seeded game's log")
struct SeededTimeoutLinesTests {

    /// One seeded game, built the way `gamelog --seed s --home h --away a` builds it, so
    /// that what the test reads is what a reader reads.
    private struct Game {
        let home: Team
        let away: Team
        let players: [PlayerID: Player]
        let rules: Rules
        let result: GameResult
    }

    private static func build(seed: UInt64, homeIndex: Int, awayIndex: Int) -> Game? {
        guard
            let world = try? WorldGenerator.generate(
                seed: seed, shape: .standard, season: 2030, parts: .teamsAndRosters,
                collegeCount: 80
            ).get()
        else { return nil }
        let home = world.teams[homeIndex]
        let away = world.teams[awayIndex]
        var weatherRandom = SplittableRandom(seed: seed &+ 104_729)
        let weather = WeatherGenerator.forGame(
            stadium: home.stadium, week: 1, using: &weatherRandom)
        let setup = GameSetup(
            game: GameID(1),
            home: GameTeam(
                id: home.id, depthChart: world.depthChart(of: home.id), scheme: home.scheme),
            away: GameTeam(
                id: away.id, depthChart: world.depthChart(of: away.id), scheme: away.scheme),
            players: world.players,
            stadium: home.stadium,
            weather: weather,
            seed: seed &+ UInt64(homeIndex) &* 7_919 &+ UInt64(awayIndex) &* 65_537)
        return Game(
            home: home, away: away, players: world.players, rules: setup.rules,
            result: GameSimulator(resolver: CrudeResolver(), caller: BaselineCaller())
                .simulate(setup))
    }

    /// The corpus: four seeds against four matchups. Sixteen games is enough to draw the
    /// rules-charged timeouts, which a scripted scenario does not reach — measured, three
    /// of these games contain one.
    private static let corpus: [Game] = {
        var games: [Game] = []
        for seed: UInt64 in [7, 11, 12, 13] {
            for (home, away) in [(0, 1), (2, 3), (3, 11), (5, 20)] {
                if let game = build(seed: seed, homeIndex: home, awayIndex: away) {
                    games.append(game)
                }
            }
        }
        return games
    }()

    /// Every charged timeout a game contains, counted from the only thing that cannot
    /// disagree with the engine: a team's remaining timeouts falling between two
    /// consecutive snaps of the same period. Halves and overtime periods restock them
    /// (4-5-1 Item 1, 16-1-3), so a pair that crosses a period is not a drop.
    private func chargedTimeouts(in game: Game) -> Int {
        var charged = 0
        for (previous, next) in zip(game.result.plays, game.result.plays.dropFirst())
        where previous.situation.quarter == next.situation.quarter {
            let other = { (team: TeamID) in team == game.home.id ? game.away.id : game.home.id }
            var before: [TeamID: Int] = [:]
            var after: [TeamID: Int] = [:]
            before[previous.situation.possession] = Int(previous.situation.offenseTimeouts)
            before[other(previous.situation.possession)] = Int(previous.situation.defenseTimeouts)
            after[next.situation.possession] = Int(next.situation.offenseTimeouts)
            after[other(next.situation.possession)] = Int(next.situation.defenseTimeouts)
            for (team, count) in before { charged += max(0, count - (after[team] ?? count)) }
        }
        return charged
    }

    private func timeoutLines(in lines: [String]) -> [Substring] {
        lines.map { $0.drop(while: { $0 == " " }) }.filter { $0.hasPrefix("timeout: ") }
    }

    /// Every timeout a game charges is printed as a timeout, with the side charged and
    /// what it has left — the ones a bench calls, and the ones the rules charge after a
    /// play. A reader counting seconds between two snaps has the stoppage on the page
    /// rather than having to infer it from two situations he cannot see.
    @Test(
        "contract: every charged timeout in a seeded game is printed with its team and what it has left",
        .tags(.contract))
    func everyChargedTimeoutIsPrinted() {
        var charged = 0
        var printed = 0
        var rulesCharged = 0
        for game in Self.corpus {
            let lines = playByPlayLines(
                home: game.home, away: game.away, players: game.players, rules: game.rules,
                isPostseason: false, result: game.result)
            let here = chargedTimeouts(in: game)
            let onThePage = timeoutLines(in: lines)
            #expect(
                onThePage.count == here,
                "\(game.away.identity.abbreviation) at \(game.home.identity.abbreviation): \(here) timeouts charged, \(onThePage.count) printed"
            )
            charged += here
            printed += onThePage.count
            rulesCharged += game.result.plays.reduce(0) {
                $0
                    + $1.decisions.compactMap(\.clockElectionValue).filter {
                        $0 == .injuryTimeoutCharged || $0 == .timeoutInsteadOfRunoff
                    }.count
            }
        }
        // Guards on the instrument. The first fires if timeouts stop being taken at all;
        // the second if the corpus stops containing the rules-charged kind, which is the
        // one a scripted scenario does not reach and the one this test exists for.
        #expect(charged > 60, "sixteen games and \(charged) timeouts charged")
        #expect(rulesCharged > 0, "no timeout the rules charged in \(Self.corpus.count) games")
        #expect(printed == charged)
    }

    /// A printed timeout names a team and a count, whichever way it came to be charged.
    @Test(
        "contract: every printed timeout line names a team and what it has left", .tags(.contract))
    func everyPrintedTimeoutNamesATeamAndACount() {
        for game in Self.corpus {
            let lines = playByPlayLines(
                home: game.home, away: game.away, players: game.players, rules: game.rules,
                isPostseason: false, result: game.result)
            let abbreviations = Set([
                game.home.identity.abbreviation, game.away.identity.abbreviation,
            ])
            for line in timeoutLines(in: lines) {
                let team = String(line.dropFirst("timeout: ".count).prefix(while: { $0 != " " }))
                #expect(abbreviations.contains(team), "unreadable team in: \(line)")
                guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"),
                    let left = Int(
                        line[line.index(after: open)..<close].split(separator: " ").first ?? "")
                else {
                    Issue.record("unreadable count in: \(line)")
                    continue
                }
                #expect(left >= 0 && left < 3, "\(line)")
            }
        }
    }
}
