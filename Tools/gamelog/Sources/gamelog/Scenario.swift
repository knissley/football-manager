// Watch one rules-conformance scenario, play by play.
//
//   cd Tools/gamelog && swift run gamelog --scenario list
//   cd Tools/gamelog && swift run gamelog --scenario safety-free-kick
//
// The conformance scenarios in `FMSimulationScenarios` are the acceptance language for
// the rules layer: each one is a game whose plays are dictated, so that what is left to
// watch is the clock, the downs, possession, scoring, enforcement and overtime. The suite
// asserts on them and prints a verdict; this prints the game, so that a rule can be shown
// to a person rather than described to him.
//
// The game is the same game: the scenario, the world, the caller and the seed all come
// from the library the suite runs, and the printer is `printPlayByPlay`, which is what a
// seeded game goes through. Nothing here scripts any football of its own.

import FMCore
import FMGeneration
import FMSimulation
import FMSimulationScenarios

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// `--scenario list`: every scenario, with the football each one is there to show.
func printScenarioList() {
    print("gamelog — the rules-conformance scenarios")
    print("")
    print("  Pass one of these names to --scenario. Under each is what the engine's")
    print("  conformance suite asserts about it, which is what to watch the game for.")
    print("")
    for line in RulesScenario.listing() { print(line) }
    print("")
    print("  \(RulesScenario.allCases.count) scenarios.")
}

/// One scripted game as `--scenario <name>` prints it: the header, then the game.
///
/// Returned rather than printed so that the tool's own suite can assert on the very lines
/// a reader sees — the drive summaries in particular, which are where the clock
/// arithmetic shows up.
func scenarioLines(_ scenario: RulesScenario) -> [String] {
    let game = scenario.game
    // The same two clubs the scenario itself plays between: `ScenarioWorld.setup` takes
    // the first two teams of the league at the game's seed, and this is that league.
    let world = ScenarioWorld.world(seed: game.seed)
    let home = world.teams[0]
    let away = world.teams[1]
    let trace = scenario.run()

    var lines = ["gamelog — scenario \(scenario.slug)"]
    for expectation in scenario.expectations { lines.append("  \(expectation)") }
    lines.append("")
    lines.append(
        "\(away.identity.fullName) (\(away.identity.abbreviation)) at "
            + "\(home.identity.fullName) (\(home.identity.abbreviation))")
    lines.append(
        "\(home.stadium.name) · scripted game at seed \(game.seed)"
            + (game.isPostseason ? ", postseason" : "")
            + (scenario.usesBaselineCaller
                ? ", played by the baseline caller" : ", played by the scripted caller"))
    // Said once, at the top, because it is the first thing that looks wrong otherwise: a
    // scripted outcome credits nobody, so there is no ball carrier to name.
    lines.append("every play is dictated by the scenario; nobody is credited, so nobody is named")
    lines.append("")

    lines += playByPlayLines(
        home: home, away: away, players: world.players, rules: game.rules,
        isPostseason: game.isPostseason, result: trace.result)
    return lines
}

/// `--scenario <name>`: one scripted game, through the same printer a seeded game goes
/// through.
func printScenario(named name: String) {
    if name == "list" {
        printScenarioList()
        return
    }
    guard let scenario = RulesScenario(name) else {
        print("unknown scenario: \(name) — try --scenario list")
        exit(1)
    }
    for line in scenarioLines(scenario) { print(line) }
}
